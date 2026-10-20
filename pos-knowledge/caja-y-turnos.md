# Caja y turnos

Casi todos los descuadres de caja y los reportes de ventas «del día equivocado» vienen de mezclar tres
cosas que parecen la misma. Este archivo las separa y describe la sesión de caja, sus estados, el
arqueo, el cierre y la conciliación.

Venta y pagos: [venta.md](venta.md). Operación sin red: [offline-y-dispositivos.md](offline-y-dispositivos.md).
Tablas: sección 7 de [schema/pos_schema.sql](schema/pos_schema.sql) y su máquina de estados en la
sección 16.2 (`fn_session_expected`, `fn_declare`, `fn_post_session`). El ejemplo de cierre, la
aprobación y el asiento los reproduce [schema/pruebas/caja.sql](schema/pruebas/caja.sql).

## Las tres cosas que no hay que mezclar

| Concepto | Pregunta que responde | Ejemplo |
|---|---|---|
| **Día de negocio** | ¿A qué jornada de la tienda pertenece la venta? Define el cierre de tienda y los reportes diarios | Un bar abre el viernes a las 18:00 y cierra el sábado a las 03:00: todo es jornada del viernes |
| **Sesión de caja** | ¿Qué dinero entró y salió de este cajón o terminal, y cuadra? | Caja 2, abierta a las 08:00 con 200.00 de fondo, cerrada a las 16:00 |
| **Turno del cajero** | ¿Quién era responsable del dinero en cada momento? | Ana de 08:00 a 12:00 y Luis de 12:00 a 16:00 en la misma caja |

