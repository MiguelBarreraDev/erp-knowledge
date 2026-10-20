-- Ciclo básico: unidades, recepción, disponibilidad, reservas y garantías de la base.
SET search_path = scm, public;
\set ON_ERROR_STOP on
\set QUIET on
\pset footer off

INSERT INTO company(id, code, legal_name, country_code, currency_code)
VALUES ('10000000-0000-0000-0000-000000000001', 'ACME', 'Acme SAC', 'PE', 'PEN');
INSERT INTO uom_category(id, name) VALUES ('10000000-0000-0000-0000-000000000010', 'Unidad');
INSERT INTO uom(id, category_id, code, name, ratio, is_reference) VALUES
  ('10000000-0000-0000-0000-000000000011', '10000000-0000-0000-0000-000000000010', 'UND', 'Unidad', 1, true),
  ('10000000-0000-0000-0000-000000000012', '10000000-0000-0000-0000-000000000010', 'CJ12', 'Caja x 12', 12, false);
INSERT INTO product_category(id, name, costing_method, removal_strategy) VALUES
  ('10000000-0000-0000-0000-000000000020', 'Mercadería', 'average', 'fifo'),
  ('10000000-0000-0000-0000-000000000021', 'Perecibles', 'average', 'fefo');
INSERT INTO product_template(id, name, category_id, uom_id, tracking) VALUES
  ('10000000-0000-0000-0000-000000000030', 'Producto X', '10000000-0000-0000-0000-000000000020', '10000000-0000-0000-0000-000000000011', 'none'),
  ('10000000-0000-0000-0000-000000000032', 'Yogur', '10000000-0000-0000-0000-000000000021', '10000000-0000-0000-0000-000000000011', 'lot');
INSERT INTO product(id, template_id, sku, name, standard_price) VALUES
  ('10000000-0000-0000-0000-000000000031', '10000000-0000-0000-0000-000000000030', 'X', 'Producto X', 10),
  ('10000000-0000-0000-0000-000000000033', '10000000-0000-0000-0000-000000000032', 'YOG', 'Yogur 1 L', 4);
INSERT INTO partner(id, doc_type, doc_number, name, is_supplier, is_customer)
VALUES ('10000000-0000-0000-0000-000000000040', 'RUC', '20999999991', 'Proveedor SA', true, false);
SELECT fn_create_warehouse('10000000-0000-0000-0000-000000000001', 'CEN', 'Almacén Central') AS wh \gset
SELECT stock_location_id AS stock, quality_location_id AS qc, view_location_id AS wview FROM warehouse WHERE id = :'wh' \gset

\echo '== 1. Compra de 2 cajas de 12 a 120.00: la recepción queda en unidad base'
INSERT INTO purchase_order(id, company_id, name, partner_id, warehouse_id, currency_code)
VALUES ('10000000-0000-0000-0000-000000000050', '10000000-0000-0000-0000-000000000001', 'OC-0001',
        '10000000-0000-0000-0000-000000000040', :'wh', 'PEN');
INSERT INTO purchase_order_line(id, order_id, product_id, qty, uom_id, price_unit)
VALUES ('10000000-0000-0000-0000-000000000051', '10000000-0000-0000-0000-000000000050',
        '10000000-0000-0000-0000-000000000031', 2, '10000000-0000-0000-0000-000000000012', 120);
UPDATE purchase_order SET status = 'purchase' WHERE id = '10000000-0000-0000-0000-000000000050';
SELECT fn_create_receipt('10000000-0000-0000-0000-000000000050') AS receipt \gset
SELECT fn_done_move(id) FROM stock_move WHERE picking_id = :'receipt' \gset
SELECT m.product_uom_qty AS cajas, m.product_qty AS unidades, m.price_unit AS costo_unitario, p.status AS recepcion
FROM stock_move m JOIN picking p ON p.id = m.picking_id WHERE m.picking_id = :'receipt';

\echo '== 2. Disponibilidad (inventario/motor.md): físico 120, QC 10, reservado 30, sin reservar 15, entrante 50'
SELECT fn_quick_move(NULL, '10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000031', 96,
                     fn_vloc('supplier'), :'stock', 10) \gset
SELECT fn_quick_move(NULL, '10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000031', 10,
                     fn_vloc('supplier'), :'qc', 10) \gset
INSERT INTO stock_move(id, company_id, product_id, product_uom_qty, uom_id, location_id, location_dest_id, status) VALUES
  ('10000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000031', 30,
   '10000000-0000-0000-0000-000000000011', :'stock', fn_vloc('customer'), 'confirmed'),
  ('10000000-0000-0000-0000-0000000000a2', '10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000031', 15,
   '10000000-0000-0000-0000-000000000011', :'stock', fn_vloc('customer'), 'confirmed'),
  ('10000000-0000-0000-0000-0000000000a3', '10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000031', 50,
   '10000000-0000-0000-0000-000000000011', fn_vloc('supplier'), :'stock', 'confirmed');
SELECT fn_reserve_move('10000000-0000-0000-0000-0000000000a1') AS reservado_pedido_a;
SELECT on_hand AS fisico, reserved AS reservado, available AS disponible, incoming AS entrante,
       outgoing AS saliente, forecast AS proyectado, atp_now AS prometible
