-- =============================================================================
-- MÓDULO LOGÍSTICA – ERP MULTITENANT (DB POR TENANT) – PostgreSQL 15+
-- Esquema de referencia: inventario, valorización, conteos, compras, pedidos, almacén y transporte.
-- Una sola fuente de verdad: las migraciones se numeran a partir del primer despliegue.
-- =============================================================================
-- Decisiones de diseño:
--  * DB por tenant => NO hay columna tenant_id. Un tenant puede tener varias empresas (company).
--  * Un schema `scm`. PK uuid.
--  * El stock es un libro mayor (patrón 1): una línea de movimiento hecha es inmutable y
--    stock_quant es una caché derivada que mantienen los triggers; fn_rebuild_quants la reconstruye.
--  * Todo movimiento va de una ubicación a otra (patrón 2). Las ubicaciones virtuales (proveedores,
--    clientes, ajustes, merma, tránsito) también tienen quants: por producto, la suma es cero.
--  * Cantidades en la unidad del documento y en la unidad base del producto (patrón 6).
--  * Valorización perpetua (patrón 7): cada movimiento que entra o sale del stock valorizado de la
--    empresa genera una capa (stock_valuation_layer) y su asiento. Método por categoría de producto:
--    promedio móvil, PEPS o estándar. El costo es por empresa.
--  * Las garantías viven en la base (patrón 9): reservas, stock negativo, inmutabilidad, cierre.
--  * Vigencias [valid_from, valid_to) con EXCLUDE donde aplica.
--  * Columnas de auditoría y triggers se añaden al final a todas las tablas (sección 14).
--  * Tablas marcadas [MVP] (primer inventario real) o [F2] (fase 2, se agregan sin romper nada).
--  * PostgreSQL 15+ por UNIQUE NULLS NOT DISTINCT en stock_quant.
--
-- Variables de sesión (SET LOCAL en cada transacción de la app):
--   app.user_id          usuario (auditoría)
--   app.reason           motivo (reabrir un cierre, ajustes)
--   app.allow_negative   'on' permite stock negativo puntual donde la ubicación no lo admite
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE SCHEMA IF NOT EXISTS scm;
SET search_path = scm, public;

-- =============================================================================
-- 0. PLATAFORMA Y CATÁLOGOS GENÉRICOS
--    Tipos sugeridos: ADJUSTMENT_REASON, SCRAP_REASON, TRANSFER_REASON (motivo de traslado de la
--    guía de remisión), RETURN_REASON, DOC_TYPE (documento de identidad)
-- =============================================================================
CREATE TABLE lookup_type (
  code        text PRIMARY KEY,
  name        text NOT NULL,
  description text
);

CREATE TABLE lookup_value (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type_code   text NOT NULL REFERENCES lookup_type(code),
  code        text NOT NULL,
  name        text NOT NULL,
  sort_order  int  NOT NULL DEFAULT 0,
  is_active   boolean NOT NULL DEFAULT true,
  meta        jsonb NOT NULL DEFAULT '{}',
  UNIQUE (type_code, code)
);

CREATE TABLE scm_setting (                -- [MVP] políticas del tenant (capa Tenant, patrón 15)
  code        text PRIMARY KEY,
  value       jsonb NOT NULL,
  description text
);
INSERT INTO scm_setting(code, value, description) VALUES
  ('PO_APPROVAL_AMOUNT',        'null', 'Monto desde el que una orden de compra exige aprobación de otra persona'),
  ('BILL_PRICE_TOLERANCE_PCT',  '2',    'Tolerancia de precio entre orden de compra y factura (%)'),
  ('RECEIPT_QTY_TOLERANCE_PCT', '0',    'Tolerancia de cantidad entre lo recibido y lo facturado (%)');

-- =============================================================================
-- 1. ESTRUCTURA OPERATIVA
-- =============================================================================
CREATE TABLE company (                    -- [MVP] contribuyente
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code           text NOT NULL UNIQUE,
  legal_name     text NOT NULL,
  tax_id         text,
  country_code   char(2) NOT NULL,
  currency_code  char(3) NOT NULL,
  is_active      boolean NOT NULL DEFAULT true
);

CREATE TABLE establishment (              -- [MVP] dirección declarada ante la autoridad fiscal
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id     uuid NOT NULL REFERENCES company(id),
  code           text NOT NULL,           -- código de establecimiento anexo (Perú: 0000 = domicilio fiscal)
  name           text NOT NULL,
  address_line   text,
  ubigeo         text,
  country_code   char(2),
  UNIQUE (company_id, code)
);

CREATE TABLE warehouse (                  -- [MVP] almacén; sus ubicaciones cuelgan de view_location_id
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id           uuid NOT NULL REFERENCES company(id),
  establishment_id     uuid REFERENCES establishment(id),
  code                 text NOT NULL,
  name                 text NOT NULL,
  view_location_id     uuid,              -- FK diferida (location)
  stock_location_id    uuid,
  input_location_id    uuid,
  output_location_id   uuid,
  quality_location_id  uuid,
  reception_steps      int NOT NULL DEFAULT 1 CHECK (reception_steps IN (1,2,3)),
  delivery_steps       int NOT NULL DEFAULT 1 CHECK (delivery_steps IN (1,2,3)),
  timezone             text NOT NULL DEFAULT 'UTC',
  is_active            boolean NOT NULL DEFAULT true,
  UNIQUE (company_id, code)
);

CREATE TABLE location (                   -- [MVP] jerarquía física y ubicaciones virtuales
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id         uuid REFERENCES location(id),
  warehouse_id      uuid REFERENCES warehouse(id),   -- NULL en las virtuales
  code              text NOT NULL,
  name              text NOT NULL,
  usage             text NOT NULL
                    CHECK (usage IN ('view','internal','supplier','customer','inventory','scrap',
                                     'transit','production','internal_use')),
  parent_path       text,                 -- '/id/id/…/' mantenido por trigger (búsqueda por subárbol)
  is_blocked        boolean NOT NULL DEFAULT false,  -- calidad, cuarentena: no suma al disponible ni se reserva
  allow_negative    boolean NOT NULL DEFAULT false,  -- p. ej. el piso de venta de una tienda
  removal_strategy  text CHECK (removal_strategy IN ('fifo','fefo','lifo','closest')),
  barcode           text UNIQUE,
  max_weight_kg     numeric(12,3),
  max_volume_m3     numeric(12,4),
  is_active         boolean NOT NULL DEFAULT true,
  UNIQUE (parent_id, code)
);
CREATE INDEX ix_location_path ON location (parent_path text_pattern_ops);
CREATE UNIQUE INDEX uq_location_virtual_usage ON location (usage)
  WHERE warehouse_id IS NULL AND usage <> 'view';

ALTER TABLE warehouse
  ADD FOREIGN KEY (view_location_id)    REFERENCES location(id),
  ADD FOREIGN KEY (stock_location_id)   REFERENCES location(id),
  ADD FOREIGN KEY (input_location_id)   REFERENCES location(id),
  ADD FOREIGN KEY (output_location_id)  REFERENCES location(id),
  ADD FOREIGN KEY (quality_location_id) REFERENCES location(id);

CREATE TABLE document_sequence (          -- [MVP] series y correlativos sin huecos (guías, documentos)
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id   uuid NOT NULL REFERENCES company(id),
  doc_type     text NOT NULL,
  series       text NOT NULL,
  next_number  bigint NOT NULL DEFAULT 1 CHECK (next_number > 0),
  UNIQUE (company_id, doc_type, series)
);

-- =============================================================================
-- 2. CATÁLOGO DE PRODUCTOS
-- =============================================================================
CREATE TABLE uom_category (               -- [MVP] unidad, peso, volumen, longitud
  id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name  text NOT NULL UNIQUE
);

CREATE TABLE uom (                        -- [MVP] unidad de medida
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id   uuid NOT NULL REFERENCES uom_category(id),
  code          text NOT NULL UNIQUE,
  name          text NOT NULL,
  ratio         numeric(18,8) NOT NULL CHECK (ratio > 0),  -- unidades de referencia que equivalen a 1 de esta
  is_reference  boolean NOT NULL DEFAULT false,
  rounding      numeric(12,6) NOT NULL DEFAULT 1 CHECK (rounding > 0),  -- 1 = enteros; 0.001 = gramos
  is_active     boolean NOT NULL DEFAULT true
);
CREATE UNIQUE INDEX uq_uom_reference ON uom (category_id) WHERE is_reference;

CREATE TABLE product_category (           -- [MVP] define el método de costo, la salida y las cuentas
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id              uuid REFERENCES product_category(id),
  name                   text NOT NULL,
  costing_method         text NOT NULL DEFAULT 'average' CHECK (costing_method IN ('average','fifo','standard')),
  removal_strategy       text NOT NULL DEFAULT 'fifo' CHECK (removal_strategy IN ('fifo','fefo','lifo','closest')),
  account_inventory      text,            -- NULL = sin asientos automáticos
  account_stock_input    text,            -- mercadería recibida por facturar
  account_cogs           text,
  account_price_diff     text,
  account_scrap          text,
  account_adjustment     text,
  account_internal_use   text
);

CREATE TABLE product_template (           -- [MVP] lo que el cliente reconoce como un producto
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name                text NOT NULL,
  category_id         uuid NOT NULL REFERENCES product_category(id),
  product_type        text NOT NULL DEFAULT 'storable'
                      CHECK (product_type IN ('storable','consumable','service','kit')),
  uom_id              uuid NOT NULL REFERENCES uom(id),   -- unidad base de stock
  purchase_uom_id     uuid REFERENCES uom(id),
  sale_uom_id         uuid REFERENCES uom(id),
  tracking            text NOT NULL DEFAULT 'none' CHECK (tracking IN ('none','lot','serial')),
  use_expiration      boolean NOT NULL DEFAULT false,
  shelf_life_days     int,
  removal_days_before int,                -- se retira de venta N días antes de vencer
  alert_days_before   int,
  description         text,
  is_active           boolean NOT NULL DEFAULT true
);

CREATE TABLE product_attribute (          -- [F2] talla, color
  id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name  text NOT NULL UNIQUE
);

CREATE TABLE product_attribute_value (    -- [F2]
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  attribute_id  uuid NOT NULL REFERENCES product_attribute(id),
  name          text NOT NULL,
  UNIQUE (attribute_id, name)
);

CREATE TABLE product (                    -- [MVP] variante (SKU): lo que se cuenta y se mueve
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id     uuid NOT NULL REFERENCES product_template(id),
  sku             text NOT NULL UNIQUE,
  name            text NOT NULL,          -- nombre completo con atributos
  standard_price  numeric(14,4) NOT NULL DEFAULT 0,   -- costo estándar o costo de referencia
  weight_kg       numeric(12,4),
  volume_m3       numeric(12,6),
  is_active       boolean NOT NULL DEFAULT true
);

CREATE TABLE product_variant_value (      -- [F2] atributos de cada variante
  product_id          uuid NOT NULL REFERENCES product(id) ON DELETE CASCADE,
  attribute_value_id  uuid NOT NULL REFERENCES product_attribute_value(id),
  PRIMARY KEY (product_id, attribute_value_id)
);

CREATE TABLE product_barcode (            -- [MVP] varios códigos por producto; uno por código
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id    uuid NOT NULL REFERENCES product(id),
  barcode       text NOT NULL UNIQUE,
  kind          text NOT NULL DEFAULT 'gtin13'
                CHECK (kind IN ('gtin13','gtin14','internal','plu','variable_weight','supplier')),
  uom_id        uuid REFERENCES uom(id),  -- unidad que representa (caja, unidad)
  qty_per_scan  numeric(14,4) NOT NULL DEFAULT 1 CHECK (qty_per_scan > 0)
);

CREATE TABLE product_packaging (          -- [F2] empaques logísticos
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id  uuid NOT NULL REFERENCES product(id),
  name        text NOT NULL,
  qty         numeric(14,4) NOT NULL CHECK (qty > 0),     -- en unidad base
  barcode     text UNIQUE
);

CREATE TABLE product_kit_line (           -- [F2] componentes de un kit (combo de venta)
  kit_product_id        uuid NOT NULL REFERENCES product(id),
  component_product_id  uuid NOT NULL REFERENCES product(id),
  qty                   numeric(14,4) NOT NULL CHECK (qty > 0),
  PRIMARY KEY (kit_product_id, component_product_id),
  CHECK (kit_product_id <> component_product_id)
);

-- =============================================================================
-- 3. TERCEROS
-- =============================================================================
CREATE TABLE partner (                    -- [MVP] un solo maestro de terceros, con roles
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_type     text,                      -- RUC, DNI, CE…
  doc_number   text,
  name         text NOT NULL,
  email        text,
  phone        text,
  is_supplier  boolean NOT NULL DEFAULT false,
  is_customer  boolean NOT NULL DEFAULT false,
  is_carrier   boolean NOT NULL DEFAULT false,
  is_active    boolean NOT NULL DEFAULT true,
  UNIQUE (doc_type, doc_number)
);

CREATE TABLE partner_address (            -- [MVP]
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id    uuid NOT NULL REFERENCES partner(id),
  kind          text NOT NULL DEFAULT 'delivery' CHECK (kind IN ('fiscal','delivery','pickup','other')),
  line1         text NOT NULL,
  district      text,
  city          text,
  ubigeo        text,
  country_code  char(2),
  is_default    boolean NOT NULL DEFAULT false
);

