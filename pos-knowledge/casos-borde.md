# Casos borde

Checklist para revisar un diseño, un requerimiento o una implementación de POS. Si un caso no tiene
respuesta, el diseño está incompleto. El porqué de cada tratamiento está en el archivo enlazado y en
[patrones.md](patrones.md). Los marcados con ✔ los prueba [schema/pruebas/](schema/README.md#cargarlo-y-probarlo).

## Caja

| Situación | Tratamiento esperado |
|---|---|
| ✔ Abrir una segunda sesión en la misma caja | Bloqueado: una sola sesión activa por caja |
| ✔ Vender con la caja todavía en apertura | Bloqueado (`SESSION_NOT_OPEN`) |
| ✔ Faltante en el cierre fuera de tolerancia | Se registra; lo aprueba un supervisor, nunca el cajero |
| ✔ Editar una sesión cerrada | Bloqueado; ajuste con motivo en el back-office |
| ✔ Venta hecha antes del cierre que llega después (caja sin red) | Se acepta, se registra la excepción y la sesión queda por conciliar |
| ✔ Venta con hora posterior al cierre de la sesión | Rechazada |
| Cajero que no cerró su sesión | El supervisor la cierra con arqueo; la sesión nueva no la hereda |
| Cambio de cajero a mitad de turno con cajón compartido | Arqueo de traspaso, o cajón por cajero |
| Faltante que se quiere cobrar al cajero | Decisión de RRHH con límites legales; el POS solo registra |
| Billete falso detectado en el arqueo | Faltante con motivo específico |
| Reloj del terminal desfasado | Verificación de hora al abrir sesión; bloqueo si supera la tolerancia |
| Caja robada o dañada | Token revocado; última numeración recuperada del servidor o del respaldo |

## Venta y cobro

| Situación | Tratamiento esperado |
|---|---|
| ✔ Doble envío de la misma venta | Una sola venta: el UUID de la caja la hace idempotente |
| ✔ Cabecera que no coincide con las líneas | Bloqueado al cobrar (`ORDER_TOTALS_MISMATCH`) |
| ✔ Pago que no cubre el total | Bloqueado (`ORDER_PAYMENT_MISMATCH`) |
| ✔ Vuelto con tarjeta | Bloqueado (`ORDER_CHANGE_INVALID`) |
| ✔ Redondeo con tarjeta | Bloqueado: el redondeo solo aplica al efectivo |
| ✔ Terminar una venta sin comprobante | Bloqueado (`ORDER_FISCAL_DOCUMENT_REQUIRED`) |
| ✔ Editar una venta terminada | Bloqueado; se devuelve con otra venta |
| ✔ Cambio de precio programado a medianoche | Se guarda con la zona horaria de la tienda; sin zona, se aplica a la hora del servidor |
| Se corta la red mientras el pinpad procesa | Se consulta el estado de la transacción antes de reintentar; nunca se cobra dos veces |
| Pago mixto en el que un medio falla | La venta queda en borrador; si se abandona, se anulan los medios ya aprobados |
| Precio de góndola menor que el del sistema | Se cobra el exhibido con un ajuste de precio con motivo; se corrige la etiqueta |
| Venta pasada la medianoche | Día de negocio de la sesión; fecha de emisión real del comprobante |
| La caja vendió sin red con un precio ya vencido | La venta se acepta con su precio; se reporta como excepción |
| Venta a crédito sobre el límite del cliente | Autorización de supervisor, solo en línea |
| Producto restringido (alcohol) en horario prohibido | La caja no lo vende; la regla viaja con el catálogo |

## Devoluciones

| Situación | Tratamiento esperado |
|---|---|
| ✔ Devolución de un producto de una promoción 3 × 2 | Se reembolsa su neto pagado prorrateado |
| ✔ Devolver más de lo vendido | Bloqueado (`REFUND_EXCEEDS_SOLD`) |
| ✔ Devolver a precio de lista y no al neto | Bloqueado (`REFUND_PRICE_MISMATCH`) |
| ✔ Reembolsar en efectivo lo pagado con tarjeta | Bloqueado (`REFUND_PAYMENT_METHOD_MISMATCH`) |
| ✔ Devolución sin ticket | Solo con autorización de un supervisor distinto del cajero |
| Devolución en otra tienda | Se busca la venta en el servidor; el stock y el reembolso son de la tienda que recibe |
| Devolución el mismo día con tarjeta | Anulación de la transacción en lugar de devolución, si el adquirente lo permite |

## Comprobantes (Perú)

| Situación | Tratamiento esperado |
|---|---|
| ✔ Boleta de más de S/ 700 sin documento del cliente | No se emite hasta identificarlo |
| ✔ Factura a un cliente con DNI | Bloqueado: la factura exige RUC |
| ✔ Una caja usa la serie de otra | Bloqueado (`FISCAL_SERIES_NOT_OWNED`) |
| ✔ Comprobante numerado sin red que llega con salto | Se acepta y los números faltantes aparecen como huecos |
| ✔ Nota de crédito mayor a lo que queda del comprobante | Bloqueado (`FISCAL_NOTE_EXCEEDS`) |
| ✔ Editar un comprobante emitido | Bloqueado; se corrige con una nota |
| El cliente pide factura después de recibir boleta | Nota de crédito a la boleta y factura nueva |
| Comprobante rechazado | Se corrige el dato y se emite otro con número nuevo; el cliente recibe el nuevo |
| Caja sin red varios días | Emite y encola; alerta antes de que venza el plazo de envío (tres días para facturas) |
| Devolución parcial de una factura | Nota de crédito por ítem que referencia a esa factura (una nota, un comprobante) |

## Saldos

| Situación | Tratamiento esperado |
|---|---|
| ✔ Consumo mayor al saldo de la tarjeta de regalo | Bloqueado (`GIFT_CARD_INSUFFICIENT`) |
| La misma tarjeta de regalo usada en dos cajas sin red | Se evita: el canje de saldos es solo en línea o con tope sin red |
| Tarjeta de regalo vencida con saldo | Asiento de vencimiento según la política y la ley; el pasivo se reconoce como ingreso |
