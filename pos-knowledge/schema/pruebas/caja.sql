-- Cierre de caja: el ejemplo de caja-y-turnos.md, cierre ciego con aprobación, venta que sincroniza
-- tarde y asiento de la sesión. Requiere pruebas/datos.sql.
SET search_path = pos, public;
\set ON_ERROR_STOP on
\set QUIET on
\pset footer off
SET app.user_id = 'ana';
SELECT t_open_session(4, 200) AS s4 \gset

-- Ventas: efectivo 1,805.50 + 45.00 = 1,850.50; tarjeta 2,340.00; QR 410.00; devolución en efectivo de 45.00
CREATE TEMP TABLE ventas(id uuid, monto numeric, medio text);
INSERT INTO ventas VALUES
  ('d0000000-0000-0000-0000-000000000001', 1805.50, 'EFE'), ('d0000000-0000-0000-0000-000000000002', 45.00, 'EFE'),
  ('d0000000-0000-0000-0000-000000000003', 2340.00, 'TAR'), ('d0000000-0000-0000-0000-000000000004', 410.00, 'QR');
SELECT count(t_new_order(id, :'s4', 'a0000000-0000-0000-0000-0000000000a1')) AS ventas FROM ventas;
SELECT count(fn_add_line(id, 'a0000000-0000-0000-0000-000000000086', 1, monto)) FROM ventas \gset
SELECT count(fn_recalc_order(id)) FROM ventas \gset
SELECT count(t_pay(id, medio, monto)) FROM ventas \gset
SELECT count(fn_complete_order(id)) AS comprobantes FROM ventas;

SELECT t_new_order('d0000000-0000-0000-0000-000000000005', :'s4', 'a0000000-0000-0000-0000-0000000000a1',
                   'd0000000-0000-0000-0000-000000000002') \gset
SELECT fn_add_line('d0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000086', -1, NULL, 0, 0,
                   (SELECT id FROM pos_order_line WHERE order_id = 'd0000000-0000-0000-0000-000000000002')) \gset
SELECT fn_recalc_order('d0000000-0000-0000-0000-000000000005') \gset
SELECT t_pay('d0000000-0000-0000-0000-000000000005', 'EFE', -45.00) \gset
SELECT fn_complete_order('d0000000-0000-0000-0000-000000000005') AS nota \gset
SELECT series || '-' || number AS nota_de_credito, total_amount, (SELECT series || '-' || number FROM fiscal_document r WHERE r.id = d.referenced_document_id) AS modifica
FROM fiscal_document d WHERE id = :'nota';

INSERT INTO cash_movement(id, session_id, kind, amount, reason, envelope_no, authorized_by) VALUES
  (gen_random_uuid(), :'s4', 'safe_drop', 1000.00, 'Retiro parcial 11:30', 'S-0001', 'luis'),
  (gen_random_uuid(), :'s4', 'petty_cash', 20.00, 'Movilidad', NULL, 'luis'),
  (gen_random_uuid(), :'s4', 'cash_in', 100.00, 'Sencillo desde bóveda', NULL, 'luis');

\echo '== 1. Cierre ciego: el cajero declara 1,080.00 en efectivo, 2,340.00 en tarjetas y 410.00 en QR'
UPDATE pos_session SET status = 'closing' WHERE id = :'s4';
SELECT fn_declare(:'s4', 'EFE', 1080.00), fn_declare(:'s4', 'TAR', 2340.00), fn_declare(:'s4', 'QR', 410.00) \gset
SELECT payment_method AS medio, expected_amount AS esperado, declared_amount AS declarado, difference AS diferencia
FROM v_session_close WHERE session_id = :'s4' ORDER BY payment_method;

\echo '== 2. Faltante de 5.50 sobre la tolerancia de 1.00: aprueba otra persona'
DO $$ BEGIN
  UPDATE pos.pos_session SET status = 'closed' WHERE terminal_id = 'a0000000-0000-0000-0000-000000000064' AND status = 'closing';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
DO $$ BEGIN
  UPDATE pos.pos_session SET status = 'closed', approved_by = 'ana' WHERE terminal_id = 'a0000000-0000-0000-0000-000000000064' AND status = 'closing';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
SET app.user_id = 'luis';
UPDATE pos_session SET status = 'closed', approved_by = 'luis' WHERE id = :'s4';
SELECT status, closed_by AS cerrada_por, approved_by AS aprobada_por,
       (SELECT declared_amount FROM session_declaration d JOIN payment_method m ON m.id = d.payment_method_id
        WHERE d.session_id = s.id AND m.code = 'EFE') - opening_float AS deposito_de_la_caja,
       (SELECT declared_amount FROM session_declaration d JOIN payment_method m ON m.id = d.payment_method_id
        WHERE d.session_id = s.id AND m.code = 'EFE') - opening_float
       + (SELECT sum(amount) FROM cash_movement WHERE session_id = s.id AND kind = 'safe_drop') AS deposito_del_dia
FROM pos_session s WHERE id = :'s4';
DO $$ BEGIN
  UPDATE pos.pos_session SET opening_float = 250 WHERE terminal_id = 'a0000000-0000-0000-0000-000000000064';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;

\echo '== 3. Venta hecha antes del cierre que sincroniza después: se acepta y se marca; una posterior al cierre, no'
INSERT INTO pos_order(id, session_id, cashier_user_id, customer_id, pricelist_id, occurred_at, currency_code,
                      terminal_id, store_id, company_id, business_date)
SELECT 'd0000000-0000-0000-0000-000000000006', id, cashier_user_id, NULL, 'a0000000-0000-0000-0000-000000000041',
       closed_at - interval '10 minutes', 'PEN', terminal_id, store_id, 'a0000000-0000-0000-0000-000000000001', current_date
FROM pos_session WHERE id = :'s4';
SELECT fn_add_line('d0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000082', 2) \gset
SELECT fn_recalc_order('d0000000-0000-0000-0000-000000000006') \gset
SELECT t_pay('d0000000-0000-0000-0000-000000000006', 'QR', 4.90) \gset
SELECT fn_complete_order('d0000000-0000-0000-0000-000000000006') \gset
SELECT e.kind AS excepcion, s.needs_reconciliation AS sesion_por_conciliar
FROM pos_sync_exception e JOIN pos_session s ON s.id = e.session_id WHERE e.order_id = 'd0000000-0000-0000-0000-000000000006';
DO $$ BEGIN
  INSERT INTO pos.pos_order(id, session_id, cashier_user_id, occurred_at, currency_code, terminal_id, store_id, company_id, business_date)
  SELECT 'd0000000-0000-0000-0000-000000000007', id, cashier_user_id, closed_at + interval '1 minute', 'PEN',
         terminal_id, store_id, 'a0000000-0000-0000-0000-000000000001', current_date
  FROM pos.pos_session WHERE terminal_id = 'a0000000-0000-0000-0000-000000000064';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;

\echo '== 4. Asiento resumen de la sesión (cuadra por construcción)'
SELECT fn_post_session(:'s4') AS asiento \gset
SELECT account_code AS cuenta, description AS concepto, sum(debit) AS debe, sum(credit) AS haber
FROM session_journal_line WHERE entry_id = :'asiento' GROUP BY account_code, description ORDER BY sum(debit) DESC, account_code;
SELECT sum(debit) AS total_debe, sum(credit) AS total_haber FROM session_journal_line WHERE entry_id = :'asiento';
RESET app.user_id;