CREATE TABLE supplier_info (              -- [MVP] condiciones del proveedor por producto, con vigencia
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id     uuid NOT NULL REFERENCES partner(id),
  product_id     uuid NOT NULL REFERENCES product(id),
  supplier_sku   text,
  uom_id         uuid REFERENCES uom(id), -- unidad de compra
  price          numeric(14,4) NOT NULL,
  currency_code  char(3) NOT NULL,
  min_qty        numeric(14,4) NOT NULL DEFAULT 0,
  multiple_qty   numeric(14,4) NOT NULL DEFAULT 1 CHECK (multiple_qty > 0),
  lead_days      int NOT NULL DEFAULT 0,
  priority       int NOT NULL DEFAULT 10,
  valid_from     date NOT NULL DEFAULT current_date,
  valid_to       date,
  CHECK (valid_to IS NULL OR valid_to > valid_from),
  EXCLUDE USING gist (partner_id WITH =, product_id WITH =, min_qty WITH =,
                      daterange(valid_from, valid_to) WITH &&)
);

-- =============================================================================
-- 4. LOTES Y PAQUETES
-- =============================================================================
CREATE TABLE lot (                        -- [MVP si hay productos con seguimiento] lote o serie
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id       uuid NOT NULL REFERENCES product(id),
  name             text NOT NULL,
  expiration_date  date,                  -- no se vende después
  removal_date     date,                  -- se retira de venta desde esta fecha
  alert_date       date,
  supplier_lot     text,
  UNIQUE (product_id, name)
);

CREATE TABLE package (                    -- [F2] unidad de manipulación: pallet, caja (LPN o SSCC)
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name               text NOT NULL UNIQUE,
  package_type       text NOT NULL DEFAULT 'box' CHECK (package_type IN ('pallet','box','bag','other')),
  parent_package_id  uuid REFERENCES package(id),
  location_id        uuid REFERENCES location(id)
);

-- =============================================================================
-- 5. OPERACIONES Y MOVIMIENTOS
--    Documento (picking) → movimientos (stock_move) → líneas hechas (stock_move_line) → quants
-- =============================================================================
CREATE TABLE picking_type (               -- [MVP] tipo de operación de un almacén
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  warehouse_id              uuid NOT NULL REFERENCES warehouse(id),
  code                      text NOT NULL
                            CHECK (code IN ('incoming','outgoing','internal','pos','adjustment','scrap',
                                            'return_in','return_out')),
  name                      text NOT NULL,
  sequence_prefix           text NOT NULL,
  next_number               int  NOT NULL DEFAULT 1,
  default_location_id       uuid REFERENCES location(id),
  default_location_dest_id  uuid REFERENCES location(id),
  reservation_method        text NOT NULL DEFAULT 'at_confirm'
                            CHECK (reservation_method IN ('at_confirm','manual','at_release')),
  UNIQUE (warehouse_id, code)
);

CREATE TABLE picking (                    -- [MVP] documento: recepción, despacho, transferencia, venta POS…
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        uuid NOT NULL REFERENCES company(id),
  picking_type_id   uuid NOT NULL REFERENCES picking_type(id),
  name              text NOT NULL UNIQUE,  -- correlativo del tipo (trigger)
  partner_id        uuid REFERENCES partner(id),
  origin_type       text NOT NULL DEFAULT 'manual'
                    CHECK (origin_type IN ('purchase','sale','pos','transfer','return','count','scrap','manual')),
  origin_ref        text,                  -- número del pedido, de la OC, de la venta del POS
  external_key      text UNIQUE,           -- idempotencia de integraciones (patrón 10)
  location_id       uuid NOT NULL REFERENCES location(id),
  location_dest_id  uuid NOT NULL REFERENCES location(id),
  status            text NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft','waiting','confirmed','assigned','done','cancelled')),
  scheduled_at      timestamptz NOT NULL DEFAULT now(),
  done_at           timestamptz,
  backorder_of_id   uuid REFERENCES picking(id),
  wave_id           uuid,                  -- FK diferida (sección 10)
  notes             text
);

CREATE TABLE stock_move (                 -- [MVP] lo que se pidió mover
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        uuid NOT NULL REFERENCES company(id),
  picking_id        uuid REFERENCES picking(id),
  product_id        uuid NOT NULL REFERENCES product(id),
  product_uom_qty   numeric(14,4) NOT NULL CHECK (product_uom_qty > 0),  -- en la unidad del documento
  uom_id            uuid NOT NULL REFERENCES uom(id),
  product_qty       numeric(14,4) NOT NULL,                              -- en unidad base (trigger)
  location_id       uuid NOT NULL REFERENCES location(id),
  location_dest_id  uuid NOT NULL REFERENCES location(id),
  status            text NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft','waiting','confirmed','partially_available','assigned',
                                      'done','cancelled')),
  date_planned      timestamptz NOT NULL DEFAULT now(),
  date_done         timestamptz,
  price_unit        numeric(14,4),         -- costo unitario de entrada por unidad base (compras)
  origin_move_id    uuid REFERENCES stock_move(id),   -- devolución: el movimiento que revierte
  move_dest_id      uuid REFERENCES stock_move(id),   -- siguiente paso de una ruta en varios pasos
  purchase_line_id  uuid,                  -- FK diferida (sección 8)
  sale_line_id      uuid,                  -- FK diferida (sección 9)
  external_key      text UNIQUE,           -- idempotencia: POS, marketplaces, handhelds
  reference         text,
  notes             text,
  CHECK (location_id <> location_dest_id)
);
CREATE INDEX ix_stock_move_product_status ON stock_move (product_id, status);
CREATE INDEX ix_stock_move_picking ON stock_move (picking_id);

CREATE TABLE stock_move_line (            -- [MVP] lo que se hizo: lote, ubicación exacta, paquete
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  move_id            uuid NOT NULL REFERENCES stock_move(id),
  product_id         uuid NOT NULL REFERENCES product(id),
  location_id        uuid NOT NULL REFERENCES location(id),
  location_dest_id   uuid NOT NULL REFERENCES location(id),
  lot_id             uuid REFERENCES lot(id),
  package_id         uuid REFERENCES package(id),
  result_package_id  uuid REFERENCES package(id),
  owner_id           uuid REFERENCES partner(id),   -- stock de terceros (consignación)
  qty                numeric(14,4) NOT NULL CHECK (qty > 0),   -- en unidad base
  status             text NOT NULL DEFAULT 'reserved' CHECK (status IN ('reserved','done','cancelled')),
  done_at            timestamptz
);
CREATE INDEX ix_move_line_move ON stock_move_line (move_id);
CREATE INDEX ix_move_line_done ON stock_move_line (product_id, done_at) WHERE status = 'done';

CREATE TABLE stock_quant (                -- [MVP] saldo derivado (caché reconstruible)
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id         uuid NOT NULL REFERENCES product(id),
  location_id        uuid NOT NULL REFERENCES location(id),
  lot_id             uuid REFERENCES lot(id),
  package_id         uuid REFERENCES package(id),
  owner_id           uuid REFERENCES partner(id),
  quantity           numeric(14,4) NOT NULL DEFAULT 0,
  reserved_quantity  numeric(14,4) NOT NULL DEFAULT 0 CHECK (reserved_quantity >= 0),
  in_date            timestamptz NOT NULL DEFAULT now(),   -- antigüedad para FIFO físico
  CONSTRAINT uq_quant UNIQUE NULLS NOT DISTINCT (product_id, location_id, lot_id, package_id, owner_id)
);
CREATE INDEX ix_quant_product ON stock_quant (product_id);

-- =============================================================================
-- 6. VALORIZACIÓN Y COSTOS
-- =============================================================================
CREATE TABLE stock_valuation_layer (      -- [MVP] capa de costo: entrada, salida o ajuste de valor
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       uuid NOT NULL REFERENCES company(id),
  product_id       uuid NOT NULL REFERENCES product(id),
  move_id          uuid REFERENCES stock_move(id),
  layer_date       timestamptz NOT NULL,
  layer_type       text NOT NULL
                   CHECK (layer_type IN ('in','out','landed_cost','price_diff','negative_correction',
                                         'revaluation')),
  quantity         numeric(14,4) NOT NULL DEFAULT 0,   -- con signo; 0 en ajustes de valor
  unit_cost        numeric(14,4),
  value            numeric(14,2) NOT NULL,             -- con signo: efecto en el valor del inventario
  remaining_qty    numeric(14,4),                      -- capas de entrada: unidades aún en stock
  remaining_value  numeric(14,2),                      -- capas de entrada: valor aún en stock (PEPS)
  cogs_amount      numeric(14,2) NOT NULL DEFAULT 0,   -- ajustes: parte que va a costo de ventas
  variance_amount  numeric(14,2) NOT NULL DEFAULT 0,   -- estándar: variación de precio de compra
  parent_layer_id  uuid REFERENCES stock_valuation_layer(id),
  landed_cost_id   uuid,                               -- FK diferida
  description      text
);
CREATE INDEX ix_svl_product ON stock_valuation_layer (company_id, product_id, layer_date);
CREATE UNIQUE INDEX uq_svl_move_main ON stock_valuation_layer (move_id)
  WHERE layer_type IN ('in','out');

CREATE TABLE landed_cost (                -- [F2] flete, seguro, aranceles prorrateados entre recepciones
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      uuid NOT NULL REFERENCES company(id),
  name            text NOT NULL UNIQUE,
  cost_date       timestamptz NOT NULL DEFAULT now(),
  vendor_bill_id  uuid,                   -- FK diferida
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted','cancelled')),
  posted_at       timestamptz
);
ALTER TABLE stock_valuation_layer ADD FOREIGN KEY (landed_cost_id) REFERENCES landed_cost(id);

CREATE TABLE landed_cost_picking (        -- [F2] recepciones a las que se aplica
  landed_cost_id  uuid NOT NULL REFERENCES landed_cost(id) ON DELETE CASCADE,
  picking_id      uuid NOT NULL REFERENCES picking(id),
  PRIMARY KEY (landed_cost_id, picking_id)
);

CREATE TABLE landed_cost_line (           -- [F2] cada costo y su criterio de reparto
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  landed_cost_id  uuid NOT NULL REFERENCES landed_cost(id) ON DELETE CASCADE,
  description     text NOT NULL,
  amount          numeric(14,2) NOT NULL CHECK (amount > 0),
  split_method    text NOT NULL DEFAULT 'by_value'
                  CHECK (split_method IN ('equal','by_quantity','by_value','by_weight','by_volume'))
);

CREATE TABLE landed_cost_allocation (     -- [F2] reparto calculado por movimiento
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  landed_cost_line_id  uuid NOT NULL REFERENCES landed_cost_line(id) ON DELETE CASCADE,
  move_id              uuid NOT NULL REFERENCES stock_move(id),
  amount               numeric(14,2) NOT NULL,
  UNIQUE (landed_cost_line_id, move_id)
);

-- =============================================================================
-- 7. CONTEOS
-- =============================================================================
CREATE TABLE stock_count (                -- [MVP] inventario completo, cíclico o puntual
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid NOT NULL REFERENCES company(id),
  warehouse_id  uuid NOT NULL REFERENCES warehouse(id),
  name          text NOT NULL UNIQUE,
  count_kind    text NOT NULL DEFAULT 'cycle' CHECK (count_kind IN ('full','cycle','spot')),
  is_blind      boolean NOT NULL DEFAULT true,
  status        text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','in_progress','done','cancelled')),
  started_at    timestamptz,
  applied_at    timestamptz,
  reason        text
);

CREATE TABLE stock_count_line (           -- [MVP] una ubicación × producto × lote
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  count_id            uuid NOT NULL REFERENCES stock_count(id) ON DELETE CASCADE,
  location_id         uuid NOT NULL REFERENCES location(id),
  product_id          uuid NOT NULL REFERENCES product(id),
  lot_id              uuid REFERENCES lot(id),
  expected_qty        numeric(14,4),      -- foto al iniciar el conteo de la línea
  snapshot_at         timestamptz,
  counted_qty         numeric(14,4) CHECK (counted_qty >= 0),
  counted_at          timestamptz,
  counted_by          text,
  difference_qty      numeric(14,4),      -- contado − (foto + movimientos posteriores)
  adjustment_move_id  uuid REFERENCES stock_move(id),
  UNIQUE NULLS NOT DISTINCT (count_id, location_id, product_id, lot_id)
);

-- =============================================================================
-- 8. COMPRAS Y ABASTECIMIENTO
-- =============================================================================
CREATE TABLE purchase_order (             -- [MVP]
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id     uuid NOT NULL REFERENCES company(id),
  name           text NOT NULL UNIQUE,
  partner_id     uuid NOT NULL REFERENCES partner(id),
  warehouse_id   uuid NOT NULL REFERENCES warehouse(id),
  currency_code  char(3) NOT NULL,
  status         text NOT NULL DEFAULT 'draft'
                 CHECK (status IN ('draft','sent','to_approve','purchase','done','cancelled')),
  order_date     date NOT NULL DEFAULT current_date,
  expected_date  date,
  approved_at    timestamptz,
  approved_by    text,
  notes          text
);

CREATE TABLE purchase_order_line (        -- [MVP]
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id       uuid NOT NULL REFERENCES purchase_order(id) ON DELETE CASCADE,
  product_id     uuid NOT NULL REFERENCES product(id),
  description    text,
  qty            numeric(14,4) NOT NULL CHECK (qty > 0),   -- en la unidad de compra
  uom_id         uuid NOT NULL REFERENCES uom(id),
  price_unit     numeric(14,4) NOT NULL CHECK (price_unit >= 0),   -- sin impuesto, por unidad de compra
  expected_date  date
);
ALTER TABLE stock_move ADD FOREIGN KEY (purchase_line_id) REFERENCES purchase_order_line(id);

