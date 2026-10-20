-- Reglas de Perú: el ticket de localizacion/peru.md, IGV reducido por empresa, umbral de la boleta,
-- factura solo con RUC y plazos de envío. Requiere pruebas/datos.sql.
SET search_path = pos, public;
\set ON_ERROR_STOP on
\set QUIET on
\pset footer off
SET app.user_id = 'ana';
SELECT t_open_session(3, 200) AS s3 \gset

\echo '== 1. Ticket: 2 detergentes, 3 galletas y una bolsa; IGV incluido, ICBPER aparte'
SELECT t_new_order('c0000000-0000-0000-0000-000000000001', :'s3') \gset
SELECT count(fn_add_line('c0000000-0000-0000-0000-000000000001', p.id, v.qty)) AS lineas
FROM (VALUES ('DET', 2), ('GAL', 3), ('BOL', 1)) v(sku, qty) JOIN product p ON p.sku = v.sku;
SELECT fn_recalc_order('c0000000-0000-0000-0000-000000000001') \gset
SELECT l.description AS linea, l.qty AS cant, l.list_price AS precio, l.price_total AS importe,
       l.price_subtotal AS base,
       sum(t.amount) FILTER (WHERE t.included_in_price) AS igv,
       sum(t.amount) FILTER (WHERE NOT t.included_in_price) AS icbper
FROM pos_order_line l JOIN pos_order_line_tax t ON t.line_id = l.id
WHERE l.order_id = 'c0000000-0000-0000-0000-000000000001'
GROUP BY l.line_no, l.description, l.qty, l.list_price, l.price_total, l.price_subtotal ORDER BY l.line_no;

\echo '== 2. Cobro en efectivo: 33.95 se redondea a favor del cliente a 33.90; paga 50.00, vuelto 16.10'
UPDATE pos_order SET cash_rounding_amount = fn_cash_rounding(amount_total) WHERE id = 'c0000000-0000-0000-0000-000000000001';
SELECT t_pay('c0000000-0000-0000-0000-000000000001', 'EFE', 33.90, 50.00) \gset
SELECT fn_complete_order('c0000000-0000-0000-0000-000000000001') \gset
SELECT d.series || '-' || d.number AS boleta, d.total_taxable AS gravado, d.total_igv AS igv,
       d.total_other_taxes AS icbper, d.total_amount AS importe_total, d.rounding_amount AS redondeo,
       p.amount AS cobrado, p.tendered_amount AS entregado, p.change_amount AS vuelto
FROM fiscal_document d JOIN pos_payment p ON p.order_id = d.order_id
WHERE d.order_id = 'c0000000-0000-0000-0000-000000000001';
SELECT line_no, unit_value AS valor_unitario_xml, unit_price AS precio_unitario, line_value AS valor_venta, igv_amount AS igv
FROM fiscal_document_line WHERE document_id = (SELECT id FROM fiscal_document WHERE order_id = 'c0000000-0000-0000-0000-000000000001')
ORDER BY line_no;

\echo '== 3. Redondeo: solo con efectivo'
DO $$ BEGIN
  PERFORM pos.t_new_order('c0000000-0000-0000-0000-000000000002', (SELECT id FROM pos.pos_session WHERE terminal_id = 'a0000000-0000-0000-0000-000000000063'));
  PERFORM pos.fn_add_line('c0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000081', 1);
  PERFORM pos.fn_recalc_order('c0000000-0000-0000-0000-000000000002');
  UPDATE pos.pos_order SET cash_rounding_amount = -0.05 WHERE id = 'c0000000-0000-0000-0000-000000000002';
  PERFORM pos.t_pay('c0000000-0000-0000-0000-000000000002', 'TAR', 12.90);
  UPDATE pos.pos_order SET status = 'paid' WHERE id = 'c0000000-0000-0000-0000-000000000002';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;

