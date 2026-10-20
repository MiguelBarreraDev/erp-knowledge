# Glosario

Términos del dominio y su equivalente en los productos del mercado.

## Inventario

- **SKU:** unidad de mantenimiento de stock; la variante concreta que se cuenta y se mueve.
- **Plantilla y variante:** el producto como lo ve el cliente (polo) y cada combinación de atributos
  que se cuenta (polo M azul).
- **Unidad base:** unidad en que se lleva el stock; compra y venta pueden usar otras con conversión.
- **GTIN / EAN-13 / GTIN-14:** códigos de barras GS1 de la unidad de consumo y del empaque.
- **PLU:** código de producto de balanza o de venta a granel.
- **Movimiento (stock move):** traslado de una cantidad de una ubicación a otra; inmutable una vez hecho.
- **Línea de movimiento:** lo que se hizo de verdad: lote, serie, paquete y ubicación exacta.
- **Quant:** saldo de un producto en una ubicación, lote, paquete y propietario.
- **Ubicación virtual:** proveedor, cliente, ajuste, merma, tránsito; existe para que todo movimiento
  tenga origen y destino.
- **Físico (on hand), reservado, disponible, proyectado:** ver
  [inventario/motor.md](inventario/motor.md#cantidades-físico-reservado-disponible-y-proyectado).
- **ATP (available to promise):** lo que puede prometerse a un pedido nuevo en una fecha.
- **Backorder:** parte de un pedido o recepción que queda pendiente.
- **FIFO / FEFO / LIFO (estrategia de salida):** qué unidad sale primero: la que entró primero, la que
  vence primero, la última que entró. Es física, no contable.
- **Lote / serie:** grupo de unidades con un origen común / unidad única.
- **Conteo cíclico:** conteo de un subconjunto de ubicaciones de forma continua.
- **IRA (inventory record accuracy):** exactitud del registro de inventario.
- **Merma (shrinkage):** pérdida de inventario; conocida (vencimiento, rotura) o desconocida (robo,
  error).
- **Desmedro:** pérdida de calidad que vuelve el bien inutilizable (término tributario peruano).
- **Consignación:** stock que está en un lugar pero pertenece a otro.

## Almacén y transporte

- **WMS:** sistema de gestión de almacenes. **TMS:** de transporte. **OMS:** de pedidos.
- **ASN:** aviso anticipado de despacho del proveedor.
- **Putaway:** ubicación de lo recibido.
- **Picking / packing:** preparación de pedidos / embalaje y verificación.
- **Ola (wave):** grupo de pedidos liberados para prepararse juntos.
- **Batch, zona, cluster, put-wall:** estrategias de picking ([almacen/operaciones.md](almacen/operaciones.md#estrategias-de-picking)).
- **Cross-docking:** de recepción a despacho sin almacenar.
- **Slotting:** asignación de posiciones según la rotación.
- **LPN / SSCC:** código de una unidad de manipulación (pallet, caja).
- **GS1-128:** código de barras logístico con identificadores de aplicación (GTIN, lote, vencimiento).
- **Dock-to-stock:** tiempo de muelle a stock disponible.
- **OTIF:** a tiempo y completo. **Fill rate:** unidades atendidas sobre pedidas.
- **3PL:** operador logístico tercerizado.
- **Última milla:** entrega final al cliente.
- **Click and collect (BOPIS):** compra en línea y retiro en tienda. **Ship from store:** despacho desde
  la tienda.
- **RMA:** autorización de devolución.

## Abastecimiento

- **Procure-to-pay:** ciclo de la necesidad al pago del proveedor.
- **Conciliación de tres vías (three-way match):** orden de compra, recepción y factura.
- **Posición de inventario:** físico + entrante − comprometido; base de la decisión de compra.
- **Stock de seguridad, punto de reorden, EOQ:** ver [compras-y-abastecimiento.md](compras-y-abastecimiento.md#ejemplo-stock-de-seguridad-punto-de-reorden-y-cantidad-económica).
- **MOQ:** cantidad mínima de compra. **Lead time:** tiempo de entrega.
- **ABC / XYZ:** clasificación por valor / por variabilidad de la demanda.
- **Drop-ship:** el proveedor entrega directamente al cliente.
- **DRP:** planificación de distribución entre almacenes.

## Costos

- **COGS:** costo de ventas.
- **Perpetuo / periódico:** valorización en cada movimiento / al cierre con conteo.
- **Promedio ponderado móvil, PEPS (FIFO), estándar, identificación específica, método minorista:** ver
  [inventario/valorizacion.md](inventario/valorizacion.md#métodos-de-costo).
- **Capa de valorización:** registro de cantidad y valor de una entrada, salida o ajuste.
- **Landed cost:** costo de importación o flete que se suma al costo del inventario.
- **Variación de precio de compra (PPV):** diferencia entre el costo estándar y el real.
- **Valor neto realizable:** precio estimado de venta menos costos para vender (NIC 2).
- **Kardex:** registro cronológico de entradas, salidas y saldos de un producto, en cantidad y valor.

## Perú

- **GRE:** guía de remisión electrónica (remitente o transportista).
- **Motivo de traslado:** por qué viaja la mercadería (venta, compra, traslado entre establecimientos…).
- **RIP:** registro de inventario permanente (en unidades físicas, formato 12.1, o valorizado, 13.1).
- **PEPS:** primeras entradas, primeras salidas.
- **PCGE:** plan contable general empresarial.
- **IGV crédito fiscal:** el IGV de las compras, que se descuenta del IGV de las ventas.

## Equivalencias con el mercado

| Aquí | SAP S/4HANA | Oracle | Dynamics 365 | Odoo |
|---|---|---|---|---|
| Producto (variante) | Material | Item | Released product / product variant | Product variant |
| Almacén | Centro (plant) y almacén (storage location) | Organización de inventario y subinventario | Site y warehouse | Warehouse |
| Ubicación | Storage bin (EWM) | Locator | Location | Location |
| Movimiento | Documento de material con clase de movimiento | Material transaction | Inventory transaction | Stock move |
| Saldo | Stock libre, en calidad, bloqueado | On-hand quantity | On-hand inventory | Quant |
| Recepción de compra | Entrada de mercancía (clase 101) | Receipt | Product receipt | Receipt |
| Salida por venta | Salida de mercancía (clase 601) | Ship confirm | Packing slip | Delivery order |
| Transferencia | Pedido de traslado o clase 311 | Transfer order | Transfer order | Internal transfer |
| Merma | Desguace (clase 551) | Miscellaneous issue | Inventory adjustment | Scrap |
| Conteo | Documento de inventario físico | Cycle count | Counting journal | Physical inventory |
| Método de costo | Control de precio S (estándar) o V (promedio móvil) | Cost method | Costing method (item model group) | Costing method |
| Costo de importación | Costos de entrega | Landed Cost Management | Landed cost | Landed costs |
| Regla de reorden | Planificación por punto de pedido | Min-max planning | Coverage (min/max) | Reordering rule |

> Las equivalencias son de nomenclatura general y pueden variar por versión y edición de cada producto.
