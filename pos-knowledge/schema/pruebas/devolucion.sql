-- Devoluciones: 3 × 2 prorrateado (venta.md), nota de crédito, reglas de reembolso y tarjeta de regalo.
-- Requiere pruebas/datos.sql.
SET search_path = pos, public;
\set ON_ERROR_STOP on
\set QUIET on
\pset footer off
SET app.user_id = 'ana';
SELECT t_open_session(5, 200) AS s5 \gset

\echo '== 1. Tres polos a 40.00 con 3 × 2: el descuento de 40.00 se prorratea en las líneas'
SELECT t_new_order('e0000000-0000-0000-0000-000000000001', :'s5') \gset
SELECT count(fn_add_line('e0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000084', 1, NULL, 0, d))
       AS lineas FROM unnest(ARRAY[13.33, 13.33, 13.34]) d;
SELECT fn_recalc_order('e0000000-0000-0000-0000-000000000001') \gset
SELECT t_pay('e0000000-0000-0000-0000-000000000001', 'TAR', 80.00) \gset
SELECT fn_complete_order('e0000000-0000-0000-0000-000000000001') \gset
SELECT line_no AS linea, list_price AS lista, promo_discount_amount AS descuento, price_total AS neto_pagado
FROM pos_order_line WHERE order_id = 'e0000000-0000-0000-0000-000000000001' ORDER BY line_no;

\echo '== 2. Devuelve un polo: se reembolsa su neto (26.67) a la tarjeta y se emite nota de crédito'
SELECT id AS linea1 FROM pos_order_line WHERE order_id = 'e0000000-0000-0000-0000-000000000001' AND line_no = 1 \gset
SELECT t_new_order('e0000000-0000-0000-0000-000000000002', :'s5', NULL, 'e0000000-0000-0000-0000-000000000001') \gset
SELECT fn_add_line('e0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000084', -1, NULL, 0, 0, :'linea1') \gset
SELECT fn_recalc_order('e0000000-0000-0000-0000-000000000002') \gset
SELECT t_pay('e0000000-0000-0000-0000-000000000002', 'TAR', -26.67) \gset
SELECT fn_complete_order('e0000000-0000-0000-0000-000000000002') AS nota \gset
SELECT d.series || '-' || d.number AS nota, d.total_amount AS importe, d.note_reason_code AS motivo,
       r.series || '-' || r.number AS modifica
FROM fiscal_document d JOIN fiscal_document r ON r.id = d.referenced_document_id WHERE d.id = :'nota';
SELECT e.qty AS efecto_stock FROM stock_effect e JOIN pos_order_line l ON l.id = e.order_line_id
WHERE l.order_id = 'e0000000-0000-0000-0000-000000000002';
SELECT line_id = :'linea1' AS es_linea1, sold_qty AS vendido, refunded_qty AS devuelto, refundable_qty AS se_puede_devolver
FROM v_order_refundable WHERE order_id = 'e0000000-0000-0000-0000-000000000001' ORDER BY 1 DESC, line_id LIMIT 2;

\echo '== 3. Reglas de la devolución'
DO $$ DECLARE v uuid; BEGIN   -- devolver otra vez el mismo polo
  SELECT id INTO v FROM pos.pos_order_line WHERE order_id = 'e0000000-0000-0000-0000-000000000001' AND line_no = 1;
  PERFORM pos.t_new_order('e0000000-0000-0000-0000-000000000003', (SELECT id FROM pos.pos_session WHERE terminal_id = 'a0000000-0000-0000-0000-000000000065'), NULL, 'e0000000-0000-0000-0000-000000000001');
  PERFORM pos.fn_add_line('e0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000084', -1, NULL, 0, 0, v);
  PERFORM pos.fn_recalc_order('e0000000-0000-0000-0000-000000000003');
  PERFORM pos.t_pay('e0000000-0000-0000-0000-000000000003', 'TAR', -26.67);
  UPDATE pos.pos_order SET status = 'paid' WHERE id = 'e0000000-0000-0000-0000-000000000003';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
