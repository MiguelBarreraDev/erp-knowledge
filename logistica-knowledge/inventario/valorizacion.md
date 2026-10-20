# Valorización de inventario

Cuánto costó lo vendido y cuánto vale lo que queda. Es donde el inventario se vuelve dinero: el costo de
ventas define el margen y el valor del inventario es, en muchas empresas comerciales, el activo más
grande del balance.

Ubicación en el mapa: nivel 5 de [mapa.md](../mapa.md). Movimientos y saldos: [motor.md](motor.md).
Métodos permitidos y libros legales en Perú:
[localizacion/peru.md › Inventario](../localizacion/peru.md#inventario-y-libros). Tablas: secciones 6
y 12 de [schema/logistica_schema.sql](../schema/logistica_schema.sql) (`fn_value_move`,
`fn_add_cost_adjustment`, `fn_post_landed_cost`). Todos los ejemplos numéricos de este archivo los
calcula la base en [schema/pruebas/valorizacion.sql](../schema/pruebas/valorizacion.sql).

> Los ejemplos usan importes sin impuesto. El IGV de las compras es crédito fiscal, no costo.

## Perpetuo o periódico

| Sistema | Cómo funciona | Cuándo se sabe el costo de ventas |
|---|---|---|
| Perpetuo | Cada movimiento se valoriza y se contabiliza al hacerse | En cada venta |
| Periódico | Se registran compras; al cierre se cuenta y costo de ventas = inicial + compras − final | Al cierre del período |

Un ERP con inventario por movimientos debe ser perpetuo: el periódico esconde la merma dentro del costo
de ventas y no permite margen por venta. El periódico se mantiene solo como respaldo legal en empresas
pequeñas que no llevan registros permanentes.

## Métodos de costo

| Método | Idea | Bueno para | Cuidado con |
|---|---|---|---|
| Promedio ponderado móvil | Cada entrada recalcula el costo unitario; las salidas salen al promedio vigente | Retail, distribución | Residuos de redondeo; devoluciones |
| Promedio periódico (diario, mensual) | Un solo costo para todas las salidas del período | Empresas con muchas salidas y pocas entradas | El costo de ventas solo es definitivo al cerrar el período |
| PEPS (FIFO) | Las salidas consumen las capas más antiguas | Productos con costo variable, perecibles | Más datos: cada capa con su saldo |
| Estándar | Un costo fijo por período; la diferencia con el real es una variación | Manufactura, empresas con control presupuestal | Mantener los estándares; analizar las variaciones |
| Identificación específica | Cada unidad lleva su propio costo | Series: autos, joyas, maquinaria | Solo con seguimiento por serie |
| Método minorista | Costo = precio de venta × relación costo / precio de la categoría | Tiendas con miles de SKU sin costeo por artículo | Rebajas y promociones distorsionan la relación |

UEPS (LIFO) no es aceptado por las NIIF (NIC 2) ni por la ley tributaria peruana.

El método se define por categoría de producto o por empresa, y no se cambia con stock sin una
revalorización formal (en Perú, además, con autorización de SUNAT).

## Ejemplo comparado

Mismos movimientos de octubre, sin saldo inicial:

| Fecha | Movimiento | Cantidad | Costo unitario | Importe |
|---|---|---|---|---|
| 02/10 | Compra | 100 | 10.00 | 1,000.00 |
| 05/10 | Compra | 50 | 13.00 | 650.00 |
| 08/10 | Venta | 120 | | |
| 12/10 | Compra | 80 | 12.00 | 960.00 |
| 15/10 | Venta | 60 | | |
| | **Total comprado** | **230** | | **2,610.00** |

### Promedio ponderado móvil (kardex)

| Fecha | Operación | Entrada | Salida | Saldo cantidad | Costo unitario | Saldo valor |
|---|---|---|---|---|---|---|
| 02/10 | Compra | 100 × 10.00 = 1,000.00 | | 100 | 10.0000 | 1,000.00 |
| 05/10 | Compra | 50 × 13.00 = 650.00 | | 150 | 11.0000 | 1,650.00 |
| 08/10 | Venta | | 120 × 11.0000 = 1,320.00 | 30 | 11.0000 | 330.00 |
| 12/10 | Compra | 80 × 12.00 = 960.00 | | 110 | 11.7273 | 1,290.00 |
| 15/10 | Venta | | 60 × 11.7273 = 703.64 | 50 | 11.7272 | 586.36 |

El costo unitario se guarda con al menos cuatro decimales (1,290.00 ÷ 110 = 11.727272…) y el importe de
cada salida se redondea al céntimo. Por eso el unitario del saldo final (586.36 ÷ 50 = 11.7272) difiere
en la cuarta cifra del que tenía antes de la venta.

### PEPS (FIFO)

| Fecha | Salida | Cálculo | Costo |
|---|---|---|---|
| 08/10 | 120 | 100 × 10.00 + 20 × 13.00 | 1,260.00 |
| 15/10 | 60 | 30 × 13.00 + 30 × 12.00 | 750.00 |

Saldo final: una capa de 50 × 12.00 = 600.00.

### Estándar (11.50 fijado al inicio del período)

| Compra | Al estándar | Real | Variación de precio |
|---|---|---|---|
| 100 u | 1,150.00 | 1,000.00 | −150.00 (favorable) |
| 50 u | 575.00 | 650.00 | +75.00 (desfavorable) |
| 80 u | 920.00 | 960.00 | +40.00 (desfavorable) |
| **Total** | **2,645.00** | **2,610.00** | **−35.00** |

Costo de ventas al estándar: 180 × 11.50 = 2,070.00. Saldo final: 50 × 11.50 = 575.00.

### Promedio mensual

Costo del mes = 2,610.00 ÷ 230 = 11.347826…; costo de ventas = 180 × 11.347826 = 2,042.61; saldo final
= 2,610.00 − 2,042.61 = 567.39.

### Comparación

| Método | Costo de ventas | Inventario final | Suma |
|---|---|---|---|
| Promedio móvil | 2,023.64 | 586.36 | 2,610.00 |
| PEPS | 2,010.00 | 600.00 | 2,610.00 |
| Estándar | 2,070.00 − 35.00 de variación = 2,035.00 | 575.00 | 2,610.00 |
| Promedio mensual | 2,042.61 | 567.39 | 2,610.00 |

Ningún método crea ni destruye costo: reparte el mismo total entre lo vendido y lo que queda. Con
precios subiendo, PEPS da el menor costo de ventas (y el mayor margen y el mayor impuesto a la renta)
porque vende primero lo barato.

## Capas de valorización

Cada movimiento que afecta el valor genera una capa (`stock_valuation_layer`) con producto, cantidad,
valor unitario, valor total, movimiento de origen y asiento. En PEPS cada capa de entrada guarda además
su cantidad restante.

- El valor del inventario a cualquier fecha = suma de capas hasta esa fecha.
- Una corrección (factura con otro precio, flete tardío, revalorización) es una capa nueva sin cantidad,
  no una edición de la capa original ([patrones.md › 7](../patrones.md#7-el-costo-se-fija-en-el-movimiento-no-en-el-reporte)).
- Cuando la cantidad de un producto llega a cero, la última salida se lleva todo el valor restante; si
  no, queda un residuo de céntimos en un producto sin stock.

## Diferencias de precio con la factura del proveedor

La recepción se valoriza al precio de la orden de compra; la factura puede llegar con otro precio.

Caso: 100 unidades recibidas a 10.00 (OC), factura a 10.40; cuando llega la factura ya se vendieron 40.

| Parte | Cálculo | Destino |
|---|---|---|
| Unidades vendidas | 40 × 0.40 = 16.00 | Costo de ventas (o variación de precio) |
| Unidades en stock | 60 × 0.40 = 24.00 | Mayor valor del inventario (capa de ajuste) |
| **Total** | **40.00** | |

Con costo estándar, toda la diferencia es variación de precio de compra; el estándar no cambia.

## Costos de importación (landed costs)

Flete, seguro, aranceles, agente de aduanas y almacenaje forman parte del costo del inventario y se
prorratean entre las líneas recibidas.

Caso: flete de 300.00 para una recepción con dos productos.

| Producto | Cantidad | Valor | Peso | Por valor | Por peso | Por cantidad |
|---|---|---|---|---|---|---|
| A | 100 | 1,000.00 | 50 kg | 150.00 (1.50 / u) | 75.00 (0.75 / u) | 200.00 (2.00 / u) |
| B | 50 | 1,000.00 | 150 kg | 150.00 (3.00 / u) | 225.00 (4.50 / u) | 100.00 (2.00 / u) |
| **Total** | | | | **300.00** | **300.00** | **300.00** |

El criterio se elige por tipo de costo: el flete se reparte por peso o volumen, el seguro y los
aranceles por valor. Si el costo llega cuando parte de la mercadería ya se vendió, se divide como en la
diferencia de precio: lo vendido a costo de ventas, lo que queda a inventario.

## Devoluciones

| Devolución | Costo con que entra o sale | Por qué |
|---|---|---|
| De cliente | Al costo con que salió en la venta original | Revierte el costo de ventas de esa venta, no el de hoy |
| A proveedor (PEPS) | Al costo de la capa de la recepción original | Se devuelve esa mercadería concreta |
| A proveedor (promedio) | Al costo promedio vigente o al de la recepción original; la diferencia a variación | Política a fijar una sola vez |

Ejemplo con el kardex promedio: el 16/10 un cliente devuelve 10 unidades de la venta del 08/10 (salieron
a 11.0000). Entran 10 × 11.00 = 110.00; nuevo saldo 60 unidades y 696.36; nuevo promedio 11.6060.
Si entraran al promedio del día (11.7272) se inventarían 7.27 de costo.

## Stock negativo

Una salida sin stock se valoriza al último costo conocido (o al estándar). Cuando llega la entrada que
faltaba, la diferencia entre ese costo provisional y el costo real de la entrada se lleva al costo de
ventas de las unidades vendidas en negativo. Si el sistema no hace este ajuste, el costo de ventas queda
mal en silencio. Política de cuándo se permite: [motor.md › Stock negativo](motor.md#stock-negativo).

## Alcance del costo: por empresa o por almacén

| Alcance | Ventaja | Costo |
|---|---|---|
| Un costo por empresa | Simple; una transferencia no mueve valor | El flete entre almacenes se diluye en todos |
| Un costo por almacén | Margen real por tienda; el flete de la transferencia va al almacén que recibe | La transferencia es una salida valorizada y una entrada; más asientos |

SAP lo llama área de valoración (normalmente el centro); Odoo valoriza por empresa. Es una decisión de
inicio difícil de cambiar.

## Valor neto realizable

Por NIC 2 el inventario se mide al menor entre el costo y el valor neto realizable (precio estimado de
venta menos costos para vender). Mercadería obsoleta, dañada o con precio de venta caído se rebaja con
una estimación contable, sin mover stock. El tratamiento tributario de esa rebaja depende del país.

## Asientos tipo

```
Recepción de compra
  Debe   Inventario                               1,000.00
    Haber  Mercadería recibida por facturar          1,000.00

Factura del proveedor
  Debe   Mercadería recibida por facturar         1,000.00
  Debe   Impuesto de compras (crédito fiscal)       180.00
    Haber  Cuentas por pagar                         1,180.00

Venta (costo)
  Debe   Costo de ventas                          1,320.00
    Haber  Inventario                                1,320.00

Merma
  Debe   Gasto por merma
    Haber  Inventario

Ajuste por sobrante
  Debe   Inventario
    Haber  Ganancia por ajuste de inventario
```

La cuenta puente «mercadería recibida por facturar» es la que muestra, al cierre, lo recibido sin
factura y lo facturado sin recibir. El ingreso de la venta y su impuesto los registra la venta, no el
inventario ([pos-knowledge › caja-y-turnos.md › Contabilidad](../../pos-knowledge/caja-y-turnos.md#contabilidad-de-la-sesión)).
Plan de cuentas peruano: [localizacion/peru.md › Contabilidad](../localizacion/peru.md#contabilidad).

## Cierre de mes

1. Bloquear la fecha: no se registran movimientos anteriores ([motor.md › Cierre](motor.md#cierre-de-inventario)).
2. Conciliar recepciones sin factura y facturas sin recepción.
3. Aplicar costos de importación y diferencias de precio pendientes.
4. Regularizar saldos negativos.
5. Si se usa promedio periódico, calcular el costo del período y valorizar las salidas.
6. Registrar la estimación por valor neto realizable si corresponde.
7. **Conciliar:** el reporte de valorización (suma de capas) debe ser igual al saldo de la cuenta
   contable de inventario. Si no lo es, alguien registró un asiento manual en la cuenta de inventario o
   un movimiento quedó sin asiento.