CREATE TABLE vendor_bill (                -- [MVP] factura del proveedor
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      uuid NOT NULL REFERENCES company(id),
  partner_id      uuid NOT NULL REFERENCES partner(id),
  doc_type        text NOT NULL DEFAULT '01',
  series          text NOT NULL,
  number          text NOT NULL,
  bill_date       date NOT NULL,
  currency_code   char(3) NOT NULL,
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted','cancelled')),
  amount_untaxed  numeric(14,2),
  amount_tax      numeric(14,2),
  amount_total    numeric(14,2),
  UNIQUE (partner_id, doc_type, series, number)
);
ALTER TABLE landed_cost ADD FOREIGN KEY (vendor_bill_id) REFERENCES vendor_bill(id);

CREATE TABLE vendor_bill_line (           -- [MVP]
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bill_id           uuid NOT NULL REFERENCES vendor_bill(id) ON DELETE CASCADE,
  purchase_line_id  uuid REFERENCES purchase_order_line(id),
  product_id        uuid REFERENCES product(id),
  qty               numeric(14,4) NOT NULL,   -- en la unidad de la línea de compra
  price_unit        numeric(14,4) NOT NULL,
  amount            numeric(14,2) NOT NULL
);

CREATE TABLE replenishment_rule (         -- [MVP] mínimo y máximo por almacén y producto
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  warehouse_id   uuid NOT NULL REFERENCES warehouse(id),
  product_id     uuid NOT NULL REFERENCES product(id),
  min_qty        numeric(14,4) NOT NULL CHECK (min_qty >= 0),
  max_qty        numeric(14,4) NOT NULL,
  multiple_qty   numeric(14,4) NOT NULL DEFAULT 1 CHECK (multiple_qty > 0),
  partner_id     uuid REFERENCES partner(id),   -- proveedor preferido
  lead_days      int,
  is_active      boolean NOT NULL DEFAULT true,
  CHECK (max_qty >= min_qty),
  UNIQUE (warehouse_id, product_id)
);

-- =============================================================================
-- 9. PEDIDOS Y DEVOLUCIONES
-- =============================================================================
CREATE TABLE sale_order (                 -- [MVP] pedido de cualquier canal
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id     uuid NOT NULL REFERENCES company(id),
  name           text NOT NULL UNIQUE,
  partner_id     uuid REFERENCES partner(id),
  channel        text NOT NULL DEFAULT 'b2b' CHECK (channel IN ('store','web','marketplace','phone','b2b')),
  warehouse_id   uuid REFERENCES warehouse(id),
  status         text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','confirmed','done','cancelled')),
  order_date     timestamptz NOT NULL DEFAULT now(),
  promised_date  date,
  external_key   text UNIQUE,
  currency_code  char(3)
);

CREATE TABLE sale_order_line (            -- [MVP]
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id       uuid NOT NULL REFERENCES sale_order(id) ON DELETE CASCADE,
  product_id     uuid NOT NULL REFERENCES product(id),
  qty            numeric(14,4) NOT NULL CHECK (qty > 0),
  uom_id         uuid NOT NULL REFERENCES uom(id),
  price_unit     numeric(14,4),
  promised_date  date
);
ALTER TABLE stock_move ADD FOREIGN KEY (sale_line_id) REFERENCES sale_order_line(id);

CREATE TABLE return_authorization (       -- [F2] autorización de devolución (RMA)
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id     uuid NOT NULL REFERENCES company(id),
  name           text NOT NULL UNIQUE,
  partner_id     uuid REFERENCES partner(id),
  sale_order_id  uuid REFERENCES sale_order(id),
  status         text NOT NULL DEFAULT 'draft'
                 CHECK (status IN ('draft','approved','received','closed','rejected')),
  reason         text
);

CREATE TABLE return_authorization_line (  -- [F2]
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rma_id            uuid NOT NULL REFERENCES return_authorization(id) ON DELETE CASCADE,
  product_id        uuid NOT NULL REFERENCES product(id),
  qty               numeric(14,4) NOT NULL CHECK (qty > 0),
  lot_id            uuid REFERENCES lot(id),
  origin_move_id    uuid REFERENCES stock_move(id),
  disposition       text CHECK (disposition IN ('restock','refurbish','return_to_vendor','scrap')),
  received_move_id  uuid REFERENCES stock_move(id)
);

-- =============================================================================
-- 10. ALMACÉN DIRIGIDO (WMS)
-- =============================================================================
CREATE TABLE putaway_rule (               -- [F2] dónde guardar lo recibido
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  location_in_id   uuid NOT NULL REFERENCES location(id),
  product_id       uuid REFERENCES product(id),
  category_id      uuid REFERENCES product_category(id),
  location_out_id  uuid NOT NULL REFERENCES location(id),
  sequence         int NOT NULL DEFAULT 10,
  CHECK (product_id IS NOT NULL OR category_id IS NOT NULL)
);

CREATE TABLE wave (                       -- [F2] pedidos que se preparan juntos
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  warehouse_id  uuid NOT NULL REFERENCES warehouse(id),
  name          text NOT NULL UNIQUE,
  status        text NOT NULL DEFAULT 'draft'
                CHECK (status IN ('draft','released','in_progress','done','cancelled')),
  cutoff_at     timestamptz,
  released_at   timestamptz
);
ALTER TABLE picking ADD FOREIGN KEY (wave_id) REFERENCES wave(id);

CREATE TABLE warehouse_task (             -- [F2] trabajo dirigido por el sistema
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  warehouse_id      uuid NOT NULL REFERENCES warehouse(id),
  task_type         text NOT NULL
                    CHECK (task_type IN ('receive','putaway','replenish','pick','pack','count','load')),
  priority          int NOT NULL DEFAULT 50,
  move_line_id      uuid REFERENCES stock_move_line(id),
  location_id       uuid REFERENCES location(id),
  location_dest_id  uuid REFERENCES location(id),
  assigned_to       text,
  status            text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','assigned','in_progress','done','cancelled')),
  started_at        timestamptz,
  finished_at       timestamptz
);
CREATE INDEX ix_task_queue ON warehouse_task (warehouse_id, status, priority);

-- =============================================================================
-- 11. TRANSPORTE Y GUÍAS DE REMISIÓN
-- =============================================================================
CREATE TABLE vehicle (                    -- [F2]
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  carrier_partner_id  uuid REFERENCES partner(id),   -- NULL = flota propia
  plate               text NOT NULL UNIQUE,
  max_weight_kg       numeric(12,3),
  is_active           boolean NOT NULL DEFAULT true
);

CREATE TABLE shipment (                   -- [F2] envío y prueba de entrega
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  picking_id          uuid NOT NULL REFERENCES picking(id),
  carrier_partner_id  uuid REFERENCES partner(id),
  vehicle_id          uuid REFERENCES vehicle(id),
  driver_name         text,
  driver_doc          text,
  tracking_ref        text,
  status              text NOT NULL DEFAULT 'planned'
                      CHECK (status IN ('planned','in_transit','delivered','failed','returned')),
  departed_at         timestamptz,
  delivered_at        timestamptz,
  proof_ref           text,               -- foto, firma, geolocalización
  failure_reason      text
);

CREATE TABLE dispatch_guide (             -- [F2] guía de remisión (Perú: GRE remitente o transportista)
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             uuid NOT NULL REFERENCES company(id),
  guide_kind             text NOT NULL DEFAULT 'sender' CHECK (guide_kind IN ('sender','carrier')),
  series                 text NOT NULL,
  number                 bigint NOT NULL,
  issue_date             date NOT NULL DEFAULT current_date,
  transfer_start_date    date NOT NULL,
  transfer_reason        text NOT NULL,   -- código del catálogo de motivos (lookup TRANSFER_REASON)
  picking_id             uuid REFERENCES picking(id),
  from_establishment_id  uuid REFERENCES establishment(id),
  from_address           text,
  from_ubigeo            text,
  to_partner_id          uuid REFERENCES partner(id),
  to_address             text,
  to_ubigeo              text,
  transport_mode         text NOT NULL CHECK (transport_mode IN ('public','private')),
  carrier_partner_id     uuid REFERENCES partner(id),
  vehicle_id             uuid REFERENCES vehicle(id),
  driver_doc             text,
  gross_weight_kg        numeric(12,3),
  status                 text NOT NULL DEFAULT 'generated'
                         CHECK (status IN ('generated','signed','sent','accepted','observed','rejected','voided')),
  submission_ref         text,
  UNIQUE (company_id, series, number),
  CHECK (transfer_start_date >= issue_date)
);

CREATE TABLE dispatch_guide_line (        -- [F2]
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  guide_id     uuid NOT NULL REFERENCES dispatch_guide(id) ON DELETE CASCADE,
  product_id   uuid REFERENCES product(id),
  description  text NOT NULL,
  qty          numeric(14,4) NOT NULL CHECK (qty > 0),
  uom_id       uuid REFERENCES uom(id)
);

-- =============================================================================
-- 12. CONTABILIDAD DE INVENTARIO
--     Si el módulo contable no arma el asiento, lo arma aquí cada capa de valorización.
-- =============================================================================
CREATE TABLE stock_journal_entry (        -- [F2] un asiento por capa
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES company(id),
  entry_date  timestamptz NOT NULL,
  layer_id    uuid NOT NULL UNIQUE REFERENCES stock_valuation_layer(id),
  description text
);

