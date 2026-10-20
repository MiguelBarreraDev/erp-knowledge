# Patrones de diseño

Decisiones que se repiten en cualquier POS serio, con su porqué. Sirven como checklist al revisar un
diseño: si un requerimiento rompe uno de estos patrones, debe justificar por qué. Cada uno está
implementado y probado en [schema/](schema/README.md).

## 1. La caja vende sin red

La caja tiene localmente lo necesario para vender (catálogo, precios, promociones, impuestos, series y
estado de la sesión) y encola lo vendido para sincronizar después. El servidor es la verdad del stock;
la caja es la verdad de lo que se vendió. Detalle en [offline-y-dispositivos.md](offline-y-dispositivos.md).

**Por qué:** la red de una tienda falla, y una caja que no cobra pierde la venta y la cola. Una venta ya
cobrada nunca se rechaza al sincronizar: si llega tarde se acepta y se registra la excepción
(`pos_sync_exception`).

## 2. Toda operación que viaja por red es idempotente

Cada venta, pago y movimiento de efectivo lleva un identificador generado en la caja (UUID). El
servidor inserta o ignora por ese identificador; nunca duplica.

**Por qué:** reintentos automáticos, doble clic en «Cobrar» y colas que reenvían. Sin idempotencia, cada
fallo de red es una venta doble.

## 3. Día de negocio, fecha del hecho y fecha de registro no se mezclan

| Fecha | Pregunta que responde | Ejemplo | Columna |
|---|---|---|---|
| Día de negocio | ¿A qué jornada y cierre pertenece? | Venta de un bar a las 00:40 del sábado: jornada del viernes | `business_date` |
| Fecha del hecho | ¿Cuándo ocurrió? Define la fecha de emisión del comprobante | Sábado 00:40 | `occurred_at` |
| Fecha de registro | ¿Cuándo lo supo el servidor? | Sábado 09:15, al sincronizar | `received_at` |

