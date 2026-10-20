# Patrones de diseño

Decisiones que se repiten en cualquier sistema serio de logística, con su porqué. Sirven como checklist
al revisar un diseño: si un requerimiento rompe uno de estos patrones, debe justificar por qué. Cada
uno está implementado y probado en [schema/](schema/README.md).

## 1. El stock es un libro mayor de movimientos; el saldo se deriva

Cada entrada y salida es un movimiento inmutable (`stock_move_line` hecha). El saldo por producto,
ubicación y lote (`stock_quant`) es una proyección de esos movimientos: se guarda como caché para leer
rápido, pero siempre se puede reconstruir sumando movimientos (`fn_rebuild_quants`).

**Por qué:** el kardex, la valorización, la auditoría y el stock a cualquier fecha salen de los
movimientos. Un sistema que hace `UPDATE stock SET cantidad = cantidad - 1` no puede explicar por qué
hay 7 unidades y no 9.

## 2. Todo movimiento va de una ubicación a otra

No hay stock que aparezca ni que desaparezca: cada movimiento tiene origen y destino. Lo que entra viene
de una ubicación virtual (proveedor, ajuste, producción) y lo que sale va a otra (cliente, merma,
consumo). Una transferencia entre almacenes pasa por tránsito. Detalle en
[inventario/motor.md › Movimientos](inventario/motor.md#movimientos-de-una-ubicación-a-otra).

**Por qué:** es la partida doble de las cantidades. Por producto, la suma de todas las ubicaciones,
reales y virtuales, es cero (`v_quant_zero_sum`), y el efecto contable de un movimiento se deduce de su
origen y su destino en vez de depender de un campo «tipo» que alguien olvida llenar.

## 3. Físico, reservado, disponible y proyectado son cantidades distintas

| Cantidad | Qué es |
|---|---|
| Física (on hand) | Lo que está en ubicaciones internas no bloqueadas |
| Reservada | Lo físico ya asignado a un pedido o tarea |
| Disponible | Física − reservada |
| Proyectada | Física + entrante − saliente |
| Prometible (ATP) | Lo que puede comprometerse a un pedido nuevo en una fecha |

Ejemplo en [inventario/motor.md › Cantidades](inventario/motor.md#cantidades-físico-reservado-disponible-y-proyectado),
calculado por `v_stock_availability`.

**Por qué:** prometer lo reservado produce sobreventa; comprar mirando solo lo físico produce compras
dobles. Cada pregunta de negocio usa una cantidad distinta.

## 4. Documento, movimiento y asiento son cosas distintas

El documento (recepción, despacho, transferencia, venta de un canal) es la intención y la evidencia; el
movimiento es el cambio físico; la capa de costo y el asiento son su efecto contable. Un documento
genera varios movimientos; un movimiento hecho genera una capa y un asiento.

**Por qué:** una recepción parcial, una devolución de una sola línea o una reubicación interna (sin
efecto contable) no caben si los tres viven en la misma fila.

## 5. Fecha del movimiento, fecha contable y fecha de registro no se mezclan

| Fecha | Pregunta que responde |
|---|---|
| Del movimiento (`date_done`) | ¿Cuándo se movió físicamente? Define el kardex y el costo |
| Contable (`layer_date`) | ¿En qué período cae su efecto? Normalmente la misma; un costo de importación tardío tiene la suya |
| De registro (`created_at`) | ¿Cuándo lo supo el sistema? Una venta sin red o una recepción digitada tarde |

**Por qué:** si se usa la fecha de registro, el kardex de un mes cerrado cambia cuando llega una venta
atrasada; si se permite cualquier fecha del movimiento, se reescriben meses cerrados. El cierre
(`inventory_lock`) fija hasta dónde se aceptan fechas pasadas.

## 6. La unidad de medida se convierte en un solo lugar

Cada producto tiene una unidad base de stock; compra y venta usan otras de la misma categoría con su
factor y su redondeo. Todo movimiento guarda la cantidad del documento y la cantidad en unidad base
(`fn_to_base_qty`).

**Por qué:** el error clásico de inventario es el ×12: se compra una caja, se registra una unidad. Si la
conversión vive en cada pantalla, cada pantalla la hace distinto.

## 7. El costo se fija en el movimiento, no en el reporte

Cada salida se valoriza al hacerse y el valor queda grabado (`stock_valuation_layer`). Las correcciones
posteriores (factura con otro precio, flete tardío) entran como capas de ajuste, sin reescribir el costo
de las salidas pasadas. Detalle en [inventario/valorizacion.md](inventario/valorizacion.md).

**Por qué:** el costo de ventas de setiembre ya se contabilizó y se declaró. Si el reporte recalcula el
promedio cada vez que se abre, el margen de un mes cerrado cambia solo.

## 8. La estrategia física de salida y el método de costo son decisiones distintas

Qué unidad sale del estante (FEFO: la que vence primero) lo decide la operación; con qué costo sale
(promedio, PEPS) lo decide la contabilidad. Un almacén puede despachar por FEFO y valorizar a promedio.

**Por qué:** mezclarlas obliga a elegir entre despachar mal (vence mercadería) o contabilizar mal.

## 9. Las garantías viven en la base, no en la pantalla

Reservas que no superan lo físico, stock negativo solo donde la ubicación lo permite, movimientos
hechos inmutables, nada con fecha de un período cerrado, conversiones solo dentro de la misma categoría,
lote obligatorio en productos con seguimiento: lo hace cumplir la base y el backend lo traduce a
mensajes legibles. Los códigos están en [schema/README.md › Qué hace cumplir la base](schema/README.md#qué-hace-cumplir-la-base).

**Por qué:** importaciones, marketplaces, el POS y los scripts escriben en las mismas tablas. Una regla
que solo está en un formulario se rompe en la primera carga masiva.

## 10. Toda operación que llega por integración es idempotente

Cada movimiento o documento que viene de otro sistema (POS, marketplace, handheld, proveedor) lleva una
clave única de origen (`external_key`). La base inserta o devuelve el existente; nunca duplica
(`fn_quick_move`).

**Por qué:** reintentos, colas que reenvían y webhooks que llegan dos veces. Sin idempotencia, cada fallo
de red es un stock descontado dos veces.

## 11. Lo hecho no se edita: se revierte con otro movimiento

Un movimiento hecho se corrige con un movimiento inverso que referencia al original (`origin_move_id`);
una recepción, con una devolución al proveedor; un costo, con una capa de ajuste; un mes cerrado, con
un movimiento en el período abierto.

**Por qué:** lo hecho ya está en el kardex, en la contabilidad y quizá en una declaración. Reescribirlo
deja inconsistentes el stock, el costo y los libros.

## 12. Nadie se aprueba a sí mismo

Quien crea una orden de compra sobre el límite no la aprueba; quien cuenta no aprueba su propio ajuste
grande; quien recibe no concilia la factura. Motivo obligatorio y auditoría en cada excepción.

**Por qué:** el inventario es dinero en estantes. La merma desconocida y las compras infladas son los
fraudes más comunes, y la segregación de funciones es el control que pide cualquier auditor.

## 13. Lotes y series se capturan cuando la mercadería se mueve

El lote, la serie y el vencimiento se registran en el movimiento, no se completan después. La
trazabilidad va en dos sentidos: de un lote a todos los clientes que lo recibieron y de una venta al
proveedor que lo entregó.

**Por qué:** un retiro de producto o una garantía se resuelven en horas solo si el dato se capturó al
moverse. Reconstruirlo después es imposible.

## 14. Los canales consumen stock; el inventario es el dueño

El POS, la web y los marketplaces no escriben saldos ni costos: publican salidas y devoluciones con su
clave, y el inventario las convierte en movimientos valorizados. Los canales leen una réplica del
disponible con su hora.

**Por qué:** si cada canal descuenta su propio stock, hay tantos saldos como canales y ninguno cuadra
con el kardex. Un solo dueño del stock es lo que permite vender el mismo producto en tienda y en web.

## 15. La configuración tiene capas y cada una tiene dueño

| Capa | Qué define | Quién |
|---|---|---|
| Sistema | Tipos de ubicación, estados, ubicaciones virtuales, motor de costo | El producto |
| Localización | Métodos de costo permitidos, libros de inventario, guía de remisión, motivos de traslado | El producto, por país |
| Tenant | Categorías y su método de costo, cuentas, tolerancias, límites de aprobación | Admin del cliente |
| Almacén | Ubicaciones, rutas, pasos de recepción y despacho, reglas de ubicación | Jefe de almacén |
| Producto | Unidad base, seguimiento, vencimientos, proveedores | Admin de catálogo |

**Por qué:** si el cliente puede activar un método de costo que la ley no permite, la contabilidad
fiscal queda mal; si el producto congela una política del cliente, no se puede vender a dos empresas.

## 16. El mínimo viable es un subconjunto del modelo completo

Aunque cada almacén tenga una sola ubicación, el movimiento ya lleva origen y destino; aunque se use
costo promedio, ya existen capas; aunque no haya WMS, ya existe la línea de movimiento con lote y
ubicación exacta.

**Por qué:** así cada mejora es aditiva y la migración es gradual. Un atajo con otra forma (stock como
columna del producto) obliga a reescribir datos más adelante.

## 17. Las migraciones son expand / contract

Igual que en [hr-knowledge › patrones.md › 11](../hr-knowledge/patrones.md#11-las-migraciones-son-expand--contract).

**Lo que sí es difícil de deshacer** y conviene decidir bien desde el inicio:
- guardar el stock como un número en el producto en lugar de derivarlo de movimientos;
- movimientos sin ubicación de origen y destino;
- costo calculado al reportar en lugar de grabado en el movimiento;
- costo por empresa o por almacén;
- integraciones sin clave de idempotencia.
