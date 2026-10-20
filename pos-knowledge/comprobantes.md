# Comprobantes de venta

El comprobante es un documento, no una vista de la venta: se emite con número, se congela, se firma, se
informa a la autoridad tributaria, se entrega y, si hay error, se corrige con otro documento. Las reglas
concretas de Perú (tipos, series, plazos, contingencia) están en
[localizacion/peru.md](localizacion/peru.md#comprobantes-de-pago).

Tablas: sección 9 de [schema/pos_schema.sql](schema/pos_schema.sql) (`fn_issue_fiscal_document`,
`fn_fiscal_guard`). Venta de la que sale: [venta.md](venta.md). Principio:
[patrones.md › 5](patrones.md#5-lo-emitido-no-se-edita-se-anula-o-se-corrige-con-otro-documento).

## Venta y comprobante son cosas distintas

| Venta (`pos_order`, `sale_order`) | Comprobante (`fiscal_document`) |
|---|---|
| Hecho comercial: qué se vendió, a quién, cómo se pagó | Documento legal que lo respalda ante la autoridad y el cliente |
| Puede tener pagos parciales, estar en espera, cancelarse | Una vez emitido, solo se anula o se corrige con otro documento |
| La genera la operación | Lo genera un servicio fiscal desde la venta ya cerrada |

Relaciones posibles: una venta con un comprobante (lo normal en caja); varias entregas con un
comprobante (factura que agrupa guías); un comprobante de anticipo y otro final que lo aplica; una
devolución con su nota de crédito que referencia al comprobante original.

## Qué debe cumplir

- **Contenido mínimo legal:** emisor, establecimiento, tipo, serie y correlativo, fecha y hora de
  emisión, adquirente cuando corresponde, líneas (cantidad, unidad, descripción, valor unitario,
  categoría de afectación), totales por categoría, impuestos, importe total, moneda, forma de pago.
- **Numeración:** serie y correlativo sin huecos ni repeticiones; un número nunca se reutiliza, ni
  siquiera si el comprobante fue rechazado o anulado.
- **Integridad:** firma digital del emisor y código de verificación (hash y QR).
- **Constancia de la autoridad:** la respuesta de aceptación (en Perú, el CDR) se guarda junto al
  documento.
- **Idéntico en todos los canales**, porque sale del mismo documento guardado, nunca de recalcular la
  venta.

## Ciclo de vida

```
generated ──► signed ──► sent ──► accepted
                           │
                           ├──► observed (aceptado con observaciones)
                           └──► rejected
accepted ──► voided (baja)  |  corrected by credit / debit note
```

| Estado | Qué significa | Qué se hace |
|---|---|---|
| `generated` | Armado desde la venta, con número asignado | Firmar |
| `signed` | Firmado; ya es el documento | Entregar al cliente y encolar el envío |
| `sent` | Enviado a la autoridad o al operador, sin respuesta | Consultar el estado antes de reenviar |
| `accepted` | Válido | Nada |
| `observed` | Válido con observaciones | Corregir la causa para los siguientes |
| `rejected` | No tiene validez | Corregir los datos y emitir un comprobante nuevo con otro número; el cliente debe recibir el nuevo |
| `voided` | Dado de baja dentro de las reglas y plazos legales | Queda visible con su motivo |

Una nota de crédito no cambia el estado del comprobante original: es otro documento que lo referencia
y que, sumado a él, da el efecto neto.

## Notas de crédito y de débito

| Motivo | Documento |
|---|---|
| Devolución total o parcial | Nota de crédito por las líneas devueltas, al neto pagado |
| Descuento posterior a la venta | Nota de crédito por el descuento |
| Error en el importe o en el impuesto | Nota de crédito y comprobante nuevo, o nota de débito si se cobró de menos |
| Anulación de la operación | Nota de crédito por el total |
| Intereses o penalidades posteriores | Nota de débito |

La nota de crédito lleva el motivo codificado según el catálogo del país y la referencia exacta al
comprobante que modifica. Si el cliente pide factura después de recibir boleta, no se «convierte»: se
corrige la boleta con nota de crédito y se emite la factura (si la ley lo permite en ese plazo).

## Quién envía a la autoridad

El POS no debería hablar con la autoridad tributaria directamente. Un servicio fiscal recibe los
comprobantes de la cola, los firma (si no vienen firmados), los envía, guarda la constancia y
reintenta.

| Modalidad (nombres de Perú) | Quién valida | Comentario |
|---|---|---|
| Directo a la autoridad | La autoridad | Sistema propio del emisor |
| Operador de servicios electrónicos (OSE) | Un operador autorizado, que luego informa a la autoridad | Respuesta más rápida y estable |
| Proveedor de servicios electrónicos (PSE) | El proveedor emite por cuenta del contribuyente | Tercerizar la emisión |

Diseño recomendado: el servicio fiscal es un módulo con su propia cola y sus propios estados, con un
adaptador por modalidad y por proveedor. Cambiar de OSE no debe tocar el POS.

## Según dónde se muestra

| Canal | Qué debe tener |
|---|---|
| Ticket impreso | Representación impresa con el contenido mínimo, el QR, el hash y la dirección para consultarlo |
| PDF | Igual al ticket, en formato A4 o de ticket; para correo y descarga |
| Correo o mensajería | Enlace o PDF; sin depender de que el cliente imprima |
| Consulta pública | Página donde el cliente valida con serie, número, fecha e importe |
| Archivo XML | El documento legal en sí; se conserva por los años que exija la ley |

## De dónde sale cada parte

| Elemento | Origen |
|---|---|
| Emisor y establecimiento | `company`, `establishment` de la tienda |
| Serie y correlativo | Serie de la caja (`document_sequence`) |
| Fecha y hora de emisión | Fecha del hecho de la venta, no el día de negocio |
| Adquirente | Cliente de la venta, con el documento validado |
| Líneas, valores unitarios, descuentos | Snapshot de `pos_order_line` (precio de lista, promociones prorrateadas, base, impuesto) |
| Totales por categoría e impuestos | Suma de las líneas, con la regla de redondeo fijada |
| Forma de pago | Pagos de la venta (contado) o condiciones de crédito |
| Firma, hash, QR | Servicio fiscal |
| Constancia de aceptación | `fiscal_submission`, con el archivo de respuesta |
