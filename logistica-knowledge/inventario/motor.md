# Motor de inventario

Cuánto hay de cada cosa, dónde, en qué estado, de quién y desde cuándo. Todo lo que compras, almacén,
POS y contabilidad leen del stock sale de aquí, así que los errores de diseño en este nivel aparecen
después como sobreventas, quiebres, compras dobles o un costo de ventas que no cuadra.

Ubicación en el mapa: nivel 4 de [mapa.md](../mapa.md). Valorización y kardex:
[valorizacion.md](valorizacion.md). Operación física del almacén:
[almacen/operaciones.md](../almacen/operaciones.md). Tablas: secciones 1 a 5 y 7 de
[schema/logistica_schema.sql](../schema/logistica_schema.sql); la lógica (estados, reservas, quants,
stock negativo) en la sección 16. Los ejemplos de este archivo los reproduce
[schema/pruebas/smoke.sql](../schema/pruebas/smoke.sql).

## Arquitectura conceptual: cómo se conecta todo

El inventario funciona como una tubería de cinco capas:

1. **Maestros:** `product`, `uom`, `warehouse`, `location`, `lot`, `partner`. Definen qué existe y dónde
   puede estar.
2. **Documentos:** recepción, despacho, transferencia, ajuste, conteo, venta del POS, devolución.
   Expresan una intención y son la evidencia (`picking`, `pos_order`, `stock_count`).
3. **Movimientos:** `stock_move` (qué producto, cuánto, de qué ubicación a cuál) y `stock_move_line`
   (el detalle real: qué lote, qué serie, qué paquete, desde qué ubicación exacta). Inmutables una vez
   hechos.
4. **Saldos derivados:** `stock_quant`, una fila por producto × ubicación × lote × paquete × propietario.
   Se actualiza con cada movimiento y se puede reconstruir desde ellos.
5. **Valorización:** `stock_valuation_layer` (cantidad y valor de cada entrada y salida) y el asiento
   contable. Ver [valorizacion.md](valorizacion.md).

