-- =============================================================================
-- MÓDULO PUNTO DE VENTA (POS) – ERP MULTITENANT (DB POR TENANT) – PostgreSQL 15+
-- Esquema de referencia del servidor: tiendas, cajas, catálogo de venta, impuestos, precios,
-- promociones, sesiones de caja, ventas, pagos, comprobantes, devoluciones y efectos de stock.
-- =============================================================================
-- Decisiones de diseño:
--  * DB por tenant => NO hay columna tenant_id. Un tenant puede tener varias empresas.
--  * Un schema `pos`. PK uuid. Las ventas, pagos y movimientos de caja llevan el UUID que genera
--    la caja: el servidor inserta o ignora por ese id (patrón 2, idempotencia).
--  * La caja vende sin red (patrón 1): calcula precio, promoción e impuesto con sus datos locales;
--    el servidor guarda el resultado y lo valida (totales, pagos, devoluciones). Una venta cobrada
--    nunca se rechaza: si llega tarde, se acepta y se registra la excepción.
--  * Día de negocio, fecha del hecho y fecha de recepción son columnas distintas (patrón 3).
--  * La línea guarda precio de lista, descuentos, base e impuestos (patrón 4).
--  * El comprobante es un documento emitido con serie por caja y correlativo sin huecos
--    (patrones 5 y 8); se corrige con notas, no se edita.
--  * El POS no es dueño del stock (patrón 10): publica efectos de stock para el módulo de
--    inventario y guarda una réplica del saldo para mostrarlo.
--  * Saldos de tarjetas de regalo y crédito de clientes = libro mayor (patrón 11).
--  * Impuestos por categoría de afectación; tasas con vigencia por país o por empresa (patrón 12).
--  * Columnas de auditoría y triggers se añaden al final a todas las tablas (sección 14).
--  * Tablas marcadas [MVP] (primera tienda real) o [F2] (fase 2).
--
-- Variables de sesión (SET LOCAL en cada transacción de la app):
--   app.user_id   usuario (auditoría, aprobaciones, cierres)
--   app.reason    motivo (reabrir una sesión en cierre)
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE SCHEMA IF NOT EXISTS pos;
SET search_path = pos, public;

-- =============================================================================
-- 0. PLATAFORMA Y CATÁLOGOS GENÉRICOS
--    Tipos sugeridos: NOTE_REASON (motivo de nota de crédito), VOID_REASON, CASH_MOVEMENT_REASON,
--    RETURN_REASON, OVERRIDE_REASON
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

CREATE TABLE pos_setting (                -- [MVP] políticas del tenant (capa Tenant)
  code        text PRIMARY KEY,
  value       jsonb NOT NULL,
  description text
);
INSERT INTO pos_setting(code, value, description) VALUES
  ('CASH_DIFF_TOLERANCE',      '1.00', 'Diferencia de cierre que se aprueba sola (por medio de pago)'),
  ('REQUIRE_FISCAL_DOCUMENT',  'true', 'Una venta solo termina con comprobante emitido'),
  ('SALES_ACCOUNT',            'null', 'Cuenta de ventas para el asiento de la sesión'),
  ('CASH_ROUNDING_ACCOUNT',    'null', 'Gasto por redondeo de efectivo a favor del cliente'),
  ('CASH_SHORTAGE_ACCOUNT',    'null', 'Faltantes de caja'),
  ('CASH_OVERAGE_ACCOUNT',     'null', 'Sobrantes de caja'),
  ('PETTY_CASH_ACCOUNT',       'null', 'Gastos pagados con caja chica'),
  ('SAFE_ACCOUNT',             'null', 'Bóveda de la tienda (retiros parciales e ingresos de sencillo)');

CREATE TABLE legal_parameter (            -- [MVP] valores legales con vigencia (capa Localización)
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  country_code char(2) NOT NULL,
  code         text NOT NULL,               -- BOLETA_ID_THRESHOLD, FACTURA_SEND_DAYS, BOLETA_SEND_DAYS…
  name         text NOT NULL,
  value        numeric(14,4) NOT NULL,
  valid_from   date NOT NULL,
  valid_to     date,
  source_ref   text,
  CHECK (valid_to IS NULL OR valid_to > valid_from),
  EXCLUDE USING gist (country_code WITH =, code WITH =, daterange(valid_from, valid_to) WITH &&)
);

CREATE SEQUENCE catalog_version_seq;      -- versión de los maestros que sincroniza la caja

-- =============================================================================
-- 1. ESTRUCTURA: EMPRESA, TIENDAS, CAJAS, SERIES, USUARIOS
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

CREATE TABLE establishment (              -- [MVP] establecimiento declarado ante la autoridad fiscal
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid NOT NULL REFERENCES company(id),
  code          text NOT NULL,            -- Perú: código de establecimiento anexo
  name          text NOT NULL,
  address_line  text,
  ubigeo        text,
  UNIQUE (company_id, code)
);

CREATE TABLE store (                      -- [MVP] tienda
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id           uuid NOT NULL REFERENCES company(id),
  establishment_id     uuid NOT NULL REFERENCES establishment(id),
  code                 text NOT NULL,
  name                 text NOT NULL,
  timezone             text NOT NULL DEFAULT 'UTC',
  business_day_start   time NOT NULL DEFAULT '05:00',   -- antes de esta hora, la venta es del día anterior
  default_pricelist_id uuid,                -- FK diferida
  inventory_ref        text,                -- almacén o ubicación en el módulo de inventario
  is_active            boolean NOT NULL DEFAULT true,
  UNIQUE (company_id, code)
);

CREATE TABLE pos_terminal (               -- [MVP] caja registrada
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id           uuid NOT NULL REFERENCES store(id),
  code               text NOT NULL,
  name               text NOT NULL,
  device_token_hash  text,                -- token propio del equipo; se revoca si lo roban
  status             text NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked')),
  registered_at      timestamptz NOT NULL DEFAULT now(),
  revoked_at         timestamptz,
  last_seen_at       timestamptz,
  last_sync_version  bigint,              -- última versión de maestros recibida
  hardware           jsonb NOT NULL DEFAULT '{}',   -- impresora, gaveta, balanza, pinpad
  UNIQUE (store_id, code)
);

CREATE TABLE document_series (            -- [MVP] serie de comprobantes, normalmente una por caja y tipo
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        uuid NOT NULL REFERENCES company(id),
  terminal_id       uuid REFERENCES pos_terminal(id),   -- NULL = serie del servicio central
  doc_type          text NOT NULL CHECK (doc_type IN ('01','03','07','08')),  -- factura, boleta, NC, ND
  series            text NOT NULL,
  next_number       bigint NOT NULL DEFAULT 1 CHECK (next_number > 0),
  last_used_number  bigint NOT NULL DEFAULT 0,
  is_active         boolean NOT NULL DEFAULT true,
  UNIQUE (company_id, doc_type, series)
);
CREATE UNIQUE INDEX uq_series_terminal_type ON document_series (terminal_id, doc_type, left(series, 1))
  WHERE terminal_id IS NOT NULL AND is_active;

CREATE TABLE pos_user (                   -- [MVP] cajeros y supervisores
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code       text NOT NULL UNIQUE,        -- el que se usa en app.user_id
  name       text NOT NULL,
  pin_hash   text,
  role       text NOT NULL DEFAULT 'cashier' CHECK (role IN ('cashier','supervisor','manager','admin')),
  is_active  boolean NOT NULL DEFAULT true
);

CREATE TABLE pos_role_limit (             -- [MVP] topes por rol; sobre el tope, autorización
  role                       text PRIMARY KEY CHECK (role IN ('cashier','supervisor','manager','admin')),
  max_discount_pct           numeric(5,2) NOT NULL DEFAULT 0,
  can_refund_without_ticket  boolean NOT NULL DEFAULT false,
  can_void_paid              boolean NOT NULL DEFAULT false,
  can_open_drawer            boolean NOT NULL DEFAULT false
);
INSERT INTO pos_role_limit VALUES ('cashier', 5, false, false, false), ('supervisor', 30, true, true, true),
                                  ('manager', 100, true, true, true), ('admin', 100, true, true, true);

-- =============================================================================
-- 2. CATÁLOGO DE VENTA
-- =============================================================================
CREATE TABLE product_category (           -- [MVP]
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id    uuid REFERENCES product_category(id),
  name         text NOT NULL,
  row_version  bigint
);

CREATE TABLE uom (                        -- [MVP]
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code      text NOT NULL UNIQUE,         -- código de la autoridad (NIU, KGM…)
  name      text NOT NULL,
  decimals  int NOT NULL DEFAULT 0 CHECK (decimals BETWEEN 0 AND 4)
);

CREATE TABLE tax_category (               -- [MVP] categoría de afectación (Perú: catálogo 07)
  code     text PRIMARY KEY,
  name     text NOT NULL,
  kind     text NOT NULL CHECK (kind IN ('taxable','exempt','unaffected','export')),
  is_free  boolean NOT NULL DEFAULT false -- transferencia gratuita: se informa, no se cobra
);

CREATE TABLE product (                    -- [MVP] lo que se vende
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sku                text NOT NULL UNIQUE,
  name               text NOT NULL,
  category_id        uuid REFERENCES product_category(id),
  uom_id             uuid NOT NULL REFERENCES uom(id),
  product_type       text NOT NULL DEFAULT 'stockable'
                     CHECK (product_type IN ('stockable','consumable','service','kit','gift_card')),
  tax_category_code  text NOT NULL REFERENCES tax_category(code),
  track_serial       boolean NOT NULL DEFAULT false,
  sold_by_weight     boolean NOT NULL DEFAULT false,
  age_restricted     boolean NOT NULL DEFAULT false,
  inventory_ref      text,                -- id del producto en el módulo de inventario
  is_active          boolean NOT NULL DEFAULT true,
  row_version        bigint
);

CREATE TABLE product_barcode (            -- [MVP]
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id    uuid NOT NULL REFERENCES product(id),
  barcode       text NOT NULL UNIQUE,
  kind          text NOT NULL DEFAULT 'gtin13' CHECK (kind IN ('gtin13','gtin14','internal','plu','variable_weight')),
  qty_per_scan  numeric(14,4) NOT NULL DEFAULT 1 CHECK (qty_per_scan > 0),
  row_version   bigint
);

CREATE TABLE product_kit_line (           -- [F2] componentes de un combo que descuenta stock
  kit_product_id        uuid NOT NULL REFERENCES product(id),
  component_product_id  uuid NOT NULL REFERENCES product(id),
  qty                   numeric(14,4) NOT NULL CHECK (qty > 0),
  PRIMARY KEY (kit_product_id, component_product_id)
);

-- =============================================================================
-- 3. IMPUESTOS
-- =============================================================================
CREATE TABLE tax (                        -- [MVP] IGV, ICBPER, ISC…
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code               text NOT NULL UNIQUE,
  name               text NOT NULL,
  kind               text NOT NULL CHECK (kind IN ('percent','fixed_per_unit')),
  included_in_price  boolean NOT NULL DEFAULT true,   -- el precio exhibido ya lo incluye
  account_code       text,
  row_version        bigint
);

CREATE TABLE tax_rate (                   -- [MVP] tasa o monto con vigencia; por país o por empresa
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tax_id      uuid NOT NULL REFERENCES tax(id),
  company_id  uuid REFERENCES company(id), -- tasa especial de una empresa (p. ej. IGV reducido)
  rate        numeric(9,6),
  amount      numeric(14,4),
  valid_from  date NOT NULL,
  valid_to    date,
  source_ref  text NOT NULL,              -- norma (patrón: lo legal lleva fuente)
  row_version bigint,
  CHECK (rate IS NOT NULL OR amount IS NOT NULL),
  CHECK (valid_to IS NULL OR valid_to > valid_from),
  EXCLUDE USING gist (tax_id WITH =,
                      (coalesce(company_id, '00000000-0000-0000-0000-000000000000'::uuid)) WITH =,
                      daterange(valid_from, valid_to) WITH &&)
);