DO $$ DECLARE v uuid; BEGIN   -- devolver el polo 2 a precio de lista (40.00) en lugar del neto pagado
  SELECT id INTO v FROM pos.pos_order_line WHERE order_id = 'e0000000-0000-0000-0000-000000000001' AND line_no = 2;
  PERFORM pos.t_new_order('e0000000-0000-0000-0000-000000000004', (SELECT id FROM pos.pos_session WHERE terminal_id = 'a0000000-0000-0000-0000-000000000065'), NULL, 'e0000000-0000-0000-0000-000000000001');
  INSERT INTO pos.pos_order_line(order_id, line_no, product_id, description, qty, list_price, price_total, price_subtotal, tax_category_code, refunded_line_id)
  VALUES ('e0000000-0000-0000-0000-000000000004', 1, 'a0000000-0000-0000-0000-000000000084', 'Polo básico', -1, 40, -40, -33.90, '10', v);
  INSERT INTO pos.pos_order_line_tax(line_id, tax_id, base_amount, rate, amount, included_in_price)
  SELECT id, 'a0000000-0000-0000-0000-000000000031', -33.90, 0.18, -6.10, true FROM pos.pos_order_line WHERE order_id = 'e0000000-0000-0000-0000-000000000004';
  PERFORM pos.fn_recalc_order('e0000000-0000-0000-0000-000000000004');
  PERFORM pos.t_pay('e0000000-0000-0000-0000-000000000004', 'TAR', -40);
  UPDATE pos.pos_order SET status = 'paid' WHERE id = 'e0000000-0000-0000-0000-000000000004';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
DO $$ DECLARE v uuid; BEGIN   -- reembolsar en efectivo lo que se pagó con tarjeta
  SELECT id INTO v FROM pos.pos_order_line WHERE order_id = 'e0000000-0000-0000-0000-000000000001' AND line_no = 2;
  PERFORM pos.t_new_order('e0000000-0000-0000-0000-000000000005', (SELECT id FROM pos.pos_session WHERE terminal_id = 'a0000000-0000-0000-0000-000000000065'), NULL, 'e0000000-0000-0000-0000-000000000001');
  PERFORM pos.fn_add_line('e0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000084', -1, NULL, 0, 0, v);
  PERFORM pos.fn_recalc_order('e0000000-0000-0000-0000-000000000005');
  PERFORM pos.t_pay('e0000000-0000-0000-0000-000000000005', 'EFE', -26.67);
  UPDATE pos.pos_order SET status = 'paid' WHERE id = 'e0000000-0000-0000-0000-000000000005';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
DO $$ BEGIN   -- devolución sin ticket sin autorización de supervisor
  PERFORM pos.t_new_order('e0000000-0000-0000-0000-000000000006', (SELECT id FROM pos.pos_session WHERE terminal_id = 'a0000000-0000-0000-0000-000000000065'));
  PERFORM pos.fn_add_line('e0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000084', -1);
  PERFORM pos.fn_recalc_order('e0000000-0000-0000-0000-000000000006');
  PERFORM pos.t_pay('e0000000-0000-0000-0000-000000000006', 'EFE', -40);
  UPDATE pos.pos_order SET status = 'paid' WHERE id = 'e0000000-0000-0000-0000-000000000006';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
DO $$ BEGIN   -- nota de crédito mayor a lo que queda del comprobante (80.00 − 26.67 = 53.33)
  INSERT INTO pos.fiscal_document(company_id, establishment_id, terminal_id, doc_type, series, number, issued_at, currency_code,
                                  total_amount, referenced_document_id, note_reason_code)
  SELECT company_id, establishment_id, terminal_id, '07', 'BC05', 99, now(), 'PEN', 60.00, id, '07'
  FROM pos.fiscal_document WHERE order_id = 'e0000000-0000-0000-0000-000000000001';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;

\echo '== 4. Tarjeta de regalo: el saldo es un libro mayor y no queda negativo'
INSERT INTO gift_card(id, code, currency_code) VALUES ('e0000000-0000-0000-0000-0000000000c1', 'GC-0001', 'PEN');
INSERT INTO gift_card_ledger(gift_card_id, entry_type, amount) VALUES
  ('e0000000-0000-0000-0000-0000000000c1', 'issue', 100.00),
  ('e0000000-0000-0000-0000-0000000000c1', 'redeem', -80.00);
DO $$ BEGIN
  INSERT INTO pos.gift_card_ledger(gift_card_id, entry_type, amount) VALUES ('e0000000-0000-0000-0000-0000000000c1', 'redeem', -30.00);
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
SELECT code, balance AS saldo FROM v_gift_card_balance WHERE code = 'GC-0001';
RESET app.user_id;