Principio rector: el stock a una fecha es la suma de los movimientos hechos hasta esa fecha. Todo el
diseño (movimientos inmutables, ubicaciones virtuales, cierre de inventario) existe para que esa suma
sea exacta y explicable ([patrones.md › 1](../patrones.md#1-el-stock-es-un-libro-mayor-de-movimientos-el-saldo-se-deriva)).

## Producto, variante y unidad de medida

### Plantilla y variante

| Entidad | Representa | Ejemplo |
|---|---|---|
| `product_template` | Lo que el cliente reconoce como «un producto» | Polo básico algodón |
| `product` (variante, SKU) | Lo que se cuenta y se mueve | Polo básico algodón, talla M, azul |

El stock, el costo y el código de barras pertenecen a la variante. Una plantilla sin variantes tiene
exactamente una.

### Tipo de producto

| Tipo | ¿Tiene stock? | Ejemplo | Efecto |
|---|---|---|---|
| Almacenable | Sí, con saldo y costo | Mercadería | Genera movimientos y valorización |
| Consumible | Se mueve pero no se controla el saldo | Bolsas, insumos de limpieza | Movimientos sin control de disponibilidad |
| Servicio | No | Instalación, delivery | Sin movimientos |
| Kit (combo de venta) | No propio: se descompone | Combo desayuno | La venta genera movimientos de cada componente |

Disponibilidad de un kit = mínimo, entre sus componentes, de `disponible ÷ cantidad por kit`. Un kit
que se arma antes de vender (ensamblado) es otra cosa: es un producto almacenable con orden de ensamble.

### Unidades de medida

- Cada producto tiene una **unidad base** de stock. Compra y venta pueden usar otras de la misma
  categoría (unidad, caja de 12, docena; kilogramo, gramo).
- La conversión es un factor y una regla de redondeo, en un solo lugar
  ([patrones.md › 6](../patrones.md#6-la-unidad-de-medida-se-convierte-en-un-solo-lugar)).
- No se cambia la unidad base de un producto con stock o con historia: se crea otro producto o se migra
  con un ajuste formal.
- Productos a granel (fruta, queso, tela) se venden por peso o longitud con decimales; el resto, en
  enteros. La precisión es parte de la unidad.

### Códigos

| Código | Uso |
|---|---|
| GTIN-13 (EAN-13) | Unidad de consumo en retail |
| GTIN-14 | Caja o empaque logístico |
| SSCC | Unidad de manipulación (pallet, caja de despacho) |
| GS1-128 | Etiqueta logística con identificadores de aplicación: GTIN, lote, vencimiento, serie |
| PLU y peso variable | Productos de balanza: el código lleva el producto y el peso o el precio |
| Código interno | Productos sin GTIN |

Un producto puede tener varios códigos (empaques, proveedores); un código pertenece a un solo producto
y a una unidad.

## Ubicaciones

### Jerarquía física

```
Almacén Central
├── Recepción (muelle)
├── Control de calidad
├── Stock
│   ├── Zona A (alta rotación)
│   │   └── Pasillo 01 › Rack 03 › Nivel 2 › Posición 04   ← ubicación de picking
│   └── Zona R (reserva, pallets)
├── Preparación (packing)
├── Despacho (muelle)
└── Devoluciones
```

Una tienda pequeña puede tener una sola ubicación «Stock»; un centro de distribución tiene miles. El
modelo es el mismo.

### Ubicaciones virtuales

| Ubicación | Para qué |
|---|---|
| Proveedores | Origen de las recepciones |
| Clientes | Destino de los despachos y de las ventas del POS |
| Ajustes de inventario | Contrapartida de sobrantes y faltantes de conteo |
| Merma | Destino de lo dañado, vencido o perdido |
| Tránsito | Entre almacenes, mientras la mercadería viaja |
| Producción | Consumo de componentes y salida de terminados |
| Consumo interno | Mercadería usada por la empresa (exhibición, muestras) |

Solo las ubicaciones internas suman al stock físico. Las virtuales existen para que todo movimiento
tenga origen y destino.

## Movimientos: de una ubicación a otra

| Operación | Origen → destino | Efecto en el stock de la empresa | Efecto contable típico |
|---|---|---|---|
| Recepción de compra | Proveedores → Stock | Sube | Inventario contra mercadería recibida por facturar |
| Venta en POS | Stock de tienda → Clientes | Baja | Costo de ventas contra inventario |
| Despacho de pedido | Stock → Despacho → Clientes | Baja al salir | Costo de ventas contra inventario |
| Transferencia | Almacén A → Tránsito → Almacén B | No cambia | Ninguno, o traslado entre almacenes si se valorizan por separado |
| Ajuste positivo | Ajustes → Stock | Sube | Inventario contra ganancia por ajuste |
| Merma | Stock → Merma | Baja | Gasto por merma contra inventario |
| Devolución de cliente | Clientes → Devoluciones | Sube | Inventario contra costo de ventas (al costo de la venta original) |
| Devolución a proveedor | Stock → Proveedores | Baja | Inventario contra cuenta del proveedor o nota de crédito por recibir |
| Consumo interno | Stock → Consumo interno | Baja | Gasto contra inventario |
| Reubicación | Ubicación interna → otra interna | No cambia | Ninguno |

### Estados del movimiento

```
draft ──► waiting ──► confirmed ──► assigned ──► done
                                         │
                       cancelled ◄───────┘ (solo antes de done)
```

| Estado | Significado |
|---|---|
| `draft` | Creado, sin efecto |
| `waiting` | Espera a otro movimiento (la etapa anterior de una ruta en varios pasos) |
| `confirmed` | Comprometido: cuenta como saliente o entrante, pero sin stock asignado |
| `assigned` | Reservado: tiene stock concreto (ubicación, lote) asignado |
| `done` | Hecho: cambió el saldo y la valorización. Inmutable |
| `cancelled` | Anulado antes de hacerse |

Un movimiento hecho no se borra ni se edita: se revierte con un movimiento inverso que referencia al
original.

### Movimiento y línea de movimiento

`stock_move` dice lo que se pidió («enviar 10 unidades»); `stock_move_line` dice lo que se hizo («6 del
lote L1 desde A-01-03 y 4 del lote L2 desde A-01-04»). Un movimiento puede hacerse en partes; lo que
queda pendiente es un pedido pendiente (backorder) o se cancela.

## Cantidades: físico, reservado, disponible y proyectado

Ejemplo: producto X en el Almacén Central, el 16/10.

| Dato | Cantidad |
|---|---|
| Físico en ubicaciones vendibles | 120 |
| En control de calidad (no vendible, no suma) | 10 |
| Reservado para pedidos con stock asignado | 30 |
| Pedidos confirmados sin stock asignado | 15 |
| Entrante: orden de compra confirmada para el 20/10 | 50 |

| Cantidad | Cálculo | Resultado |
|---|---|---|
| Disponible | 120 − 30 | 90 |
| Proyectada | 120 + 50 − 30 − 15 | 125 |
| Prometible hoy (ATP) | 120 − 30 − 15 | 75 |
| Prometible desde el 20/10 | 75 + 50 | 125 |

El disponible (90) es lo que puede reservarse ahora; el prometible (75) es lo que puede comprometerse a
un pedido nuevo sin quitarle a los ya confirmados. Comprar mirando el físico (120) en lugar de la
posición de inventario lleva a compras dobles
([compras-y-abastecimiento.md › Posición de inventario](../compras-y-abastecimiento.md#posición-de-inventario)).

Variaciones habituales:
- **Por canal:** stock de seguridad reservado para la tienda física para que la web no la vacíe.
- **Varios almacenes:** el prometible de un pedido web es la suma de los almacenes que pueden atenderlo.
- **El POS no reserva:** vende de lo que está en el estante; la venta mueve el físico directamente.

## Reservas

- **Cuándo se reserva:** al confirmar el pedido (rápido de prometer, inmoviliza stock) o al liberar a
  picking (más flexible). Es una política por tipo de operación.
- **Reserva dura o blanda:** la dura asigna lote y ubicación; la blanda solo cantidad, y se concreta al
  preparar.
- **Prioridad:** cuando no alcanza, se reserva por fecha prometida, prioridad del cliente o del canal.
- **Vencimiento:** las reservas de carritos web o de pedidos no pagados expiran.
- **Liberación:** cancelar un pedido libera su reserva en la misma transacción.

## Estrategias de salida

| Estrategia | Qué unidad sale primero | Uso típico |
|---|---|---|
| FIFO | La que entró primero | General |
| FEFO | La que vence primero | Alimentos, farmacia, cosmética |
| LIFO | La última que entró | Granel apilado (física, no contable) |
| Más cercana | La ubicación más cercana al punto de despacho | Almacenes grandes |
| Menos paquetes | La que completa con menos bultos | Despacho por cajas cerradas |

Es una decisión física, independiente del método de costo
([patrones.md › 8](../patrones.md#8-la-estrategia-física-de-salida-y-el-método-de-costo-son-decisiones-distintas)).

## Lotes, series y vencimientos

- **Lote:** varias unidades con el mismo origen (fecha de producción, proveedor). **Serie:** una unidad
  única (celular, electrodoméstico).
- **Fechas de un lote:** vencimiento (no se vende después), retiro (se saca de venta antes de vencer),
  alerta (se avisa antes del retiro), consumo preferente.
- **Un lote o serie se captura en el movimiento**, no después
  ([patrones.md › 13](../patrones.md#13-lotes-y-series-se-capturan-cuando-la-mercadería-se-mueve)).
- **Trazabilidad:** de un lote a sus clientes (retiro de producto) y de una venta a su proveedor
  (garantía).
- Un lote vencido o retirado pasa a un estado bloqueado: el POS no lo vende y la reserva no lo toma.

## Stock negativo

Ocurre cuando se registra una salida de algo que el sistema cree que no hay: la caja vende un producto
que llegó sin recepción registrada, o un conteo previo quedó mal.

| Política | Dónde se usa | Efecto |
|---|---|---|
| Prohibido | Almacenes, despachos | El movimiento no se hace sin stock |
| Permitido con alerta | POS, venta de mostrador | La venta pasa; el saldo queda negativo y se avisa |

Si se permite, la salida se valoriza con el último costo conocido y se corrige cuando llega la entrada
que faltaba ([valorizacion.md › Stock negativo](valorizacion.md#stock-negativo)). El stock negativo
persistente es una alerta de proceso, no un estado normal.

## Conteos y ajustes

- **Inventario completo:** todas las ubicaciones a la vez, normalmente con la operación detenida. Al
  cierre del ejercicio suele ser obligación legal.
- **Conteo cíclico:** un subconjunto cada día o semana, por clasificación ABC (A más seguido que C), por
  ubicación o por excepción (ubicación con diferencia, stock negativo).
- **Conteo ciego:** el contador no ve la cantidad esperada.
- **Conteo con la operación en marcha:** se toma una foto de la cantidad esperada al iniciar el conteo
  de cada ubicación; la diferencia se calcula contra esa foto más los movimientos ocurridos después.
- **Ajuste:** la diferencia genera un movimiento desde o hacia «Ajustes de inventario», con motivo y
  aprobación cuando supera un umbral de cantidad o de valor.
- **Exactitud de inventario (IRA):** porcentaje de ubicaciones contadas sin diferencia (o dentro de la
  tolerancia). Es el indicador que dice si el sistema merece confianza.

## Merma

| Tipo | Ejemplos | Cómo se registra |
|---|---|---|
| Conocida | Vencimiento, rotura, consumo, degustación | Movimiento a Merma con motivo, en el momento |
| Desconocida | Robo, error de recepción, error de despacho | Aparece como faltante en el conteo |

La merma desconocida se mide como porcentaje de las ventas y es uno de los indicadores más vigilados
del retail.

## Multialmacén y tránsito

- Una transferencia entre almacenes tiene dos pasos: salida (A → Tránsito) y recepción (Tránsito → B).
  Mientras viaja, el stock no es de ninguno de los dos.
- Si llega menos de lo enviado, la diferencia queda en tránsito hasta que se investiga y se ajusta con
  responsable (transportista, almacén de origen).
- Entre empresas distintas del mismo grupo no es una transferencia: es una venta y una compra.

## Propiedad y consignación

- **Stock de terceros en almacén propio** (consignación recibida, cliente que deja mercadería): suma al
  físico pero no al valor; cada quant tiene `owner`.
- **Stock propio en almacén de terceros** (consignación entregada, operador logístico): suma al valor y
  se controla con una ubicación por tercero.

## Rutas y operaciones en varios pasos

Un almacén puede recibir y despachar en uno, dos o tres pasos:

| Pasos | Recepción | Despacho |
|---|---|---|
| 1 | Proveedores → Stock | Stock → Clientes |
| 2 | Proveedores → Recepción → Stock | Stock → Despacho → Clientes |
| 3 | Proveedores → Recepción → Calidad → Stock | Stock → Preparación → Despacho → Clientes |

Cada paso es un movimiento encadenado (`waiting` hasta que termina el anterior). Las rutas también
definen reabastecimiento entre almacenes: la tienda «jala» del centro de distribución cuando cae bajo su
mínimo ([compras-y-abastecimiento.md](../compras-y-abastecimiento.md)).

## Cierre de inventario

- Al cerrar un mes contable se fija una fecha de bloqueo: no se registran movimientos con fecha
  anterior.
- Lo que llega tarde se registra en el período abierto con referencia al documento original.
- Antes de cerrar: recepciones sin factura conciliadas, conteos aplicados, transferencias en tránsito
  revisadas, saldos negativos regularizados, y el valor del inventario igual al saldo de la cuenta
  contable ([valorizacion.md › Cierre](valorizacion.md#cierre-de-mes)).
