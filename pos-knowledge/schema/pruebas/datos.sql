-- Datos base de las pruebas: una bodega en Lima con cinco cajas, IGV, ICBPER y medios de pago.
-- Se carga una vez, antes de las demás pruebas. Valores legales de localizacion/peru.md.
SET search_path = pos, public;
\set ON_ERROR_STOP on
\set QUIET on

INSERT INTO legal_parameter(country_code, code, name, value, valid_from, source_ref) VALUES
  ('PE', 'BOLETA_ID_THRESHOLD', 'Boleta: identificar al adquirente sobre este importe', 700, '2019-01-01', 'RS 097-2012/SUNAT, mod. RS 303-2018/SUNAT (vigencia: verificar)'),
  ('PE', 'FACTURA_SEND_DAYS', 'Factura: días calendario para enviarla', 3, '2023-01-01', 'RS 000003-2023/SUNAT (vigencia: verificar)'),
  ('PE', 'BOLETA_SEND_DAYS', 'Boleta: días calendario para enviarla', 7, '2019-01-01', 'Verificar');

INSERT INTO company(id, code, legal_name, tax_id, country_code, currency_code) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'BOD', 'Bodega San Martín SAC', '20111111111', 'PE', 'PEN'),
  ('a0000000-0000-0000-0000-000000000002', 'RES', 'Cevichería del Puerto SAC', '20222222222', 'PE', 'PEN');
INSERT INTO establishment(id, company_id, code, name)
VALUES ('a0000000-0000-0000-0000-000000000011', 'a0000000-0000-0000-0000-000000000001', '0000', 'Local principal');

INSERT INTO uom(id, code, name, decimals) VALUES
  ('a0000000-0000-0000-0000-000000000021', 'NIU', 'Unidad', 0),
  ('a0000000-0000-0000-0000-000000000022', 'KGM', 'Kilogramo', 3);
INSERT INTO tax_category(code, name, kind) VALUES
  ('10', 'Gravado – operación onerosa', 'taxable'),
  ('20', 'Exonerado – operación onerosa', 'exempt'),
  ('30', 'Inafecto – operación onerosa', 'unaffected');
INSERT INTO tax(id, code, name, kind, included_in_price, account_code) VALUES
  ('a0000000-0000-0000-0000-000000000031', 'IGV', 'Impuesto general a las ventas', 'percent', true, '40111'),
  ('a0000000-0000-0000-0000-000000000032', 'ICBPER', 'Impuesto a las bolsas plásticas', 'fixed_per_unit', false, '40189');
INSERT INTO tax_rate(tax_id, rate, amount, valid_from, source_ref) VALUES
  ('a0000000-0000-0000-0000-000000000031', 0.18, NULL, '2011-03-01', 'Ley 29666 (16 % IGV + 2 % IPM)'),
  ('a0000000-0000-0000-0000-000000000032', NULL, 0.50, '2023-01-01', 'Ley 30884');
INSERT INTO tax_category_tax VALUES ('10', 'a0000000-0000-0000-0000-000000000031');

INSERT INTO pricelist(id, code, name, currency_code)
VALUES ('a0000000-0000-0000-0000-000000000041', 'GEN', 'Precios de tienda', 'PEN');
INSERT INTO store(id, company_id, establishment_id, code, name, timezone, default_pricelist_id)
VALUES ('a0000000-0000-0000-0000-000000000051', 'a0000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000011', 'T01', 'Bodega Miraflores', 'America/Lima',
        'a0000000-0000-0000-0000-000000000041');

-- Cinco cajas, cada una con sus series: boleta B00n, factura F00n y notas de crédito BC0n / FC0n
INSERT INTO pos_terminal(id, store_id, code, name)
SELECT ('a0000000-0000-0000-0000-00000000006' || n)::uuid, 'a0000000-0000-0000-0000-000000000051', 'CAJA' || n, 'Caja ' || n
FROM generate_series(1, 5) n;
INSERT INTO document_series(company_id, terminal_id, doc_type, series)
SELECT 'a0000000-0000-0000-0000-000000000001', ('a0000000-0000-0000-0000-00000000006' || n)::uuid, d.doc_type, d.prefix || n
FROM generate_series(1, 5) n,
     (VALUES ('03', 'B00'), ('01', 'F00'), ('07', 'BC0'), ('07', 'FC0')) d(doc_type, prefix);

INSERT INTO pos_user(id, code, name, role) VALUES
  ('a0000000-0000-0000-0000-000000000071', 'ana', 'Ana Quispe', 'cashier'),
  ('a0000000-0000-0000-0000-000000000072', 'luis', 'Luis Rojas', 'supervisor');