Y una cuarta que no es operativa sino legal: la **fecha de emisión** del comprobante es la fecha real
del hecho. La venta de las 00:40 del sábado pertenece a la jornada del viernes, pero su comprobante dice
sábado y entra en el resumen fiscal del sábado
([patrones.md › 3](patrones.md#3-día-de-negocio-fecha-del-hecho-y-fecha-de-registro-no-se-mezclan)).

## Modelos de sesión

| Modelo | Cómo funciona | Cuándo conviene | Quién lo usa así |
|---|---|---|---|
| Sesión por terminal | Una sesión por caja; todos los cajeros que la usan comparten el cajón | Tiendas pequeñas, un cajero por caja | Odoo |
| Sesión por cajero (cajón propio) | Cada cajero tiene su cajón; puede llevarlo de una caja a otra | Supermercados, cadenas con alta rotación de cajeros | Grandes POS de retail (Oracle Xstore, Dynamics 365 Commerce) |
| Turno suspendible | El turno se suspende en una caja y se retoma en otra | Cajeros que cubren descansos | Dynamics 365 Commerce |

Si dos cajeros comparten un cajón sin arqueo intermedio, una diferencia no tiene responsable. El
cambio de turno con cajón compartido exige un arqueo de traspaso.

## Estados de la sesión

```
opening ──► opened ──► closing ──► closed ──► posted
```

| Estado | Qué se puede hacer |
|---|---|
| `opening` | Contar el fondo inicial; todavía no se vende |
| `opened` | Vender, cobrar, devolver, retirar e ingresar efectivo |
| `closing` | Ya no se vende; se cuenta y se declara por medio de pago |
| `closed` | Diferencias calculadas y aprobadas; inmutable |
| `posted` | Asiento contable generado |

Reglas que la base hace cumplir ([patrones.md › 9](patrones.md#9-las-garantías-viven-en-la-base-no-en-la-pantalla)):
- Una sola sesión abierta por terminal (o por cajón, en el modelo por cajero).
- No hay venta sin sesión abierta ni con hora posterior al cierre.
- La base no puede saber lo que la caja todavía no envió: si llega una venta hecha antes del cierre,
  se acepta, se registra la excepción (`late_after_close`) y la sesión queda marcada para conciliar.
  Por eso la caja intenta sincronizar todo antes de pasar a cierre.
- No se cierra con ventas en borrador ni sin declarar cada medio de pago con movimiento.
- Una sesión cerrada no se edita. Un error se corrige con un ajuste en el back-office, con motivo,
  autorización y referencia a la sesión.

## Apertura

- **Fondo fijo (sencillo):** importe definido por caja, contado por denominación.
- **Continuidad:** el fondo de apertura debe ser igual al que se dejó en el cierre anterior; si no, la
  diferencia se registra antes de vender.
- **Validaciones de inicio:** fecha y hora del terminal correctas, series fiscales vigentes, catálogo y
  precios actualizados, impresora y gaveta respondiendo.

## Movimientos de efectivo durante la sesión

| Movimiento | Signo | Ejemplo |
|---|---|---|
| Venta en efectivo (neta de vuelto) | + | Cobro de una boleta |
| Devolución en efectivo | − | Reembolso de un producto |
| Retiro parcial a bóveda | − | Cuando el cajón supera el tope (por seguridad) |
| Ingreso de sencillo | + | Monedas traídas desde bóveda |
| Pago de caja chica | − | Movilidad, con comprobante del gasto |
| Propina en efectivo | + | Restaurantes, si se registra en caja |

Cada movimiento tiene motivo, responsable y, sobre un monto, autorización. El retiro parcial genera un
sobre con su propio número que la bóveda recibe y cuenta.

## Arqueo y cierre

- **Lectura X:** reporte parcial de la sesión sin cerrarla. Se puede pedir varias veces.
- **Cierre Z:** cierre definitivo, numerado, que deja los acumulados en cero. La terminología viene de
  las impresoras fiscales y se sigue usando.
- **Cierre ciego:** el cajero declara lo contado por medio de pago sin ver lo esperado; el sistema
  calcula la diferencia y la muestra al supervisor
  ([patrones.md › 6](patrones.md#6-el-dinero-siempre-tiene-un-responsable)).
- **Tolerancia:** una diferencia dentro del umbral se registra y se aprueba sola; fuera de él exige
  motivo y aprobación del supervisor.
- **Faltantes:** se registran siempre, aunque se repongan. Cobrarlos al cajero tiene límites legales
  (descuento en planilla con autorización); no es una decisión del POS.

### Ejemplo de cierre

| Efectivo | Importe |
|---|---|
| Fondo inicial | 200.00 |
| Ventas en efectivo (netas de vuelto) | 1,850.50 |
| Devoluciones en efectivo | −45.00 |
| Retiro parcial a bóveda (11:30) | −1,000.00 |
| Pago de caja chica | −20.00 |
| Ingreso de sencillo desde bóveda | 100.00 |
| **Esperado** | **1,085.50** |
| Contado por el cajero | 1,080.00 |
| **Diferencia** | **−5.50 (faltante)** |

| Otros medios | Esperado (sistema) | Declarado | Diferencia |
|---|---|---|---|
| Tarjetas | 2,340.00 | 2,340.00 (cierre de lote del pinpad) | 0.00 |
| Billetera QR | 410.00 | 410.00 | 0.00 |

Destino del efectivo: se deja el fondo de 200.00 para la apertura siguiente y se deposita 880.00
(1,080.00 − 200.00); con el retiro parcial que ya está en bóveda, el depósito al banco del día es
1,880.00.

## Cierre de tienda (día de negocio)

1. Todas las sesiones de la jornada cerradas (o forzadas por el supervisor, con arqueo).
2. Bóveda contada: retiros parciales recibidos, sobres cuadrados.
3. Depósito preparado o recojo de transportadora de valores registrado.
4. Reporte del día: ventas por medio de pago, por categoría, por cajero; diferencias; anulaciones y
   devoluciones; descuentos con autorización.
5. Comprobantes del día enviados a la autoridad o en cola dentro del plazo
   ([comprobantes.md](comprobantes.md)).

Un cajero que olvidó cerrar no hereda su sesión al día siguiente: el supervisor la cierra con un arqueo
y la sesión nueva empieza con su propio fondo.

## Conciliación de tarjetas y billeteras

Tres registros deben cuadrar:

```
Ventas del POS por medio  ↔  Cierre de lote del pinpad o reporte de la billetera  ↔  Abono en el banco
```

- El adquirente liquida días después (T+1, T+2 o más), descontando su comisión (MDR) y, a veces,
  impuestos sobre la comisión.
- El abono del banco = ventas con tarjeta − comisión − contracargos y devoluciones del período.
- Las diferencias típicas son ventas digitadas con otro importe (terminal no integrado), anulaciones
  del día que el POS no registró y contracargos.

## Contabilidad de la sesión

Asiento resumen por sesión (o por día y tienda), al cerrar:

```
Debe   Caja (efectivo contado)
Debe   Tarjetas por cobrar al adquirente
Debe   Billeteras por cobrar
Debe   Faltante de caja (si hay)
  Haber  Ventas (base)
  Haber  IGV por pagar
  Haber  Otros impuestos (bolsas plásticas, selectivo)
  Haber  Sobrante de caja (si hay)
```

El costo de ventas lo registra el movimiento de stock, no la sesión
([logistica-knowledge › valorizacion.md › Asientos](../logistica-knowledge/inventario/valorizacion.md#asientos-tipo)). Al cobrar el
adquirente: debe banco y comisiones, haber tarjetas por cobrar.

## Dónde va cada cosa en la interfaz

| Vista | Contiene |
|---|---|
| POS › Caja | Abrir con fondo, retiros e ingresos, lectura X, cierre ciego |
| Tienda (supervisor) › Cajas | Sesiones abiertas, diferencias por aprobar, cierres forzados |
| Back-office › Sesiones | Historial por tienda y fecha, ajustes con motivo, asiento |
| Back-office › Conciliación | Lotes de tarjetas y abonos bancarios contra ventas |

Regla de UX central, igual que en el ciclo de nómina: el botón primario cambia según el estado. En
`opening` es «Abrir caja»; en `opened`, «Vender»; en `closing`, «Declarar»; nunca conviven
([ux.md](ux.md)).
