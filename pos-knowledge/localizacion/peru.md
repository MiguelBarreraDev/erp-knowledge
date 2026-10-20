# Localización Perú

Reglas y parámetros de venta, impuestos, comprobantes y protección al consumidor para Perú. Cada valor
indica desde cuándo rige, su fuente y su estado de verificación. **Verificado** = contrastado con la
fuente en la fecha indicada. **Verificar** = conocimiento general que falta contrastar con la norma
vigente o un especialista. La guía de remisión y los libros de inventario están en
[logistica-knowledge › localizacion/peru.md](../../logistica-knowledge/localizacion/peru.md).

Última revisión general: 2026-10-16.

En el esquema: las tasas van en `tax_rate` (por país o por empresa, con vigencia y norma) y los demás
valores en `legal_parameter`; [schema/pruebas/peru.sql](../schema/pruebas/peru.sql) reproduce el
ejemplo de este archivo.

## Impuestos a la venta

| Código | Valor | Vigente desde | Fuente | Estado | Revisar |
|---|---|---|---|---|---|
| IGV general | 18 % (16 % IGV + 2 % IPM) | 2011-03-01 | Ley 29666 | Verificar | — |
| IGV reducido: restaurantes, hoteles y alojamientos turísticos MYPE | 2026: 10.5 % (8 % IGV + 2.5 % IPM). 2027: 15 % (12 % IGV + 3 % IPM) | Régimen desde 2022-09-01 | Ley 31556, prórroga Ley 32219, IPM Ley 32387 | Verificado para 2026 (SUNAT orientación). Verificar fin de vigencia: las fuentes dicen 2026-12-31 y 2027-12-31 | Diciembre 2026 |
| ICBPER (impuesto a las bolsas plásticas) | S/ 0.50 por bolsa | 2023-01-01 | Ley 30884 (cronograma desde S/ 0.10 en 2019) | Verificar que no cambió en 2026 | Enero de cada año |
| UIT 2026 | S/ 5,500.00 | 2026-01-01 | DS 301-2025-EF | Verificado (en hr-knowledge) | Enero 2027 |
| ISC (selectivo al consumo) | Por producto: licores, cigarrillos, combustibles, bebidas azucaradas | — | TUO de la Ley del IGV e ISC | Verificar tasas y montos fijos | — |

