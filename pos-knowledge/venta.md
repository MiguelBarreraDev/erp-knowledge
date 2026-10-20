# Motor de venta del POS

Cómo se registra, se calcula y se cobra una venta en caja, y cómo se devuelve. La caja y sus turnos
tienen su propio archivo ([caja-y-turnos.md](caja-y-turnos.md)); el comprobante también
([comprobantes.md](comprobantes.md)); la operación sin red, también
([offline-y-dispositivos.md](offline-y-dispositivos.md)).

Ubicación en el mapa: niveles 4, 8 y 9 de [mapa.md](mapa.md). Tablas: secciones 4, 6 y 8 de
[schema/pos_schema.sql](schema/pos_schema.sql); el cálculo de referencia de una línea es `fn_add_line` y
la validación al cobrar, `fn_validate_order`. El prorrateo del 3 × 2 y sus devoluciones los reproduce
[schema/pruebas/devolucion.sql](schema/pruebas/devolucion.sql).

> Los importes de ejemplo usan el IGV general de Perú (18 %). Las tasas reales y sus vigencias están en
> [localizacion/peru.md](localizacion/peru.md); el motor nunca las escribe en código.

Una venta en caja produce cinco cosas, y todas deben cuadrar entre sí:
1. **Un comprobante** (boleta, factura) con su número.
2. **Efectos de stock** de la tienda hacia el cliente, que el inventario convierte en movimientos
   valorizados ([patrones.md › 10](patrones.md#10-el-pos-no-es-dueño-del-stock-lo-consume-y-lo-publica)).
3. **Pagos** por medio, que alimentan la sesión de caja.
4. **Ingreso e impuestos** para la contabilidad.
5. **Datos** para comisiones, fidelización y análisis.

## Estructura de una venta

| Entidad | Contiene |
|---|---|
| `pos_order` | Identificador generado en la caja (UUID), sesión, terminal, cajero, vendedor, cliente, día de negocio, fecha y hora del hecho, estado, totales |
| `pos_order_line` | Producto, cantidad y unidad, precio de lista, descuentos y promociones aplicados, base, impuestos, total, lote o serie, vendedor de la línea |
| `pos_payment` | Medio de pago, importe, vuelto, referencia de autorización, estado |
| `fiscal_document` | El comprobante emitido desde la venta ([comprobantes.md](comprobantes.md)) |

### Estados

```
draft ──► paid ──► done ──► posted
  │         │
  └─────────┴──► cancelled (antes de terminar, con los pagos anulados)
```

| Estado | Significado |
|---|---|
| `draft` | Carrito abierto; se puede editar todo |
| `paid` | Cobrada completamente; la base validó totales, pagos, vuelto, redondeo y devoluciones |
| `done` | Comprobante emitido y efectos de stock publicados (en la caja, aunque no haya red) |
| `posted` | Contabilizada con el asiento de la sesión |

La sincronización no es un estado: la venta llega al servidor con su `received_at`. La caja la arma en
borrador y la termina en una sola transacción; el servidor la recibe igual.

Una venta cobrada no vuelve atrás: se devuelve con otra venta en negativo que referencia a la original
([patrones.md › 5](patrones.md#5-lo-emitido-no-se-edita-se-anula-o-se-corrige-con-otro-documento)).
Una venta suspendida («en espera», para atender a otro cliente) sigue en `draft`.

## Cómo se calcula una línea

Orden de evaluación. Cada paso deja su traza en la línea
([patrones.md › 4](patrones.md#4-precio-descuento-e-impuesto-se-calculan-por-reglas-y-la-línea-guarda-el-resultado)):

1. **Precio de lista** vigente para la tienda, el canal, el cliente, la cantidad y la fecha y hora.
2. **Descuento manual de línea**, con tope por rol; sobre el tope, autorización de supervisor.
3. **Promociones de producto:** precio especial, NxM, segunda unidad con descuento.
4. **Promociones de pedido:** monto mínimo, combos, descuento global; se prorratean a las líneas.
5. **Cupones.**
6. **Promociones por medio de pago** (por ejemplo, descuento con una tarjeta de un banco): se conocen al
   cobrar, así que el total se recalcula después de elegir el medio y antes de autorizar el cobro.
7. **Impuestos** según la categoría de afectación de cada línea.
8. **Redondeo:** se calcula con precisión y se redondea al céntimo según una regla fija. El redondeo del
   efectivo es otra cosa y ocurre al cobrar ([Pagos](#pagos)).

### Precio con impuesto incluido

En venta al consumidor el precio exhibido incluye el impuesto, así que la base se obtiene dividiendo.
Esto crea diferencias de céntimos según dónde se redondee:

| Cálculo | Base | IGV | Total |
|---|---|---|---|
| Por total: 3 × 10.00 = 30.00; 30.00 ÷ 1.18 | 25.42 | 4.58 | 30.00 |
| Por línea: 10.00 ÷ 1.18 = 8.47 e IGV 1.53, sumado tres veces | 25.41 | 4.59 | 30.00 |

El total cobrado no cambia; cambia cómo se reparte entre base e impuesto. La regla (redondear por línea
o por total) se fija una sola vez y debe ser la misma en el POS, en el comprobante y en la contabilidad.
Ejemplo con la regla peruana en [localizacion/peru.md › Ejemplo](localizacion/peru.md#ejemplo-completo-de-un-ticket).

## Promociones

| Tipo | Ejemplo | Cómo se reparte el descuento |
|---|---|---|
| Porcentaje o monto en producto | 20 % en polos | En la línea |
| Precio especial | Gaseosa a 2.50 | En la línea |
| NxM | 3 × 2 en galletas | Entre las unidades que participan |
| Combo o paquete | Hamburguesa + bebida a 15.00 | Entre los componentes, por peso de su precio de lista |
| Umbral de pedido | 10 % comprando más de 200.00 | Entre todas las líneas que califican |
| Cupón | 15.00 de descuento con el código | Entre las líneas que califican |
| Por medio de pago | 15 % con la tarjeta de un banco | Entre las líneas; a menudo lo financia el banco |
| Por cliente o nivel | Precio de socio | En la línea |

### Reglas de combinación

- **Exclusiva:** si aplica, ninguna otra aplica a esas líneas.
- **Acumulable:** se suma a las anteriores, en el orden de evaluación.
- **La mejor para el cliente:** entre promociones excluyentes se elige la de mayor descuento.
- **Prioridad explícita:** cuando dos reglas compiten, gana la de mayor prioridad, no la creada primero.

### Prorrateo y devoluciones

Caso: tres polos a 40.00 con 3 × 2.

| Línea | Precio de lista | Descuento prorrateado | Neto pagado |
|---|---|---|---|
| Polo 1 | 40.00 | 13.33 | 26.67 |
| Polo 2 | 40.00 | 13.33 | 26.67 |
| Polo 3 | 40.00 | 13.34 | 26.66 |
| **Total** | **120.00** | **40.00** | **80.00** |

Si el cliente devuelve un polo, se le reembolsa su neto pagado (26.67), no el precio de lista (40.00) ni
cero. Sin el descuento prorrateado y guardado en la línea, la devolución no tiene respuesta correcta.
La política alternativa (recalcular la promoción con lo que queda) existe, pero es más difícil de
explicar al cliente y se usa poco.

## Impuestos

- Cada producto tiene una **categoría de afectación** (gravado, exonerado, inafecto, exportación,
  gratuito), no una tasa. La tasa sale de la localización con su vigencia.
- Una línea puede tener **varios impuestos:** uno porcentual sobre la base (IGV) y otros específicos por
  unidad (impuesto a las bolsas plásticas) o selectivos (licores, cigarrillos).
- **Transferencias gratuitas** (bonificaciones, regalos promocionales) se informan con su valor
  referencial aunque no se cobren; el tratamiento del impuesto depende del país.
- **Tasas especiales por actividad** (por ejemplo, IGV reducido para restaurantes en Perú) son
  propiedad de la empresa o del establecimiento, con vigencia.

## Clientes

- **Anónimo o identificado:** la venta al consumidor final puede ser anónima hasta un monto; sobre ese
  monto, o si el cliente lo pide, se identifica con su documento.
- **El documento define el comprobante:** con número de contribuyente se emite factura; con documento de
  identidad, boleta ([localizacion/peru.md › Comprobantes](localizacion/peru.md#comprobantes-de-pago)).
- **Validación:** el número se valida con dígito verificador en la caja y contra el padrón de la
  autoridad cuando hay red; sin red, con una copia local de los clientes frecuentes.
- **Crédito:** venta a cuenta corriente con límite; exceder el límite exige autorización.

## Pagos

| Medio | Particularidad |
|---|---|
| Efectivo | Único medio que da vuelto; sujeto a redondeo a favor del consumidor donde la ley lo exige |
| Tarjeta con pinpad integrado | El POS envía el importe al pinpad y recibe la autorización; no hay digitación |
| Tarjeta con terminal no integrado | El cajero digita el importe en el terminal y registra la referencia; riesgo de error de digitación |
| Billetera o QR | QR dinámico con el importe (se confirma solo) o estático (el cajero verifica la notificación) |
| Transferencia | Se confirma con la referencia; típica en ventas grandes o a empresas |
| Tarjeta de regalo o vale | Requiere validar saldo en línea para evitar que se use dos veces |
| Nota de crédito o saldo a favor | De una devolución anterior |
| Crédito del cliente | Genera una cuenta por cobrar |
| Puntos de fidelización | Medio de pago con su propio pasivo contable |

Reglas:
- **Pagos mixtos:** una venta se paga con varios medios; el comprobante se emite cuando la suma cubre el
  total.
- **Si un medio falla a mitad de cobro,** la venta queda pendiente con los medios ya aprobados; si se
  abandona, esos medios se anulan (reversa de la autorización), nunca se olvidan.
- **El POS no toca datos de tarjeta.** Con un pinpad semi-integrado el número de tarjeta nunca pasa por
  el POS, lo que reduce el alcance de PCI DSS.
- **Estados de un pago con tarjeta:** `pending → authorized → captured`, o `declined`, `voided`
  (anulado el mismo día, antes de la liquidación) y `refunded` (devuelto después). Ante un tiempo de
  espera agotado, primero se consulta el estado de la transacción y después se reintenta; nunca al
  revés.
- **Propinas:** se registran aparte del importe de la venta, porque no son ingreso de la empresa.
- **Conciliación** de tarjetas y billeteras contra el adquirente: [caja-y-turnos.md › Conciliación](caja-y-turnos.md#conciliación-de-tarjetas-y-billeteras).

## Devoluciones, cambios y anulaciones

| Situación | Tratamiento |
|---|---|
| Quitar una línea antes de cobrar | Se elimina del carrito, con registro si la línea ya estaba escaneada (indicador de fraude) |
| Anular una venta cobrada antes de emitir | Se revierten los pagos; no hay comprobante |
| Anular una venta con comprobante emitido | Nota de crédito, o baja del comprobante si la ley lo permite ([localizacion/peru.md](localizacion/peru.md#anulación-y-corrección)) |
| Devolución con ticket | Se busca la venta original (por QR o número del ticket); se devuelve al neto pagado de cada línea; la nota de crédito referencia el comprobante original |
| Devolución sin ticket | Según política: no se acepta, se da un vale, o se reembolsa al menor precio de los últimos N días; siempre con autorización |
| Cambio de producto | Devolución más venta nueva; si hay diferencia, se cobra o se reembolsa |
| Devolución en otra tienda | Se busca la venta en el servidor; el stock entra en la tienda que recibe; el reembolso sale de su caja |

Reglas:
- **Al mismo medio de pago:** lo pagado con tarjeta se devuelve a la tarjeta, no en efectivo; es el
  control más simple contra el lavado y el fraude.
- **Plazo y estado del producto:** la política de devoluciones vive en la configuración de la empresa,
  con plazo por categoría.
- **Destino del stock:** a la ubicación de devoluciones para inspección, o directo al stock vendible si
  la política lo permite. Costo con que reingresa: [logistica-knowledge › valorizacion.md › Devoluciones](../logistica-knowledge/inventario/valorizacion.md#devoluciones).
- **Autorización:** devoluciones sobre un monto, sin ticket o fuera de plazo requieren supervisor
  ([patrones.md › 7](patrones.md#7-nadie-se-autoriza-a-sí-mismo)).

## Vendedores y comisiones

- El vendedor no es el cajero: en tiendas asistidas (ropa, electro) el vendedor atiende y el cajero
  cobra. La venta guarda ambos y la línea puede tener su propio vendedor.
- La comisión se calcula sobre la venta neta de devoluciones del período, con la regla del plan de
  comisiones.
- El resultado entra a la nómina como novedad: `payroll_input` con `source = 'commission'` en el
  esquema de [hr-knowledge](../hr-knowledge/schema/hr_schema.sql).

## Ventas especiales

| Venta | Diferencia con la venta normal |
|---|---|
| Con entrega posterior (despacho a domicilio) | Se cobra en caja pero el stock se reserva y sale con el despacho, no del estante |
| Separado (layaway) | Pagos parciales; el producto se reserva; se entrega al completar el pago |
| Anticipo | Se cobra antes de entregar; en muchos países exige comprobante del anticipo y su aplicación después |
| Por peso | El código de la balanza trae el peso o el importe; la línea guarda ambos |
| Con número de serie | La serie se captura al vender; garantía y trazabilidad dependen de ella |
| Producto restringido | Alcohol o tabaco: validación de edad, horario o días de prohibición configurables |
| Pedido web retirado en tienda | La venta ya existe y está pagada; la caja solo entrega y registra la salida |
