-- Valorización: los ejemplos de inventario/valorizacion.md, calculados por la base.
SET search_path = scm, public;
\set ON_ERROR_STOP on
\set QUIET on
\pset footer off

INSERT INTO company(id, code, legal_name, country_code, currency_code)
VALUES ('20000000-0000-0000-0000-000000000001', 'VAL', 'Valorización SAC', 'PE', 'PEN');
INSERT INTO uom_category(id, name) VALUES ('20000000-0000-0000-0000-000000000010', 'Unidad (val)');
INSERT INTO uom(id, category_id, code, name, ratio, is_reference)
VALUES ('20000000-0000-0000-0000-000000000011', '20000000-0000-0000-0000-000000000010', 'U-VAL', 'Unidad', 1, true);
INSERT INTO product_category(id, name, costing_method, account_inventory, account_stock_input, account_cogs,
                             account_price_diff, account_scrap, account_adjustment, account_internal_use) VALUES
  ('20000000-0000-0000-0000-000000000021', 'Promedio', 'average',  '20111', '6091', '6911', '6092', '6595', '7599', '6596'),
  ('20000000-0000-0000-0000-000000000022', 'PEPS',     'fifo',     '20111', '6091', '6911', '6092', '6595', '7599', '6596'),
  ('20000000-0000-0000-0000-000000000023', 'Estándar', 'standard', '20111', '6091', '6911', '6092', '6595', '7599', '6596');
INSERT INTO product_template(id, name, category_id, uom_id) VALUES
  ('20000000-0000-0000-0000-000000000031', 'A promedio', '20000000-0000-0000-0000-000000000021', '20000000-0000-0000-0000-000000000011'),
  ('20000000-0000-0000-0000-000000000032', 'F peps',     '20000000-0000-0000-0000-000000000022', '20000000-0000-0000-0000-000000000011'),
  ('20000000-0000-0000-0000-000000000033', 'S estándar', '20000000-0000-0000-0000-000000000023', '20000000-0000-0000-0000-000000000011'),
  ('20000000-0000-0000-0000-000000000034', 'D precio',   '20000000-0000-0000-0000-000000000021', '20000000-0000-0000-0000-000000000011'),
  ('20000000-0000-0000-0000-000000000035', 'LA flete',   '20000000-0000-0000-0000-000000000021', '20000000-0000-0000-0000-000000000011'),
  ('20000000-0000-0000-0000-000000000036', 'LB flete',   '20000000-0000-0000-0000-000000000021', '20000000-0000-0000-0000-000000000011'),
  ('20000000-0000-0000-0000-000000000037', 'N negativo', '20000000-0000-0000-0000-000000000021', '20000000-0000-0000-0000-000000000011');
INSERT INTO product(id, template_id, sku, name, standard_price, weight_kg) VALUES
  ('20000000-0000-0000-0000-000000000041', '20000000-0000-0000-0000-000000000031', 'A', 'A promedio', 0, NULL),
  ('20000000-0000-0000-0000-000000000042', '20000000-0000-0000-0000-000000000032', 'F', 'F peps', 0, NULL),
  ('20000000-0000-0000-0000-000000000043', '20000000-0000-0000-0000-000000000033', 'S', 'S estándar', 11.50, NULL),
  ('20000000-0000-0000-0000-000000000044', '20000000-0000-0000-0000-000000000034', 'D', 'D precio', 0, NULL),
  ('20000000-0000-0000-0000-000000000045', '20000000-0000-0000-0000-000000000035', 'LA', 'LA flete', 0, 0.5),
  ('20000000-0000-0000-0000-000000000046', '20000000-0000-0000-0000-000000000036', 'LB', 'LB flete', 0, 3),
  ('20000000-0000-0000-0000-000000000047', '20000000-0000-0000-0000-000000000037', 'N', 'N negativo', 11, NULL);
SELECT fn_create_warehouse('20000000-0000-0000-0000-000000000001', 'VAL', 'Almacén valorización') AS wh \gset
SELECT stock_location_id AS stock, view_location_id AS wview FROM warehouse WHERE id = :'wh' \gset