CREATE TABLE stock_journal_line (         -- [F2]
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id      uuid NOT NULL REFERENCES stock_journal_entry(id) ON DELETE CASCADE,
  account_code  text NOT NULL,
  debit         numeric(14,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
  credit        numeric(14,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
  CHECK (debit = 0 OR credit = 0)
);

-- =============================================================================
-- 13. CIERRE Y APROBACIONES
-- =============================================================================
CREATE TABLE inventory_lock (             -- [MVP] cierre: no hay movimientos con fecha <= lock_date
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES company(id),
  lock_date   date NOT NULL,
  reason      text,
  UNIQUE (company_id, lock_date)
);

CREATE TABLE approval_request (           -- [F2] flujo genérico (ajustes grandes, OC, devoluciones)
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_table  text NOT NULL,
  entity_id     uuid NOT NULL,
  request_type  text NOT NULL,
  status        text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','approved','rejected','cancelled')),
  requested_by  text,
  requested_at  timestamptz NOT NULL DEFAULT now(),
  decided_at    timestamptz,
  payload       jsonb NOT NULL DEFAULT '{}'
);

CREATE TABLE approval_step (              -- [F2]
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id   uuid NOT NULL REFERENCES approval_request(id) ON DELETE CASCADE,
  step_order   int NOT NULL,
  approver     text,
  status       text NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending','approved','rejected','skipped')),
  decided_at   timestamptz,
  comment      text,
  UNIQUE (request_id, step_order)
);

-- =============================================================================
-- 14. AUDITORÍA
-- =============================================================================
CREATE TABLE audit_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  table_name  text NOT NULL,
  record_id   uuid,
  action      text NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  changed_by  text,
  changed_at  timestamptz NOT NULL DEFAULT now(),
  old_data    jsonb,
  new_data    jsonb
);
CREATE INDEX ix_audit_table_rec ON audit_log(table_name, record_id);

CREATE OR REPLACE FUNCTION scm.fn_set_audit() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := now();
    NEW.created_by := nullif(current_setting('app.user_id', true), '');
  END IF;
  NEW.updated_at := now();
  NEW.updated_by := nullif(current_setting('app.user_id', true), '');
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION scm.fn_audit_log() RETURNS trigger AS $$
BEGIN
  INSERT INTO scm.audit_log(table_name, record_id, action, changed_by, old_data, new_data)
  VALUES (TG_TABLE_NAME,
          COALESCE((to_jsonb(NEW)->>'id'), (to_jsonb(OLD)->>'id'))::uuid,
          TG_OP,
          nullif(current_setting('app.user_id', true), ''),
          CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
          CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END);
  RETURN COALESCE(NEW, OLD);
END $$ LANGUAGE plpgsql;

-- Columnas de auditoría en todas las tablas con PK uuid "id"; audit_log solo en las sensibles.
DO $$
DECLARE
  t record;
  sensitive text[] := ARRAY[
    'product_category','product','supplier_info','location','warehouse',
    'stock_move','stock_count','stock_count_line','stock_valuation_layer',
    'landed_cost','landed_cost_line','purchase_order','purchase_order_line',
    'vendor_bill','replenishment_rule','inventory_lock','dispatch_guide'
  ];
BEGIN
  FOR t IN
    SELECT c.table_name
    FROM information_schema.columns c
    JOIN information_schema.tables tb
      ON tb.table_schema = c.table_schema AND tb.table_name = c.table_name
    WHERE c.table_schema = 'scm' AND c.column_name = 'id'
      AND tb.table_type = 'BASE TABLE' AND c.table_name <> 'audit_log'
  LOOP
    EXECUTE format('ALTER TABLE scm.%I
      ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
      ADD COLUMN IF NOT EXISTS created_by text,
      ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now(),
      ADD COLUMN IF NOT EXISTS updated_by text', t.table_name);

    EXECUTE format('CREATE TRIGGER trg_%1$s_audit_cols BEFORE INSERT OR UPDATE ON scm.%1$I
      FOR EACH ROW EXECUTE FUNCTION scm.fn_set_audit()', t.table_name);

    IF t.table_name = ANY (sensitive) THEN
      EXECUTE format('CREATE TRIGGER trg_%1$s_audit_log AFTER INSERT OR UPDATE OR DELETE ON scm.%1$I
        FOR EACH ROW EXECUTE FUNCTION scm.fn_audit_log()', t.table_name);
    END IF;
  END LOOP;
END $$;

-- =============================================================================
-- 16. LÓGICA
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 16.1 Ubicaciones [MVP]
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION scm.fn_location_path() RETURNS trigger AS $$
DECLARE v_parent text;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.parent_id IS DISTINCT FROM OLD.parent_id
     AND EXISTS (SELECT 1 FROM scm.location c WHERE c.parent_id = NEW.id) THEN
    RAISE EXCEPTION 'LOCATION_HAS_CHILDREN: mueve primero las ubicaciones hijas';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.usage IS DISTINCT FROM OLD.usage AND EXISTS (
       SELECT 1 FROM scm.stock_move_line l WHERE NEW.id IN (l.location_id, l.location_dest_id)) THEN
    RAISE EXCEPTION 'LOCATION_USAGE_LOCKED: la ubicación ya tiene movimientos';
  END IF;
  SELECT parent_path INTO v_parent FROM scm.location WHERE id = NEW.parent_id;
  NEW.parent_path := coalesce(v_parent, '/') || NEW.id::text || '/';
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_location_path
  BEFORE INSERT OR UPDATE OF parent_id, usage ON location
  FOR EACH ROW EXECUTE FUNCTION scm.fn_location_path();

-- Ubicaciones virtuales del sistema (capa Sistema, patrón 15)
INSERT INTO location(code, name, usage) VALUES ('VIRTUAL', 'Ubicaciones virtuales', 'view');
INSERT INTO location(parent_id, code, name, usage)
SELECT (SELECT id FROM location WHERE code = 'VIRTUAL' AND parent_id IS NULL), v.code, v.name, v.usage
FROM (VALUES ('SUPPLIERS','Proveedores','supplier'), ('CUSTOMERS','Clientes','customer'),
             ('ADJUSTMENT','Ajustes de inventario','inventory'), ('SCRAP','Merma','scrap'),
             ('TRANSIT','Tránsito','transit'), ('PRODUCTION','Producción','production'),
             ('INTERNAL_USE','Consumo interno','internal_use')) v(code, name, usage);

CREATE OR REPLACE FUNCTION scm.fn_vloc(p_usage text) RETURNS uuid AS $$
DECLARE v uuid;
BEGIN
  SELECT id INTO v FROM scm.location WHERE warehouse_id IS NULL AND usage = p_usage;
  IF v IS NULL THEN RAISE EXCEPTION 'VIRTUAL_LOCATION_MISSING: %', p_usage; END IF;
  RETURN v;
END $$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION scm.fn_in_subtree(p_location uuid, p_root uuid) RETURNS boolean AS $$
  SELECT EXISTS (SELECT 1 FROM scm.location l, scm.location r
                 WHERE l.id = p_location AND r.id = p_root AND l.parent_path LIKE r.parent_path || '%');
$$ LANGUAGE sql STABLE;

-- Crea un almacén con su árbol de ubicaciones y sus tipos de operación
CREATE OR REPLACE FUNCTION scm.fn_create_warehouse(p_company uuid, p_code text, p_name text,
                                                   p_establishment uuid DEFAULT NULL)
RETURNS uuid AS $$
DECLARE w uuid; v_view uuid; v_stock uuid; v_in uuid; v_out uuid; v_qc uuid;
BEGIN
  INSERT INTO scm.warehouse(company_id, establishment_id, code, name)
  VALUES (p_company, p_establishment, p_code, p_name) RETURNING id INTO w;
  INSERT INTO scm.location(warehouse_id, code, name, usage) VALUES (w, p_code, p_name, 'view') RETURNING id INTO v_view;
  INSERT INTO scm.location(parent_id, warehouse_id, code, name, usage) VALUES (v_view, w, 'STOCK', 'Stock', 'internal') RETURNING id INTO v_stock;
  INSERT INTO scm.location(parent_id, warehouse_id, code, name, usage) VALUES (v_view, w, 'INPUT', 'Recepción', 'internal') RETURNING id INTO v_in;
  INSERT INTO scm.location(parent_id, warehouse_id, code, name, usage) VALUES (v_view, w, 'OUTPUT', 'Despacho', 'internal') RETURNING id INTO v_out;
  INSERT INTO scm.location(parent_id, warehouse_id, code, name, usage, is_blocked) VALUES (v_view, w, 'QC', 'Control de calidad', 'internal', true) RETURNING id INTO v_qc;
  UPDATE scm.warehouse SET view_location_id = v_view, stock_location_id = v_stock, input_location_id = v_in,
         output_location_id = v_out, quality_location_id = v_qc WHERE id = w;
  INSERT INTO scm.picking_type(warehouse_id, code, name, sequence_prefix, default_location_id, default_location_dest_id) VALUES
    (w, 'incoming',   'Recepciones',             p_code || '/IN/',  scm.fn_vloc('supplier'),  v_stock),
    (w, 'outgoing',   'Despachos',               p_code || '/OUT/', v_stock, scm.fn_vloc('customer')),
    (w, 'internal',   'Transferencias internas', p_code || '/INT/', v_stock, v_stock),
    (w, 'pos',        'Ventas del POS',          p_code || '/POS/', v_stock, scm.fn_vloc('customer')),
    (w, 'adjustment', 'Ajustes',                 p_code || '/ADJ/', scm.fn_vloc('inventory'), v_stock),
    (w, 'scrap',      'Merma',                   p_code || '/SCR/', v_stock, scm.fn_vloc('scrap')),
    (w, 'return_in',  'Devoluciones de clientes',p_code || '/RET/', scm.fn_vloc('customer'), v_stock),
    (w, 'return_out', 'Devoluciones a proveedores', p_code || '/RTV/', v_stock, scm.fn_vloc('supplier'));
  RETURN w;
END $$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- 16.2 Unidades, documentos y numeración [MVP]
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION scm.fn_to_base_qty(p_product uuid, p_qty numeric, p_uom uuid) RETURNS numeric AS $$
DECLARE v_ratio numeric; v_cat uuid; b_ratio numeric; b_cat uuid; b_round numeric;
BEGIN
  SELECT u.ratio, u.category_id INTO v_ratio, v_cat FROM scm.uom u WHERE u.id = p_uom;
  SELECT u.ratio, u.category_id, u.rounding INTO b_ratio, b_cat, b_round
  FROM scm.product p JOIN scm.product_template t ON t.id = p.template_id JOIN scm.uom u ON u.id = t.uom_id
  WHERE p.id = p_product;
  IF v_cat IS DISTINCT FROM b_cat THEN
    RAISE EXCEPTION 'UOM_CATEGORY_MISMATCH: la unidad no es de la misma categoría que la unidad base';
  END IF;
  RETURN round(p_qty * v_ratio / b_ratio / b_round) * b_round;
END $$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION scm.fn_next_number(p_company uuid, p_doc_type text, p_series text) RETURNS bigint AS $$
DECLARE v bigint;
BEGIN
  UPDATE scm.document_sequence SET next_number = next_number + 1
  WHERE company_id = p_company AND doc_type = p_doc_type AND series = p_series
  RETURNING next_number - 1 INTO v;          -- el bloqueo de fila garantiza correlativos sin huecos
  IF v IS NULL THEN RAISE EXCEPTION 'SEQUENCE_MISSING: % %', p_doc_type, p_series; END IF;
  RETURN v;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION scm.fn_picking_name() RETURNS trigger AS $$
DECLARE v_prefix text; v_n int;
BEGIN
  IF NEW.name IS NULL THEN
    UPDATE scm.picking_type SET next_number = next_number + 1 WHERE id = NEW.picking_type_id
    RETURNING sequence_prefix, next_number - 1 INTO v_prefix, v_n;
    NEW.name := v_prefix || lpad(v_n::text, 5, '0');
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_picking_name BEFORE INSERT ON picking FOR EACH ROW EXECUTE FUNCTION scm.fn_picking_name();

-- -----------------------------------------------------------------------------
-- 16.3 Cierre de inventario [MVP]
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION scm.fn_check_inventory_lock(p_company uuid, p_at timestamptz) RETURNS void AS $$
DECLARE v_lock date;
BEGIN
  SELECT max(lock_date) INTO v_lock FROM scm.inventory_lock WHERE company_id = p_company;
  IF v_lock IS NOT NULL AND p_at::date <= v_lock THEN
    RAISE EXCEPTION 'INVENTORY_PERIOD_LOCKED: el inventario está cerrado hasta el %; registra en el período abierto', v_lock;
  END IF;
END $$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION scm.fn_inventory_lock_guard() RETURNS trigger AS $$
BEGIN
  IF nullif(current_setting('app.reason', true), '') IS NULL THEN
    RAISE EXCEPTION 'LOCK_REASON_REQUIRED: reabrir un cierre de inventario exige motivo (app.reason)';
  END IF;
  RETURN OLD;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_inventory_lock_guard BEFORE UPDATE OR DELETE ON inventory_lock
  FOR EACH ROW EXECUTE FUNCTION scm.fn_inventory_lock_guard();

-- -----------------------------------------------------------------------------
-- 16.4 Quants: el saldo se deriva de las líneas hechas [MVP]
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION scm.fn_quant_reserve(p_product uuid, p_location uuid, p_lot uuid, p_package uuid,
                                                p_owner uuid, p_delta numeric) RETURNS void AS $$
DECLARE v_q numeric; v_r numeric; v_usage text; v_blocked boolean;
BEGIN
  IF p_delta > 0 THEN
    SELECT usage, is_blocked INTO v_usage, v_blocked FROM scm.location WHERE id = p_location;
    IF v_usage <> 'internal' OR v_blocked THEN
      RAISE EXCEPTION 'RESERVE_LOCATION_INVALID: solo se reserva en ubicaciones internas no bloqueadas';
    END IF;
  END IF;
  UPDATE scm.stock_quant SET reserved_quantity = reserved_quantity + p_delta
  WHERE product_id = p_product AND location_id = p_location AND lot_id IS NOT DISTINCT FROM p_lot
    AND package_id IS NOT DISTINCT FROM p_package AND owner_id IS NOT DISTINCT FROM p_owner
  RETURNING quantity, reserved_quantity INTO v_q, v_r;
  IF NOT FOUND THEN
    IF p_delta > 0 THEN RAISE EXCEPTION 'RESERVE_NO_STOCK: no hay stock en la ubicación'; END IF;
    RETURN;
  END IF;
  IF p_delta > 0 AND v_r > v_q THEN
    RAISE EXCEPTION 'RESERVE_EXCEEDS_STOCK: se reservaría % de % físicas', v_r, v_q;
  END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION scm.fn_quant_apply_done(p_line scm.stock_move_line) RETURNS void AS $$
DECLARE v_q numeric; v_usage text; v_neg boolean; v_company uuid;
BEGIN
  SELECT company_id INTO v_company FROM scm.stock_move WHERE id = p_line.move_id;
  PERFORM scm.fn_check_inventory_lock(v_company, p_line.done_at);

  INSERT INTO scm.stock_quant(product_id, location_id, lot_id, package_id, owner_id, quantity)
  VALUES (p_line.product_id, p_line.location_id, p_line.lot_id, p_line.package_id, p_line.owner_id, -p_line.qty)
  ON CONFLICT ON CONSTRAINT uq_quant DO UPDATE SET quantity = scm.stock_quant.quantity + EXCLUDED.quantity
  RETURNING quantity INTO v_q;

  IF v_q < 0 THEN
    SELECT usage, allow_negative INTO v_usage, v_neg FROM scm.location WHERE id = p_line.location_id;
    IF v_usage = 'internal' AND NOT v_neg
       AND coalesce(current_setting('app.allow_negative', true), '') <> 'on' THEN
      RAISE EXCEPTION 'STOCK_NEGATIVE_NOT_ALLOWED: el movimiento deja % en la ubicación', v_q;
    END IF;
  END IF;

  INSERT INTO scm.stock_quant(product_id, location_id, lot_id, package_id, owner_id, quantity, in_date)
  VALUES (p_line.product_id, p_line.location_dest_id, p_line.lot_id,
          coalesce(p_line.result_package_id, p_line.package_id), p_line.owner_id, p_line.qty, p_line.done_at)
  ON CONFLICT ON CONSTRAINT uq_quant DO UPDATE
    SET quantity = scm.stock_quant.quantity + EXCLUDED.quantity,
        in_date  = CASE WHEN scm.stock_quant.quantity <= 0 THEN EXCLUDED.in_date ELSE scm.stock_quant.in_date END;
END $$ LANGUAGE plpgsql;

-- Reconstruye los quants desde las líneas (patrón 1). Devuelve las filas reconstruidas.
CREATE OR REPLACE FUNCTION scm.fn_rebuild_quants() RETURNS bigint AS $$
DECLARE n bigint;
BEGIN
  DELETE FROM scm.stock_quant;
  INSERT INTO scm.stock_quant(product_id, location_id, lot_id, package_id, owner_id, quantity, in_date)
  SELECT product_id, location_id, lot_id, package_id, owner_id, sum(qty), min(done_at)
  FROM (SELECT product_id, location_dest_id AS location_id, lot_id,
               coalesce(result_package_id, package_id) AS package_id, owner_id, qty, done_at
        FROM scm.stock_move_line WHERE status = 'done'
        UNION ALL
        SELECT product_id, location_id, lot_id, package_id, owner_id, -qty, done_at
        FROM scm.stock_move_line WHERE status = 'done') x
  GROUP BY product_id, location_id, lot_id, package_id, owner_id;
  GET DIAGNOSTICS n = ROW_COUNT;
  UPDATE scm.stock_quant q SET reserved_quantity = r.qty
  FROM (SELECT product_id, location_id, lot_id, package_id, owner_id, sum(qty) qty
        FROM scm.stock_move_line WHERE status = 'reserved'
        GROUP BY product_id, location_id, lot_id, package_id, owner_id) r
  WHERE q.product_id = r.product_id AND q.location_id = r.location_id AND q.lot_id IS NOT DISTINCT FROM r.lot_id
    AND q.package_id IS NOT DISTINCT FROM r.package_id AND q.owner_id IS NOT DISTINCT FROM r.owner_id;
  RETURN n;
END $$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- 16.5 Movimientos: estados, inmutabilidad y líneas [MVP]
--
--   draft ──► waiting ──► confirmed ──► partially_available ──► assigned ──► done
--                              └────────────────────────────────────────────► done
--   cancelled: desde cualquier estado anterior a done. done y cancelled son finales.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION scm.fn_stock_move_before() RETURNS trigger AS $$
DECLARE v_type text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'draft' THEN
      RAISE EXCEPTION 'MOVE_DELETE_FORBIDDEN: solo se borran movimientos en borrador; cancela o revierte';
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'INSERT' THEN
    SELECT t.product_type INTO v_type FROM scm.product p JOIN scm.product_template t ON t.id = p.template_id
    WHERE p.id = NEW.product_id;
    IF v_type IN ('service','kit') THEN
      RAISE EXCEPTION 'MOVE_PRODUCT_NOT_STOCKABLE: un % no se mueve (los kits se descomponen con fn_kit_components)', v_type;
    END IF;
    IF NEW.status NOT IN ('draft','waiting','confirmed') THEN
      RAISE EXCEPTION 'MOVE_INVALID_INITIAL_STATUS: un movimiento nace en draft, waiting o confirmed';
    END IF;
    NEW.product_qty := scm.fn_to_base_qty(NEW.product_id, NEW.product_uom_qty, NEW.uom_id);
    IF NEW.product_qty <= 0 THEN RAISE EXCEPTION 'MOVE_QTY_ZERO: la cantidad en unidad base es cero'; END IF;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF OLD.status IN ('done','cancelled') THEN
    IF (NEW.product_id, NEW.product_uom_qty, NEW.uom_id, NEW.location_id, NEW.location_dest_id, NEW.status,
        NEW.date_done, NEW.price_unit, NEW.company_id, NEW.picking_id, NEW.origin_move_id)
       IS DISTINCT FROM
       (OLD.product_id, OLD.product_uom_qty, OLD.uom_id, OLD.location_id, OLD.location_dest_id, OLD.status,
        OLD.date_done, OLD.price_unit, OLD.company_id, OLD.picking_id, OLD.origin_move_id) THEN
      RAISE EXCEPTION 'MOVE_DONE_IMMUTABLE: un movimiento % no se edita; se revierte con otro movimiento', OLD.status;
    END IF;
    RETURN NEW;
  END IF;

  IF (NEW.product_id, NEW.location_id, NEW.location_dest_id) IS DISTINCT FROM
     (OLD.product_id, OLD.location_id, OLD.location_dest_id) AND OLD.status <> 'draft' THEN
    RAISE EXCEPTION 'MOVE_LOCKED: producto y ubicaciones solo cambian en borrador';
  END IF;
  IF NEW.product_uom_qty IS DISTINCT FROM OLD.product_uom_qty OR NEW.uom_id IS DISTINCT FROM OLD.uom_id THEN
    IF EXISTS (SELECT 1 FROM scm.stock_move_line WHERE move_id = NEW.id AND status <> 'cancelled') THEN
      RAISE EXCEPTION 'MOVE_QTY_LOCKED: libera las reservas antes de cambiar la cantidad';
    END IF;
    NEW.product_qty := scm.fn_to_base_qty(NEW.product_id, NEW.product_uom_qty, NEW.uom_id);
  END IF;

  IF NEW.status <> OLD.status THEN
    IF (OLD.status, NEW.status) NOT IN (
         ('draft','waiting'), ('draft','confirmed'), ('draft','cancelled'),
         ('waiting','confirmed'), ('waiting','cancelled'),
         ('confirmed','partially_available'), ('confirmed','assigned'), ('confirmed','done'), ('confirmed','cancelled'),
         ('partially_available','confirmed'), ('partially_available','assigned'), ('partially_available','done'),
         ('partially_available','cancelled'),
         ('assigned','confirmed'), ('assigned','partially_available'), ('assigned','done'), ('assigned','cancelled')) THEN
      RAISE EXCEPTION 'MOVE_INVALID_TRANSITION: % → %', OLD.status, NEW.status;
    END IF;
    IF NEW.status = 'done' THEN
      IF EXISTS (SELECT 1 FROM scm.stock_move_line WHERE move_id = NEW.id AND status = 'reserved') THEN
        RAISE EXCEPTION 'MOVE_HAS_RESERVED_LINES: usa fn_done_move';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM scm.stock_move_line WHERE move_id = NEW.id AND status = 'done') THEN
        RAISE EXCEPTION 'MOVE_NO_DONE_LINES: un movimiento hecho necesita líneas hechas';
      END IF;
      NEW.date_done := coalesce(NEW.date_done, now());
    END IF;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_stock_move_before
  BEFORE INSERT OR UPDATE OR DELETE ON stock_move
  FOR EACH ROW EXECUTE FUNCTION scm.fn_stock_move_before();

CREATE OR REPLACE FUNCTION scm.fn_sync_picking(p_picking uuid) RETURNS void AS $$
DECLARE v_status text; v_done timestamptz;
BEGIN
  IF p_picking IS NULL THEN RETURN; END IF;
  SELECT CASE
           WHEN bool_and(status = 'cancelled') THEN 'cancelled'
           WHEN bool_and(status IN ('done','cancelled')) THEN 'done'
           WHEN bool_and(status IN ('assigned','done','cancelled')) THEN 'assigned'
           WHEN bool_or(status IN ('confirmed','partially_available','assigned')) THEN 'confirmed'
           WHEN bool_or(status = 'waiting') THEN 'waiting'
           ELSE 'draft' END,
         max(date_done)
  INTO v_status, v_done
  FROM scm.stock_move WHERE picking_id = p_picking;
  UPDATE scm.picking SET status = v_status, done_at = CASE WHEN v_status = 'done' THEN v_done END
  WHERE id = p_picking AND status IS DISTINCT FROM v_status;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION scm.fn_stock_move_after() RETURNS trigger AS $$
BEGIN
  IF NEW.status = 'done' AND OLD.status <> 'done' THEN
    PERFORM scm.fn_value_move(NEW.id);
  ELSIF NEW.status IN ('cancelled','confirmed') AND OLD.status IN ('partially_available','assigned') THEN
    UPDATE scm.stock_move_line SET status = 'cancelled' WHERE move_id = NEW.id AND status = 'reserved';
  ELSIF NEW.status = 'cancelled' THEN
    UPDATE scm.stock_move_line SET status = 'cancelled' WHERE move_id = NEW.id AND status = 'reserved';
  END IF;
  PERFORM scm.fn_sync_picking(NEW.picking_id);
  RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_stock_move_after
  AFTER UPDATE OF status ON stock_move
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION scm.fn_stock_move_after();

CREATE OR REPLACE FUNCTION scm.fn_move_line_guard() RETURNS trigger AS $$
DECLARE m scm.stock_move; v_tracking text; v_lot_product uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status = 'done' THEN RAISE EXCEPTION 'MOVE_LINE_IMMUTABLE: una línea hecha no se borra'; END IF;
    IF OLD.status = 'reserved' THEN
      PERFORM scm.fn_quant_reserve(OLD.product_id, OLD.location_id, OLD.lot_id, OLD.package_id, OLD.owner_id, -OLD.qty);
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF OLD.status IN ('done','cancelled') THEN
      RAISE EXCEPTION 'MOVE_LINE_IMMUTABLE: una línea % no se edita', OLD.status;
    END IF;
    IF (NEW.qty, NEW.location_id, NEW.location_dest_id, NEW.lot_id, NEW.package_id, NEW.owner_id, NEW.product_id)
       IS DISTINCT FROM
       (OLD.qty, OLD.location_id, OLD.location_dest_id, OLD.lot_id, OLD.package_id, OLD.owner_id, OLD.product_id) THEN
      RAISE EXCEPTION 'MOVE_LINE_RESERVED_LOCKED: cancela la reserva y vuelve a reservar';
    END IF;
    IF NEW.status = 'done' THEN NEW.done_at := coalesce(NEW.done_at, now()); END IF;
    RETURN NEW;
  END IF;

  -- INSERT
  SELECT * INTO m FROM scm.stock_move WHERE id = NEW.move_id;
  IF m.status IN ('done','cancelled') THEN
    RAISE EXCEPTION 'MOVE_CLOSED: el movimiento ya está %', m.status;
  END IF;
  IF NEW.status = 'cancelled' THEN RAISE EXCEPTION 'MOVE_LINE_INVALID_STATUS'; END IF;
  NEW.product_id := m.product_id;
  NEW.location_id := coalesce(NEW.location_id, m.location_id);
  NEW.location_dest_id := coalesce(NEW.location_dest_id, m.location_dest_id);
  IF NOT scm.fn_in_subtree(NEW.location_id, m.location_id)
     OR NOT scm.fn_in_subtree(NEW.location_dest_id, m.location_dest_id) THEN
    RAISE EXCEPTION 'MOVE_LINE_LOCATION_OUTSIDE: la línea debe estar dentro de las ubicaciones del movimiento';
  END IF;
  SELECT t.tracking INTO v_tracking FROM scm.product p JOIN scm.product_template t ON t.id = p.template_id
  WHERE p.id = m.product_id;
  IF NEW.lot_id IS NOT NULL THEN
    SELECT product_id INTO v_lot_product FROM scm.lot WHERE id = NEW.lot_id;
    IF v_lot_product <> m.product_id THEN RAISE EXCEPTION 'LOT_PRODUCT_MISMATCH'; END IF;
  END IF;
  IF v_tracking <> 'none' AND NEW.lot_id IS NULL AND NEW.status = 'done' THEN
    RAISE EXCEPTION 'LOT_REQUIRED: el producto se controla por %; captura el lote al moverlo', v_tracking;
  END IF;
  IF v_tracking = 'serial' AND NEW.qty <> 1 THEN
    RAISE EXCEPTION 'SERIAL_QTY_ONE: cada serie es una unidad';
  END IF;
  IF NEW.status = 'done' THEN NEW.done_at := coalesce(NEW.done_at, now()); END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_move_line_guard
  BEFORE INSERT OR UPDATE OR DELETE ON stock_move_line
  FOR EACH ROW EXECUTE FUNCTION scm.fn_move_line_guard();

CREATE OR REPLACE FUNCTION scm.fn_move_line_after() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'reserved' THEN
      PERFORM scm.fn_quant_reserve(NEW.product_id, NEW.location_id, NEW.lot_id, NEW.package_id, NEW.owner_id, NEW.qty);
    ELSIF NEW.status = 'done' THEN
      PERFORM scm.fn_quant_apply_done(NEW);
    END IF;
  ELSIF TG_OP = 'UPDATE' AND OLD.status = 'reserved' AND NEW.status IN ('done','cancelled') THEN
    PERFORM scm.fn_quant_reserve(OLD.product_id, OLD.location_id, OLD.lot_id, OLD.package_id, OLD.owner_id, -OLD.qty);
    IF NEW.status = 'done' THEN PERFORM scm.fn_quant_apply_done(NEW); END IF;
  END IF;
  RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_move_line_after
  AFTER INSERT OR UPDATE OF status ON stock_move_line
  FOR EACH ROW EXECUTE FUNCTION scm.fn_move_line_after();

-- -----------------------------------------------------------------------------
-- 16.6 Reservas y ejecución [MVP]
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION scm.fn_confirm_move(p_move uuid) RETURNS void AS $$
  UPDATE scm.stock_move SET status = 'confirmed' WHERE id = p_move AND status IN ('draft','waiting');
$$ LANGUAGE sql;

-- Reserva stock concreto según la estrategia de salida (FIFO, FEFO, LIFO, más cercana).
CREATE OR REPLACE FUNCTION scm.fn_reserve_move(p_move uuid) RETURNS numeric AS $$
DECLARE
  m scm.stock_move; v_usage text; v_root text; v_strategy text; v_need numeric; v_take numeric;
  v_total numeric := 0; v_reserved numeric; q record;
BEGIN
  SELECT * INTO m FROM scm.stock_move WHERE id = p_move FOR UPDATE;
  IF m.status NOT IN ('confirmed','partially_available') THEN RETURN 0; END IF;
  SELECT usage, parent_path, removal_strategy INTO v_usage, v_root, v_strategy
  FROM scm.location WHERE id = m.location_id;
  IF v_usage NOT IN ('internal','view') THEN        -- entradas: no hay nada que reservar
    UPDATE scm.stock_move SET status = 'assigned' WHERE id = m.id;
    RETURN 0;
  END IF;
  IF v_strategy IS NULL THEN
    SELECT c.removal_strategy INTO v_strategy FROM scm.product p
    JOIN scm.product_template t ON t.id = p.template_id JOIN scm.product_category c ON c.id = t.category_id
    WHERE p.id = m.product_id;
  END IF;
  SELECT coalesce(sum(qty), 0) INTO v_reserved FROM scm.stock_move_line WHERE move_id = m.id AND status = 'reserved';
  v_need := m.product_qty - v_reserved;

  FOR q IN
    SELECT sq.location_id, sq.lot_id, sq.package_id, sq.quantity - sq.reserved_quantity AS free
    FROM scm.stock_quant sq
    JOIN scm.location l ON l.id = sq.location_id
    LEFT JOIN scm.lot lt ON lt.id = sq.lot_id
    WHERE sq.product_id = m.product_id
      AND l.parent_path LIKE v_root || '%' AND l.usage = 'internal' AND NOT l.is_blocked
      AND sq.owner_id IS NULL
      AND sq.quantity - sq.reserved_quantity > 0
      AND (lt.id IS NULL OR coalesce(lt.removal_date, lt.expiration_date) IS NULL
           OR coalesce(lt.removal_date, lt.expiration_date) > current_date)
    ORDER BY CASE WHEN v_strategy = 'fefo' THEN coalesce(lt.removal_date, lt.expiration_date) END NULLS LAST,
             CASE WHEN v_strategy = 'lifo' THEN sq.in_date END DESC NULLS LAST,
             CASE WHEN v_strategy = 'closest' THEN l.parent_path END,
             sq.in_date, sq.id
    FOR UPDATE OF sq
  LOOP
    EXIT WHEN v_need <= 0;
    v_take := least(v_need, q.free);
    INSERT INTO scm.stock_move_line(move_id, location_id, lot_id, package_id, qty, status)
    VALUES (m.id, q.location_id, q.lot_id, q.package_id, v_take, 'reserved');
    v_need := v_need - v_take;
    v_total := v_total + v_take;
  END LOOP;

  UPDATE scm.stock_move
  SET status = CASE WHEN v_need <= 0 THEN 'assigned'
                    WHEN v_reserved + v_total > 0 THEN 'partially_available'
                    ELSE 'confirmed' END
  WHERE id = m.id AND status IS DISTINCT FROM
        CASE WHEN v_need <= 0 THEN 'assigned' WHEN v_reserved + v_total > 0 THEN 'partially_available' ELSE 'confirmed' END;
  RETURN v_total;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION scm.fn_unreserve_move(p_move uuid) RETURNS void AS $$
  UPDATE scm.stock_move SET status = 'confirmed' WHERE id = p_move AND status IN ('partially_available','assigned');
$$ LANGUAGE sql;

-- Hace un movimiento (completo o parcial). Lo parcial crea un pendiente (backorder) y libera reservas.
CREATE OR REPLACE FUNCTION scm.fn_done_move(p_move uuid, p_qty numeric DEFAULT NULL,
                                            p_done_at timestamptz DEFAULT NULL, p_lot uuid DEFAULT NULL)
RETURNS uuid AS $$
DECLARE m scm.stock_move; v_at timestamptz := coalesce(p_done_at, now()); v_qty numeric; v_res numeric; v_ratio numeric;
BEGIN
  SELECT * INTO m FROM scm.stock_move WHERE id = p_move FOR UPDATE;
  IF m.status = 'done' THEN RETURN m.id; END IF;              -- idempotente
  IF m.status = 'cancelled' THEN RAISE EXCEPTION 'MOVE_CANCELLED'; END IF;
  IF m.status IN ('draft','waiting') THEN PERFORM scm.fn_confirm_move(m.id); END IF;
  v_qty := coalesce(p_qty, m.product_qty);
  IF v_qty <= 0 OR v_qty > m.product_qty THEN
    RAISE EXCEPTION 'MOVE_DONE_QTY_INVALID: % de %', v_qty, m.product_qty;
  END IF;

  IF v_qty < m.product_qty THEN
    PERFORM scm.fn_unreserve_move(m.id);
    v_ratio := m.product_uom_qty / m.product_qty;
    INSERT INTO scm.stock_move(company_id, picking_id, product_id, product_uom_qty, uom_id, location_id,
                               location_dest_id, status, date_planned, price_unit, origin_move_id,
                               purchase_line_id, sale_line_id, reference)
    VALUES (m.company_id, m.picking_id, m.product_id, (m.product_qty - v_qty) * v_ratio, m.uom_id, m.location_id,
            m.location_dest_id, 'confirmed', m.date_planned, m.price_unit, m.origin_move_id,
            m.purchase_line_id, m.sale_line_id, m.reference);
    UPDATE scm.stock_move SET product_uom_qty = v_qty * v_ratio WHERE id = m.id;
  END IF;

  SELECT coalesce(sum(qty), 0) INTO v_res FROM scm.stock_move_line WHERE move_id = m.id AND status = 'reserved';
  UPDATE scm.stock_move_line SET status = 'done', done_at = v_at WHERE move_id = m.id AND status = 'reserved';
  IF v_res < v_qty THEN
    INSERT INTO scm.stock_move_line(move_id, qty, status, done_at, lot_id)
    VALUES (m.id, v_qty - v_res, 'done', v_at, p_lot);
  END IF;
  UPDATE scm.stock_move SET status = 'done', date_done = v_at WHERE id = m.id;
  RETURN m.id;
END $$ LANGUAGE plpgsql;

-- Crea y hace un movimiento en un paso; idempotente por clave externa (patrón 10).
CREATE OR REPLACE FUNCTION scm.fn_quick_move(p_external_key text, p_company uuid, p_product uuid, p_qty numeric,
                                             p_src uuid, p_dest uuid, p_price_unit numeric DEFAULT NULL,
                                             p_done_at timestamptz DEFAULT NULL, p_lot uuid DEFAULT NULL,
                                             p_origin_move uuid DEFAULT NULL, p_uom uuid DEFAULT NULL,
                                             p_picking uuid DEFAULT NULL, p_reference text DEFAULT NULL)
RETURNS uuid AS $$
DECLARE v_id uuid; v_uom uuid;
BEGIN
  IF p_external_key IS NOT NULL THEN
    SELECT id INTO v_id FROM scm.stock_move WHERE external_key = p_external_key;
    IF FOUND THEN RETURN v_id; END IF;
  END IF;
  v_uom := coalesce(p_uom, (SELECT t.uom_id FROM scm.product p JOIN scm.product_template t ON t.id = p.template_id
                             WHERE p.id = p_product));
  INSERT INTO scm.stock_move(company_id, picking_id, product_id, product_uom_qty, uom_id, location_id,
                             location_dest_id, status, price_unit, origin_move_id, external_key, reference,
                             date_planned)
  VALUES (p_company, p_picking, p_product, p_qty, v_uom, p_src, p_dest, 'confirmed', p_price_unit,
          p_origin_move, p_external_key, p_reference, coalesce(p_done_at, now()))
  RETURNING id INTO v_id;
  RETURN scm.fn_done_move(v_id, NULL, p_done_at, p_lot);
END $$ LANGUAGE plpgsql;

-- Componentes de un kit para una cantidad vendida
CREATE OR REPLACE FUNCTION scm.fn_kit_components(p_kit uuid, p_qty numeric)
RETURNS TABLE (product_id uuid, qty numeric) AS $$
  SELECT component_product_id, kl.qty * p_qty FROM scm.product_kit_line kl WHERE kl.kit_product_id = p_kit;
$$ LANGUAGE sql STABLE;

-- -----------------------------------------------------------------------------
-- 16.7 Valorización [MVP]
--   Entrada: costo de compra; devolución de cliente al costo con que salió; ajuste al promedio.
--   Salida: promedio vigente, capas PEPS o estándar. Todas las salidas consumen las capas de
--   entrada en orden PEPS (remaining_qty) para poder repartir después los ajustes de costo.
--   Promedio con stock negativo: la entrada corrige el costo provisional de lo vendido en negativo.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION scm.fn_svl_guard() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'VALUATION_IMMUTABLE: una capa no se borra'; END IF;
  IF TG_OP = 'INSERT' THEN
    PERFORM scm.fn_check_inventory_lock(NEW.company_id, NEW.layer_date);
    RETURN NEW;
  END IF;
  IF (NEW.quantity, NEW.value, NEW.unit_cost, NEW.layer_type, NEW.layer_date, NEW.product_id, NEW.move_id,
      NEW.cogs_amount, NEW.variance_amount)
     IS DISTINCT FROM
     (OLD.quantity, OLD.value, OLD.unit_cost, OLD.layer_type, OLD.layer_date, OLD.product_id, OLD.move_id,
      OLD.cogs_amount, OLD.variance_amount) THEN
    RAISE EXCEPTION 'VALUATION_IMMUTABLE: solo cambia el saldo restante; corrige con una capa nueva';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_svl_guard BEFORE INSERT OR UPDATE OR DELETE ON stock_valuation_layer
  FOR EACH ROW EXECUTE FUNCTION scm.fn_svl_guard();

CREATE OR REPLACE FUNCTION scm.fn_value_move(p_move uuid) RETURNS uuid AS $$
DECLARE
  m scm.stock_move; v_src text; v_dst text; v_in boolean; v_out boolean;
  v_ptype text; v_method text; v_std numeric; v_qty numeric; v_q numeric; v_v numeric; v_last numeric;
  v_unit numeric; v_value numeric; v_variance numeric := 0; v_layer uuid;
  v_cover numeric; v_prov numeric; v_corr numeric; v_left numeric; v_take numeric; v_take_value numeric;
  v_fifo numeric := 0; l record;
BEGIN
  SELECT * INTO m FROM scm.stock_move WHERE id = p_move;
  SELECT usage INTO v_src FROM scm.location WHERE id = m.location_id;
  SELECT usage INTO v_dst FROM scm.location WHERE id = m.location_dest_id;
  v_in  := v_src NOT IN ('internal','transit') AND v_dst IN ('internal','transit');
  v_out := v_src IN ('internal','transit') AND v_dst NOT IN ('internal','transit');
  IF NOT (v_in OR v_out) THEN RETURN NULL; END IF;     -- reubicación: no cambia el valor

  SELECT t.product_type, c.costing_method, p.standard_price INTO v_ptype, v_method, v_std
  FROM scm.product p JOIN scm.product_template t ON t.id = p.template_id
  JOIN scm.product_category c ON c.id = t.category_id WHERE p.id = m.product_id;
  IF v_ptype <> 'storable' THEN RETURN NULL; END IF;  -- los consumibles no se valorizan

  SELECT coalesce(sum(qty), 0) INTO v_qty FROM scm.stock_move_line WHERE move_id = m.id AND status = 'done';
  PERFORM pg_advisory_xact_lock(hashtextextended(m.company_id::text || m.product_id::text, 0));
  SELECT coalesce(sum(quantity), 0), coalesce(sum(value), 0) INTO v_q, v_v
  FROM scm.stock_valuation_layer WHERE company_id = m.company_id AND product_id = m.product_id;
  SELECT unit_cost INTO v_last FROM scm.stock_valuation_layer
  WHERE company_id = m.company_id AND product_id = m.product_id AND layer_type = 'in'
  ORDER BY layer_date DESC, created_at DESC LIMIT 1;
  v_last := coalesce(v_last, nullif(v_std, 0));

  IF v_in THEN
    IF m.origin_move_id IS NOT NULL THEN                 -- devolución: al costo con que salió
      SELECT unit_cost INTO v_unit FROM scm.stock_valuation_layer
      WHERE move_id = m.origin_move_id AND layer_type = 'out';
    END IF;
    IF v_unit IS NULL THEN
      v_unit := CASE WHEN v_method = 'standard' THEN v_std
                     WHEN m.price_unit IS NOT NULL THEN m.price_unit
                     WHEN v_q > 0 THEN round(v_v / v_q, 4)
                     ELSE v_last END;
    END IF;
    IF v_unit IS NULL THEN
      RAISE EXCEPTION 'MOVE_COST_UNKNOWN: la entrada no tiene costo (precio de compra o costo de referencia)';
    END IF;
    v_value := round(v_qty * v_unit, 2);
    IF v_method = 'standard' AND m.price_unit IS NOT NULL AND m.origin_move_id IS NULL THEN
      v_variance := round(v_qty * m.price_unit, 2) - v_value;
    END IF;
    INSERT INTO scm.stock_valuation_layer(company_id, product_id, move_id, layer_date, layer_type, quantity,
                                          unit_cost, value, remaining_qty, remaining_value, variance_amount)
    VALUES (m.company_id, m.product_id, m.id, m.date_done, 'in', v_qty, v_unit, v_value, v_qty, v_value, v_variance)
    RETURNING id INTO v_layer;

    IF v_q < 0 THEN                                     -- había stock negativo
      v_cover := least(-v_q, v_qty);
      UPDATE scm.stock_valuation_layer
      SET remaining_qty = remaining_qty - v_cover, remaining_value = remaining_value - round(v_cover * v_unit, 2)
      WHERE id = v_layer;
      IF v_method = 'average' THEN
        v_prov := v_v / v_q;                            -- costo provisional de lo vendido en negativo
        v_corr := round((v_unit - v_prov) * v_cover, 2);
        IF v_corr <> 0 THEN
          INSERT INTO scm.stock_valuation_layer(company_id, product_id, move_id, layer_date, layer_type,
                                                quantity, value, cogs_amount, parent_layer_id, description)
          VALUES (m.company_id, m.product_id, m.id, m.date_done, 'negative_correction', 0, -v_corr, v_corr,
                  v_layer, 'Corrección del costo provisional de unidades vendidas sin stock');
        END IF;
      END IF;
    END IF;
    RETURN v_layer;
  END IF;

  -- Salida
  IF v_method = 'standard' THEN
    v_value := round(v_qty * v_std, 2);
  ELSIF v_method = 'average' THEN
    IF v_q <= 0 THEN v_value := round(v_qty * coalesce(v_last, 0), 2);
    ELSIF v_qty >= v_q THEN v_value := v_v + round((v_qty - v_q) * (v_v / v_q), 2);  -- se lleva todo el saldo
    ELSE v_value := round(v_qty * v_v / v_q, 2);
    END IF;
  END IF;

  v_left := v_qty;
  FOR l IN
    SELECT id, remaining_qty, remaining_value FROM scm.stock_valuation_layer
    WHERE company_id = m.company_id AND product_id = m.product_id AND layer_type = 'in' AND remaining_qty > 0
    ORDER BY (move_id = m.origin_move_id) DESC NULLS LAST, layer_date, created_at, id
    FOR UPDATE
  LOOP
    EXIT WHEN v_left <= 0;
    v_take := least(v_left, l.remaining_qty);
    v_take_value := CASE WHEN v_take = l.remaining_qty THEN l.remaining_value
                         ELSE round(l.remaining_value * v_take / l.remaining_qty, 2) END;
    UPDATE scm.stock_valuation_layer
    SET remaining_qty = remaining_qty - v_take, remaining_value = remaining_value - v_take_value
    WHERE id = l.id;
    v_fifo := v_fifo + v_take_value;
    v_left := v_left - v_take;
  END LOOP;
  IF v_method = 'fifo' THEN
    v_value := v_fifo + round(v_left * coalesce(v_last, 0), 2);   -- lo que falta (negativo) al último costo
  END IF;

  INSERT INTO scm.stock_valuation_layer(company_id, product_id, move_id, layer_date, layer_type, quantity,
                                        unit_cost, value)
  VALUES (m.company_id, m.product_id, m.id, m.date_done, 'out', -v_qty, round(v_value / v_qty, 4), -v_value)
  RETURNING id INTO v_layer;
  RETURN v_layer;
END $$ LANGUAGE plpgsql;

-- Ajuste de costo de una recepción (diferencia de precio de la factura, flete, arancel).
-- Lo que sigue en stock va al inventario; lo ya vendido, a costo de ventas. Con estándar, todo a variación.
CREATE OR REPLACE FUNCTION scm.fn_add_cost_adjustment(p_move uuid, p_amount numeric, p_type text,
                                                      p_landed_cost uuid DEFAULT NULL,
                                                      p_date timestamptz DEFAULT now())
RETURNS uuid AS $$
DECLARE l scm.stock_valuation_layer; v_method text; v_inv numeric; v_cogs numeric; v_var numeric := 0; v_id uuid;
BEGIN
  IF p_type NOT IN ('landed_cost','price_diff') THEN RAISE EXCEPTION 'COST_ADJUSTMENT_TYPE: %', p_type; END IF;
  SELECT * INTO l FROM scm.stock_valuation_layer WHERE move_id = p_move AND layer_type = 'in' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'COST_ADJUSTMENT_NO_RECEIPT: el movimiento no es una entrada valorizada'; END IF;
  SELECT c.costing_method INTO v_method FROM scm.product p JOIN scm.product_template t ON t.id = p.template_id
  JOIN scm.product_category c ON c.id = t.category_id WHERE p.id = l.product_id;
  IF v_method = 'standard' THEN
    v_inv := 0; v_cogs := 0; v_var := p_amount;
  ELSE
    v_inv := round(p_amount * l.remaining_qty / l.quantity, 2);
    v_cogs := p_amount - v_inv;
  END IF;
  INSERT INTO scm.stock_valuation_layer(company_id, product_id, move_id, layer_date, layer_type, quantity, value,
                                        cogs_amount, variance_amount, parent_layer_id, landed_cost_id)
  VALUES (l.company_id, l.product_id, p_move, p_date, p_type, 0, v_inv, v_cogs, v_var, l.id, p_landed_cost)
  RETURNING id INTO v_id;
  IF v_method = 'fifo' THEN
    UPDATE scm.stock_valuation_layer SET remaining_value = remaining_value + v_inv WHERE id = l.id;
  END IF;
  RETURN v_id;
END $$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- 16.8 Costos de importación [F2]
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION scm.fn_compute_landed_cost(p_lc uuid) RETURNS void AS $$
DECLARE ln record; v_total numeric; v_acc numeric; r record; v_n int; v_i int;
BEGIN
  DELETE FROM scm.landed_cost_allocation a USING scm.landed_cost_line l
  WHERE a.landed_cost_line_id = l.id AND l.landed_cost_id = p_lc;
  FOR ln IN SELECT * FROM scm.landed_cost_line WHERE landed_cost_id = p_lc LOOP
    CREATE TEMP TABLE IF NOT EXISTS _lc_basis (move_id uuid, w numeric) ON COMMIT DROP;
    TRUNCATE _lc_basis;
    INSERT INTO _lc_basis
    SELECT m.id,
           CASE ln.split_method
             WHEN 'equal'       THEN 1
             WHEN 'by_quantity' THEN m.product_qty
             WHEN 'by_value'    THEN svl.value
             WHEN 'by_weight'   THEN m.product_qty * coalesce(p.weight_kg, 0)
             WHEN 'by_volume'   THEN m.product_qty * coalesce(p.volume_m3, 0) END
    FROM scm.landed_cost_picking lp
    JOIN scm.stock_move m ON m.picking_id = lp.picking_id AND m.status = 'done'
    JOIN scm.stock_valuation_layer svl ON svl.move_id = m.id AND svl.layer_type = 'in'
    JOIN scm.product p ON p.id = m.product_id
    WHERE lp.landed_cost_id = p_lc;
    SELECT sum(w), count(*) INTO v_total, v_n FROM _lc_basis;
    IF coalesce(v_total, 0) = 0 THEN
      RAISE EXCEPTION 'LANDED_COST_NO_BASIS: no hay base para repartir «%» por %', ln.description, ln.split_method;
    END IF;
    v_acc := 0; v_i := 0;
    FOR r IN SELECT * FROM _lc_basis ORDER BY move_id LOOP
      v_i := v_i + 1;
      INSERT INTO scm.landed_cost_allocation(landed_cost_line_id, move_id, amount)
      VALUES (ln.id, r.move_id,
              CASE WHEN v_i = v_n THEN ln.amount - v_acc ELSE round(ln.amount * r.w / v_total, 2) END);
      v_acc := v_acc + round(ln.amount * r.w / v_total, 2);
    END LOOP;
  END LOOP;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION scm.fn_post_landed_cost(p_lc uuid) RETURNS void AS $$
DECLARE c scm.landed_cost; r record;
BEGIN
  SELECT * INTO c FROM scm.landed_cost WHERE id = p_lc FOR UPDATE;
  IF c.status <> 'draft' THEN RAISE EXCEPTION 'LANDED_COST_NOT_DRAFT'; END IF;
  PERFORM scm.fn_compute_landed_cost(p_lc);
  FOR r IN SELECT a.move_id, sum(a.amount) amount
           FROM scm.landed_cost_allocation a JOIN scm.landed_cost_line l ON l.id = a.landed_cost_line_id
           WHERE l.landed_cost_id = p_lc GROUP BY a.move_id LOOP
    PERFORM scm.fn_add_cost_adjustment(r.move_id, r.amount, 'landed_cost', p_lc, c.cost_date);
  END LOOP;
  UPDATE scm.landed_cost SET status = 'posted', posted_at = now() WHERE id = p_lc;
END $$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- 16.9 Conteos [MVP]
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION scm.fn_start_count(p_count uuid) RETURNS void AS $$
BEGIN
  UPDATE scm.stock_count_line cl
  SET expected_qty = coalesce((SELECT sum(q.quantity) FROM scm.stock_quant q
                               WHERE q.product_id = cl.product_id AND q.location_id = cl.location_id
                                 AND q.lot_id IS NOT DISTINCT FROM cl.lot_id AND q.owner_id IS NULL), 0),
      snapshot_at = clock_timestamp()
  WHERE cl.count_id = p_count AND cl.snapshot_at IS NULL;
  UPDATE scm.stock_count SET status = 'in_progress', started_at = coalesce(started_at, now())
  WHERE id = p_count AND status = 'draft';
END $$ LANGUAGE plpgsql;

-- Diferencia = contado − (foto + movimientos hechos después de la foto). Idempotente por línea.
CREATE OR REPLACE FUNCTION scm.fn_apply_count(p_count uuid) RETURNS int AS $$
DECLARE c scm.stock_count; cl record; v_after numeric; v_diff numeric; v_move uuid; v_n int := 0;
BEGIN
  SELECT * INTO c FROM scm.stock_count WHERE id = p_count FOR UPDATE;
  IF c.status <> 'in_progress' THEN RAISE EXCEPTION 'COUNT_NOT_IN_PROGRESS'; END IF;
  FOR cl IN SELECT * FROM scm.stock_count_line WHERE count_id = p_count AND counted_qty IS NOT NULL LOOP
    SELECT coalesce(sum(CASE WHEN l.location_dest_id = cl.location_id THEN l.qty ELSE -l.qty END), 0) INTO v_after
    FROM scm.stock_move_line l
    WHERE l.status = 'done' AND l.product_id = cl.product_id AND l.lot_id IS NOT DISTINCT FROM cl.lot_id
      AND l.done_at > cl.snapshot_at AND cl.location_id IN (l.location_id, l.location_dest_id)
      AND l.move_id IS DISTINCT FROM cl.adjustment_move_id;
    v_diff := cl.counted_qty - (cl.expected_qty + v_after);
    IF v_diff <> 0 THEN
      v_move := scm.fn_quick_move('count:' || cl.id, c.company_id, cl.product_id, abs(v_diff),
                                  CASE WHEN v_diff > 0 THEN scm.fn_vloc('inventory') ELSE cl.location_id END,
                                  CASE WHEN v_diff > 0 THEN cl.location_id ELSE scm.fn_vloc('inventory') END,
                                  NULL, NULL, cl.lot_id, NULL, NULL, NULL, c.name);
      v_n := v_n + 1;
    END IF;
    UPDATE scm.stock_count_line SET difference_qty = v_diff, adjustment_move_id = v_move WHERE id = cl.id;
    v_move := NULL;
  END LOOP;
  UPDATE scm.stock_count SET status = 'done', applied_at = now() WHERE id = p_count;
  RETURN v_n;
END $$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- 16.10 Compras [MVP]
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION scm.fn_purchase_order_guard() RETURNS trigger AS $$
DECLARE v_limit numeric; v_total numeric;
BEGIN
  IF NEW.status = 'purchase' AND OLD.status <> 'purchase' THEN
    SELECT (value #>> '{}')::numeric INTO v_limit FROM scm.scm_setting WHERE code = 'PO_APPROVAL_AMOUNT';
    SELECT coalesce(sum(qty * price_unit), 0) INTO v_total FROM scm.purchase_order_line WHERE order_id = NEW.id;
    IF v_limit IS NOT NULL AND v_total >= v_limit THEN
      IF NEW.approved_by IS NULL THEN
        RAISE EXCEPTION 'PO_APPROVAL_REQUIRED: la orden de % supera el límite de %', v_total, v_limit;
      END IF;
      IF NEW.approved_by = OLD.created_by THEN
        RAISE EXCEPTION 'PO_SELF_APPROVAL: quien crea la orden no la aprueba';
      END IF;
      NEW.approved_at := now();
    END IF;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_purchase_order_guard BEFORE UPDATE OF status ON purchase_order
  FOR EACH ROW EXECUTE FUNCTION scm.fn_purchase_order_guard();

-- Crea la recepción de una OC aprobada: un movimiento por línea, con el costo por unidad base.
CREATE OR REPLACE FUNCTION scm.fn_create_receipt(p_po uuid) RETURNS uuid AS $$
DECLARE po scm.purchase_order; w scm.warehouse; v_type uuid; v_pick uuid;
BEGIN
  SELECT * INTO po FROM scm.purchase_order WHERE id = p_po;
  IF po.status <> 'purchase' THEN RAISE EXCEPTION 'PO_NOT_CONFIRMED: la orden no está aprobada'; END IF;
  SELECT * INTO w FROM scm.warehouse WHERE id = po.warehouse_id;
  SELECT id INTO v_type FROM scm.picking_type WHERE warehouse_id = w.id AND code = 'incoming';
  INSERT INTO scm.picking(company_id, picking_type_id, partner_id, origin_type, origin_ref, external_key,
                          location_id, location_dest_id, status)
  VALUES (po.company_id, v_type, po.partner_id, 'purchase', po.name, 'po:' || po.id,
          scm.fn_vloc('supplier'), CASE WHEN w.reception_steps = 1 THEN w.stock_location_id ELSE w.input_location_id END,
          'confirmed')
  RETURNING id INTO v_pick;
  INSERT INTO scm.stock_move(company_id, picking_id, product_id, product_uom_qty, uom_id, location_id,
                             location_dest_id, status, price_unit, purchase_line_id, reference)
  SELECT po.company_id, v_pick, l.product_id, l.qty, l.uom_id, scm.fn_vloc('supplier'),
         CASE WHEN w.reception_steps = 1 THEN w.stock_location_id ELSE w.input_location_id END, 'confirmed',
         round(l.price_unit * l.qty / scm.fn_to_base_qty(l.product_id, l.qty, l.uom_id), 4), l.id, po.name
  FROM scm.purchase_order_line l WHERE l.order_id = po.id;
  PERFORM scm.fn_sync_picking(v_pick);
  RETURN v_pick;
END $$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- 16.11 Asientos de inventario [F2]: cada capa genera su asiento; débito positivo, crédito negativo
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION scm.fn_journal_line(p_entry uuid, p_account text, p_amount numeric) RETURNS void AS $$
BEGIN
  IF coalesce(p_amount, 0) = 0 THEN RETURN; END IF;
  IF p_account IS NULL THEN RAISE EXCEPTION 'ACCOUNT_MISSING: falta una cuenta en la categoría del producto'; END IF;
  INSERT INTO scm.stock_journal_line(entry_id, account_code, debit, credit)
  VALUES (p_entry, p_account, greatest(p_amount, 0), greatest(-p_amount, 0));
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION scm.fn_journal_for_layer() RETURNS trigger AS $$
DECLARE c scm.product_category; v_src text; v_dst text; v_entry uuid; v_counter text;
BEGIN
  SELECT pc.* INTO c FROM scm.product p JOIN scm.product_template t ON t.id = p.template_id
  JOIN scm.product_category pc ON pc.id = t.category_id WHERE p.id = NEW.product_id;
  IF c.account_inventory IS NULL THEN RETURN NULL; END IF;     -- contabilidad desactivada
  SELECT ls.usage, ld.usage INTO v_src, v_dst FROM scm.stock_move m
  JOIN scm.location ls ON ls.id = m.location_id JOIN scm.location ld ON ld.id = m.location_dest_id
  WHERE m.id = NEW.move_id;

  INSERT INTO scm.stock_journal_entry(company_id, entry_date, layer_id, description)
  VALUES (NEW.company_id, NEW.layer_date, NEW.id, NEW.layer_type) RETURNING id INTO v_entry;
  PERFORM scm.fn_journal_line(v_entry, c.account_inventory, NEW.value);

  IF NEW.layer_type IN ('in','out') THEN
    v_counter := CASE CASE WHEN NEW.layer_type = 'in' THEN v_src ELSE v_dst END
                   WHEN 'supplier'     THEN c.account_stock_input
                   WHEN 'customer'     THEN c.account_cogs
                   WHEN 'scrap'        THEN c.account_scrap
                   WHEN 'internal_use' THEN c.account_internal_use
                   ELSE c.account_adjustment END;
    PERFORM scm.fn_journal_line(v_entry, c.account_price_diff, NEW.variance_amount);
    PERFORM scm.fn_journal_line(v_entry, v_counter, -(NEW.value + NEW.variance_amount));
  ELSE
    PERFORM scm.fn_journal_line(v_entry, c.account_cogs, NEW.cogs_amount);
    PERFORM scm.fn_journal_line(v_entry, c.account_price_diff, NEW.variance_amount);
    IF NEW.layer_type <> 'negative_correction' THEN
      PERFORM scm.fn_journal_line(v_entry, c.account_stock_input, -(NEW.value + NEW.cogs_amount + NEW.variance_amount));
    END IF;
  END IF;
  RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_journal_for_layer AFTER INSERT ON stock_valuation_layer
  FOR EACH ROW EXECUTE FUNCTION scm.fn_journal_for_layer();

-- =============================================================================
-- 15. VISTAS
-- =============================================================================

-- Físico, reservado, disponible, entrante, saliente, proyectado y prometible por almacén (patrón 3)
CREATE OR REPLACE VIEW v_stock_availability AS
WITH wl AS (
  SELECT w.id AS warehouse_id, l.id AS location_id, l.usage, l.is_blocked
  FROM scm.warehouse w JOIN scm.location v ON v.id = w.view_location_id
  JOIN scm.location l ON l.parent_path LIKE v.parent_path || '%'
), q AS (
  SELECT wl.warehouse_id, sq.product_id, sum(sq.quantity) AS on_hand, sum(sq.reserved_quantity) AS reserved
  FROM scm.stock_quant sq JOIN wl ON wl.location_id = sq.location_id
  WHERE wl.usage = 'internal' AND NOT wl.is_blocked AND sq.owner_id IS NULL
  GROUP BY 1, 2
), mv AS (
  SELECT d.warehouse_id, m.product_id, m.product_qty AS incoming, 0::numeric AS outgoing
  FROM scm.stock_move m JOIN wl d ON d.location_id = m.location_dest_id
  LEFT JOIN wl s ON s.location_id = m.location_id AND s.warehouse_id = d.warehouse_id
  WHERE m.status IN ('waiting','confirmed','partially_available','assigned') AND s.location_id IS NULL
  UNION ALL
  SELECT s.warehouse_id, m.product_id, 0, m.product_qty
  FROM scm.stock_move m JOIN wl s ON s.location_id = m.location_id
  LEFT JOIN wl d ON d.location_id = m.location_dest_id AND d.warehouse_id = s.warehouse_id
  WHERE m.status IN ('waiting','confirmed','partially_available','assigned') AND d.location_id IS NULL
), mvs AS (
  SELECT warehouse_id, product_id, sum(incoming) AS incoming, sum(outgoing) AS outgoing FROM mv GROUP BY 1, 2
)
SELECT coalesce(q.warehouse_id, mvs.warehouse_id) AS warehouse_id,
       coalesce(q.product_id, mvs.product_id) AS product_id,
       coalesce(q.on_hand, 0) AS on_hand,
       coalesce(q.reserved, 0) AS reserved,
       coalesce(q.on_hand, 0) - coalesce(q.reserved, 0) AS available,
       coalesce(mvs.incoming, 0) AS incoming,
       coalesce(mvs.outgoing, 0) AS outgoing,
       coalesce(q.on_hand, 0) + coalesce(mvs.incoming, 0) - coalesce(mvs.outgoing, 0) AS forecast,
       coalesce(q.on_hand, 0) - coalesce(mvs.outgoing, 0) AS atp_now
FROM q FULL JOIN mvs ON mvs.warehouse_id = q.warehouse_id AND mvs.product_id = q.product_id;

-- Disponibilidad de kits: mínimo entre componentes
CREATE OR REPLACE VIEW v_kit_availability AS
SELECT a.warehouse_id, k.kit_product_id AS product_id, min(floor(greatest(a.available, 0) / k.qty)) AS available
FROM scm.product_kit_line k JOIN scm.v_stock_availability a ON a.product_id = k.component_product_id
GROUP BY a.warehouse_id, k.kit_product_id
HAVING count(*) = (SELECT count(*) FROM scm.product_kit_line k2 WHERE k2.kit_product_id = k.kit_product_id);

-- Kardex valorizado (formato 13.1 en Perú: ver localizacion/peru.md)
CREATE OR REPLACE VIEW v_kardex AS
SELECT l.company_id, l.product_id, l.layer_date, coalesce(pk.name, m.reference) AS document, l.layer_type,
       CASE WHEN l.quantity > 0 THEN l.quantity END AS qty_in,
       CASE WHEN l.quantity > 0 THEN l.unit_cost END AS unit_cost_in,
       CASE WHEN l.value > 0 THEN l.value END AS value_in,
       CASE WHEN l.quantity < 0 THEN -l.quantity END AS qty_out,
       CASE WHEN l.quantity < 0 THEN l.unit_cost END AS unit_cost_out,
       CASE WHEN l.value < 0 THEN -l.value END AS value_out,
       sum(l.quantity) OVER w AS balance_qty,
       sum(l.value) OVER w AS balance_value,
       round(sum(l.value) OVER w / nullif(sum(l.quantity) OVER w, 0), 4) AS balance_unit_cost
FROM scm.stock_valuation_layer l
LEFT JOIN scm.stock_move m ON m.id = l.move_id
LEFT JOIN scm.picking pk ON pk.id = m.picking_id
WINDOW w AS (PARTITION BY l.company_id, l.product_id ORDER BY l.layer_date, l.created_at, l.id);

CREATE OR REPLACE VIEW v_inventory_valuation AS
SELECT company_id, product_id, sum(quantity) AS quantity, sum(value) AS value,
       round(sum(value) / nullif(sum(quantity), 0), 4) AS unit_cost
FROM scm.stock_valuation_layer GROUP BY company_id, product_id;

-- Cierre: el valor de las capas debe ser igual al saldo contable de las cuentas de inventario
CREATE OR REPLACE VIEW v_valuation_check AS
WITH layers AS (
  SELECT company_id, sum(value) AS layers_value FROM scm.stock_valuation_layer GROUP BY company_id
), ledger AS (
  SELECT e.company_id, sum(jl.debit - jl.credit) AS ledger_value
  FROM scm.stock_journal_line jl JOIN scm.stock_journal_entry e ON e.id = jl.entry_id
  WHERE jl.account_code IN (SELECT account_inventory FROM scm.product_category WHERE account_inventory IS NOT NULL)
  GROUP BY e.company_id
)
SELECT l.company_id, l.layers_value, coalesce(g.ledger_value, 0) AS ledger_value,
       l.layers_value - coalesce(g.ledger_value, 0) AS difference
FROM layers l LEFT JOIN ledger g ON g.company_id = l.company_id;

CREATE OR REPLACE VIEW v_journal_unbalanced AS
SELECT entry_id, sum(debit) AS debit, sum(credit) AS credit
FROM scm.stock_journal_line GROUP BY entry_id HAVING sum(debit) <> sum(credit);

-- Partida doble de cantidades: por producto, la suma de todas las ubicaciones es cero
CREATE OR REPLACE VIEW v_quant_zero_sum AS
SELECT product_id, sum(quantity) AS total FROM scm.stock_quant GROUP BY product_id HAVING sum(quantity) <> 0;

-- Venta de mostrador sobre stock reservado: aviso, no error
CREATE OR REPLACE VIEW v_quant_over_reserved AS
SELECT * FROM scm.stock_quant WHERE reserved_quantity > greatest(quantity, 0);

CREATE OR REPLACE VIEW v_lot_expiry AS
SELECT q.product_id, q.lot_id, lt.name AS lot, sum(q.quantity) AS quantity, lt.expiration_date, lt.removal_date,
       CASE WHEN lt.expiration_date <= current_date THEN 'expired'
            WHEN lt.removal_date <= current_date THEN 'remove'
            WHEN lt.alert_date <= current_date THEN 'alert'
            ELSE 'ok' END AS status
FROM scm.stock_quant q JOIN scm.lot lt ON lt.id = q.lot_id JOIN scm.location l ON l.id = q.location_id
WHERE l.usage = 'internal'
GROUP BY q.product_id, q.lot_id, lt.name, lt.expiration_date, lt.removal_date, lt.alert_date
HAVING sum(q.quantity) <> 0;

-- Series con cantidad distinta de 0 o 1 en stock interno (vendidas dos veces, duplicadas)
CREATE OR REPLACE VIEW v_serial_anomalies AS
SELECT q.product_id, q.lot_id, sum(q.quantity) AS quantity
FROM scm.stock_quant q JOIN scm.location l ON l.id = q.location_id
JOIN scm.product p ON p.id = q.product_id JOIN scm.product_template t ON t.id = p.template_id
WHERE t.tracking = 'serial' AND l.usage = 'internal'
GROUP BY q.product_id, q.lot_id HAVING sum(q.quantity) NOT IN (0, 1);

-- Sugerencia de reposición: sobre la posición (proyectado), no sobre el físico
CREATE OR REPLACE VIEW v_replenishment_suggestion AS
SELECT r.warehouse_id, r.product_id, r.min_qty, r.max_qty, coalesce(a.forecast, 0) AS position,
       greatest(ceil((r.max_qty - coalesce(a.forecast, 0)) / r.multiple_qty) * r.multiple_qty,
                coalesce(si.min_qty, 0)) AS suggested_qty,
       coalesce(r.partner_id, si.partner_id) AS partner_id
FROM scm.replenishment_rule r
LEFT JOIN scm.v_stock_availability a ON a.warehouse_id = r.warehouse_id AND a.product_id = r.product_id
LEFT JOIN LATERAL (
  SELECT s.partner_id, s.min_qty FROM scm.supplier_info s
  WHERE s.product_id = r.product_id AND s.valid_from <= current_date AND (s.valid_to IS NULL OR s.valid_to > current_date)
  ORDER BY (s.partner_id = r.partner_id) DESC NULLS LAST, s.priority LIMIT 1) si ON true
WHERE r.is_active AND coalesce(a.forecast, 0) <= r.min_qty;

-- Conciliación de tres vías por línea de compra (cantidades en la unidad de compra)
CREATE OR REPLACE VIEW v_three_way_match AS
WITH rec AS (
  SELECT purchase_line_id, sum(product_qty) AS received_base FROM scm.stock_move
  WHERE status = 'done' AND purchase_line_id IS NOT NULL GROUP BY 1
), bil AS (
  SELECT bl.purchase_line_id, sum(bl.qty) AS billed_qty, max(bl.price_unit) AS billed_price
  FROM scm.vendor_bill_line bl JOIN scm.vendor_bill b ON b.id = bl.bill_id
  WHERE b.status <> 'cancelled' AND bl.purchase_line_id IS NOT NULL GROUP BY 1
), tol AS (
  SELECT (SELECT (value #>> '{}')::numeric FROM scm.scm_setting WHERE code = 'BILL_PRICE_TOLERANCE_PCT') AS price_pct,
         (SELECT (value #>> '{}')::numeric FROM scm.scm_setting WHERE code = 'RECEIPT_QTY_TOLERANCE_PCT') AS qty_pct
), base AS (
  SELECT l.id AS purchase_line_id, l.order_id, l.product_id, l.qty AS ordered_qty, l.price_unit AS po_price,
         round(coalesce(rec.received_base, 0) * l.qty / scm.fn_to_base_qty(l.product_id, l.qty, l.uom_id), 4) AS received_qty,
         coalesce(bil.billed_qty, 0) AS billed_qty, bil.billed_price
  FROM scm.purchase_order_line l LEFT JOIN rec ON rec.purchase_line_id = l.id
  LEFT JOIN bil ON bil.purchase_line_id = l.id
)
SELECT b.*,
       CASE WHEN b.received_qty = 0 THEN 'not_received'
            WHEN b.billed_qty = 0 THEN 'not_billed'
            WHEN abs(b.billed_qty - b.received_qty) > b.received_qty * coalesce(t.qty_pct, 0) / 100 THEN 'qty_mismatch'
            WHEN abs(b.billed_price - b.po_price) > b.po_price * coalesce(t.price_pct, 0) / 100 THEN 'price_mismatch'
            ELSE 'ok' END AS match_status
FROM base b CROSS JOIN tol t;