CREATE TABLE tax_category_tax (           -- [MVP] impuestos que aplica cada categoría (gravado → IGV)
  tax_category_code  text NOT NULL REFERENCES tax_category(code),
  tax_id             uuid NOT NULL REFERENCES tax(id),
  PRIMARY KEY (tax_category_code, tax_id)
);

CREATE TABLE product_tax (                -- [MVP] impuestos propios de un producto (bolsas, selectivo)
  product_id  uuid NOT NULL REFERENCES product(id),
  tax_id      uuid NOT NULL REFERENCES tax(id),
  PRIMARY KEY (product_id, tax_id)
);

-- =============================================================================
-- 4. PRECIOS Y PROMOCIONES
--    El motor de promociones corre en la caja (debe funcionar sin red); la base guarda las reglas,
--    las distribuye y valida el resultado de cada línea.
-- =============================================================================
CREATE TABLE pricelist (                  -- [MVP]
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code           text NOT NULL UNIQUE,
  name           text NOT NULL,
  currency_code  char(3) NOT NULL,
  is_active      boolean NOT NULL DEFAULT true
);
ALTER TABLE store ADD FOREIGN KEY (default_pricelist_id) REFERENCES pricelist(id);

CREATE TABLE pricelist_item (             -- [MVP] precio con impuesto incluido, con vigencia y por cantidad
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pricelist_id  uuid NOT NULL REFERENCES pricelist(id),
  product_id    uuid NOT NULL REFERENCES product(id),
  min_qty       numeric(14,4) NOT NULL DEFAULT 0,
  price         numeric(14,4) NOT NULL CHECK (price >= 0),
  valid_from    timestamptz NOT NULL DEFAULT now(),
  valid_to      timestamptz,             -- cambio programado: la caja lo recibe antes y lo aplica a su hora
  row_version   bigint,
  CHECK (valid_to IS NULL OR valid_to > valid_from),
  EXCLUDE USING gist (pricelist_id WITH =, product_id WITH =, min_qty WITH =,
                      tstzrange(valid_from, valid_to) WITH &&)
);

CREATE TABLE payment_method (             -- [MVP] medios de pago (sección 6, aquí por las promociones)
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                    text NOT NULL UNIQUE,
  name                    text NOT NULL,
  kind                    text NOT NULL
                          CHECK (kind IN ('cash','card','wallet_qr','transfer','gift_card','credit_note',
                                          'customer_credit','points','voucher')),
  requires_online         boolean NOT NULL DEFAULT false,
  applies_cash_rounding   boolean NOT NULL DEFAULT false,
  account_code            text,
  integration             text,           -- adaptador del pinpad o de la billetera
  is_active               boolean NOT NULL DEFAULT true
);

CREATE TABLE promotion (                  -- [F2]
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                text NOT NULL UNIQUE,
  name                text NOT NULL,
  promo_type          text NOT NULL
                      CHECK (promo_type IN ('percent','amount','special_price','buy_x_pay_y','bundle',
                                            'order_threshold','coupon','payment_method','customer_tier')),
  combinability       text NOT NULL DEFAULT 'exclusive' CHECK (combinability IN ('exclusive','stackable','best_for_customer')),
  priority            int NOT NULL DEFAULT 10,
  valid_from          timestamptz NOT NULL,
  valid_to            timestamptz,
  days_of_week        int[],              -- 1 = lunes … 7 = domingo; NULL = todos
  start_time          time,
  end_time            time,
  discount_pct        numeric(5,2),
  discount_amount     numeric(14,2),
  special_price       numeric(14,4),
  buy_qty             int,
  pay_qty             int,
  min_order_amount    numeric(14,2),
  payment_method_id   uuid REFERENCES payment_method(id),
  funded_by           text NOT NULL DEFAULT 'company' CHECK (funded_by IN ('company','bank','supplier')),
  is_active           boolean NOT NULL DEFAULT true,
  row_version         bigint,
  CHECK (promo_type <> 'buy_x_pay_y' OR (buy_qty > pay_qty AND pay_qty > 0))
);

CREATE TABLE promotion_product (          -- [F2] productos o categorías que participan
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  promotion_id  uuid NOT NULL REFERENCES promotion(id) ON DELETE CASCADE,
  product_id    uuid REFERENCES product(id),
  category_id   uuid REFERENCES product_category(id),
  CHECK (product_id IS NOT NULL OR category_id IS NOT NULL)
);

CREATE TABLE promotion_store (            -- [F2] sin filas = todas las tiendas
  promotion_id  uuid NOT NULL REFERENCES promotion(id) ON DELETE CASCADE,
  store_id      uuid NOT NULL REFERENCES store(id),
  PRIMARY KEY (promotion_id, store_id)
);

CREATE TABLE coupon (                     -- [F2]
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code          text NOT NULL UNIQUE,
  promotion_id  uuid NOT NULL REFERENCES promotion(id),
  max_uses      int,
  used_count    int NOT NULL DEFAULT 0,
  valid_until   timestamptz,
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('active','used','expired','cancelled')),
  CHECK (max_uses IS NULL OR used_count <= max_uses)
);

-- =============================================================================
-- 5. CLIENTES Y SALDOS
-- =============================================================================
CREATE TABLE customer (                   -- [MVP]
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_type      text NOT NULL CHECK (doc_type IN ('DNI','RUC','CE','PAS','OTHER')),
  doc_number    text NOT NULL,
  name          text NOT NULL,
  email         text,
  phone         text,
  address       text,
  pricelist_id  uuid REFERENCES pricelist(id),
  credit_limit  numeric(14,2),
  is_active     boolean NOT NULL DEFAULT true,
  row_version   bigint,
  UNIQUE (doc_type, doc_number)
);

CREATE TABLE customer_credit_ledger (     -- [F2] cuenta corriente: saldo = SUM(amount)
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id  uuid NOT NULL REFERENCES customer(id),
  entry_type   text NOT NULL CHECK (entry_type IN ('charge','payment','adjustment')),
  amount       numeric(14,2) NOT NULL,   -- + cargo, − pago
  order_id     uuid,                      -- FK diferida
  occurred_at  timestamptz NOT NULL DEFAULT now(),
  reason       text
);

CREATE TABLE gift_card (                  -- [F2]
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code             text NOT NULL UNIQUE,
  currency_code    char(3) NOT NULL,
  status           text NOT NULL DEFAULT 'active' CHECK (status IN ('active','blocked','expired')),
  expires_on       date,
  issued_order_id  uuid                   -- FK diferida
);