Detalle en [caja-y-turnos.md](caja-y-turnos.md#las-tres-cosas-que-no-hay-que-mezclar).

**Por qué:** con la fecha de registro, una caja sin red reporta ventas en el día equivocado; con el día
de negocio como fecha fiscal, el comprobante sale con una fecha de emisión falsa.

## 4. Precio, descuento e impuesto se calculan por reglas y la línea guarda el resultado

El precio sale de listas con vigencia, las promociones de reglas con orden y combinabilidad explícitos y
el impuesto de la categoría de afectación vigente. La línea guarda el resultado y su traza: precio de
lista, descuentos (los de la orden, prorrateados), base e impuestos. Ver [venta.md](venta.md#cómo-se-calcula-una-línea).

**Por qué:** una devolución se reembolsa al precio efectivamente pagado, un reclamo pregunta por qué se
cobró eso y un análisis de margen necesita saber qué promoción lo erosionó. Nada de eso se responde
recalculando con las reglas de hoy.

## 5. Lo emitido no se edita: se anula o se corrige con otro documento

Un comprobante emitido se corrige con una nota de crédito o de débito; una venta terminada, con una
devolución que la referencia; una sesión cerrada, con un ajuste registrado con motivo. Ver
[comprobantes.md](comprobantes.md).

**Por qué:** lo emitido ya se entregó al cliente, se informó a la autoridad o se contó en un cierre.
Reescribirlo deja inconsistentes la caja, la contabilidad y la declaración.

## 6. El dinero siempre tiene un responsable

Cada sol en una caja pertenece a una sesión y a un cajero en cada momento. El cierre es ciego (el cajero
declara lo contado sin ver lo esperado) y la diferencia se registra siempre, aunque se reponga.

**Por qué:** el POS es el punto de mayor riesgo de fraude interno de una empresa minorista. Sin
responsable no hay control, y sin cierre ciego el cajero declara lo que el sistema espera.

## 7. Nadie se autoriza a sí mismo

Descuentos sobre el tope del rol, anulaciones de ventas cobradas, devoluciones sin ticket y diferencias
de cierre fuera de tolerancia las aprueba otra persona, con motivo y registro.

**Por qué:** es el control que pide cualquier auditor y el primero que falta en los sistemas pequeños.

## 8. Cada caja numera sola

Cada caja tiene sus propias series de comprobantes; el correlativo se toma al emitir, sin preguntarle a
nadie. El servidor valida que la serie sea de esa caja y detecta los huecos (`v_fiscal_number_gaps`).

**Por qué:** una serie compartida obliga a pedir números al servidor, y entonces la caja deja de vender
sin red. Un hueco en la numeración es un incidente fiscal que hay que poder ver.

## 9. Las garantías viven en la base, no en la pantalla

Una sola sesión activa por caja, nada de ventas fuera de una sesión, totales que cuadran con las líneas,
pagos que cubren el total, vuelto solo en efectivo, devoluciones dentro de lo vendido, comprobante
inmutable: lo hace cumplir la base y el backend lo traduce a mensajes legibles. Los códigos están en
[schema/README.md › Qué hace cumplir la base](schema/README.md#qué-hace-cumplir-la-base).

**Por qué:** la sincronización de las cajas, las integraciones y los scripts escriben en las mismas
tablas. Una regla que solo está en la pantalla de la caja se rompe en la primera caja con una versión
vieja.

## 10. El POS no es dueño del stock: lo consume y lo publica

La venta publica efectos de stock (`stock_effect`) con una clave única; el inventario los convierte en
movimientos valorizados. La caja muestra el disponible de una réplica con su hora (`store_stock_level`).

**Por qué:** si la caja descuenta su propio saldo, hay tantos stocks como cajas y ninguno cuadra con el
kardex. El costo de lo vendido lo calcula el inventario
([logistica-knowledge › patrones.md › 14](../logistica-knowledge/patrones.md#14-los-canales-consumen-stock-el-inventario-es-el-dueño)).

## 11. Los saldos se derivan de un libro mayor

Tarjeta de regalo, crédito del cliente y puntos son la suma de sus movimientos; nunca un número que se
sobrescribe. La base impide que un consumo deje el saldo negativo.

**Por qué:** auditoría completa, reconstrucción a cualquier fecha y protección contra usar el mismo
saldo dos veces.

## 12. El impuesto es de la localización

El producto lleva una categoría de afectación, no una tasa; la tasa sale de la localización con su
vigencia, y una empresa puede tener una tasa especial (IGV reducido) con su propia vigencia y su norma.

**Por qué:** las tasas cambian por ley y por régimen. Una tasa escrita en el producto o en el código
queda mal el día que cambia, y no se puede explicar con qué norma se cobró.

## 13. Venta, pago y comprobante son cosas distintas

La venta es el hecho comercial; el pago, cada cobro por medio; el comprobante, el documento legal. Una
venta puede tener varios pagos, una devolución tiene su propia nota, un pago puede fallar sin que la
venta exista todavía.

**Por qué:** si viven en la misma fila no caben los pagos mixtos, las devoluciones parciales ni el
comprobante rechazado que se reemite con otro número.

## 14. La configuración tiene capas y cada una tiene dueño

| Capa | Qué define | Quién |
|---|---|---|
| Sistema | Estados, orden de cálculo, motor de promociones | El producto |
| Localización | Impuestos y tasas, tipos de comprobante, umbrales y plazos, reglas de redondeo | El producto, por país |
| Tenant | Listas de precios, promociones, política de devoluciones, tolerancia de caja, topes por rol | Admin del cliente |
| Tienda | Jornada, zona horaria, medios aceptados, lista de precios | Admin de operaciones |
| Caja | Series, impresora, gaveta, balanza, pinpad | Soporte de tienda |

**Por qué:** si el cliente puede editar una tasa de impuesto, tarde o temprano emite mal; si el producto
congela una política del cliente, no se puede vender a dos cadenas distintas.

## 15. El mínimo viable es un subconjunto del modelo completo

Aunque haya una sola caja, ya existe la sesión; aunque no haya promociones, la línea ya guarda precio de
lista y descuento; aunque todo sea en línea, la venta ya nace con el UUID de la caja.

**Por qué:** así cada mejora es aditiva y la migración es gradual. Una venta sin sesión o sin UUID obliga
a reescribir datos el día que se agrega el modo sin red.

## 16. Las migraciones son expand / contract

Igual que en [hr-knowledge › patrones.md › 11](../hr-knowledge/patrones.md#11-las-migraciones-son-expand--contract).
Con cajas sin red conviven versiones de la aplicación de caja durante días: el servidor acepta el
formato viejo y el nuevo hasta que todas las cajas actualizan.

**Lo que sí es difícil de deshacer** y conviene decidir bien desde el inicio:
- ventas sin identificador generado en la caja;
- una sola serie de comprobantes compartida por todas las cajas;
- precio y descuento de la línea sin guardar (solo el total);
- venta y comprobante en la misma fila;
- el POS descontando su propio stock.