-- Mismos movimientos de octubre para A (promedio), F (PEPS) y S (estándar 11.50)
CREATE TEMP TABLE mov(p uuid, d timestamptz, kind text, qty numeric, cost numeric);
INSERT INTO mov
SELECT p, d::timestamptz, kind, qty, cost
FROM unnest(ARRAY['20000000-0000-0000-0000-000000000041','20000000-0000-0000-0000-000000000042',
                  '20000000-0000-0000-0000-000000000043']::uuid[]) p,
     (VALUES ('2026-10-02 10:00-05','in',100,10), ('2026-10-05 10:00-05','in',50,13),
             ('2026-10-08 10:00-05','out',120,NULL), ('2026-10-12 10:00-05','in',80,12),
             ('2026-10-15 10:00-05','out',60,NULL)) v(d, kind, qty, cost);
SELECT count(fn_quick_move('val:' || sku || ':' || to_char(d, 'MMDD'), '20000000-0000-0000-0000-000000000001', p, qty,
                           CASE kind WHEN 'in' THEN fn_vloc('supplier') ELSE :'stock' END,
                           CASE kind WHEN 'in' THEN :'stock' ELSE fn_vloc('customer') END,
                           cost, d, NULL, NULL, NULL, NULL, sku || ' ' || kind || ' ' || to_char(d, 'DD/MM')))
       AS movimientos
FROM (SELECT mov.*, pr.sku FROM mov JOIN product pr ON pr.id = mov.p ORDER BY d, pr.sku) x;

\echo '== 1. Kardex de A con promedio ponderado móvil'
SELECT to_char(layer_date AT TIME ZONE 'America/Lima', 'DD/MM') AS fecha, qty_in AS entra, unit_cost_in AS cu_entra,
       value_in AS valor_entra, qty_out AS sale, unit_cost_out AS cu_sale, value_out AS valor_sale,
       balance_qty AS saldo, balance_unit_cost AS cu_saldo, balance_value AS valor_saldo
FROM v_kardex WHERE product_id = '20000000-0000-0000-0000-000000000041' ORDER BY layer_date;

\echo '== 2. Comparación de métodos: costo de ventas, inventario final y variación del estándar'
SELECT p.sku AS producto, c.costing_method AS metodo,
       -sum(l.value) FILTER (WHERE l.layer_type = 'out') AS costo_de_ventas,
       sum(l.value) AS inventario_final,
       sum(l.variance_amount) AS variacion_estandar
FROM stock_valuation_layer l JOIN product p ON p.id = l.product_id
JOIN product_template t ON t.id = p.template_id JOIN product_category c ON c.id = t.category_id
WHERE p.sku IN ('A','F','S') GROUP BY p.sku, c.costing_method ORDER BY p.sku;

\echo '== 3. Devolución de cliente: 10 u de la venta del 08/10 entran a 11.0000, no al promedio del día'
SELECT fn_quick_move('val:A:ret', '20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000041', 10,
                     fn_vloc('customer'), :'stock', NULL, '2026-10-16 10:00-05', NULL,
                     (SELECT id FROM stock_move WHERE external_key = 'val:A:1008')) AS devolucion \gset
SELECT l.unit_cost AS costo_devolucion, l.value AS valor, v.quantity AS saldo, v.unit_cost AS nuevo_promedio
FROM stock_valuation_layer l JOIN v_inventory_valuation v ON v.product_id = l.product_id
WHERE l.move_id = :'devolucion';

\echo '== 4. Factura a 10.40 de una recepción a 10.00 con 40 de 100 ya vendidas'
SELECT fn_quick_move('val:D:in', '20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000044', 100,
                     fn_vloc('supplier'), :'stock', 10, '2026-10-02 10:00-05') AS recepcion_d \gset
SELECT fn_quick_move('val:D:out', '20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000044', 40,
                     :'stock', fn_vloc('customer'), NULL, '2026-10-03 10:00-05') \gset
SELECT fn_add_cost_adjustment(:'recepcion_d', 100 * 0.40, 'price_diff', NULL, '2026-10-06 10:00-05') AS ajuste \gset
SELECT value AS a_inventario, cogs_amount AS a_costo_de_ventas FROM stock_valuation_layer WHERE id = :'ajuste';