FROM v_stock_availability WHERE warehouse_id = :'wh' AND product_id = '10000000-0000-0000-0000-000000000031';

\echo '== 3. Garantías en la base'
DO $$ BEGIN
  INSERT INTO scm.stock_move_line(move_id, location_id, qty, status)
  SELECT '10000000-0000-0000-0000-0000000000a2', stock_location_id, 100, 'reserved'
  FROM scm.warehouse WHERE code = 'CEN';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
DO $$ BEGIN
  PERFORM scm.fn_quick_move(NULL, '10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000031', 500,
                            (SELECT stock_location_id FROM scm.warehouse WHERE code = 'CEN'), scm.fn_vloc('customer'));
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
SELECT fn_done_move('10000000-0000-0000-0000-0000000000a1') \gset
DO $$ BEGIN
  UPDATE scm.stock_move SET product_uom_qty = 1 WHERE id = '10000000-0000-0000-0000-0000000000a1';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
DO $$ BEGIN
  UPDATE scm.stock_move_line SET qty = 1 WHERE move_id = '10000000-0000-0000-0000-0000000000a1';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
DO $$ BEGIN
  DELETE FROM scm.stock_move WHERE id = '10000000-0000-0000-0000-0000000000a1';
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;

\echo '== 4. Idempotencia: la misma venta del POS llega dos veces'
SELECT fn_quick_move('pos:CAJA1-0001', '10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000031', 2,
                     :'stock', fn_vloc('customer')) = fn_quick_move('pos:CAJA1-0001', '10000000-0000-0000-0000-000000000001',
                     '10000000-0000-0000-0000-000000000031', 2, :'stock', fn_vloc('customer')) AS mismo_movimiento;
SELECT count(*) AS movimientos FROM stock_move WHERE external_key = 'pos:CAJA1-0001';

\echo '== 5. El piso de venta admite stock negativo; el almacén no'
INSERT INTO location(parent_id, warehouse_id, code, name, usage, allow_negative)
VALUES (:'wview', :'wh', 'SHOP', 'Piso de venta', 'internal', true) RETURNING id AS shop \gset
SELECT fn_quick_move('pos:CAJA1-0002', '10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000031', 3,
                     :'shop', fn_vloc('customer')) \gset
SELECT quantity AS saldo_piso_de_venta FROM stock_quant WHERE location_id = :'shop';

\echo '== 6. Partida doble de cantidades y reconstrucción desde las líneas'
SELECT count(*) AS productos_con_suma_distinta_de_cero FROM v_quant_zero_sum;
CREATE TEMP TABLE quants_antes AS
  SELECT product_id, location_id, lot_id, package_id, owner_id, quantity, reserved_quantity FROM stock_quant;
SELECT fn_rebuild_quants() > 0 AS reconstruido;
SELECT (SELECT count(*) FROM (SELECT * FROM quants_antes EXCEPT SELECT product_id, location_id, lot_id, package_id, owner_id, quantity, reserved_quantity FROM stock_quant) a)
     + (SELECT count(*) FROM (SELECT product_id, location_id, lot_id, package_id, owner_id, quantity, reserved_quantity FROM stock_quant EXCEPT SELECT * FROM quants_antes) b)
       AS diferencias_tras_reconstruir;

\echo '== 7. Lotes: se exigen al mover y FEFO reserva el que vence primero (sin tocar el vencido)'
DO $$ BEGIN
  PERFORM scm.fn_quick_move(NULL, '10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000033', 5,
                            scm.fn_vloc('supplier'), (SELECT stock_location_id FROM scm.warehouse WHERE code = 'CEN'), 4);
  RAISE NOTICE 'MAL'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK %', split_part(SQLERRM, ':', 1); END $$;
INSERT INTO lot(id, product_id, name, expiration_date) VALUES
  ('10000000-0000-0000-0000-0000000000b0', '10000000-0000-0000-0000-000000000033', 'L-VENCIDO', '2026-01-31'),
  ('10000000-0000-0000-0000-0000000000b1', '10000000-0000-0000-0000-000000000033', 'L-DIC', '2099-12-31'),
  ('10000000-0000-0000-0000-0000000000b2', '10000000-0000-0000-0000-000000000033', 'L-NOV', '2099-11-30');
SELECT count(fn_quick_move(NULL, '10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000033', 10,
                           fn_vloc('supplier'), :'stock', 4, NULL, l.id)) AS lotes_recibidos_10_c_u
FROM lot l WHERE l.product_id = '10000000-0000-0000-0000-000000000033';
INSERT INTO stock_move(id, company_id, product_id, product_uom_qty, uom_id, location_id, location_dest_id, status) VALUES
  ('10000000-0000-0000-0000-0000000000a4', '10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000033', 12,
   '10000000-0000-0000-0000-000000000011', :'stock', fn_vloc('customer'), 'confirmed');
SELECT fn_reserve_move('10000000-0000-0000-0000-0000000000a4') AS reservado;
SELECT lt.name AS lote, l.qty AS reservado FROM stock_move_line l JOIN lot lt ON lt.id = l.lot_id
WHERE l.move_id = '10000000-0000-0000-0000-0000000000a4' ORDER BY lt.expiration_date;
