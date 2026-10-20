# Mapa de logística

Los submódulos de un sistema de logística (inventario, costos, compras, almacén, pedidos y transporte),
en orden de dependencia, con su contenido, sus menús y su equivalente en el mercado. Es la puerta de
entrada al resto de esta base.

- **Regla de lectura:** los submódulos dependen unos de otros. No se despacha sin inventario, no hay
  inventario sin productos, unidades y ubicaciones, y no hay costo sin movimientos. Se estudia y se
  construye en ese orden.
- **Modelo de datos:** las tablas citadas están en [schema/logistica_schema.sql](schema/logistica_schema.sql).
- **Los canales de venta están fuera:** el POS, la web y los marketplaces consumen stock; esta base es
  la dueña del stock y de su costo. El POS tiene su propia base:
  [pos-knowledge](../pos-knowledge/README.md).

## Índice

1. [Mapa en capas (orden de dependencia)](#1-mapa-en-capas-orden-de-dependencia)
2. [Cada submódulo en detalle](#2-cada-submódulo-en-detalle)
3. [Cómo se traduce a menús](#3-cómo-se-traduce-a-menús)
4. [Equivalencias con el mercado](#4-equivalencias-con-el-mercado)
5. [Orden de estudio y de construcción](#5-orden-de-estudio-y-de-construcción)
6. [Por profundizar](#6-por-profundizar)

---

## 1. Mapa en capas (orden de dependencia)

| Nivel | Submódulo | Pregunta que responde | Depende de |
|---|---|---|---|
| 0 | Plataforma | ¿Quién puede hacer qué, cómo se numera y cómo se registra? | — |
| 1 | Estructura operativa | ¿Qué empresas, establecimientos, almacenes y ubicaciones hay? | 0 |
| 2 | Catálogo de productos | ¿Qué se compra, guarda y despacha, en qué unidad y con qué código? | 0 |
| 3 | Terceros | ¿A quién se compra, a quién se despacha y quién transporta? | 0 |
| 4 | **Inventario** | ¿Cuánto hay, dónde, en qué estado y de quién? | 1, 2 |
| 5 | **Costos y valorización** | ¿Cuánto costó lo que salió y cuánto vale lo que queda? | 4 |
| 6 | Compras y abastecimiento | ¿Qué se pide, a quién, cuándo y cuánto? | 2, 3, 4 |
| 7 | Operaciones de almacén (WMS) | ¿Cómo entra, se guarda, se prepara y sale físicamente? | 4 |
| 8 | Pedidos y fulfillment (OMS) | ¿Cómo se promete y se entrega un pedido de cualquier canal? | 4, 7 |
| 9 | Transporte y guías (TMS) | ¿Cómo llega la mercadería y con qué documento viaja? | 7, 8 |
| 10 | Analítica y planificación | ¿Qué rota, qué falta, qué sobra y qué se perdió? | Todo |
| Transversal | Canales que consumen stock | POS, web, marketplaces: publican salidas, no escriben saldos | 4 |
| Transversal | Dispositivos de almacén | Handhelds, impresoras de etiquetas, balanzas | Todo |

> Los dispositivos no son un submódulo: son un **canal**. El almacenero casi nunca usa teclado y mouse.

---

## 2. Cada submódulo en detalle

### Nivel 0. Plataforma

- **Contenido:** tenant, usuarios, roles y permisos (por función y por alcance: empresa, almacén),
  aprobaciones, numeración de documentos, auditoría, importación y exportación, integraciones con
  idempotencia, idioma, moneda y zona horaria.
- **Tablas:** `lookup_type`, `lookup_value`, `scm_setting`, `document_sequence`, `approval_request`,
  `approval_step`, `audit_log`.

### Nivel 1. Estructura operativa

- **Conceptos:** empresa (contribuyente), establecimiento (dirección declarada ante la autoridad
  fiscal), almacén, ubicación (jerarquía física y virtual).
- **Tienda y almacén no son lo mismo:** una tienda tiene al menos un almacén (piso de venta, trastienda)
  y un almacén puede no tener tienda (centro de distribución).
- **Tablas:** `company`, `establishment`, `warehouse`, `location`. `fn_create_warehouse` crea el árbol
  de ubicaciones y los tipos de operación.

### Nivel 2. Catálogo de productos

- **Conceptos:** plantilla y variante, SKU, tipo (almacenable, consumible, servicio, kit), unidades de
  medida y conversiones, códigos de barras, lotes y series, categorías con método de costo.
- **Tablas:** `uom_category`, `uom`, `product_category`, `product_template`, `product`,
  `product_attribute`, `product_attribute_value`, `product_variant_value`, `product_barcode`,
  `product_packaging`, `product_kit_line`.
- Detalle en [inventario/motor.md › Producto](inventario/motor.md#producto-variante-y-unidad-de-medida).

### Nivel 3. Terceros

- **Conceptos:** proveedor (condiciones, plazos, lista de precios de compra), cliente, transportista.
  Un tercero es uno solo con roles, no dos maestros.
- **Tablas:** `partner`, `partner_address`, `supplier_info`.

### Nivel 4. Inventario

Detalle en [inventario/motor.md](inventario/motor.md).

- **Conceptos:** movimiento de una ubicación a otra, saldo derivado, cantidad física, reservada y
  disponible, reservas, estrategias de salida, lotes y vencimientos, conteos, ajustes, merma,
  transferencias con tránsito, consignación, stock negativo.
- **Procesos:** recibir, transferir, reservar, despachar, ajustar, contar, cerrar el mes.
- **Tablas:** `picking_type`, `picking`, `stock_move`, `stock_move_line`, `stock_quant`, `lot`,
  `package`, `stock_count`, `stock_count_line`, `inventory_lock`.

### Nivel 5. Costos y valorización

Detalle en [inventario/valorizacion.md](inventario/valorizacion.md).

- **Conceptos:** inventario perpetuo, promedio móvil, PEPS, estándar, capas de costo, costos de
  importación, diferencias de precio, devoluciones, stock negativo, kardex, asientos, cierre.
- **Tablas:** `stock_valuation_layer`, `landed_cost`, `landed_cost_line`, `landed_cost_picking`,
  `landed_cost_allocation`, `stock_journal_entry`, `stock_journal_line`.

### Nivel 6. Compras y abastecimiento

Detalle en [compras-y-abastecimiento.md](compras-y-abastecimiento.md).

- **Conceptos:** orden de compra con aprobación, recepción, factura de proveedor, conciliación de tres
  vías, posición de inventario, mínimo y máximo, punto de reorden, stock de seguridad.
- **Tablas:** `purchase_order`, `purchase_order_line`, `vendor_bill`, `vendor_bill_line`,
  `replenishment_rule`, `supplier_info`.

### Nivel 7. Operaciones de almacén (WMS)

Detalle en [almacen/operaciones.md](almacen/operaciones.md).

- **Conceptos:** recepción, control de calidad, putaway, reabastecimiento interno, olas, picking,
  packing, despacho, cross-docking, unidades de manipulación, tareas, productividad.
- **Tres niveles de madurez:** sin ubicaciones internas, con ubicaciones, dirigido por tareas. El modelo
  de datos es el mismo; cambia cuánto decide el sistema.
- **Tablas:** `putaway_rule`, `wave`, `warehouse_task`, `package`.

### Nivel 8. Pedidos y fulfillment (OMS)

- **Contenido:** pedido de cualquier canal, promesa de disponibilidad (ATP) y de fecha, asignación del
  almacén que despacha, divisiones de envío, pedidos pendientes, retiro en tienda, despacho desde
  tienda, devoluciones (RMA).
- **Por qué es un nivel propio:** en comercio unificado el pedido no pertenece a un almacén; el OMS
  decide desde dónde se atiende según stock, costo y plazo.
- **Tablas:** `sale_order`, `sale_order_line`, `return_authorization`, `return_authorization_line`.

### Nivel 9. Transporte y guías (TMS)

- **Contenido:** transportistas, vehículos, envíos, prueba de entrega, entregas fallidas, guía de
  remisión ([localizacion/peru.md › Guía de remisión](localizacion/peru.md#guía-de-remisión)).
- **Tablas:** `vehicle`, `shipment`, `dispatch_guide`, `dispatch_guide_line`.
- Es la capa menos estudiada en esta base ([Por profundizar](#6-por-profundizar)).

### Nivel 10. Analítica y planificación

- **Contenido:** rotación y días de inventario, quiebres de stock, merma, exactitud de inventario,
  productividad del almacén, cumplimiento de proveedores, pronóstico de demanda.
- **Datos:** vistas sobre movimientos y capas (`v_kardex`, `v_stock_availability`,
  `v_inventory_valuation`, `v_lot_expiry`); no requiere tablas nuevas hasta que haya pronóstico.

### Transversal. Canales que consumen stock

El POS, la web y los marketplaces no escriben saldos: publican salidas (y devoluciones) con una clave
única, y el inventario las convierte en movimientos idempotentes
([patrones.md › 14](patrones.md#14-los-canales-consumen-stock-el-inventario-es-el-dueño)). Del lado del
POS: [pos-knowledge › patrones.md › 10](../pos-knowledge/patrones.md#10-el-pos-no-es-dueño-del-stock-lo-consume-y-lo-publica).

---

## 3. Cómo se traduce a menús

### Patrón de cuatro grupos por submódulo

| Grupo | Contenido | Usuario |
|---|---|---|
| Operación | Día a día: documentos, listas, tareas | Almacenero, comprador |
| Procesos | Acciones por lote: reabastecer, valorizar, cerrar, importar | Jefe de almacén, contador |
| Reportes | Consultas y exportaciones | Todos según permiso |
| Configuración | Catálogos, reglas, políticas | Admin |

### Menú principal del back-office

```
Inicio

Productos
  Operación:  Productos · Variantes · Códigos de barras · Kits
  Procesos:   Importar catálogo
  Config.:    Categorías · Unidades de medida · Atributos

Inventario
  Operación:  Recepciones · Despachos · Transferencias · Ajustes · Conteos · Lotes y series
  Procesos:   Reabastecimiento · Revalorización · Costos de importación · Cierre de inventario
  Reportes:   Stock por ubicación · Kardex · Valorización · Rotación · Vencimientos · Merma
  Config.:    Almacenes · Ubicaciones · Rutas · Estrategias de salida · Motivos de ajuste

Almacén (WMS)
  Operación:  Olas · Tareas · Paquetes · Muelles
  Reportes:   Productividad · Exactitud · Ocupación
  Config.:    Zonas · Reglas de ubicación · Tipos de operación

Compras
  Operación:  Requisiciones · Cotizaciones · Órdenes de compra · Facturas de proveedor
  Procesos:   Sugerencia de reposición · Conciliación de tres vías
  Reportes:   Compras por proveedor · Cumplimiento de proveedores
  Config.:    Proveedores · Listas de precios de compra · Reglas de reorden

Pedidos
  Operación:  Pedidos · Devoluciones · Retiros en tienda
  Reportes:   Cumplimiento (OTIF) · Pendientes

Transporte
  Operación:  Envíos · Rutas · Pruebas de entrega · Guías de remisión
  Config.:    Transportistas · Vehículos · Tarifas

Configuración global
  Empresas y establecimientos · Roles · Aprobaciones · Numeración · Integraciones · Auditoría
```

### Aplicación de campo (handheld)

| Almacenero | Supervisor de almacén |
|---|---|
| Mis tareas | Olas y tareas atrasadas |
| Recibir | Diferencias de recepción |
| Ubicar | Ajustes por aprobar |
| Preparar (picking) | Ubicaciones bloqueadas |
| Contar | Productividad del turno |
| Consultar ubicación o producto | Reabastecimientos urgentes |

---

## 4. Equivalencias con el mercado

| Submódulo propio | SAP S/4HANA | Oracle | Dynamics 365 | Odoo | NetSuite |
|---|---|---|---|---|---|
| Inventario | Inventory Management (MM-IM) | Fusion Inventory Management | Supply Chain Management › Inventory management | Inventory | Inventory Management |
| Costos | Material Ledger, control de precio S/V | Cost Management | Costing (item model group) | Valorización por categoría | Costing methods por artículo |
| Almacén | Extended Warehouse Management (EWM) | Warehouse Management Cloud | Warehouse management | Inventory con ubicaciones, olas y app Barcode | WMS |
| Compras | Purchasing (MM-PUR) | Fusion Procurement | Procurement and sourcing | Purchase | Procurement |
| Pedidos | Sales (SD) y Logistics Execution | Order Management | Sales, Intelligent Order Management | Sales | Order Management |
| Transporte | Transportation Management (TM) | Transportation Management (OTM) | Transportation management | Conectores de transportistas | Integraciones |
| Movimiento | Documento de material con clase de movimiento | Material transaction | Inventory transaction | Stock move | Item fulfillment / receipt |

### Lectura competitiva

- **SAP, Oracle y Dynamics 365:** ganan en profundidad (WMS dirigido, costos estándar con libro de
  materiales, multiempresa, transporte) a cambio de implementaciones largas y caras.
- **Odoo:** gana en integración (inventario, compras, ventas y contabilidad en un solo modelo) y precio,
  a cambio de profundidad en almacenes de alto volumen.
- **NetSuite:** gana en nube y finanzas integradas, con WMS y OMS correctos para empresas medianas.
- **Espacio para competir (en el medio):**
  - Inventario contable correcto desde el día uno (costo por movimiento, kardex legal exportable).
  - Localización nativa: guías de remisión electrónicas, registros de inventario, métodos de costo
    permitidos.
  - Un solo stock para tienda, web y marketplace, con integraciones idempotentes.
  - Handheld simple, orientado al escaneo, que funciona con mala señal.

> Las equivalencias son de nomenclatura general y pueden variar por versión y edición de cada producto.

---

## 5. Orden de estudio y de construcción

| # | Etapa | Niveles |
|---|---|---|
| 1 | Plataforma: permisos, numeración, auditoría | 0 |
| 2 | Estructura operativa, catálogo y terceros | 1, 2, 3 |
| 3 | Inventario: movimientos, quants, ajustes, transferencias | 4 |
| 4 | Valorización, kardex y cierre | 5 |
| 5 | Compras con recepción, factura y tres vías | 6 |
| 6 | Pedidos y despacho; entrada de ventas de los canales | 8, transversal |
| 7 | Almacén con ubicaciones, picking y conteo cíclico | 7 |
| 8 | Reposición automática, transporte y guías, analítica | 6, 9, 10 |

### Fases de producto sugeridas

| Fase | Alcance |
|---|---|
| MVP | Una empresa con varios almacenes; catálogo con variantes y códigos; movimientos con costo promedio; ajustes y transferencias; compras con recepción; entrada de ventas del POS; kardex; cierre de mes |
| Fase 2 | Lotes y series con vencimiento (FEFO); ubicaciones internas y putaway; picking por ola; reglas de reorden; costos de importación; conteo cíclico; guía de remisión electrónica; registro de inventario valorizado legal; PEPS y estándar |
| Fase 3 | WMS dirigido por tareas (slotting, LPN, productividad); TMS y ruteo; pronóstico de demanda; reabastecimiento multiescalón; costo por almacén; RFID; marketplaces |

---

## 6. Por profundizar

Temas que esta base todavía no cubre a fondo. Cuando se estudien, se escriben en su archivo y se
quitan de aquí.

- Escenarios de prueba de punta a punta (goldens) más allá de los de `schema/pruebas/`.
- Manufactura ligera: listas de materiales, ensamble de kits, consumo por receta.
- Transporte: ruteo, planificación de carga, tarifas, seguimiento.
- Pronóstico de demanda y reabastecimiento multiescalón.
- Costo por almacén y precios de transferencia entre empresas del grupo.
- Localizaciones distintas de Perú.
