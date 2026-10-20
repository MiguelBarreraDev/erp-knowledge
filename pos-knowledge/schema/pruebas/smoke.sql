-- Ciclo básico: sesión, venta idempotente, comprobante, efectos de stock y garantías de la base.
-- Requiere pruebas/datos.sql.
SET search_path = pos, public;
\set ON_ERROR_STOP on
\set QUIET on
\pset footer off
SET app.user_id = 'ana';

\echo '== 1. Sesión: una sola abierta por caja'
SELECT t_open_session(1, 200) AS s1 \gset
SELECT s.status, s.opening_float AS fondo, b.business_date = (now() AT TIME ZONE 'America/Lima' - interval '5 hours')::date AS dia_de_negocio_ok
FROM pos_session s JOIN business_day b ON b.id = s.business_day_id WHERE s.id = :'s1';
DO $$ BEGIN
  INSERT INTO pos.pos_session(terminal_id, cashier_user_id) VALUES ('a0000000-0000-0000-0000-000000000061', 'a0000000-0000-0000-0000-000000000071');
  RAISE NOTICE 'MAL'; EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'OK SESSION_ALREADY_OPEN (%)', 'uq_session_active_terminal'; END $$;

\echo '== 2. Venta de 2 polos con tarjeta: comprobante B001-1 y efecto de stock'
SELECT t_new_order('b0000000-0000-0000-0000-000000000001', :'s1') \gset
SELECT fn_add_line('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000084', 2) \gset
SELECT fn_recalc_order('b0000000-0000-0000-0000-000000000001') \gset
SELECT t_pay('b0000000-0000-0000-0000-000000000001', 'TAR', 80.00) \gset
SELECT fn_complete_order('b0000000-0000-0000-0000-000000000001') AS doc \gset
SELECT o.status, o.amount_untaxed AS base, o.amount_tax AS igv, o.amount_total AS total,
       d.series || '-' || d.number AS comprobante, d.total_amount AS total_comprobante
FROM pos_order o JOIN fiscal_document d ON d.order_id = o.id WHERE o.id = 'b0000000-0000-0000-0000-000000000001';
SELECT e.qty AS efecto_stock, e.status, e.external_key LIKE 'pos:%' AS clave_idempotente
FROM stock_effect e JOIN pos_order_line l ON l.id = e.order_line_id WHERE l.order_id = 'b0000000-0000-0000-0000-000000000001';

\echo '== 3. La misma venta llega dos veces (reintento de la caja): no se duplica'
INSERT INTO pos_order(id, session_id, cashier_user_id, occurred_at, currency_code, terminal_id, store_id, company_id, business_date)
VALUES ('b0000000-0000-0000-0000-000000000001', :'s1', 'a0000000-0000-0000-0000-000000000071', now(), 'PEN',
        'a0000000-0000-0000-0000-000000000061', 'a0000000-0000-0000-0000-000000000051', 'a0000000-0000-0000-0000-000000000001', current_date)
ON CONFLICT (id) DO NOTHING;
SELECT count(*) AS ventas_con_ese_id FROM pos_order WHERE id = 'b0000000-0000-0000-0000-000000000001';

\echo '== 4. Garantías en la base'
DO $$ BEGIN
  UPDATE pos.pos_order_line SET qty = 1 WHERE order_id = 'b0000000-0000-0000-0000-000000000001';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
DO $$ BEGIN
  UPDATE pos.fiscal_document SET total_amount = 1 WHERE order_id = 'b0000000-0000-0000-0000-000000000001';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
DO $$ BEGIN   -- cabecera que no coincide con las líneas
  PERFORM pos.t_new_order('b0000000-0000-0000-0000-000000000002', (SELECT id FROM pos.pos_session WHERE terminal_id = 'a0000000-0000-0000-0000-000000000061'));
  PERFORM pos.fn_add_line('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000084', 1);
  UPDATE pos.pos_order SET amount_total = 35, amount_untaxed = 30, amount_tax = 5 WHERE id = 'b0000000-0000-0000-0000-000000000002';
  PERFORM pos.t_pay('b0000000-0000-0000-0000-000000000002', 'TAR', 35);
  UPDATE pos.pos_order SET status = 'paid' WHERE id = 'b0000000-0000-0000-0000-000000000002';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