INSERT INTO product(id, sku, name, uom_id, product_type, tax_category_code) VALUES
  ('a0000000-0000-0000-0000-000000000081', 'DET', 'Detergente 1 kg', 'a0000000-0000-0000-0000-000000000021', 'stockable', '10'),
  ('a0000000-0000-0000-0000-000000000082', 'GAL', 'Galletas', 'a0000000-0000-0000-0000-000000000021', 'stockable', '10'),
  ('a0000000-0000-0000-0000-000000000083', 'BOL', 'Bolsa plástica', 'a0000000-0000-0000-0000-000000000021', 'consumable', '10'),
  ('a0000000-0000-0000-0000-000000000084', 'POLO', 'Polo básico', 'a0000000-0000-0000-0000-000000000021', 'stockable', '10'),
  ('a0000000-0000-0000-0000-000000000085', 'TV', 'Televisor 50"', 'a0000000-0000-0000-0000-000000000021', 'stockable', '10'),
  ('a0000000-0000-0000-0000-000000000086', 'VAR', 'Venta variada', 'a0000000-0000-0000-0000-000000000021', 'stockable', '10');
INSERT INTO product_tax VALUES ('a0000000-0000-0000-0000-000000000083', 'a0000000-0000-0000-0000-000000000032');
INSERT INTO pricelist_item(pricelist_id, product_id, price, valid_from)
SELECT 'a0000000-0000-0000-0000-000000000041', p.id, v.price, '2026-01-01'
FROM (VALUES ('DET', 12.95), ('GAL', 2.45), ('BOL', 0.20), ('POLO', 40.00), ('TV', 1899.00)) v(sku, price)
JOIN product p ON p.sku = v.sku;

INSERT INTO payment_method(id, code, name, kind, applies_cash_rounding, requires_online, account_code) VALUES
  ('a0000000-0000-0000-0000-000000000091', 'EFE', 'Efectivo', 'cash', true, false, '1011'),
  ('a0000000-0000-0000-0000-000000000092', 'TAR', 'Tarjeta', 'card', false, true, '1213'),
  ('a0000000-0000-0000-0000-000000000093', 'QR', 'Billetera QR', 'wallet_qr', false, true, '1214'),
  ('a0000000-0000-0000-0000-000000000094', 'GC', 'Tarjeta de regalo', 'gift_card', false, true, '4961');
INSERT INTO store_payment_method SELECT 'a0000000-0000-0000-0000-000000000051', id FROM payment_method;

INSERT INTO customer(id, doc_type, doc_number, name) VALUES
  ('a0000000-0000-0000-0000-0000000000a1', 'DNI', '41234567', 'María Pérez'),
  ('a0000000-0000-0000-0000-0000000000a2', 'RUC', '20123456789', 'Cliente Corporativo SAC');

UPDATE pos_setting SET value = to_jsonb(v.acc)
FROM (VALUES ('SALES_ACCOUNT', '70111'), ('CASH_ROUNDING_ACCOUNT', '6591'), ('CASH_SHORTAGE_ACCOUNT', '6592'),
             ('CASH_OVERAGE_ACCOUNT', '7592'), ('PETTY_CASH_ACCOUNT', '6593'), ('SAFE_ACCOUNT', '1012')) v(code, acc)
WHERE pos_setting.code = v.code;

-- Ayuda de las pruebas: abre una sesión en una caja y devuelve su id
CREATE OR REPLACE FUNCTION pos.t_open_session(p_terminal int, p_float numeric) RETURNS uuid AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO pos.pos_session(terminal_id, cashier_user_id, opening_float)
  VALUES (('a0000000-0000-0000-0000-00000000006' || p_terminal)::uuid, 'a0000000-0000-0000-0000-000000000071', p_float)
  RETURNING id INTO v;
  UPDATE pos.pos_session SET status = 'opened' WHERE id = v;
  RETURN v;
END $$ LANGUAGE plpgsql;

-- Ayuda de las pruebas: crea una venta en borrador con el id que generaría la caja
CREATE OR REPLACE FUNCTION pos.t_new_order(p_id uuid, p_session uuid, p_customer uuid DEFAULT NULL,
                                           p_refund_of uuid DEFAULT NULL) RETURNS uuid AS $$
  INSERT INTO pos.pos_order(id, session_id, cashier_user_id, customer_id, pricelist_id, occurred_at, currency_code,
                            refund_of_order_id, terminal_id, store_id, company_id, business_date)
  VALUES (p_id, p_session, 'a0000000-0000-0000-0000-000000000071', p_customer, 'a0000000-0000-0000-0000-000000000041',
          now(), 'PEN', p_refund_of, 'a0000000-0000-0000-0000-000000000061', 'a0000000-0000-0000-0000-000000000051',
          'a0000000-0000-0000-0000-000000000001', current_date)
  RETURNING id;
$$ LANGUAGE sql;

-- Ayuda de las pruebas: agrega un pago con el id que generaría la caja
CREATE OR REPLACE FUNCTION pos.t_pay(p_order uuid, p_method text, p_amount numeric, p_tendered numeric DEFAULT NULL)
RETURNS uuid AS $$
  INSERT INTO pos.pos_payment(id, order_id, payment_method_id, amount, tendered_amount, change_amount)
  SELECT gen_random_uuid(), p_order, m.id, p_amount, p_tendered, coalesce(p_tendered - p_amount, 0)
  FROM pos.payment_method m WHERE m.code = p_method
  RETURNING id;
$$ LANGUAGE sql;