\echo '== 4. Boleta de 1,899.00: sin documento del cliente no se emite; con DNI, sí'
SELECT t_new_order('c0000000-0000-0000-0000-000000000003', :'s3') \gset
SELECT fn_add_line('c0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000085', 1) \gset
SELECT fn_recalc_order('c0000000-0000-0000-0000-000000000003') \gset
SELECT t_pay('c0000000-0000-0000-0000-000000000003', 'TAR', 1899.00) \gset
DO $$ BEGIN
  PERFORM pos.fn_complete_order('c0000000-0000-0000-0000-000000000003');
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
UPDATE pos_order SET customer_id = 'a0000000-0000-0000-0000-0000000000a1' WHERE id = 'c0000000-0000-0000-0000-000000000003';
SELECT fn_complete_order('c0000000-0000-0000-0000-000000000003') \gset
SELECT series || '-' || number AS boleta, customer_doc_type || ' ' || customer_doc_number AS cliente, total_amount
FROM fiscal_document WHERE order_id = 'c0000000-0000-0000-0000-000000000003';

\echo '== 5. Factura: solo a un cliente con RUC'
SELECT t_new_order('c0000000-0000-0000-0000-000000000004', :'s3', 'a0000000-0000-0000-0000-0000000000a1') \gset
SELECT fn_add_line('c0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000081', 10) \gset
SELECT fn_recalc_order('c0000000-0000-0000-0000-000000000004') \gset
SELECT t_pay('c0000000-0000-0000-0000-000000000004', 'TAR', 129.50) \gset
DO $$ BEGIN
  PERFORM pos.fn_complete_order('c0000000-0000-0000-0000-000000000004', '01');
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
UPDATE pos_order SET customer_id = 'a0000000-0000-0000-0000-0000000000a2' WHERE id = 'c0000000-0000-0000-0000-000000000004';
SELECT fn_complete_order('c0000000-0000-0000-0000-000000000004') \gset
SELECT series || '-' || number AS factura, customer_doc_number AS ruc, total_taxable AS base, total_igv AS igv, total_amount
FROM fiscal_document WHERE order_id = 'c0000000-0000-0000-0000-000000000004';

\echo '== 6. Plazo de envío: factura 3 días, boleta 7 (parámetros legales con vigencia)'
SELECT doc_type AS tipo, series || '-' || number AS comprobante, send_deadline - (issued_at AT TIME ZONE 'America/Lima')::date AS dias_para_enviar
FROM v_fiscal_pending WHERE series IN ('B003','F003') ORDER BY doc_type, number;

\echo '== 7. IGV reducido 2026 para la cevichería (8 % + 2.5 % IPM); el resto sigue con 18 %'
INSERT INTO tax_rate(tax_id, company_id, rate, valid_from, valid_to, source_ref)
VALUES ('a0000000-0000-0000-0000-000000000031', 'a0000000-0000-0000-0000-000000000002', 0.105, '2026-01-01', '2027-01-01',
        'Ley 31556, prórroga Ley 32219, IPM Ley 32387');
SELECT (fn_tax_rate('a0000000-0000-0000-0000-000000000031', 'a0000000-0000-0000-0000-000000000002', '2026-10-16')).rate AS igv_cevicheria,
       (fn_tax_rate('a0000000-0000-0000-0000-000000000031', 'a0000000-0000-0000-0000-000000000001', '2026-10-16')).rate AS igv_bodega,
       round(25.00 / 1.105, 2) AS base_menu_25, 25.00 - round(25.00 / 1.105, 2) AS igv_menu_25;
DO $$ BEGIN
  INSERT INTO pos.tax_rate(tax_id, rate, valid_from, source_ref) VALUES ('a0000000-0000-0000-0000-000000000031', 0.19, '2026-06-01', 'prueba');
  RAISE NOTICE 'MAL'; EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'OK TAX_RATE_OVERLAP (dos tasas generales vigentes a la vez)'; END $$;
RESET app.user_id;