\echo '== 5. Flete de 300.00 repartido por peso entre A (50 kg) y B (150 kg)'
INSERT INTO picking(id, company_id, picking_type_id, location_id, location_dest_id, origin_type)
SELECT '20000000-0000-0000-0000-0000000000d1', '20000000-0000-0000-0000-000000000001', id, fn_vloc('supplier'), :'stock', 'purchase'
FROM picking_type WHERE warehouse_id = :'wh' AND code = 'incoming';
SELECT count(fn_quick_move('val:' || x.sku || ':imp', '20000000-0000-0000-0000-000000000001', x.id, x.qty, fn_vloc('supplier'),
                           :'stock', x.cost, '2026-10-07 10:00-05', NULL, NULL, NULL, '20000000-0000-0000-0000-0000000000d1'))
       AS recepciones
FROM (VALUES ('20000000-0000-0000-0000-000000000045'::uuid, 'LA', 100, 10), ('20000000-0000-0000-0000-000000000046'::uuid, 'LB', 50, 20))
     x(id, sku, qty, cost);
INSERT INTO landed_cost(id, company_id, name, cost_date)
VALUES ('20000000-0000-0000-0000-0000000000e1', '20000000-0000-0000-0000-000000000001', 'IMP-001', '2026-10-09 10:00-05');
INSERT INTO landed_cost_picking VALUES ('20000000-0000-0000-0000-0000000000e1', '20000000-0000-0000-0000-0000000000d1');
INSERT INTO landed_cost_line(landed_cost_id, description, amount, split_method)
VALUES ('20000000-0000-0000-0000-0000000000e1', 'Flete', 300, 'by_weight');
SELECT fn_post_landed_cost('20000000-0000-0000-0000-0000000000e1') \gset
SELECT p.sku AS producto, a.amount AS flete, v.unit_cost AS nuevo_costo_unitario
FROM landed_cost_allocation a JOIN stock_move m ON m.id = a.move_id JOIN product p ON p.id = m.product_id
JOIN v_inventory_valuation v ON v.product_id = p.id ORDER BY p.sku;

\echo '== 6. Stock negativo: 10 vendidas sin stock a 11.00 (provisional); llegan 30 a 12.00'
INSERT INTO location(parent_id, warehouse_id, code, name, usage, allow_negative)
VALUES (:'wview', :'wh', 'SHOP', 'Piso de venta', 'internal', true) RETURNING id AS shop \gset
SELECT fn_quick_move('val:N:out', '20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000047', 10,
                     :'shop', fn_vloc('customer'), NULL, '2026-10-10 10:00-05') \gset
SELECT fn_quick_move('val:N:in', '20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000047', 30,
                     fn_vloc('supplier'), :'shop', 12, '2026-10-11 10:00-05') \gset
SELECT layer_type AS capa, quantity AS cantidad, value AS valor, cogs_amount AS a_costo_de_ventas
FROM stock_valuation_layer WHERE product_id = '20000000-0000-0000-0000-000000000047' ORDER BY layer_date, created_at;
SELECT quantity AS saldo, value AS valor, unit_cost AS costo_unitario FROM v_inventory_valuation
WHERE product_id = '20000000-0000-0000-0000-000000000047';

\echo '== 7. Cierre: capas = saldo contable de inventario; asientos cuadrados'
SELECT layers_value AS capas, ledger_value AS contabilidad, difference AS diferencia
FROM v_valuation_check WHERE company_id = '20000000-0000-0000-0000-000000000001';
SELECT count(*) AS asientos_descuadrados FROM v_journal_unbalanced;

\echo '== 8. Cierre de inventario al 31/10: un movimiento con fecha 20/10 se rechaza'
INSERT INTO inventory_lock(company_id, lock_date, reason) VALUES ('20000000-0000-0000-0000-000000000001', '2026-10-31', 'Cierre de octubre');
DO $$ BEGIN
  PERFORM scm.fn_quick_move(NULL, '20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000041', 1,
                            (SELECT stock_location_id FROM scm.warehouse WHERE code = 'VAL'), scm.fn_vloc('scrap'),
                            NULL, '2026-10-20 10:00-05');
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
