# Compras y abastecimiento

Qué se pide, a quién, cuándo y cuánto. Comprar tarde produce quiebres de stock y ventas perdidas;
comprar de más inmoviliza caja y genera merma. Este archivo cubre el ciclo de compra y las reglas de
reabastecimiento.

Ubicación en el mapa: nivel 6 de [mapa.md](mapa.md). Tablas: sección 8 de
[schema/logistica_schema.sql](schema/logistica_schema.sql) (`fn_create_receipt`,
`v_three_way_match`, `v_replenishment_suggestion`); el ejemplo de reposición y la conciliación de tres
vías los reproduce [schema/pruebas/operacion.sql](schema/pruebas/operacion.sql). Recepción física:
[almacen/operaciones.md](almacen/operaciones.md#flujo-de-entrada-inbound). Costo de lo comprado:
[inventario/valorizacion.md](inventario/valorizacion.md).

## Ciclo de compra (procure-to-pay)

```
Necesidad → solicitud de cotización → orden de compra → aprobación → envío al proveedor
   → confirmación → recepción → factura → conciliación de tres vías → pago
```

| Paso | Documento | Detalle |
|---|---|---|
| Necesidad | Requisición o sugerencia de reposición | Manual (un área pide) o automática (regla de reorden) |
| Cotización | Solicitud de cotización | Una o varias a distintos proveedores; se comparan precio, plazo y condiciones |
| Orden de compra | `purchase_order` | Proveedor, líneas, precio, unidad de compra, fecha prometida, almacén de destino, moneda |
| Aprobación | Por monto, por categoría o por presupuesto | Quien pide no aprueba ([patrones.md › 12](patrones.md#12-nadie-se-aprueba-a-sí-mismo)) |
| Recepción | Recepción contra la OC | Parcial o total; lo pendiente queda como saldo de la OC |
| Factura | `vendor_bill` | Del proveedor, con su impuesto |
| Conciliación | Tres vías | OC, recepción y factura deben coincidir dentro de la tolerancia |
| Pago | Tesorería | Según condiciones de pago |

### Conciliación de tres vías

| Compara | Pregunta |
|---|---|
| OC ↔ factura | ¿Se cobra el precio pactado? |
| Recepción ↔ factura | ¿Se cobra lo que realmente llegó? |
| OC ↔ recepción | ¿Llegó lo que se pidió? |

Política de facturación: pagar lo recibido (lo habitual con mercadería) o lo pedido (servicios,
anticipos). Una diferencia de precio fuera de tolerancia bloquea el pago hasta que compras la aprueba;
dentro de tolerancia, ajusta el costo ([valorizacion.md › Diferencias de precio](inventario/valorizacion.md#diferencias-de-precio-con-la-factura-del-proveedor)).

### Condiciones del proveedor

`supplier_info` por producto y proveedor: precio con vigencia, cantidad mínima de compra, múltiplo
(se compra por cajas de 12), unidad de compra, tiempo de entrega, código del producto en el proveedor.
Un producto puede tener varios proveedores con prioridad.

Evaluación del proveedor: cumplimiento de plazo, de cantidad y de calidad (OTIF del proveedor), precio
frente al mercado, devoluciones.

## Reabastecimiento

### Posición de inventario

La decisión de comprar se toma sobre la **posición**, no sobre el físico:

```
Posición = físico + entrante (OC confirmadas sin recibir) − comprometido (pedidos sin despachar)
```

Si se mira solo el físico, cada día que la OC no llega se vuelve a pedir. Cantidades en
[inventario/motor.md › Cantidades](inventario/motor.md#cantidades-físico-reservado-disponible-y-proyectado).

### Métodos

| Método | Regla | Cuándo conviene |
|---|---|---|
| Mínimo y máximo | Si la posición ≤ mínimo, pedir hasta el máximo | El más usado en ERP; simple de explicar |
| Punto de reorden y cantidad fija | Si la posición ≤ punto de reorden, pedir la cantidad económica | Demanda estable, costo de pedido relevante |
| Revisión periódica | Cada N días, pedir hasta un nivel objetivo | Proveedores con día fijo de pedido; consolidar camiones |
| Por pedido (make/buy to order) | Se compra cuando entra un pedido | Productos caros o especiales |
| Por pronóstico | Pedido según la demanda proyectada | Estacionalidad, promociones, lanzamientos |
| Reposición de tienda por venta | La tienda pide lo que vendió para volver a su nivel | Cadenas con centro de distribución |

### Ejemplo: stock de seguridad, punto de reorden y cantidad económica

Datos: demanda diaria promedio 40 u, desviación de la demanda diaria 10 u, tiempo de entrega 5 días,
nivel de servicio 95 % (z = 1.65), demanda anual 14,600 u (40 × 365), costo por pedido 50.00, costo de
mantener una unidad un año 2.00 (25 % de un costo de 8.00).

| Concepto | Fórmula | Resultado |
|---|---|---|
| Stock de seguridad | z × σ diaria × √tiempo de entrega = 1.65 × 10 × √5 = 36.89 | 37 u |
| Punto de reorden | demanda diaria × tiempo de entrega + stock de seguridad = 40 × 5 + 37 | 237 u |
| Cantidad económica (EOQ) | √(2 × demanda anual × costo por pedido ÷ costo de mantener) = √(2 × 14,600 × 50 ÷ 2) = √730,000 = 854.4 | 854 u |
| Mínimo y máximo equivalentes | mínimo = 237; máximo = 237 + 854 | 237 y 1,091 u |

Con una posición de 200 unidades (180 físicas más 20 por recibir) y un proveedor que vende por cajas de
12, la sugerencia es 1,091 − 200 = 891, redondeado al múltiplo: 75 cajas = 900 unidades.

Ajustes reales: redondear al múltiplo del proveedor y a la cantidad mínima, limitar por espacio y
por vencimiento (no comprar más de lo que se vende antes de vencer), y considerar descuentos por
volumen, que cambian la cantidad económica.

### Clasificación ABC y XYZ

- **ABC (Pareto por valor):** A ≈ 20 % de los productos que hacen ≈ 80 % del valor vendido; B el
  siguiente tramo; C el resto. A se revisa y se cuenta más seguido y tiene mayor nivel de servicio.
- **XYZ (variabilidad de la demanda):** X estable, Y variable, Z errática. Un producto AX se repone
  automáticamente con confianza; uno CZ, por pedido o con revisión manual.

### Multiescalón

Centro de distribución → tiendas: las tiendas se reponen desde el centro (transferencias) y el centro
compra a proveedores con la demanda agregada de las tiendas. El tiempo de entrega de una tienda es el
del centro, no el del proveedor. Detalle de reabastecimiento multiescalón y pronóstico:
[mapa.md › Por profundizar](mapa.md#6-por-profundizar).

## Variantes de compra

| Variante | Particularidad |
|---|---|
| Importación | Moneda extranjera, costos de importación prorrateados, recepción en aduana o almacén temporal ([valorizacion.md › Costos de importación](inventario/valorizacion.md#costos-de-importación-landed-costs)) |
| Despacho directo (drop-ship) | El proveedor entrega al cliente; no entra a almacén, pero sí hay compra, venta y costo |
| Consignación recibida | El stock está en el almacén pero es del proveedor; se compra al vender o al consumir |
| Contrato marco | Precio y volumen pactados; las OC se emiten contra el contrato |
| Compra de servicios o gastos | Sin recepción de stock; conciliación de dos vías |

## Moneda extranjera

La recepción se valoriza al tipo de cambio de su fecha; la diferencia con el tipo de cambio de la
factura o del pago es diferencia de cambio (resultado financiero), no costo del inventario. Es la regla
general de la NIC 21; el tipo de cambio que exige la norma tributaria local se confirma en la
localización.