**Requisitos del IGV reducido** (SUNAT): MYPE cuya actividad principal sea restaurante, hotel o
alojamiento turístico, con al menos 70 % de sus ingresos de esas actividades, ventas anuales de hasta
1,700 UIT y sin vinculación económica con empresas que no cumplan. En el diseño: la tasa es de la
empresa con vigencia, no del producto
([patrones.md › 12](../patrones.md#12-el-impuesto-es-de-la-localización)).

**ICBPER:** el comprobante indica la cantidad de bolsas, la sigla «ICBPER» y el importe del impuesto
(RS 150-2019/SUNAT, verificado). Es un impuesto por unidad, no un porcentaje, y no está incluido en el
precio de la bolsa.

### Tipo de afectación del IGV (catálogo 07)

| Código | Afectación |
|---|---|
| 10 | Gravado, operación onerosa |
| 11 a 17 | Gravado, retiros y transferencias gratuitas (bonificación, premio, donación…) |
| 20 | Exonerado, operación onerosa |
| 21 | Exonerado, transferencia gratuita |
| 30 | Inafecto, operación onerosa |
| 31 a 37 | Inafecto, retiros y transferencias gratuitas |
| 40 | Exportación |

Estado: verificar contra el catálogo vigente de SUNAT. Es el dato que el producto lleva en lugar de
«tasa» (`product.tax_category_code`).

## Comprobantes de pago

| Tipo | Código (catálogo 01) | Serie | Para qué |
|---|---|---|---|
| Factura | 01 | Empieza con F (F001) | Venta a quien tiene RUC; sustenta crédito fiscal y gasto |
| Boleta de venta | 03 | Empieza con B (B001) | Venta al consumidor final |
| Nota de crédito | 07 | Empieza con F o B según el comprobante que modifica | Devoluciones, descuentos, anulación de la operación |
| Nota de débito | 08 | Igual que la nota de crédito | Aumentos posteriores (intereses, penalidades) |

Estado: verificar códigos y prefijos con el catálogo vigente. El emisor crea las series que necesite;
en el diseño, una serie por caja y tipo
([offline-y-dispositivos.md › Numeración](../offline-y-dispositivos.md#numeración-sin-coordinación)).
Las pruebas usan BC01 y FC01 para las notas: es una convención, no una exigencia.

### Reglas

| Regla | Fuente | Estado |
|---|---|---|
| La boleta identifica al adquirente (nombres y documento de identidad) si el importe total supera S/ 700, o si el cliente lo pide | RS 097-2012/SUNAT, modificada por RS 303-2018/SUNAT | Verificado (SUNAT orientación, 2026-10-16) |
| La factura y sus notas se envían hasta el tercer día calendario contado desde el día siguiente a la emisión | RS 000003-2023/SUNAT | Verificado |
| Las boletas y sus notas se envían por resumen diario o individualmente; plazo hasta el séptimo día calendario siguiente a la emisión | RS 097-2012/SUNAT y modificatorias | Verificar (solo fuente secundaria) |
| Comunicación de baja: hasta 7 días calendario | SUNAT orientación | Verificado (guía); verificar texto vigente |
| Una nota de crédito o débito modifica un solo comprobante también en el SEE-OSE; el resumen diario de baja se envía en 7 días calendario | RS 000048-2026/SUNAT; vigencia pospuesta al 2027-01-01 por RS 000143-2026/SUNAT | Verificado (fuente secundaria: Sovos); revisar en enero de 2027 |
| La factura indica la forma de pago (contado o crédito) y, si es a crédito, las cuotas con importe y fecha | RS 193-2020/SUNAT | Verificar |
| Formato: XML UBL 2.1 con firma digital; representación impresa con código QR | Especificaciones técnicas de SUNAT | Verificar versión vigente |
| Conservación de XML y constancias durante el plazo de prescripción | Código Tributario | Verificar plazo |

En el esquema: `BOLETA_ID_THRESHOLD`, `FACTURA_SEND_DAYS` y `BOLETA_SEND_DAYS` en `legal_parameter`;
`fn_fiscal_guard` exige el documento del cliente y `v_fiscal_pending` muestra el plazo que queda.

### Sistemas de emisión

| Sistema | Cómo funciona |
|---|---|
| SEE del contribuyente | El emisor genera, firma y envía a SUNAT desde su propio sistema |
| SEE-OSE | El emisor envía a un operador de servicios electrónicos, que valida, responde con la constancia y luego informa a SUNAT |
| SEE-SOL y APP Emprender | Emisión manual en el portal o la aplicación de SUNAT; no sirve para un POS |
| PSE | Un proveedor emite por cuenta del contribuyente |

La constancia de recepción (CDR) dice si el comprobante fue aceptado, aceptado con observaciones o
rechazado. Diseño del servicio fiscal: [comprobantes.md › Quién envía](../comprobantes.md#quién-envía-a-la-autoridad).

### Anulación y corrección

| Situación | Tratamiento | Estado |
|---|---|---|
| Error detectado antes de entregar la factura al cliente | Comunicación de baja dentro del plazo | Verificar condiciones exactas de procedencia |
| Boleta que debe anularse | Baja mediante el resumen diario (estado anulado) | Verificar |
| Operación ya entregada: devolución, descuento, error de importe | Nota de crédito con el motivo del catálogo 09 (por ejemplo, anulación de la operación, descuento global, devolución total, devolución por ítem) | Verificar códigos |
| Comprobante rechazado | No tiene validez; se emite uno nuevo con otro número | Verificar si el correlativo rechazado puede reutilizarse (el diseño asume que no) |
| El cliente pide factura después de recibir boleta | Nota de crédito a la boleta y emisión de la factura | Verificar plazo y condiciones |

### Contingencia

Si el emisor no puede emitir electrónicamente por causas no imputables a él, puede emitir comprobantes
físicos de contingencia (preimpresos autorizados) e informarlos después a SUNAT. Estado: verificar
condiciones, numeración y plazo del informe. Para un POS, la estrategia preferida es otra: seguir
emitiendo electrónicamente en la caja y enviar dentro del plazo legal
([offline-y-dispositivos.md › Comprobantes sin red](../offline-y-dispositivos.md#comprobantes-sin-red)).

## Consumidor

| Regla | Fuente | Estado |
|---|---|---|
| Prohibido redondear en perjuicio del consumidor salvo que acepte expresamente al pagar; aplica al efectivo. Ejemplo oficial: S/ 9.96 se cobra S/ 9.90 | Ley 29571, art. 44; Circular BCRP 2011 | Verificado |
| Las monedas de 5 céntimos dejaron de circular; la menor moneda es de 10 céntimos | BCRP, desde 2019-01-01 | Verificado |
| Retener céntimos del vuelto para una donación requiere consentimiento del cliente | Indecopi, Resolución 3570-2019/SPC | Verificado (LP Derecho) |
| El precio exhibido es el precio total, con impuestos incluidos | Código de Protección y Defensa del Consumidor | Verificar artículo |
| Libro de reclamaciones físico o virtual en los establecimientos abiertos al público | Ley 29571 y su reglamento | Verificar |

**El redondeo en el sistema:** el comprobante se emite por el importe exacto; la caja cobra el importe
redondeado hacia abajo solo en efectivo (`fn_cash_rounding`), y la diferencia se registra en la venta
(`cash_rounding_amount`) y en la contabilidad como gasto por redondeo, no como faltante de caja. En el
XML existe un campo de redondeo del importe total; verificar su uso vigente.

## Contabilidad

Plan Contable General Empresarial, cuentas de uso frecuente en la caja (verificar subcuentas con el
contador):

| Cuenta | Uso |
|---|---|
| 10 Efectivo y equivalentes | Caja, bóveda, bancos |
| 12 Cuentas por cobrar comerciales | Ventas a crédito, tarjetas y billeteras por cobrar al adquirente |
| 40 Tributos por pagar | IGV, ICBPER |
| 49 Pasivos diferidos | Tarjetas de regalo vendidas y no usadas (verificar) |
| 70 Ventas | Ingreso |
| 65 / 75 Otros gastos / ingresos de gestión | Faltantes y sobrantes de caja, redondeo (verificar) |

El costo de ventas (69 contra 20) lo registra el inventario, no la caja.

## Ejemplo completo de un ticket

Boleta electrónica de una bodega, régimen general, cliente sin identificar (total menor a S/ 700),
pago en efectivo. Precios exhibidos con IGV incluido.

| Línea | Cantidad | Precio con IGV | Importe con IGV | Valor de venta (base) | IGV |
|---|---|---|---|---|---|
| Detergente 1 kg | 2 | 12.95 | 25.90 | 21.95 | 3.95 |
| Galletas | 3 | 2.45 | 7.35 | 6.23 | 1.12 |
| Bolsa plástica | 1 | 0.20 | 0.20 | 0.17 | 0.03 |
| **Total gravado** | | | **33.45** | **28.35** | **5.10** |
| ICBPER | 1 bolsa × 0.50 | | 0.50 | | |
| **Importe total** | | | **33.95** | | |

| Cálculo | Detalle |
|---|---|
| Base de cada línea | Importe ÷ 1.18, redondeado: 25.90 ÷ 1.18 = 21.949… → 21.95 |
| IGV de cada línea | Importe − base, y coincide con base × 18 %: 21.95 × 0.18 = 3.951 → 3.95 |
| Valor unitario en el XML | Dos formas válidas: valor de venta ÷ cantidad = 21.95 ÷ 2 = 10.975, o precio ÷ 1.18 = 12.95 ÷ 1.18 = 10.9746. Ambas multiplicadas por 2 dan 21.95; se fija una sola. El esquema usa la primera |
| Control del total | 28.35 × 18 % = 5.103 → 5.10, igual a la suma de líneas |
| Cobro en efectivo | 33.95 se redondea a favor del cliente a 33.90 (0.05 de redondeo) |
| Vuelto | Paga con 50.00: 50.00 − 33.90 = 16.10 |

Si pagara con tarjeta o QR se cobra 33.95 exacto. Con otros precios, la suma de las bases por línea
puede diferir en un céntimo de la base calculada sobre el total
([venta.md › Precio con impuesto incluido](../venta.md#precio-con-impuesto-incluido)); SUNAT valida esas
sumas con tolerancias que hay que confirmar en las reglas de validación vigentes.

## Fuentes

- [SUNAT – RS 000003-2023/SUNAT, plazo de envío de la factura electrónica](https://www.sunat.gob.pe/legislacion/superin/2023/000003-2023.pdf)
- [Andina – Ampliación del plazo para envío de facturas electrónicas](https://andina.pe/agencia/noticia-sunat-dispuso-ampliacion-del-plazo-para-envio-facturas-electronicas-926338.aspx)
- [SUNAT orientación – Operatividad del SEE (resumen diario, comunicación de baja)](https://orientacion.sunat.gob.pe/node/732)
- [SUNAT orientación – Boleta de venta](https://orientacion.sunat.gob.pe/03-boleta-de-venta)
- [SUNAT – RS 303-2018/SUNAT](https://ww3.sunat.gob.pe/legislacion/superin/2018/303-2018.pdf)
- [Sovos – RS 000048-2026/SUNAT sobre la boleta de venta electrónica](https://sovos.com/es/cambios-regulatorios/iva/peru-boleta-venta-electronica-rs-000048-2026-sunat/)
- [SUNAT Emprender – Tasa reducida de IGV para restaurantes y hoteles](https://emprender.sunat.gob.pe/principales-impuestos/imp-general-las-ventas-igv/reduccion-igv-para-restaurantes-hoteles)
- [Gestión – Extensión de la reducción del IGV a restaurantes y hoteles](https://gestion.pe/economia/congreso-aprobo-extender-la-rebaja-del-igv-a-restaurantes-y-hoteles-noticia/)
- [LP Derecho – Impuesto al consumo de bolsas plásticas](https://lpderecho.pe/impuesto-consumo-bolsas-plastico/)
- [SUNAT – RS 150-2019/SUNAT, ICBPER en comprobantes](https://ww3.sunat.gob.pe/legislacion/superin/2019/150-2019.pdf)
- [BCRP – Circular 002-2011, redondeo a favor del consumidor](https://www.bcrp.gob.pe:443/docs/Transparencia/Normas-Legales/Circulares/2011/Circular-002-2011-BCRP.pdf)
- [LP Derecho – Moneda de cinco céntimos deja de circular en 2019](https://lpderecho.pe/moneda-cinco-centimos-dejara-circular-2019/)
- [LP Derecho – Indecopi sanciona retención de céntimos del vuelto](https://lpderecho.pe/sancionan-supermercado-no-informar-retencion-centimos-vuelto-donaciones-fe-alegria-resolucion-3570-2019-spc-indecopi/)
- [El Peruano – UIT 2026](https://elperuano.pe/noticia/285318-nueva-uit-2026-conoce-los-montos-que-afectan-sueldos-multas-y-beneficios-laborales)
