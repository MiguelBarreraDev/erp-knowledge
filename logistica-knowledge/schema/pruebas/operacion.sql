-- Conteo con la operación en marcha, compras con aprobación, recepción parcial, tres vías y reposición.
SET search_path = scm, public;
\set ON_ERROR_STOP on
\set QUIET on
\pset footer off

INSERT INTO company(id, code, legal_name, country_code, currency_code)
VALUES ('30000000-0000-0000-0000-000000000001', 'OPE', 'Operación SAC', 'PE', 'PEN');
INSERT INTO uom_category(id, name) VALUES ('30000000-0000-0000-0000-000000000010', 'Unidad (ope)');
INSERT INTO uom(id, category_id, code, name, ratio, is_reference)
VALUES ('30000000-0000-0000-0000-000000000011', '30000000-0000-0000-0000-000000000010', 'U-OPE', 'Unidad', 1, true);
INSERT INTO product_category(id, name) VALUES ('30000000-0000-0000-0000-000000000021', 'General');
INSERT INTO product_template(id, name, category_id, uom_id) VALUES
  ('30000000-0000-0000-0000-000000000031', 'Conteo', '30000000-0000-0000-0000-000000000021', '30000000-0000-0000-0000-000000000011'),
  ('30000000-0000-0000-0000-000000000032', 'Compra', '30000000-0000-0000-0000-000000000021', '30000000-0000-0000-0000-000000000011');
INSERT INTO product(id, template_id, sku, name) VALUES
  ('30000000-0000-0000-0000-000000000041', '30000000-0000-0000-0000-000000000031', 'CNT', 'Producto contado'),
  ('30000000-0000-0000-0000-000000000042', '30000000-0000-0000-0000-000000000032', 'CMP', 'Producto comprado');
INSERT INTO partner(id, doc_type, doc_number, name, is_supplier)
VALUES ('30000000-0000-0000-0000-000000000050', 'RUC', '20999999992', 'Distribuidora SA', true);
SELECT fn_create_warehouse('30000000-0000-0000-0000-000000000001', 'OPE', 'Almacén operación') AS wh \gset
SELECT stock_location_id AS stock FROM warehouse WHERE id = :'wh' \gset

\echo '== 1. Conteo: foto de 50, se venden 5 durante el conteo, se cuentan 44'
SELECT fn_quick_move(NULL, '30000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000041', 50,
                     fn_vloc('supplier'), :'stock', 8) \gset
INSERT INTO stock_count(id, company_id, warehouse_id, name)
VALUES ('30000000-0000-0000-0000-0000000000c1', '30000000-0000-0000-0000-000000000001', :'wh', 'CC-0001');
INSERT INTO stock_count_line(count_id, location_id, product_id)
VALUES ('30000000-0000-0000-0000-0000000000c1', :'stock', '30000000-0000-0000-0000-000000000041');
SELECT fn_start_count('30000000-0000-0000-0000-0000000000c1') \gset
SELECT fn_quick_move('pos:OPE-1', '30000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000041', 5,
                     :'stock', fn_vloc('customer')) \gset
UPDATE stock_count_line SET counted_qty = 44, counted_at = now() WHERE count_id = '30000000-0000-0000-0000-0000000000c1';
SELECT fn_apply_count('30000000-0000-0000-0000-0000000000c1') AS ajustes;
SELECT cl.expected_qty AS foto, cl.counted_qty AS contado, cl.difference_qty AS diferencia, q.quantity AS saldo_final
FROM stock_count_line cl JOIN stock_quant q ON q.product_id = cl.product_id AND q.location_id = cl.location_id
WHERE cl.count_id = '30000000-0000-0000-0000-0000000000c1';
DO $$ BEGIN
  PERFORM scm.fn_apply_count('30000000-0000-0000-0000-0000000000c1');
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;

\echo '== 2. Orden de compra de 1,200.00 con límite de aprobación de 1,000.00: nadie se aprueba a sí mismo'
UPDATE scm_setting SET value = '1000' WHERE code = 'PO_APPROVAL_AMOUNT';
SET app.user_id = 'ana';
INSERT INTO purchase_order(id, company_id, name, partner_id, warehouse_id, currency_code)
VALUES ('30000000-0000-0000-0000-0000000000f1', '30000000-0000-0000-0000-000000000001', 'OC-OPE-1',
        '30000000-0000-0000-0000-000000000050', :'wh', 'PEN');
