# Glosario

Términos del dominio y su equivalente en los productos del mercado.

## Caja

- **Caja (terminal, register):** equipo registrado desde el que se vende, con su token y sus series.
- **Sesión de caja:** período de operación de un cajón o caja, de la apertura al cierre.
- **Día de negocio:** jornada de la tienda a la que pertenece una venta.
- **Turno:** tiempo en que un cajero es responsable del dinero.
- **Fondo (float):** efectivo inicial para dar vuelto.
- **Retiro parcial (safe drop):** efectivo que se saca del cajón a bóveda durante la sesión.
- **Ingreso de sencillo:** monedas que se traen de la bóveda al cajón.
- **Arqueo:** conteo del efectivo y de los demás medios. **Cierre ciego:** el cajero declara sin ver
  lo esperado.
- **Lectura X / cierre Z:** reporte parcial / cierre definitivo numerado.
- **Override:** autorización de un supervisor sobre una regla.

## Venta

- **Ticket:** la venta en la caja; su representación impresa es el comprobante.
- **Precio de lista:** el de la lista de precios vigente, antes de descuentos.
- **Prorrateo:** reparto de un descuento de la orden entre sus líneas.
- **NxM (3 × 2):** lleva N, paga M.
- **Categoría de afectación:** gravado, exonerado, inafecto, exportación, gratuito.
- **Anulación (void) / devolución (refund):** cancelar antes de que la operación se complete / revertir
  una venta ya hecha.
- **Separado (layaway):** venta con pagos parciales y entrega al completar.
- **Comercio unificado:** un solo stock, cliente y pedido para todos los canales.
- **Click and collect:** compra en línea y retiro en tienda.

## Pagos

- **Medio de pago (tender):** efectivo, tarjeta, QR, vale, crédito.
- **Vuelto:** efectivo entregado menos lo aplicado; solo existe en efectivo.
- **Redondeo a favor del consumidor:** cobrar en efectivo hacia la décima inferior.
- **Adquirente:** entidad que procesa los pagos con tarjeta del comercio. **MDR:** su comisión.
- **Pinpad semi-integrado:** el POS envía el importe y el terminal maneja la tarjeta.
- **EMV:** estándar de pago con chip. **PCI DSS:** estándar de seguridad de datos de tarjetas.
  **P2PE:** cifrado de punto a punto.
- **Tap to pay / SoftPOS:** cobro sin contacto con el propio teléfono o tableta.
- **Contracargo (chargeback):** reverso de un cobro con tarjeta iniciado por el titular.
- **Liquidación:** abono del adquirente al comercio, neto de comisiones.

## Operación sin red

- **Offline-first:** la caja trabaja con datos locales y sincroniza después.
- **Cola de salida (outbox):** lo vendido que espera ser enviado.
- **Idempotencia:** enviar dos veces produce el mismo resultado que una.
- **Cursor de sincronización:** última versión de maestros que la caja recibió.
- **Servidor de tienda:** servidor local que atiende a las cajas cuando se cae internet.
- **KDS:** pantalla de cocina.

## Perú

- **CPE:** comprobante de pago electrónico. **SEE:** sistema de emisión electrónica.
- **OSE / PSE:** operador de servicios electrónicos / proveedor de servicios electrónicos.
- **CDR:** constancia de recepción del comprobante.
- **UBL 2.1:** formato XML de los comprobantes.
- **Resumen diario:** envío agrupado de boletas y sus notas.
- **Comunicación de baja:** anulación informada de un comprobante.
- **IGV / IPM:** impuesto general a las ventas / impuesto de promoción municipal (juntos, 18 %).
- **ICBPER:** impuesto al consumo de las bolsas de plástico.
- **ISC:** impuesto selectivo al consumo.
- **RUC / DNI:** registro único de contribuyentes / documento nacional de identidad.
- **PCGE:** plan contable general empresarial.

## Equivalencias con el mercado

| Aquí | Dynamics 365 Commerce | Odoo Point of Sale |
|---|---|---|
| Sesión de caja | Shift | POS session |
| Fondo inicial | Declare start amount | Opening cash |
| Ingreso de sencillo | Float entry | Cash in |
| Retiro parcial a bóveda | Safe drop | Cash out |
| Depósito al banco | Bank drop | — |
| Declaración en el cierre | Tender declaration | Closing control |
| Cierre ciego | Blind close | — |
| Lectura X / cierre Z | X report / Z report | Reporte de la sesión |
| Medio de pago | Payment method | Payment method |
| Devolución | Return | Refund |

> Las equivalencias son de nomenclatura general y pueden variar por versión y edición de cada producto.