CREATE TABLE gift_card_ledger (           -- [F2] saldo = SUM(amount); nunca negativo
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gift_card_id uuid NOT NULL REFERENCES gift_card(id),
  entry_type   text NOT NULL CHECK (entry_type IN ('issue','redeem','refund','expire','adjustment')),
  amount       numeric(14,2) NOT NULL,
  payment_id   uuid,                      -- FK diferida
  occurred_at  timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- 6. MEDIOS DE PAGO POR TIENDA
-- =============================================================================
CREATE TABLE store_payment_method (       -- [MVP] medios aceptados en cada tienda
  store_id           uuid NOT NULL REFERENCES store(id),
  payment_method_id  uuid NOT NULL REFERENCES payment_method(id),
  PRIMARY KEY (store_id, payment_method_id)
);

-- =============================================================================
-- 7. CAJA: DÍA DE NEGOCIO, SESIONES, MOVIMIENTOS Y DECLARACIONES
-- =============================================================================
CREATE TABLE business_day (               -- [MVP] jornada de una tienda
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id       uuid NOT NULL REFERENCES store(id),
  business_date  date NOT NULL,
  status         text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  opened_at      timestamptz NOT NULL DEFAULT now(),
  closed_at      timestamptz,
  closed_by      text,
  UNIQUE (store_id, business_date)
);

CREATE TABLE pos_session (                -- [MVP] sesión de caja: del fondo inicial al cierre
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  terminal_id           uuid NOT NULL REFERENCES pos_terminal(id),
  store_id              uuid NOT NULL REFERENCES store(id),
  cashier_user_id       uuid NOT NULL REFERENCES pos_user(id),
  business_day_id       uuid REFERENCES business_day(id),
  status                text NOT NULL DEFAULT 'opening'
                        CHECK (status IN ('opening','opened','closing','closed','posted')),
  opening_float         numeric(14,2) NOT NULL DEFAULT 0 CHECK (opening_float >= 0),
  opened_at             timestamptz,
  closing_at            timestamptz,
  closed_at             timestamptz,
  closed_by             text,
  approved_by           text,             -- supervisor que aprueba las diferencias fuera de tolerancia
  needs_reconciliation  boolean NOT NULL DEFAULT false,   -- llegaron ventas después del cierre
  posted_at             timestamptz,
  notes                 text
);
CREATE UNIQUE INDEX uq_session_active_terminal ON pos_session (terminal_id)
  WHERE status IN ('opening','opened','closing');

CREATE TABLE pos_session_status_log (     -- [MVP]
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  session_id   uuid NOT NULL REFERENCES pos_session(id),
  from_status  text,
  to_status    text NOT NULL,
  changed_by   text,
  changed_at   timestamptz NOT NULL DEFAULT now(),
  reason       text
);

CREATE TABLE cash_movement (              -- [MVP] efectivo que entra o sale del cajón sin ser venta
  id             uuid PRIMARY KEY,          -- generado en la caja
  session_id     uuid NOT NULL REFERENCES pos_session(id),
  kind           text NOT NULL CHECK (kind IN ('cash_in','cash_out','safe_drop','petty_cash')),
  amount         numeric(14,2) NOT NULL CHECK (amount > 0),
  reason         text NOT NULL,
  envelope_no    text,                     -- sobre del retiro parcial
  authorized_by  text,
  occurred_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE session_declaration (        -- [MVP] cierre ciego: lo que el cajero declara por medio
  session_id         uuid NOT NULL REFERENCES pos_session(id),
  payment_method_id  uuid NOT NULL REFERENCES payment_method(id),
  expected_amount    numeric(14,2) NOT NULL,      -- calculado por la base; la pantalla no lo muestra
  declared_amount    numeric(14,2) NOT NULL,
  difference         numeric(14,2) GENERATED ALWAYS AS (declared_amount - expected_amount) STORED,
  denominations      jsonb,                         -- conteo por billete y moneda
  declared_by        text,
  declared_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, payment_method_id)
);

-- =============================================================================
-- 8. VENTAS Y PAGOS
-- =============================================================================
CREATE TABLE pos_order (                  -- [MVP] venta o devolución; el id lo genera la caja
  id                    uuid PRIMARY KEY,
  session_id            uuid NOT NULL REFERENCES pos_session(id),
  terminal_id           uuid NOT NULL REFERENCES pos_terminal(id),
  store_id              uuid NOT NULL REFERENCES store(id),
  company_id            uuid NOT NULL REFERENCES company(id),
  cashier_user_id       uuid NOT NULL REFERENCES pos_user(id),
  salesperson_user_id   uuid REFERENCES pos_user(id),
  customer_id           uuid REFERENCES customer(id),
  pricelist_id          uuid REFERENCES pricelist(id),
  business_date         date NOT NULL,    -- de la sesión (patrón 3)
  occurred_at           timestamptz NOT NULL,   -- reloj de la caja: fecha del hecho
  received_at           timestamptz NOT NULL DEFAULT now(),   -- fecha de registro en el servidor
  status                text NOT NULL DEFAULT 'draft'
                        CHECK (status IN ('draft','paid','done','posted','cancelled')),
  refund_of_order_id    uuid REFERENCES pos_order(id),
  authorized_by         text,             -- supervisor (devolución sin ticket, descuento sobre tope)
  amount_untaxed        numeric(14,2) NOT NULL DEFAULT 0,
  amount_tax            numeric(14,2) NOT NULL DEFAULT 0,
  amount_total          numeric(14,2) NOT NULL DEFAULT 0,   -- importe exacto del comprobante
  cash_rounding_amount  numeric(14,2) NOT NULL DEFAULT 0 CHECK (cash_rounding_amount <= 0 AND cash_rounding_amount > -0.10),
  currency_code         char(3) NOT NULL,
  notes                 text
);
CREATE INDEX ix_pos_order_session ON pos_order (session_id, status);
ALTER TABLE customer_credit_ledger ADD FOREIGN KEY (order_id) REFERENCES pos_order(id);
ALTER TABLE gift_card ADD FOREIGN KEY (issued_order_id) REFERENCES pos_order(id);

CREATE TABLE pos_order_line (             -- [MVP] snapshot del cálculo de la línea
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id                uuid NOT NULL REFERENCES pos_order(id),
  line_no                 int NOT NULL,
  product_id              uuid NOT NULL REFERENCES product(id),
  description             text NOT NULL,
  qty                     numeric(14,4) NOT NULL CHECK (qty <> 0),   -- negativa en devoluciones
  list_price              numeric(14,4) NOT NULL,   -- precio unitario de lista con impuesto incluido
  manual_discount_amount  numeric(14,2) NOT NULL DEFAULT 0,
  promo_discount_amount   numeric(14,2) NOT NULL DEFAULT 0,   -- prorrateado (patrón 4)
  price_total             numeric(14,2) NOT NULL,   -- neto pagado con impuestos incluidos
  price_subtotal          numeric(14,2) NOT NULL,   -- base imponible
  tax_category_code       text NOT NULL REFERENCES tax_category(code),
  lot_serial              text,
  salesperson_user_id     uuid REFERENCES pos_user(id),
  refunded_line_id        uuid REFERENCES pos_order_line(id),
  price_trace             jsonb NOT NULL DEFAULT '{}',   -- lista, reglas y promociones aplicadas
  UNIQUE (order_id, line_no),
  CHECK (price_total = round(qty * list_price, 2) - manual_discount_amount - promo_discount_amount)
);

CREATE TABLE pos_order_line_tax (         -- [MVP] impuestos de la línea
  line_id            uuid NOT NULL REFERENCES pos_order_line(id) ON DELETE CASCADE,
  tax_id             uuid NOT NULL REFERENCES tax(id),
  base_amount        numeric(14,2) NOT NULL,
  rate               numeric(9,6),
  amount             numeric(14,2) NOT NULL,
  included_in_price  boolean NOT NULL,
  PRIMARY KEY (line_id, tax_id)
);

CREATE TABLE pos_order_line_promotion (   -- [F2] traza: qué promoción dio cuánto en la línea
  line_id          uuid NOT NULL REFERENCES pos_order_line(id) ON DELETE CASCADE,
  promotion_id     uuid NOT NULL REFERENCES promotion(id),
  coupon_id        uuid REFERENCES coupon(id),
  discount_amount  numeric(14,2) NOT NULL,
  PRIMARY KEY (line_id, promotion_id)
);

CREATE TABLE pos_payment (                -- [MVP] el id lo genera la caja
  id                    uuid PRIMARY KEY,
  order_id              uuid NOT NULL REFERENCES pos_order(id),
  payment_method_id     uuid NOT NULL REFERENCES payment_method(id),
  amount                numeric(14,2) NOT NULL,   -- aplicado a la venta; negativo en devoluciones
  tendered_amount       numeric(14,2),            -- efectivo entregado por el cliente
  change_amount         numeric(14,2) NOT NULL DEFAULT 0 CHECK (change_amount >= 0),
  status                text NOT NULL DEFAULT 'captured'
                        CHECK (status IN ('pending','authorized','captured','declined','voided','refunded')),
  auth_code             text,
  acquirer_ref          text,
  card_brand            text,
  card_last4            text,
  gift_card_id          uuid REFERENCES gift_card(id),
  refund_of_payment_id  uuid REFERENCES pos_payment(id),
  occurred_at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_pos_payment_order ON pos_payment (order_id);
ALTER TABLE gift_card_ledger ADD FOREIGN KEY (payment_id) REFERENCES pos_payment(id);

CREATE TABLE pos_sync_exception (         -- [MVP] excepciones aceptadas al sincronizar (patrón 1)
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id     uuid REFERENCES pos_order(id),
  session_id   uuid REFERENCES pos_session(id),
  kind         text NOT NULL CHECK (kind IN ('late_after_close','negative_stock','price_expired',
                                             'promotion_expired','serial_duplicate','clock_drift')),
  detail       jsonb NOT NULL DEFAULT '{}',
  status       text NOT NULL DEFAULT 'open' CHECK (status IN ('open','resolved','ignored')),
  resolved_by  text,
  resolution   text
);

-- =============================================================================
-- 9. COMPROBANTES
-- =============================================================================
CREATE TABLE fiscal_document (            -- [MVP] comprobante emitido (factura, boleta, notas)
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id              uuid NOT NULL REFERENCES company(id),
  establishment_id        uuid NOT NULL REFERENCES establishment(id),
  terminal_id             uuid REFERENCES pos_terminal(id),
  order_id                uuid REFERENCES pos_order(id),
  doc_type                text NOT NULL CHECK (doc_type IN ('01','03','07','08')),
  series                  text NOT NULL,
  number                  bigint NOT NULL CHECK (number > 0),
  issued_at               timestamptz NOT NULL,  -- fecha del hecho, no el día de negocio
  customer_doc_type       text,
  customer_doc_number     text,
  customer_name           text,
  currency_code           char(3) NOT NULL,
  total_taxable           numeric(14,2) NOT NULL DEFAULT 0,   -- base gravada
  total_exempt            numeric(14,2) NOT NULL DEFAULT 0,
  total_unaffected        numeric(14,2) NOT NULL DEFAULT 0,
  total_free              numeric(14,2) NOT NULL DEFAULT 0,
  total_igv               numeric(14,2) NOT NULL DEFAULT 0,
  total_other_taxes       numeric(14,2) NOT NULL DEFAULT 0,   -- ICBPER, ISC
  total_amount            numeric(14,2) NOT NULL,
  rounding_amount         numeric(14,2) NOT NULL DEFAULT 0,
  payment_terms           text NOT NULL DEFAULT 'cash' CHECK (payment_terms IN ('cash','credit')),
  referenced_document_id  uuid REFERENCES fiscal_document(id),
  note_reason_code        text,
  note_reason             text,
  status                  text NOT NULL DEFAULT 'generated'
                          CHECK (status IN ('generated','signed','sent','accepted','observed','rejected','voided')),
  hash                    text,
  qr_text                 text,
  xml_ref                 text,
  UNIQUE (company_id, doc_type, series, number),
  CHECK (doc_type IN ('01','03') OR (referenced_document_id IS NOT NULL AND note_reason_code IS NOT NULL))
);
CREATE INDEX ix_fiscal_order ON fiscal_document (order_id);

CREATE TABLE fiscal_document_line (       -- [MVP] snapshot de las líneas
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id        uuid NOT NULL REFERENCES fiscal_document(id),
  line_no            int NOT NULL,
  product_id         uuid REFERENCES product(id),
  description        text NOT NULL,
  qty                numeric(14,4) NOT NULL,
  uom_code           text NOT NULL,
  unit_value         numeric(20,10) NOT NULL,   -- sin impuestos
  unit_price         numeric(20,10) NOT NULL,   -- con impuestos
  line_value         numeric(14,2) NOT NULL,    -- base
  igv_amount         numeric(14,2) NOT NULL DEFAULT 0,
  other_tax_amount   numeric(14,2) NOT NULL DEFAULT 0,
  discount_amount    numeric(14,2) NOT NULL DEFAULT 0,
  tax_category_code  text NOT NULL,
  UNIQUE (document_id, line_no)
);

CREATE TABLE fiscal_submission (          -- [MVP] cada envío a la autoridad o al operador
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id       uuid NOT NULL REFERENCES fiscal_document(id),
  channel           text NOT NULL CHECK (channel IN ('direct','ose','pse','daily_summary')),
  attempt           int NOT NULL DEFAULT 1,
  sent_at           timestamptz NOT NULL DEFAULT now(),
  ticket            text,
  result            text NOT NULL DEFAULT 'pending' CHECK (result IN ('pending','accepted','observed','rejected','error')),
  response_code     text,
  response_message  text,
  cdr_ref           text
);

CREATE TABLE fiscal_daily_summary (       -- [F2] resumen diario de boletas y sus notas
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid NOT NULL REFERENCES company(id),
  summary_date  date NOT NULL,
  sequence      int NOT NULL,
  status        text NOT NULL DEFAULT 'generated' CHECK (status IN ('generated','sent','accepted','rejected')),
  ticket        text,
  UNIQUE (company_id, summary_date, sequence)
);

CREATE TABLE fiscal_daily_summary_item (  -- [F2]
  summary_id   uuid NOT NULL REFERENCES fiscal_daily_summary(id) ON DELETE CASCADE,
  document_id  uuid NOT NULL REFERENCES fiscal_document(id),
  condition    text NOT NULL CHECK (condition IN ('add','modify','void')),
  PRIMARY KEY (summary_id, document_id)
);

-- =============================================================================
-- 10. STOCK: EFECTOS PARA INVENTARIO Y RÉPLICA DEL SALDO
-- =============================================================================
CREATE TABLE stock_effect (               -- [MVP] salida (o entrada) de stock que el POS publica
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_line_id  uuid NOT NULL REFERENCES pos_order_line(id),
  store_id       uuid NOT NULL REFERENCES store(id),
  product_id     uuid NOT NULL REFERENCES product(id),
  qty            numeric(14,4) NOT NULL,  -- negativa: sale de la tienda
  external_key   text NOT NULL UNIQUE,    -- clave de idempotencia para el módulo de inventario
  status         text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','sent','acknowledged','error')),
  sent_at        timestamptz,
  acknowledged_at timestamptz,
  external_ref   text,                    -- id del movimiento en inventario
  error_message  text
);

CREATE TABLE store_stock_level (          -- [MVP] réplica del disponible para mostrar en caja
  store_id    uuid NOT NULL REFERENCES store(id),
  product_id  uuid NOT NULL REFERENCES product(id),
  available   numeric(14,4) NOT NULL,
  as_of       timestamptz NOT NULL,       -- se muestra siempre con su hora
  source      text NOT NULL DEFAULT 'inventory',
  PRIMARY KEY (store_id, product_id)
);

-- =============================================================================
-- 11. CONCILIACIÓN DE TARJETAS [F2]
-- =============================================================================
CREATE TABLE card_settlement (            -- [F2] liquidación del adquirente
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       uuid NOT NULL REFERENCES company(id),
  acquirer         text NOT NULL,
  settlement_date  date NOT NULL,
  gross_amount     numeric(14,2) NOT NULL,
  fee_amount       numeric(14,2) NOT NULL DEFAULT 0,
  net_amount       numeric(14,2) NOT NULL,
  bank_ref         text,
  CHECK (net_amount = gross_amount - fee_amount)
);

CREATE TABLE card_settlement_line (       -- [F2]
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  settlement_id       uuid NOT NULL REFERENCES card_settlement(id) ON DELETE CASCADE,
  acquirer_ref        text,
  auth_code           text,
  amount              numeric(14,2) NOT NULL,
  fee_amount          numeric(14,2) NOT NULL DEFAULT 0,
  matched_payment_id  uuid REFERENCES pos_payment(id)
);

-- =============================================================================
-- 12. CONTABILIDAD DE LA SESIÓN Y COMISIONES [F2]
-- =============================================================================
CREATE TABLE session_journal_entry (      -- [F2] un asiento resumen por sesión
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  uuid NOT NULL UNIQUE REFERENCES pos_session(id),
  entry_date  date NOT NULL
);

CREATE TABLE session_journal_line (       -- [F2]
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id      uuid NOT NULL REFERENCES session_journal_entry(id) ON DELETE CASCADE,
  account_code  text NOT NULL,
  debit         numeric(14,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
  credit        numeric(14,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
  description   text
);

CREATE TABLE commission_result (          -- [F2] comisión por vendedor y período, exportada a nómina
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  salesperson_user_id  uuid NOT NULL REFERENCES pos_user(id),
  period_start         date NOT NULL,
  period_end           date NOT NULL,
  net_sales            numeric(14,2) NOT NULL,
  rate_pct             numeric(5,2) NOT NULL,
  amount               numeric(14,2) NOT NULL,
  payroll_external_key text UNIQUE,       -- clave de la novedad en nómina (idempotencia)
  exported_at          timestamptz,
  UNIQUE (salesperson_user_id, period_start, period_end)
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

CREATE OR REPLACE FUNCTION pos.fn_set_audit() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := now();
    NEW.created_by := nullif(current_setting('app.user_id', true), '');
  END IF;
  NEW.updated_at := now();
  NEW.updated_by := nullif(current_setting('app.user_id', true), '');
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pos.fn_audit_log() RETURNS trigger AS $$
BEGIN
  INSERT INTO pos.audit_log(table_name, record_id, action, changed_by, old_data, new_data)
  VALUES (TG_TABLE_NAME,
          COALESCE((to_jsonb(NEW)->>'id'), (to_jsonb(OLD)->>'id'))::uuid,
          TG_OP,
          nullif(current_setting('app.user_id', true), ''),
          CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END,
          CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END);
  RETURN COALESCE(NEW, OLD);
END $$ LANGUAGE plpgsql;

DO $$
DECLARE
  t record;
  sensitive text[] := ARRAY[
    'pos_terminal','document_series','pos_user','tax_rate','pricelist_item','promotion','payment_method',
    'pos_session','cash_movement','pos_order','pos_payment','fiscal_document','gift_card','gift_card_ledger',
    'customer_credit_ledger','legal_parameter','pos_sync_exception'
  ];
BEGIN
  FOR t IN
    SELECT c.table_name
    FROM information_schema.columns c
    JOIN information_schema.tables tb
      ON tb.table_schema = c.table_schema AND tb.table_name = c.table_name
    WHERE c.table_schema = 'pos' AND c.column_name = 'id'
      AND tb.table_type = 'BASE TABLE' AND c.table_name NOT IN ('audit_log','pos_session_status_log')
  LOOP
    EXECUTE format('ALTER TABLE pos.%I
      ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
      ADD COLUMN IF NOT EXISTS created_by text,
      ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now(),
      ADD COLUMN IF NOT EXISTS updated_by text', t.table_name);
    EXECUTE format('CREATE TRIGGER trg_%1$s_audit_cols BEFORE INSERT OR UPDATE ON pos.%1$I
      FOR EACH ROW EXECUTE FUNCTION pos.fn_set_audit()', t.table_name);
    IF t.table_name = ANY (sensitive) THEN
      EXECUTE format('CREATE TRIGGER trg_%1$s_audit_log AFTER INSERT OR UPDATE OR DELETE ON pos.%1$I
        FOR EACH ROW EXECUTE FUNCTION pos.fn_audit_log()', t.table_name);
    END IF;
  END LOOP;
END $$;

-- =============================================================================
-- 16. LÓGICA
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 16.1 Utilidades: parámetros legales, tasas, precios, día de negocio, versión de maestros [MVP]
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pos.fn_setting(p_code text) RETURNS jsonb AS $$
  SELECT value FROM pos.pos_setting WHERE code = p_code;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION pos.fn_legal_param(p_country char(2), p_code text, p_date date) RETURNS numeric AS $$
  SELECT value FROM pos.legal_parameter
  WHERE country_code = p_country AND code = p_code AND valid_from <= p_date AND (valid_to IS NULL OR valid_to > p_date);
$$ LANGUAGE sql STABLE;

-- Tasa vigente de un impuesto: la especial de la empresa si existe, si no la general
CREATE OR REPLACE FUNCTION pos.fn_tax_rate(p_tax uuid, p_company uuid, p_date date,
                                           OUT rate numeric, OUT amount numeric) AS $$
  SELECT r.rate, r.amount FROM pos.tax_rate r
  WHERE r.tax_id = p_tax AND (r.company_id = p_company OR r.company_id IS NULL)
    AND r.valid_from <= p_date AND (r.valid_to IS NULL OR r.valid_to > p_date)
  ORDER BY (r.company_id IS NOT NULL) DESC LIMIT 1;
$$ LANGUAGE sql STABLE;

-- Precio de lista vigente para una cantidad y un instante (el mayor tramo de cantidad que aplica)
CREATE OR REPLACE FUNCTION pos.fn_list_price(p_pricelist uuid, p_product uuid, p_qty numeric, p_at timestamptz)
RETURNS numeric AS $$
  SELECT price FROM pos.pricelist_item
  WHERE pricelist_id = p_pricelist AND product_id = p_product AND min_qty <= abs(p_qty)
    AND valid_from <= p_at AND (valid_to IS NULL OR valid_to > p_at)
  ORDER BY min_qty DESC LIMIT 1;
$$ LANGUAGE sql STABLE;

-- Día de negocio: hora local de la tienda menos la hora de inicio de la jornada
CREATE OR REPLACE FUNCTION pos.fn_business_date(p_store uuid, p_at timestamptz) RETURNS date AS $$
  SELECT ((p_at AT TIME ZONE s.timezone) - s.business_day_start)::date FROM pos.store s WHERE s.id = p_store;
$$ LANGUAGE sql STABLE;

-- Redondeo del efectivo a favor del cliente (a la décima inferior)
CREATE OR REPLACE FUNCTION pos.fn_cash_rounding(p_amount numeric) RETURNS numeric AS $$
  SELECT CASE WHEN p_amount >= 0 THEN floor(p_amount * 10) / 10 - p_amount
              ELSE -(ceil(-p_amount * 10) / 10 + p_amount) END;
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION pos.fn_bump_row_version() RETURNS trigger AS $$
BEGIN
  NEW.row_version := nextval('pos.catalog_version_seq');
  RETURN NEW;
END $$ LANGUAGE plpgsql;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['product_category','product','product_barcode','tax','tax_rate','pricelist_item',
                           'promotion','customer'] LOOP
    EXECUTE format('CREATE TRIGGER trg_%1$s_row_version BEFORE INSERT OR UPDATE ON pos.%1$I
                    FOR EACH ROW EXECUTE FUNCTION pos.fn_bump_row_version()', t);
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 16.2 Sesión de caja: máquina de estados [MVP]
--
--   opening ──► opened ──► closing ──► closed ──► posted
--                  ▲           │
--                  └─(motivo)──┘
--   · closing → closed: sin ventas en borrador, una declaración por medio con movimiento y,
--     si una diferencia supera la tolerancia, aprobación de alguien que no sea el cajero.
--   · closed y posted son inmutables (salvo pasar a posted y marcar conciliación).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pos.fn_session_expected(p_session uuid)
RETURNS TABLE (payment_method_id uuid, expected_amount numeric) AS $$
  WITH pay AS (
    SELECT p.payment_method_id, sum(p.amount) AS amount
    FROM pos.pos_payment p JOIN pos.pos_order o ON o.id = p.order_id
    WHERE o.session_id = p_session AND o.status IN ('paid','done','posted')
      AND p.status IN ('authorized','captured')
    GROUP BY p.payment_method_id
  ), cash AS (
    SELECT pm.id AS payment_method_id,
           s.opening_float
           + coalesce((SELECT sum(CASE WHEN m.kind = 'cash_in' THEN m.amount ELSE -m.amount END)
                       FROM pos.cash_movement m WHERE m.session_id = s.id), 0) AS base
    FROM pos.pos_session s CROSS JOIN pos.payment_method pm
    WHERE s.id = p_session AND pm.kind = 'cash'
      AND pm.id IN (SELECT payment_method_id FROM pos.store_payment_method WHERE store_id = s.store_id)
  )
  SELECT coalesce(c.payment_method_id, pay.payment_method_id),
         coalesce(c.base, 0) + coalesce(pay.amount, 0)
  FROM cash c FULL JOIN pay ON pay.payment_method_id = c.payment_method_id;
$$ LANGUAGE sql STABLE;

-- El cajero declara; la base guarda lo esperado y la diferencia (cierre ciego)
CREATE OR REPLACE FUNCTION pos.fn_declare(p_session uuid, p_method_code text, p_declared numeric,
                                          p_denominations jsonb DEFAULT NULL) RETURNS void AS $$
DECLARE v_method uuid; v_expected numeric; v_status text;
BEGIN
  SELECT status INTO v_status FROM pos.pos_session WHERE id = p_session;
  IF v_status <> 'closing' THEN RAISE EXCEPTION 'SESSION_NOT_CLOSING: primero pasa la sesión a cierre'; END IF;
  SELECT id INTO v_method FROM pos.payment_method WHERE code = p_method_code;
  SELECT coalesce((SELECT e.expected_amount FROM pos.fn_session_expected(p_session) e
                   WHERE e.payment_method_id = v_method), 0) INTO v_expected;
  INSERT INTO pos.session_declaration(session_id, payment_method_id, expected_amount, declared_amount,
                                      denominations, declared_by)
  VALUES (p_session, v_method, v_expected, p_declared, p_denominations, nullif(current_setting('app.user_id', true), ''))
  ON CONFLICT (session_id, payment_method_id) DO UPDATE
    SET expected_amount = EXCLUDED.expected_amount, declared_amount = EXCLUDED.declared_amount,
        denominations = EXCLUDED.denominations, declared_by = EXCLUDED.declared_by, declared_at = now();
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pos.fn_session_guard() RETURNS trigger AS $$
DECLARE
  v_user text := nullif(current_setting('app.user_id', true), '');
  v_reason text := nullif(current_setting('app.reason', true), '');
  v_tol numeric; v_cashier text; v_bd date;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'opening' THEN RAISE EXCEPTION 'SESSION_INVALID_INITIAL_STATUS'; END IF;
    SELECT t.store_id INTO NEW.store_id FROM pos.pos_terminal t WHERE t.id = NEW.terminal_id AND t.status = 'active';
    IF NEW.store_id IS NULL THEN RAISE EXCEPTION 'TERMINAL_NOT_ACTIVE: la caja no está registrada o fue revocada'; END IF;
    IF NEW.business_day_id IS NULL THEN
      v_bd := pos.fn_business_date(NEW.store_id, now());
      INSERT INTO pos.business_day(store_id, business_date) VALUES (NEW.store_id, v_bd)
      ON CONFLICT (store_id, business_date) DO NOTHING;
      SELECT id INTO NEW.business_day_id FROM pos.business_day WHERE store_id = NEW.store_id AND business_date = v_bd;
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status IN ('closed','posted') THEN
    IF (NEW.terminal_id, NEW.cashier_user_id, NEW.opening_float, NEW.closed_at, NEW.approved_by, NEW.business_day_id)
       IS DISTINCT FROM
       (OLD.terminal_id, OLD.cashier_user_id, OLD.opening_float, OLD.closed_at, OLD.approved_by, OLD.business_day_id)
       OR (NEW.status <> OLD.status AND (OLD.status, NEW.status) <> ('closed','posted')) THEN
      RAISE EXCEPTION 'SESSION_CLOSED: una sesión cerrada no se edita; registra un ajuste con motivo';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.opening_float IS DISTINCT FROM OLD.opening_float AND OLD.status <> 'opening' THEN
    RAISE EXCEPTION 'SESSION_FLOAT_LOCKED: el fondo inicial se fija al abrir';
  END IF;
  IF NEW.status = OLD.status THEN RETURN NEW; END IF;

  IF (OLD.status, NEW.status) NOT IN (('opening','opened'), ('opened','closing'), ('closing','opened'),
                                      ('closing','closed')) THEN
    RAISE EXCEPTION 'SESSION_INVALID_TRANSITION: % → %', OLD.status, NEW.status;
  END IF;
  IF (OLD.status, NEW.status) = ('closing','opened') AND v_reason IS NULL THEN
    RAISE EXCEPTION 'SESSION_REASON_REQUIRED: reabrir una sesión en cierre exige motivo (app.reason)';
  END IF;
  IF NEW.status = 'opened' AND OLD.status = 'opening' THEN NEW.opened_at := now(); END IF;
  IF NEW.status = 'closing' THEN NEW.closing_at := now(); END IF;

  IF NEW.status = 'closed' THEN
    IF EXISTS (SELECT 1 FROM pos.pos_order WHERE session_id = NEW.id AND status = 'draft') THEN
      RAISE EXCEPTION 'SESSION_HAS_OPEN_ORDERS: hay ventas en borrador; complétalas o anúlalas';
    END IF;
    IF EXISTS (SELECT 1 FROM pos.fn_session_expected(NEW.id) e
               WHERE e.expected_amount <> 0
                 AND NOT EXISTS (SELECT 1 FROM pos.session_declaration d
                                 WHERE d.session_id = NEW.id AND d.payment_method_id = e.payment_method_id)) THEN
      RAISE EXCEPTION 'SESSION_DECLARATION_MISSING: falta declarar algún medio de pago';
    END IF;
    UPDATE pos.session_declaration d SET expected_amount = e.expected_amount
    FROM pos.fn_session_expected(NEW.id) e
    WHERE d.session_id = NEW.id AND d.payment_method_id = e.payment_method_id
      AND d.expected_amount IS DISTINCT FROM e.expected_amount;
    v_tol := (pos.fn_setting('CASH_DIFF_TOLERANCE') #>> '{}')::numeric;
    IF EXISTS (SELECT 1 FROM pos.session_declaration d WHERE d.session_id = NEW.id AND abs(d.difference) > v_tol) THEN
      SELECT code INTO v_cashier FROM pos.pos_user WHERE id = NEW.cashier_user_id;
      IF NEW.approved_by IS NULL THEN
        RAISE EXCEPTION 'SESSION_DIFF_APPROVAL_REQUIRED: hay diferencias mayores a %; aprueba un supervisor', v_tol;
      END IF;
      IF NEW.approved_by = v_cashier THEN
        RAISE EXCEPTION 'SESSION_SELF_APPROVAL: el cajero no aprueba su propia diferencia';
      END IF;
    END IF;
    NEW.closed_at := now();
    NEW.closed_by := v_user;
  END IF;

  INSERT INTO pos.pos_session_status_log(session_id, from_status, to_status, changed_by, reason)
  VALUES (NEW.id, OLD.status, NEW.status, v_user, v_reason);
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_pos_session_guard BEFORE INSERT OR UPDATE ON pos_session
  FOR EACH ROW EXECUTE FUNCTION pos.fn_session_guard();

CREATE OR REPLACE FUNCTION pos.fn_cash_movement_guard() RETURNS trigger AS $$
DECLARE v_status text;
BEGIN
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'CASH_MOVEMENT_IMMUTABLE: se corrige con otro movimiento'; END IF;
  SELECT status INTO v_status FROM pos.pos_session WHERE id = NEW.session_id;
  IF v_status NOT IN ('opened','closing') THEN
    RAISE EXCEPTION 'SESSION_NOT_OPEN: los movimientos de efectivo van en una sesión abierta';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_cash_movement_guard BEFORE INSERT OR UPDATE OR DELETE ON cash_movement
  FOR EACH ROW EXECUTE FUNCTION pos.fn_cash_movement_guard();

-- -----------------------------------------------------------------------------
-- 16.3 Ventas: llegada, cálculo de referencia, validación y estados [MVP]
--
--   draft ──► paid ──► done ──► posted          draft ──► cancelled
--   · La venta llega aunque la sesión ya cerró, si ocurrió antes del cierre (venta sin red que
--     sincroniza tarde): se acepta y se registra la excepción. Una venta posterior al cierre, no.
--   · Líneas y pagos solo cambian en borrador.
--   · paid valida totales, pagos, redondeo y devoluciones; done exige comprobante y publica stock.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pos.fn_order_guard() RETURNS trigger AS $$
DECLARE s pos.pos_session;
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'ORDER_DELETE_FORBIDDEN: una venta se anula, no se borra'; END IF;

  IF TG_OP = 'INSERT' THEN
    SELECT * INTO s FROM pos.pos_session WHERE id = NEW.session_id;
    IF s.status = 'opening' THEN RAISE EXCEPTION 'SESSION_NOT_OPEN: abre la caja antes de vender'; END IF;
    IF s.status IN ('closing','closed','posted')
       AND NEW.occurred_at > coalesce(CASE WHEN s.status = 'closing' THEN s.closing_at ELSE s.closed_at END, now()) THEN
      RAISE EXCEPTION 'SESSION_CLOSED: la venta es posterior al cierre de la sesión';
    END IF;
    IF NEW.status <> 'draft' THEN RAISE EXCEPTION 'ORDER_INVALID_INITIAL_STATUS: una venta llega en borrador'; END IF;
    NEW.terminal_id := s.terminal_id;
    NEW.store_id := s.store_id;
    SELECT company_id INTO NEW.company_id FROM pos.store WHERE id = s.store_id;
    SELECT business_date INTO NEW.business_date FROM pos.business_day WHERE id = s.business_day_id;
    NEW.received_at := now();
    RETURN NEW;
  END IF;

  -- UPDATE
  IF OLD.status IN ('done','posted','cancelled') THEN
    IF NEW.status IS DISTINCT FROM OLD.status AND (OLD.status, NEW.status) <> ('done','posted') THEN
      RAISE EXCEPTION 'ORDER_LOCKED: una venta % no cambia; se devuelve con otra venta', OLD.status;
    END IF;
    IF (NEW.amount_total, NEW.amount_tax, NEW.amount_untaxed, NEW.customer_id, NEW.session_id, NEW.occurred_at,
        NEW.cash_rounding_amount, NEW.refund_of_order_id)
       IS DISTINCT FROM
       (OLD.amount_total, OLD.amount_tax, OLD.amount_untaxed, OLD.customer_id, OLD.session_id, OLD.occurred_at,
        OLD.cash_rounding_amount, OLD.refund_of_order_id) THEN
      RAISE EXCEPTION 'ORDER_LOCKED: una venta % no cambia; se devuelve con otra venta', OLD.status;
    END IF;
    RETURN NEW;
  END IF;
  IF OLD.status = 'paid' AND (NEW.amount_total, NEW.amount_tax, NEW.amount_untaxed, NEW.customer_id,
                              NEW.cash_rounding_amount)
     IS DISTINCT FROM (OLD.amount_total, OLD.amount_tax, OLD.amount_untaxed, OLD.customer_id, OLD.cash_rounding_amount) THEN
    RAISE EXCEPTION 'ORDER_LOCKED: una venta cobrada no cambia';
  END IF;
  IF NEW.status <> OLD.status AND (OLD.status, NEW.status) NOT IN
     (('draft','paid'), ('draft','cancelled'), ('paid','done'), ('paid','cancelled')) THEN
    RAISE EXCEPTION 'ORDER_INVALID_TRANSITION: % → %', OLD.status, NEW.status;
  END IF;
  IF NEW.status = 'paid' AND OLD.status = 'draft' THEN PERFORM pos.fn_validate_order(NEW); END IF;
  IF NEW.status = 'cancelled' AND EXISTS (SELECT 1 FROM pos.pos_payment WHERE order_id = NEW.id
                                          AND status IN ('authorized','captured')) THEN
    RAISE EXCEPTION 'ORDER_HAS_APPROVED_PAYMENTS: anula o reversa los pagos aprobados antes de cancelar';
  END IF;
  IF NEW.status = 'done' AND (pos.fn_setting('REQUIRE_FISCAL_DOCUMENT') #>> '{}')::boolean
     AND NEW.amount_total <> 0
     AND NOT EXISTS (SELECT 1 FROM pos.fiscal_document WHERE order_id = NEW.id AND status <> 'rejected') THEN
    RAISE EXCEPTION 'ORDER_FISCAL_DOCUMENT_REQUIRED: emite el comprobante antes de terminar la venta';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_pos_order_guard BEFORE INSERT OR UPDATE OR DELETE ON pos_order
  FOR EACH ROW EXECUTE FUNCTION pos.fn_order_guard();

CREATE OR REPLACE FUNCTION pos.fn_order_after() RETURNS trigger AS $$
DECLARE s pos.pos_session;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT * INTO s FROM pos.pos_session WHERE id = NEW.session_id;
    IF s.status IN ('closed','posted') THEN
      INSERT INTO pos.pos_sync_exception(order_id, session_id, kind, detail)
      VALUES (NEW.id, s.id, 'late_after_close', jsonb_build_object('occurred_at', NEW.occurred_at, 'closed_at', s.closed_at));
      UPDATE pos.pos_session SET needs_reconciliation = true WHERE id = s.id;
    END IF;
  ELSIF NEW.status = 'done' AND OLD.status <> 'done' THEN
    -- Efectos de stock para el módulo de inventario (los kits se descomponen)
    INSERT INTO pos.stock_effect(order_line_id, store_id, product_id, qty, external_key)
    SELECT l.id, NEW.store_id, coalesce(k.component_product_id, l.product_id), -l.qty * coalesce(k.qty, 1),
           'pos:' || l.id || coalesce(':' || k.component_product_id, '')
    FROM pos.pos_order_line l JOIN pos.product p ON p.id = l.product_id
    LEFT JOIN pos.product_kit_line k ON k.kit_product_id = p.id AND p.product_type = 'kit'
    WHERE l.order_id = NEW.id AND (p.product_type IN ('stockable','consumable') OR k.kit_product_id IS NOT NULL)
    ON CONFLICT (external_key) DO NOTHING;
  END IF;
  RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_pos_order_after AFTER INSERT OR UPDATE OF status ON pos_order
  FOR EACH ROW EXECUTE FUNCTION pos.fn_order_after();

-- Líneas, impuestos, promociones y pagos solo cambian mientras la venta está en borrador
CREATE OR REPLACE FUNCTION pos.fn_order_child_guard() RETURNS trigger AS $$
DECLARE v_order uuid; v_status text;
BEGIN
  IF TG_TABLE_NAME IN ('pos_order_line_tax','pos_order_line_promotion') THEN
    SELECT order_id INTO v_order FROM pos.pos_order_line WHERE id = COALESCE(NEW.line_id, OLD.line_id);
  ELSE
    v_order := COALESCE(NEW.order_id, OLD.order_id);
  END IF;
  SELECT status INTO v_status FROM pos.pos_order WHERE id = v_order;
  IF TG_TABLE_NAME = 'pos_payment' AND TG_OP = 'UPDATE' THEN
    IF (NEW.amount, NEW.payment_method_id, NEW.order_id, NEW.tendered_amount, NEW.change_amount)
       IS DISTINCT FROM (OLD.amount, OLD.payment_method_id, OLD.order_id, OLD.tendered_amount, OLD.change_amount) THEN
      RAISE EXCEPTION 'PAYMENT_LOCKED: el importe de un pago no cambia';
    END IF;
    IF NEW.status <> OLD.status AND (OLD.status, NEW.status) NOT IN
       (('pending','authorized'), ('pending','captured'), ('pending','declined'), ('pending','voided'),
        ('authorized','captured'), ('authorized','voided'), ('captured','voided'), ('captured','refunded')) THEN
      RAISE EXCEPTION 'PAYMENT_INVALID_TRANSITION: % → %', OLD.status, NEW.status;
    END IF;
    IF NEW.status = 'voided' AND v_status NOT IN ('draft','paid','cancelled') THEN
      RAISE EXCEPTION 'PAYMENT_LOCKED: un pago de una venta terminada se devuelve, no se anula';
    END IF;
    RETURN NEW;
  END IF;
  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'ORDER_LOCKED: líneas y pagos solo cambian en borrador (venta %)', v_status;
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_line_guard BEFORE INSERT OR UPDATE OR DELETE ON pos_order_line
  FOR EACH ROW EXECUTE FUNCTION pos.fn_order_child_guard();
CREATE TRIGGER trg_order_line_tax_guard BEFORE INSERT OR UPDATE OR DELETE ON pos_order_line_tax
  FOR EACH ROW EXECUTE FUNCTION pos.fn_order_child_guard();
CREATE TRIGGER trg_order_line_promo_guard BEFORE INSERT OR UPDATE OR DELETE ON pos_order_line_promotion
  FOR EACH ROW EXECUTE FUNCTION pos.fn_order_child_guard();
CREATE TRIGGER trg_pos_payment_guard BEFORE INSERT OR UPDATE OR DELETE ON pos_payment
  FOR EACH ROW EXECUTE FUNCTION pos.fn_order_child_guard();

-- Cálculo de referencia de una línea (la caja hace lo mismo con sus datos locales):
--   total = cantidad × precio de lista − descuentos; base = total ÷ (1 + tasa) redondeada;
--   impuesto incluido = total − base; impuestos por unidad (bolsas) = cantidad × monto.
--   En una devolución con ticket el neto sale de la línea original, prorrateado.
CREATE OR REPLACE FUNCTION pos.fn_add_line(p_order uuid, p_product uuid, p_qty numeric,
                                           p_list_price numeric DEFAULT NULL, p_manual_discount numeric DEFAULT 0,
                                           p_promo_discount numeric DEFAULT 0, p_refunded_line uuid DEFAULT NULL)
RETURNS uuid AS $$
DECLARE
  o pos.pos_order; p pos.product; ol pos.pos_order_line; v_list numeric; v_total numeric; v_manual numeric;
  v_promo numeric; v_rate numeric := 0; v_base numeric; v_line uuid; v_no int; t record; r record; v_date date;
BEGIN
  SELECT * INTO o FROM pos.pos_order WHERE id = p_order;
  SELECT * INTO p FROM pos.product WHERE id = p_product;
  SELECT (o.occurred_at AT TIME ZONE s.timezone)::date INTO v_date FROM pos.store s WHERE s.id = o.store_id;
  IF p_refunded_line IS NOT NULL THEN
    SELECT * INTO ol FROM pos.pos_order_line WHERE id = p_refunded_line;
    v_list := ol.list_price;
    v_total := round(ol.price_total * p_qty / ol.qty, 2);
    v_manual := round(ol.manual_discount_amount * p_qty / ol.qty, 2);
    v_promo := round(p_qty * v_list, 2) - v_manual - v_total;
  ELSE
    v_list := coalesce(p_list_price, pos.fn_list_price(o.pricelist_id, p_product, p_qty, o.occurred_at));
    IF v_list IS NULL THEN RAISE EXCEPTION 'PRICE_NOT_FOUND: el producto % no tiene precio vigente', p.sku; END IF;
    v_manual := p_manual_discount; v_promo := p_promo_discount;
    v_total := round(p_qty * v_list, 2) - v_manual - v_promo;
  END IF;

  FOR t IN SELECT tx.* FROM pos.tax_category_tax ct JOIN pos.tax tx ON tx.id = ct.tax_id
           WHERE ct.tax_category_code = p.tax_category_code AND tx.kind = 'percent' AND tx.included_in_price LOOP
    SELECT * INTO r FROM pos.fn_tax_rate(t.id, o.company_id, v_date);
    v_rate := v_rate + coalesce(r.rate, 0);
  END LOOP;
  v_base := round(v_total / (1 + v_rate), 2);

  SELECT coalesce(max(line_no), 0) + 1 INTO v_no FROM pos.pos_order_line WHERE order_id = p_order;
  INSERT INTO pos.pos_order_line(order_id, line_no, product_id, description, qty, list_price, manual_discount_amount,
                                 promo_discount_amount, price_total, price_subtotal, tax_category_code, refunded_line_id)
  VALUES (p_order, v_no, p_product, p.name, p_qty, v_list, v_manual, v_promo, v_total, v_base,
          p.tax_category_code, p_refunded_line)
  RETURNING id INTO v_line;

  FOR t IN SELECT tx.* FROM pos.tax_category_tax ct JOIN pos.tax tx ON tx.id = ct.tax_id
           WHERE ct.tax_category_code = p.tax_category_code AND tx.kind = 'percent' AND tx.included_in_price LOOP
    SELECT * INTO r FROM pos.fn_tax_rate(t.id, o.company_id, v_date);
    INSERT INTO pos.pos_order_line_tax(line_id, tax_id, base_amount, rate, amount, included_in_price)
    VALUES (v_line, t.id, v_base, r.rate, v_total - v_base, true);
  END LOOP;
  FOR t IN SELECT tx.* FROM pos.product_tax pt JOIN pos.tax tx ON tx.id = pt.tax_id
           WHERE pt.product_id = p_product AND tx.kind = 'fixed_per_unit' LOOP
    SELECT * INTO r FROM pos.fn_tax_rate(t.id, o.company_id, v_date);
    INSERT INTO pos.pos_order_line_tax(line_id, tax_id, base_amount, rate, amount, included_in_price)
    VALUES (v_line, t.id, 0, NULL, round(p_qty * r.amount, 2), false);
  END LOOP;
  RETURN v_line;
END $$ LANGUAGE plpgsql;

-- Totales de la venta desde sus líneas
CREATE OR REPLACE FUNCTION pos.fn_recalc_order(p_order uuid) RETURNS void AS $$
  UPDATE pos.pos_order o SET
    amount_untaxed = x.untaxed,
    amount_tax = x.tax,
    amount_total = x.untaxed + x.tax
  FROM (SELECT coalesce(sum(l.price_subtotal), 0) AS untaxed,
               coalesce((SELECT sum(t.amount) FROM pos.pos_order_line_tax t JOIN pos.pos_order_line l2 ON l2.id = t.line_id
                         WHERE l2.order_id = p_order), 0) AS tax
        FROM pos.pos_order_line l WHERE l.order_id = p_order) x
  WHERE o.id = p_order;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION pos.fn_validate_order(o pos.pos_order) RETURNS void AS $$
DECLARE
  v_untaxed numeric; v_tax numeric; v_included numeric; v_paid numeric; v_has_cash boolean; v_bad record;
  v_cashier text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pos.pos_order_line WHERE order_id = o.id) THEN
    RAISE EXCEPTION 'ORDER_EMPTY: la venta no tiene líneas';
  END IF;
  -- Cada línea: base + impuestos incluidos = total
  SELECT l.line_no INTO v_bad FROM pos.pos_order_line l
  WHERE l.order_id = o.id
    AND l.price_subtotal + coalesce((SELECT sum(amount) FROM pos.pos_order_line_tax t
                                     WHERE t.line_id = l.id AND t.included_in_price), 0) <> l.price_total
  LIMIT 1;
  IF FOUND THEN RAISE EXCEPTION 'ORDER_LINE_TAX_MISMATCH: en la línea % base + impuesto no da el total', v_bad.line_no; END IF;

  SELECT coalesce(sum(price_subtotal), 0) INTO v_untaxed FROM pos.pos_order_line WHERE order_id = o.id;
  SELECT coalesce(sum(t.amount), 0) INTO v_tax FROM pos.pos_order_line_tax t
  JOIN pos.pos_order_line l ON l.id = t.line_id WHERE l.order_id = o.id;
  IF (o.amount_untaxed, o.amount_tax, o.amount_total) IS DISTINCT FROM (v_untaxed, v_tax, v_untaxed + v_tax) THEN
    RAISE EXCEPTION 'ORDER_TOTALS_MISMATCH: la cabecera no coincide con las líneas (base %, impuestos %)', v_untaxed, v_tax;
  END IF;

  -- Pagos: aprobados = total + redondeo; el vuelto solo en efectivo
  SELECT coalesce(sum(p.amount) FILTER (WHERE p.status IN ('authorized','captured')), 0),
         coalesce(bool_or(m.kind = 'cash' AND p.status IN ('authorized','captured')), false)
  INTO v_paid, v_has_cash
  FROM pos.pos_payment p JOIN pos.payment_method m ON m.id = p.payment_method_id WHERE p.order_id = o.id;
  IF v_paid <> o.amount_total + o.cash_rounding_amount THEN
    RAISE EXCEPTION 'ORDER_PAYMENT_MISMATCH: pagado % para un total de %', v_paid, o.amount_total + o.cash_rounding_amount;
  END IF;
  IF o.cash_rounding_amount <> 0 AND NOT v_has_cash THEN
    RAISE EXCEPTION 'ORDER_ROUNDING_WITHOUT_CASH: el redondeo solo aplica al pago en efectivo';
  END IF;
  IF EXISTS (SELECT 1 FROM pos.pos_payment p JOIN pos.payment_method m ON m.id = p.payment_method_id
             WHERE p.order_id = o.id AND (
               (m.kind <> 'cash' AND (p.change_amount <> 0 OR p.tendered_amount IS NOT NULL))
               OR (m.kind = 'cash' AND p.tendered_amount IS NOT NULL AND p.tendered_amount - p.amount <> p.change_amount))) THEN
    RAISE EXCEPTION 'ORDER_CHANGE_INVALID: el vuelto es entregado − aplicado y solo existe en efectivo';
  END IF;

  -- Devoluciones
  IF EXISTS (SELECT 1 FROM pos.pos_order_line WHERE order_id = o.id AND qty < 0) THEN
    IF o.refund_of_order_id IS NULL THEN
      SELECT code INTO v_cashier FROM pos.pos_user WHERE id = o.cashier_user_id;
      IF o.authorized_by IS NULL OR o.authorized_by = v_cashier THEN
        RAISE EXCEPTION 'REFUND_NO_TICKET_AUTH_REQUIRED: la devolución sin ticket la autoriza un supervisor';
      END IF;
    ELSE
      SELECT l.line_no INTO v_bad FROM pos.pos_order_line l
      LEFT JOIN pos.pos_order_line ol ON ol.id = l.refunded_line_id
      WHERE l.order_id = o.id AND l.qty < 0 AND (ol.id IS NULL OR ol.order_id <> o.refund_of_order_id) LIMIT 1;
      IF FOUND THEN RAISE EXCEPTION 'REFUND_LINE_NOT_IN_ORIGINAL: la línea % no es de la venta original', v_bad.line_no; END IF;

      SELECT l.line_no INTO v_bad FROM pos.pos_order_line l JOIN pos.pos_order_line ol ON ol.id = l.refunded_line_id
      WHERE l.order_id = o.id
        AND -l.qty > ol.qty - coalesce((SELECT -sum(r.qty) FROM pos.pos_order_line r JOIN pos.pos_order ro ON ro.id = r.order_id
                                        WHERE r.refunded_line_id = ol.id AND ro.id <> o.id
                                          AND ro.status IN ('paid','done','posted')), 0)
      LIMIT 1;
      IF FOUND THEN RAISE EXCEPTION 'REFUND_EXCEEDS_SOLD: la línea % devuelve más de lo vendido', v_bad.line_no; END IF;

      SELECT l.line_no INTO v_bad FROM pos.pos_order_line l JOIN pos.pos_order_line ol ON ol.id = l.refunded_line_id
      WHERE l.order_id = o.id AND l.price_total <> round(ol.price_total * l.qty / ol.qty, 2) LIMIT 1;
      IF FOUND THEN RAISE EXCEPTION 'REFUND_PRICE_MISMATCH: la línea % no se devuelve al neto pagado', v_bad.line_no; END IF;

      IF EXISTS (SELECT 1 FROM pos.pos_payment p WHERE p.order_id = o.id
                 AND p.payment_method_id NOT IN (SELECT payment_method_id FROM pos.pos_payment
                                                 WHERE order_id = o.refund_of_order_id)) THEN
        RAISE EXCEPTION 'REFUND_PAYMENT_METHOD_MISMATCH: se reembolsa al medio con que se pagó';
      END IF;
    END IF;
  END IF;
END $$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- 16.4 Comprobantes: numeración, reglas y emisión [MVP]
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pos.fn_next_fiscal_number(p_series uuid) RETURNS bigint AS $$
DECLARE v bigint;
BEGIN
  UPDATE pos.document_series SET next_number = next_number + 1
  WHERE id = p_series AND is_active RETURNING next_number - 1 INTO v;   -- bloqueo de fila: sin huecos
  IF v IS NULL THEN RAISE EXCEPTION 'SERIES_NOT_ACTIVE'; END IF;
  RETURN v;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pos.fn_fiscal_guard() RETURNS trigger AS $$
DECLARE
  sr pos.document_series; ref pos.fiscal_document; v_country char(2); v_threshold numeric; v_noted numeric;
  v_date date;
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'FISCAL_IMMUTABLE: un comprobante no se borra'; END IF;
  IF TG_OP = 'UPDATE' THEN
    IF (to_jsonb(NEW) - ARRAY['status','hash','qr_text','xml_ref','updated_at','updated_by'])
       IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['status','hash','qr_text','xml_ref','updated_at','updated_by']) THEN
      RAISE EXCEPTION 'FISCAL_IMMUTABLE: un comprobante emitido no se edita; se corrige con una nota';
    END IF;
    IF NEW.status <> OLD.status AND (OLD.status, NEW.status) NOT IN
       (('generated','signed'), ('signed','sent'), ('sent','accepted'), ('sent','observed'), ('sent','rejected'),
        ('signed','accepted'), ('signed','observed'), ('signed','rejected'),
        ('accepted','voided'), ('observed','voided')) THEN
      RAISE EXCEPTION 'FISCAL_INVALID_TRANSITION: % → %', OLD.status, NEW.status;
    END IF;
    RETURN NEW;
  END IF;

  SELECT * INTO sr FROM pos.document_series
  WHERE company_id = NEW.company_id AND doc_type = NEW.doc_type AND series = NEW.series;
  IF NOT FOUND OR NOT sr.is_active THEN RAISE EXCEPTION 'FISCAL_SERIES_UNKNOWN: % %', NEW.doc_type, NEW.series; END IF;
  IF sr.terminal_id IS NOT NULL AND sr.terminal_id IS DISTINCT FROM NEW.terminal_id THEN
    RAISE EXCEPTION 'FISCAL_SERIES_NOT_OWNED: la serie % pertenece a otra caja', NEW.series;
  END IF;
  SELECT country_code INTO v_country FROM pos.company WHERE id = NEW.company_id;
  SELECT (NEW.issued_at AT TIME ZONE coalesce(st.timezone, 'UTC'))::date INTO v_date
  FROM (SELECT 1) x LEFT JOIN pos.pos_terminal t ON t.id = NEW.terminal_id LEFT JOIN pos.store st ON st.id = t.store_id;

  IF NEW.doc_type = '01' AND NEW.customer_doc_type IS DISTINCT FROM 'RUC' THEN
    RAISE EXCEPTION 'FISCAL_FACTURA_REQUIRES_RUC: la factura se emite a un cliente con RUC';
  END IF;
  IF NEW.doc_type = '03' THEN
    v_threshold := pos.fn_legal_param(v_country, 'BOLETA_ID_THRESHOLD', v_date);
    IF v_threshold IS NOT NULL AND NEW.total_amount > v_threshold AND NEW.customer_doc_number IS NULL THEN
      RAISE EXCEPTION 'FISCAL_CUSTOMER_ID_REQUIRED: una boleta de más de % identifica al cliente', v_threshold;
    END IF;
  END IF;
  IF NEW.doc_type IN ('07','08') THEN
    SELECT * INTO ref FROM pos.fiscal_document WHERE id = NEW.referenced_document_id;
    IF ref.company_id <> NEW.company_id OR ref.doc_type NOT IN ('01','03') OR ref.status IN ('rejected','voided') THEN
      RAISE EXCEPTION 'FISCAL_NOTE_REFERENCE_INVALID: la nota modifica una factura o boleta válida de la misma empresa';
    END IF;
    IF left(NEW.series, 1) <> left(ref.series, 1) THEN
      RAISE EXCEPTION 'FISCAL_NOTE_SERIES: la serie de la nota sigue a la del comprobante (%)', left(ref.series, 1);
    END IF;
    IF NEW.doc_type = '07' THEN
      SELECT coalesce(sum(total_amount), 0) INTO v_noted FROM pos.fiscal_document
      WHERE referenced_document_id = ref.id AND doc_type = '07' AND status NOT IN ('rejected','voided');
      IF v_noted + NEW.total_amount > ref.total_amount THEN
        RAISE EXCEPTION 'FISCAL_NOTE_EXCEEDS: las notas de crédito superarían el comprobante (% de %)',
          v_noted + NEW.total_amount, ref.total_amount;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_fiscal_guard BEFORE INSERT OR UPDATE OR DELETE ON fiscal_document
  FOR EACH ROW EXECUTE FUNCTION pos.fn_fiscal_guard();

CREATE OR REPLACE FUNCTION pos.fn_fiscal_after_insert() RETURNS trigger AS $$
BEGIN
  UPDATE pos.document_series SET last_used_number = greatest(last_used_number, NEW.number),
         next_number = greatest(next_number, NEW.number + 1)       -- números asignados en la caja sin red
  WHERE company_id = NEW.company_id AND doc_type = NEW.doc_type AND series = NEW.series;
  RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_fiscal_after_insert AFTER INSERT ON fiscal_document
  FOR EACH ROW EXECUTE FUNCTION pos.fn_fiscal_after_insert();

CREATE OR REPLACE FUNCTION pos.fn_fiscal_line_guard() RETURNS trigger AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'FISCAL_IMMUTABLE: las líneas del comprobante no cambian'; END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_fiscal_line_guard BEFORE INSERT OR UPDATE OR DELETE ON fiscal_document_line
  FOR EACH ROW EXECUTE FUNCTION pos.fn_fiscal_line_guard();

-- Emite el comprobante desde la venta cobrada (snapshot), con la serie de la caja.
-- Tipo automático: devolución → nota de crédito; cliente con RUC → factura; si no → boleta.
CREATE OR REPLACE FUNCTION pos.fn_issue_fiscal_document(p_order uuid, p_doc_type text DEFAULT NULL,
                                                        p_note_reason_code text DEFAULT '07',
                                                        p_note_reason text DEFAULT 'Devolución')
RETURNS uuid AS $$
DECLARE
  o pos.pos_order; c pos.customer; st pos.store; v_type text; v_ref pos.fiscal_document; sr pos.document_series;
  v_number bigint; v_doc uuid; v_sign int;
BEGIN
  SELECT * INTO o FROM pos.pos_order WHERE id = p_order;
  IF o.status <> 'paid' THEN RAISE EXCEPTION 'ORDER_NOT_PAID: el comprobante se emite de una venta cobrada'; END IF;
  SELECT * INTO c FROM pos.customer WHERE id = o.customer_id;
  SELECT * INTO st FROM pos.store WHERE id = o.store_id;
  IF o.refund_of_order_id IS NOT NULL THEN
    SELECT * INTO v_ref FROM pos.fiscal_document
    WHERE order_id = o.refund_of_order_id AND doc_type IN ('01','03') AND status NOT IN ('rejected','voided');
    IF NOT FOUND THEN RAISE EXCEPTION 'FISCAL_ORIGINAL_NOT_FOUND: la venta original no tiene comprobante'; END IF;
    v_type := '07';
  ELSE
    v_type := coalesce(p_doc_type, CASE WHEN c.doc_type = 'RUC' THEN '01' ELSE '03' END);
  END IF;
  SELECT * INTO sr FROM pos.document_series
  WHERE terminal_id = o.terminal_id AND doc_type = v_type AND is_active
    AND (v_type NOT IN ('07','08') OR left(series, 1) = left(v_ref.series, 1))
  LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'FISCAL_SERIES_MISSING: la caja no tiene serie para el tipo %', v_type; END IF;
  v_number := pos.fn_next_fiscal_number(sr.id);
  v_sign := CASE WHEN v_type = '07' THEN -1 ELSE 1 END;        -- la nota se emite en positivo

  INSERT INTO pos.fiscal_document(company_id, establishment_id, terminal_id, order_id, doc_type, series, number,
                                  issued_at, customer_doc_type, customer_doc_number, customer_name, currency_code,
                                  total_taxable, total_exempt, total_unaffected, total_free, total_igv,
                                  total_other_taxes, total_amount, rounding_amount, referenced_document_id,
                                  note_reason_code, note_reason)
  SELECT o.company_id, st.establishment_id, o.terminal_id, o.id, v_type, sr.series, v_number, o.occurred_at,
         c.doc_type, c.doc_number, c.name, o.currency_code,
         v_sign * coalesce(sum(l.price_subtotal) FILTER (WHERE tc.kind = 'taxable' AND NOT tc.is_free), 0),
         v_sign * coalesce(sum(l.price_subtotal) FILTER (WHERE tc.kind = 'exempt'), 0),
         v_sign * coalesce(sum(l.price_subtotal) FILTER (WHERE tc.kind = 'unaffected'), 0),
         v_sign * coalesce(sum(l.price_subtotal) FILTER (WHERE tc.is_free), 0),
         v_sign * coalesce((SELECT sum(t.amount) FROM pos.pos_order_line_tax t JOIN pos.pos_order_line l2 ON l2.id = t.line_id
                            WHERE l2.order_id = o.id AND t.included_in_price), 0),
         v_sign * coalesce((SELECT sum(t.amount) FROM pos.pos_order_line_tax t JOIN pos.pos_order_line l2 ON l2.id = t.line_id
                            WHERE l2.order_id = o.id AND NOT t.included_in_price), 0),
         v_sign * o.amount_total, v_sign * o.cash_rounding_amount,
         CASE WHEN v_type IN ('07','08') THEN v_ref.id END,
         CASE WHEN v_type IN ('07','08') THEN p_note_reason_code END,
         CASE WHEN v_type IN ('07','08') THEN p_note_reason END
  FROM pos.pos_order_line l JOIN pos.tax_category tc ON tc.code = l.tax_category_code
  WHERE l.order_id = o.id
  RETURNING id INTO v_doc;

  INSERT INTO pos.fiscal_document_line(document_id, line_no, product_id, description, qty, uom_code, unit_value,
                                       unit_price, line_value, igv_amount, other_tax_amount, discount_amount,
                                       tax_category_code)
  SELECT v_doc, l.line_no, l.product_id, l.description, v_sign * l.qty, u.code,
         round(l.price_subtotal / l.qty, 10), round(l.price_total / l.qty, 10), v_sign * l.price_subtotal,
         v_sign * coalesce((SELECT sum(amount) FROM pos.pos_order_line_tax t WHERE t.line_id = l.id AND t.included_in_price), 0),
         v_sign * coalesce((SELECT sum(amount) FROM pos.pos_order_line_tax t WHERE t.line_id = l.id AND NOT t.included_in_price), 0),
         v_sign * (l.manual_discount_amount + l.promo_discount_amount), l.tax_category_code
  FROM pos.pos_order_line l JOIN pos.product p ON p.id = l.product_id JOIN pos.uom u ON u.id = p.uom_id
  WHERE l.order_id = o.id;
  RETURN v_doc;
END $$ LANGUAGE plpgsql;

-- Cobrada → comprobante → terminada, en una transacción
CREATE OR REPLACE FUNCTION pos.fn_complete_order(p_order uuid, p_doc_type text DEFAULT NULL) RETURNS uuid AS $$
DECLARE v_doc uuid;
BEGIN
  UPDATE pos.pos_order SET status = 'paid' WHERE id = p_order AND status = 'draft';
  v_doc := pos.fn_issue_fiscal_document(p_order, p_doc_type);
  UPDATE pos.pos_order SET status = 'done' WHERE id = p_order;
  RETURN v_doc;
END $$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- 16.5 Tarjetas de regalo: libro mayor sin saldo negativo [F2]
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pos.fn_gift_card_ledger_guard() RETURNS trigger AS $$
DECLARE v_status text; v_balance numeric;
BEGIN
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'GIFT_CARD_LEDGER_IMMUTABLE: se corrige con un asiento de ajuste'; END IF;
  SELECT status INTO v_status FROM pos.gift_card WHERE id = NEW.gift_card_id FOR UPDATE;
  IF NEW.entry_type = 'redeem' AND v_status <> 'active' THEN RAISE EXCEPTION 'GIFT_CARD_NOT_ACTIVE'; END IF;
  SELECT coalesce(sum(amount), 0) INTO v_balance FROM pos.gift_card_ledger WHERE gift_card_id = NEW.gift_card_id;
  IF v_balance + NEW.amount < 0 THEN
    RAISE EXCEPTION 'GIFT_CARD_INSUFFICIENT: saldo % para un consumo de %', v_balance, -NEW.amount;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_gift_card_ledger_guard BEFORE INSERT OR UPDATE OR DELETE ON gift_card_ledger
  FOR EACH ROW EXECUTE FUNCTION pos.fn_gift_card_ledger_guard();

-- -----------------------------------------------------------------------------
-- 16.6 Asiento resumen de la sesión [F2]
--   Debe: cada medio de pago, redondeo a favor del cliente, faltante, caja chica, bóveda
--   Haber: ventas (base), impuestos, sobrante
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pos.fn_jl(p_entry uuid, p_account text, p_amount numeric, p_desc text) RETURNS void AS $$
BEGIN
  IF coalesce(p_amount, 0) = 0 THEN RETURN; END IF;
  IF p_account IS NULL THEN RAISE EXCEPTION 'ACCOUNT_MISSING: falta la cuenta de «%»', p_desc; END IF;
  INSERT INTO pos.session_journal_line(entry_id, account_code, debit, credit, description)
  VALUES (p_entry, p_account, greatest(p_amount, 0), greatest(-p_amount, 0), p_desc);
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pos.fn_post_session(p_session uuid) RETURNS uuid AS $$
DECLARE s pos.pos_session; v_entry uuid; r record; v_cash_acc text; v_diff numeric;
BEGIN
  SELECT * INTO s FROM pos.pos_session WHERE id = p_session FOR UPDATE;
  IF s.status <> 'closed' THEN RAISE EXCEPTION 'SESSION_NOT_CLOSED'; END IF;
  INSERT INTO pos.session_journal_entry(session_id, entry_date)
  SELECT s.id, business_date FROM pos.business_day WHERE id = s.business_day_id RETURNING id INTO v_entry;

  FOR r IN SELECT m.account_code, m.name, sum(p.amount) AS amount
           FROM pos.pos_payment p JOIN pos.pos_order o ON o.id = p.order_id
           JOIN pos.payment_method m ON m.id = p.payment_method_id
           WHERE o.session_id = s.id AND o.status IN ('done','posted') AND p.status IN ('authorized','captured')
           GROUP BY m.account_code, m.name LOOP
    PERFORM pos.fn_jl(v_entry, r.account_code, r.amount, r.name);
  END LOOP;
  PERFORM pos.fn_jl(v_entry, pos.fn_setting('CASH_ROUNDING_ACCOUNT') #>> '{}',
                    -(SELECT coalesce(sum(cash_rounding_amount), 0) FROM pos.pos_order
                      WHERE session_id = s.id AND status IN ('done','posted')), 'Redondeo a favor del cliente');
  PERFORM pos.fn_jl(v_entry, pos.fn_setting('SALES_ACCOUNT') #>> '{}',
                    -(SELECT coalesce(sum(amount_untaxed), 0) FROM pos.pos_order
                      WHERE session_id = s.id AND status IN ('done','posted')), 'Ventas');
  FOR r IN SELECT tx.account_code, tx.code, sum(t.amount) AS amount
           FROM pos.pos_order_line_tax t JOIN pos.pos_order_line l ON l.id = t.line_id
           JOIN pos.pos_order o ON o.id = l.order_id JOIN pos.tax tx ON tx.id = t.tax_id
           WHERE o.session_id = s.id AND o.status IN ('done','posted') GROUP BY tx.account_code, tx.code LOOP
    PERFORM pos.fn_jl(v_entry, r.account_code, -r.amount, r.code);
  END LOOP;

  SELECT m.account_code, d.difference INTO v_cash_acc, v_diff
  FROM pos.session_declaration d JOIN pos.payment_method m ON m.id = d.payment_method_id
  WHERE d.session_id = s.id AND m.kind = 'cash';
  IF v_diff < 0 THEN
    PERFORM pos.fn_jl(v_entry, pos.fn_setting('CASH_SHORTAGE_ACCOUNT') #>> '{}', -v_diff, 'Faltante de caja');
    PERFORM pos.fn_jl(v_entry, v_cash_acc, v_diff, 'Faltante de caja');
  ELSIF v_diff > 0 THEN
    PERFORM pos.fn_jl(v_entry, v_cash_acc, v_diff, 'Sobrante de caja');
    PERFORM pos.fn_jl(v_entry, pos.fn_setting('CASH_OVERAGE_ACCOUNT') #>> '{}', -v_diff, 'Sobrante de caja');
  END IF;
  FOR r IN SELECT kind, sum(amount) AS amount FROM pos.cash_movement WHERE session_id = s.id GROUP BY kind LOOP
    IF r.kind IN ('safe_drop','cash_in') THEN
      PERFORM pos.fn_jl(v_entry, pos.fn_setting('SAFE_ACCOUNT') #>> '{}',
                        CASE WHEN r.kind = 'safe_drop' THEN r.amount ELSE -r.amount END, 'Bóveda');
      PERFORM pos.fn_jl(v_entry, v_cash_acc, CASE WHEN r.kind = 'safe_drop' THEN -r.amount ELSE r.amount END, 'Bóveda');
    ELSIF r.kind = 'petty_cash' THEN
      PERFORM pos.fn_jl(v_entry, pos.fn_setting('PETTY_CASH_ACCOUNT') #>> '{}', r.amount, 'Caja chica');
      PERFORM pos.fn_jl(v_entry, v_cash_acc, -r.amount, 'Caja chica');
    END IF;
  END LOOP;

  UPDATE pos.pos_order SET status = 'posted' WHERE session_id = s.id AND status = 'done';
  UPDATE pos.pos_session SET status = 'posted', posted_at = now() WHERE id = s.id;
  RETURN v_entry;
END $$ LANGUAGE plpgsql;

-- =============================================================================
-- 15. VISTAS
-- =============================================================================
CREATE OR REPLACE VIEW v_session_close AS
SELECT s.id AS session_id, s.terminal_id, s.status, m.code AS payment_method, e.expected_amount,
       d.declared_amount, d.declared_amount - e.expected_amount AS difference
FROM pos.pos_session s
CROSS JOIN LATERAL pos.fn_session_expected(s.id) e
JOIN pos.payment_method m ON m.id = e.payment_method_id
LEFT JOIN pos.session_declaration d ON d.session_id = s.id AND d.payment_method_id = e.payment_method_id;

CREATE OR REPLACE VIEW v_order_refundable AS
SELECT ol.order_id, ol.id AS line_id, ol.product_id, ol.qty AS sold_qty,
       coalesce(-sum(r.qty) FILTER (WHERE ro.status IN ('paid','done','posted')), 0) AS refunded_qty,
       ol.qty - coalesce(-sum(r.qty) FILTER (WHERE ro.status IN ('paid','done','posted')), 0) AS refundable_qty,
       round(ol.price_total / ol.qty, 4) AS net_unit_price
FROM pos.pos_order_line ol
LEFT JOIN pos.pos_order_line r ON r.refunded_line_id = ol.id
LEFT JOIN pos.pos_order ro ON ro.id = r.order_id
WHERE ol.qty > 0
GROUP BY ol.order_id, ol.id, ol.product_id, ol.qty, ol.price_total;

-- Comprobantes sin aceptación y días que quedan para enviarlos (plazos en legal_parameter)
CREATE OR REPLACE VIEW v_fiscal_pending AS
SELECT d.id, d.doc_type, d.series, d.number, d.issued_at, d.status,
       d.issued_at::date + pos.fn_legal_param(c.country_code,
         CASE WHEN d.doc_type = '01' OR (d.doc_type IN ('07','08') AND left(d.series, 1) = 'F')
              THEN 'FACTURA_SEND_DAYS' ELSE 'BOLETA_SEND_DAYS' END, d.issued_at::date)::int AS send_deadline
FROM pos.fiscal_document d JOIN pos.company c ON c.id = d.company_id
WHERE d.status IN ('generated','signed','sent');

-- Huecos en la numeración de cada serie (un número que falta es un incidente fiscal)
CREATE OR REPLACE VIEW v_fiscal_number_gaps AS
SELECT s.company_id, s.doc_type, s.series, g.n AS missing_number
FROM pos.document_series s
CROSS JOIN LATERAL generate_series(1::bigint, s.last_used_number) g(n)
WHERE NOT EXISTS (SELECT 1 FROM pos.fiscal_document d
                  WHERE d.company_id = s.company_id AND d.doc_type = s.doc_type AND d.series = s.series AND d.number = g.n);

CREATE OR REPLACE VIEW v_gift_card_balance AS
SELECT g.id, g.code, g.status, coalesce(sum(l.amount), 0) AS balance
FROM pos.gift_card g LEFT JOIN pos.gift_card_ledger l ON l.gift_card_id = g.id GROUP BY g.id, g.code, g.status;

CREATE OR REPLACE VIEW v_daily_sales AS
SELECT o.store_id, o.business_date, m.code AS payment_method, count(DISTINCT o.id) AS orders, sum(p.amount) AS amount
FROM pos.pos_order o JOIN pos.pos_payment p ON p.order_id = o.id JOIN pos.payment_method m ON m.id = p.payment_method_id
WHERE o.status IN ('done','posted') AND p.status IN ('authorized','captured')
GROUP BY o.store_id, o.business_date, m.code;

-- Venta neta por vendedor (base de comisiones; devoluciones restan)
CREATE OR REPLACE VIEW v_salesperson_net_sales AS
SELECT coalesce(l.salesperson_user_id, o.salesperson_user_id) AS salesperson_user_id, o.business_date,
       sum(l.price_subtotal) AS net_sales
FROM pos.pos_order_line l JOIN pos.pos_order o ON o.id = l.order_id
WHERE o.status IN ('done','posted') AND coalesce(l.salesperson_user_id, o.salesperson_user_id) IS NOT NULL
GROUP BY 1, 2;

-- Lo que la caja debe descargar: filas con versión mayor a su cursor
CREATE OR REPLACE VIEW v_catalog_changes AS
SELECT 'product' AS entity, id, row_version FROM pos.product
UNION ALL SELECT 'product_barcode', id, row_version FROM pos.product_barcode
UNION ALL SELECT 'product_category', id, row_version FROM pos.product_category
UNION ALL SELECT 'tax', id, row_version FROM pos.tax
UNION ALL SELECT 'tax_rate', id, row_version FROM pos.tax_rate
UNION ALL SELECT 'pricelist_item', id, row_version FROM pos.pricelist_item
UNION ALL SELECT 'promotion', id, row_version FROM pos.promotion
UNION ALL SELECT 'customer', id, row_version FROM pos.customer;

CREATE OR REPLACE VIEW v_open_sync_exceptions AS
SELECT e.*, o.store_id, o.terminal_id FROM pos.pos_sync_exception e LEFT JOIN pos.pos_order o ON o.id = e.order_id
WHERE e.status = 'open';