INSERT INTO purchase_order_line(id, order_id, product_id, qty, uom_id, price_unit) VALUES
  ('30000000-0000-0000-0000-0000000000f2', '30000000-0000-0000-0000-0000000000f1', '30000000-0000-0000-0000-000000000042', 100, '30000000-0000-0000-0000-000000000011', 10),
  ('30000000-0000-0000-0000-0000000000f3', '30000000-0000-0000-0000-0000000000f1', '30000000-0000-0000-0000-000000000041', 25, '30000000-0000-0000-0000-000000000011', 8);
DO $$ BEGIN
  UPDATE scm.purchase_order SET status = 'purchase' WHERE id = '30000000-0000-0000-0000-0000000000f1';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
DO $$ BEGIN
  UPDATE scm.purchase_order SET status = 'purchase', approved_by = 'ana' WHERE id = '30000000-0000-0000-0000-0000000000f1';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
SET app.user_id = 'luis';
UPDATE purchase_order SET status = 'purchase', approved_by = 'luis' WHERE id = '30000000-0000-0000-0000-0000000000f1';
SELECT status, approved_by AS aprobada_por FROM purchase_order WHERE id = '30000000-0000-0000-0000-0000000000f1';
RESET app.user_id;

\echo '== 3. Recepción parcial: llegan 80 de 100; queda un pendiente de 20'
SELECT fn_create_receipt('30000000-0000-0000-0000-0000000000f1') AS receipt \gset
SELECT count(fn_done_move(id, CASE WHEN purchase_line_id = '30000000-0000-0000-0000-0000000000f2' THEN 80 END))
       AS movimientos_hechos
FROM stock_move WHERE picking_id = :'receipt';
SELECT pl.product_id = '30000000-0000-0000-0000-000000000042' AS es_cmp, m.product_qty AS cantidad, m.status
FROM stock_move m JOIN purchase_order_line pl ON pl.id = m.purchase_line_id
WHERE m.picking_id = :'receipt' ORDER BY 1 DESC, m.status;

\echo '== 4. Tres vías: factura de 80 a 10.40 (precio fuera de tolerancia) y de 25 a 8.00'
INSERT INTO vendor_bill(id, company_id, partner_id, series, number, bill_date, currency_code, status)
VALUES ('30000000-0000-0000-0000-0000000000b1', '30000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000050', 'F001', '000123', '2026-10-16', 'PEN', 'posted');
INSERT INTO vendor_bill_line(bill_id, purchase_line_id, qty, price_unit, amount) VALUES
  ('30000000-0000-0000-0000-0000000000b1', '30000000-0000-0000-0000-0000000000f2', 80, 10.40, 832.00),
  ('30000000-0000-0000-0000-0000000000b1', '30000000-0000-0000-0000-0000000000f3', 25, 8.00, 200.00);
SELECT p.sku AS producto, ordered_qty AS pedido, received_qty AS recibido, billed_qty AS facturado,
       po_price AS precio_oc, billed_price AS precio_factura, match_status AS resultado
FROM v_three_way_match t JOIN product p ON p.id = t.product_id
WHERE t.order_id = '30000000-0000-0000-0000-0000000000f1' ORDER BY p.sku;

\echo '== 5. Reposición: mínimo 237, máximo 1,091, múltiplo 12; posición 200 → pedir 900'
INSERT INTO replenishment_rule(warehouse_id, product_id, min_qty, max_qty, multiple_qty, partner_id)
VALUES (:'wh', '30000000-0000-0000-0000-000000000042', 237, 1091, 12, '30000000-0000-0000-0000-000000000050');
SELECT fn_quick_move(NULL, '30000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000042', 100,
                     fn_vloc('supplier'), :'stock', 10) \gset
SELECT a.on_hand AS fisico, a.incoming AS entrante, a.outgoing AS saliente, s.position AS posicion,
       s.suggested_qty AS sugerido
FROM v_replenishment_suggestion s JOIN v_stock_availability a ON a.warehouse_id = s.warehouse_id AND a.product_id = s.product_id
WHERE s.product_id = '30000000-0000-0000-0000-000000000042';