DO $$ BEGIN   -- pago que no cubre el total
  PERFORM pos.t_new_order('b0000000-0000-0000-0000-000000000003', (SELECT id FROM pos.pos_session WHERE terminal_id = 'a0000000-0000-0000-0000-000000000061'));
  PERFORM pos.fn_add_line('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000084', 1);
  PERFORM pos.fn_recalc_order('b0000000-0000-0000-0000-000000000003');
  PERFORM pos.t_pay('b0000000-0000-0000-0000-000000000003', 'TAR', 30);
  UPDATE pos.pos_order SET status = 'paid' WHERE id = 'b0000000-0000-0000-0000-000000000003';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
DO $$ BEGIN   -- vuelto con tarjeta
  PERFORM pos.t_new_order('b0000000-0000-0000-0000-000000000004', (SELECT id FROM pos.pos_session WHERE terminal_id = 'a0000000-0000-0000-0000-000000000061'));
  PERFORM pos.fn_add_line('b0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000084', 1);
  PERFORM pos.fn_recalc_order('b0000000-0000-0000-0000-000000000004');
  PERFORM pos.t_pay('b0000000-0000-0000-0000-000000000004', 'TAR', 40, 50);
  UPDATE pos.pos_order SET status = 'paid' WHERE id = 'b0000000-0000-0000-0000-000000000004';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
DO $$ BEGIN   -- terminar sin comprobante
  PERFORM pos.t_new_order('b0000000-0000-0000-0000-000000000005', (SELECT id FROM pos.pos_session WHERE terminal_id = 'a0000000-0000-0000-0000-000000000061'));
  PERFORM pos.fn_add_line('b0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000084', 1);
  PERFORM pos.fn_recalc_order('b0000000-0000-0000-0000-000000000005');
  PERFORM pos.t_pay('b0000000-0000-0000-0000-000000000005', 'TAR', 40);
  UPDATE pos.pos_order SET status = 'paid' WHERE id = 'b0000000-0000-0000-0000-000000000005';
  UPDATE pos.pos_order SET status = 'done' WHERE id = 'b0000000-0000-0000-0000-000000000005';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
DO $$ BEGIN   -- la caja 1 usa la serie de la caja 2
  INSERT INTO pos.fiscal_document(company_id, establishment_id, terminal_id, doc_type, series, number, issued_at, currency_code, total_amount)
  VALUES ('a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000011', 'a0000000-0000-0000-0000-000000000061',
          '03', 'B002', 1, now(), 'PEN', 10);
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
DO $$ BEGIN   -- vender con la caja todavía en apertura
  INSERT INTO pos.pos_session(id, terminal_id, cashier_user_id) VALUES ('b0000000-0000-0000-0000-0000000000f2', 'a0000000-0000-0000-0000-000000000062', 'a0000000-0000-0000-0000-000000000071');
  PERFORM pos.t_new_order('b0000000-0000-0000-0000-000000000006', 'b0000000-0000-0000-0000-0000000000f2');
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;

\echo '== 5. Numeración hecha en la caja sin red: llega el B001-5 y la base detecta los huecos 2 a 4'
INSERT INTO fiscal_document(company_id, establishment_id, terminal_id, doc_type, series, number, issued_at, currency_code, total_amount)
VALUES ('a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000011', 'a0000000-0000-0000-0000-000000000061',
        '03', 'B001', 5, now(), 'PEN', 10);
SELECT string_agg(missing_number::text, ', ' ORDER BY missing_number) AS numeros_faltantes_B001
FROM v_fiscal_number_gaps WHERE series = 'B001';
SELECT next_number AS siguiente_B001 FROM document_series WHERE series = 'B001';

\echo '== 6. Cambio de precio programado a la medianoche de Lima: la caja descarga solo lo que cambió'
SELECT max(row_version) AS cursor FROM v_catalog_changes \gset
UPDATE pricelist_item SET valid_to = '2026-11-01 00:00-05' WHERE product_id = 'a0000000-0000-0000-0000-000000000084';
INSERT INTO pricelist_item(pricelist_id, product_id, price, valid_from)
VALUES ('a0000000-0000-0000-0000-000000000041', 'a0000000-0000-0000-0000-000000000084', 35.00, '2026-11-01 00:00-05');
SELECT entity, count(*) AS cambios FROM v_catalog_changes WHERE row_version > :cursor GROUP BY entity;
SELECT fn_list_price('a0000000-0000-0000-0000-000000000041', 'a0000000-0000-0000-0000-000000000084', 1, '2026-10-31 23:59-05') AS precio_31_oct,
       fn_list_price('a0000000-0000-0000-0000-000000000041', 'a0000000-0000-0000-0000-000000000084', 1, '2026-11-01 00:00-05') AS precio_1_nov;
RESET app.user_id;
