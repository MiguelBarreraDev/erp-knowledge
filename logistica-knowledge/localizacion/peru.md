# Localización Perú

Reglas y parámetros de inventario, costos, traslado de bienes y compras para Perú. Cada valor indica
desde cuándo rige, su fuente y su estado de verificación. **Verificado** = contrastado con la fuente en
la fecha indicada. **Verificar** = conocimiento general que falta contrastar con la norma vigente o un
especialista. Los comprobantes de venta y el IGV de la venta están en
[pos-knowledge › localizacion/peru.md](../../pos-knowledge/localizacion/peru.md).

Última revisión general: 2026-10-16.

## Parámetros

| Código | Valor | Vigente desde | Fuente | Estado | Revisar |
|---|---|---|---|---|---|
| UIT 2026 | S/ 5,500.00 | 2026-01-01 | DS 301-2025-EF | Verificado (en hr-knowledge) | Enero 2027 |
| IGV de las compras | 18 % (16 % IGV + 2 % IPM); es crédito fiscal, no costo del inventario | 2011-03-01 | Ley 29666 | Verificar | — |

La UIT define qué registros de inventario debe llevar la empresa ([abajo](#inventario-y-libros)).

## Guía de remisión

| Regla | Fuente | Estado | Revisar |
|---|---|---|---|
| Guía de remisión electrónica remitente y transportista obligatoria para todo traslado de bienes en el territorio nacional | Designación progresiva desde enero de 2023; obligatoria para todos desde 2024-01-01 | Verificado (nota de prensa SUNAT 001-2025) | — |
| Cambios en los sujetos obligados a emitir la GRE remitente | RS 000108-2026/SUNAT | Verificar alcance | Noviembre 2026 |
| Ticket de salida en traslados portuarios hasta 2026-10-31; GRE remitente obligatoria para esos traslados desde 2026-11-01 | RS 000124-2026/SUNAT | Verificado (fuente secundaria) | Noviembre 2026 |
| Se emite antes de iniciar el traslado, con motivo, punto de partida y de llegada, transporte (público o privado), peso y bienes | Reglamento de comprobantes de pago | Verificar campos obligatorios | — |
| Tipos: GRE remitente (código 09, serie que empieza con T) y GRE transportista (código 31, serie que empieza con V) | Catálogo 01 de SUNAT | Verificar | — |

**Relación con el inventario:** cada operación que mueve mercadería por la vía pública lleva una guía con
su motivo de traslado, y el motivo sale del tipo de movimiento
([inventario/motor.md › Movimientos](../inventario/motor.md#movimientos-de-una-ubicación-a-otra)):

| Operación del inventario | Motivo de traslado |
|---|---|
| Despacho de un pedido | Venta |
| Recojo en el proveedor con transporte propio | Compra |
| Transferencia entre almacenes de la misma empresa | Traslado entre establecimientos de la misma empresa |
| Devolución a proveedor | Devolución |
| Mercadería en consignación | Consignación |
| Importación o exportación | Importación / exportación |

Los códigos del catálogo de motivos se verifican en el catálogo vigente de SUNAT (en el esquema:
`dispatch_guide.transfer_reason` contra un `lookup_value` del tipo `TRANSFER_REASON`). La venta de
mostrador que el cliente se lleva no requiere guía del vendedor; verificar los casos en que sí.

## Inventario y libros

| Regla | Fuente | Estado |
|---|---|---|
| Métodos de valuación permitidos: PEPS; promedio diario, mensual o anual; identificación específica; inventario al detalle; existencias básicas. UEPS no está entre ellos | Art. 62 del TUO de la Ley del Impuesto a la Renta | Verificado (carta SUNAT 084-2012) |
| El método se aplica uniformemente y no se cambia sin autorización de SUNAT | Reglamento de la LIR, art. 35 inc. g | Verificado (misma fuente) |
| Ingresos brutos del año anterior > 1,500 UIT: registro de costos, registro de inventario permanente en unidades físicas y registro de inventario permanente valorizado (formato 13.1) | Reglamento de la LIR, art. 35 | Verificar vigencia del texto |
| Entre 500 y 1,500 UIT: registro de inventario permanente en unidades físicas (formato 12.1) | Igual | Verificar |
| Menos de 500 UIT: inventario físico al cierre del ejercicio | Igual | Verificar |
| Merma deducible con informe técnico de un profesional independiente; desmedro deducible con destrucción ante notario y aviso previo a SUNAT | Reglamento de la LIR, art. 21 inc. c | Verificar |

Con la UIT de 2026, 500 UIT son S/ 2,750,000 y 1,500 UIT son S/ 8,250,000 de ingresos brutos.

**Formato 13.1 (kardex valorizado):** por cada movimiento, fecha, tipo de documento (tabla 10), serie,
número, tipo de operación (tabla 12), entradas, salidas y saldo con cantidad, costo unitario y costo
total, además del establecimiento, el código y tipo de existencia, la unidad de medida y el método de
valuación. Estado: verificar la versión vigente de la estructura (RS 042-2018/SUNAT y modificatorias).

En el esquema, `v_kardex` ya tiene entradas, salidas y saldo con costo; para exportar el 13.1 faltan el
tipo de operación de la tabla 12 (sale del tipo de movimiento, igual que el motivo de traslado) y los
datos del documento de sustento (serie y número del comprobante o de la guía).

**Merma y desmedro en el sistema:** la merma conocida se registra como movimiento a la ubicación de
merma con motivo; para que sea deducible hace falta el informe técnico o el acta de destrucción, que se
adjuntan al documento del movimiento.

## Contabilidad

Plan Contable General Empresarial, cuentas de uso frecuente en inventario (verificar subcuentas con el
contador):

| Cuenta | Uso |
|---|---|
| 20 Mercaderías | Inventario valorizado |
| 28 Existencias por recibir | Mercadería en tránsito o recibida sin factura (cuenta puente) |
| 40 Tributos por pagar | IGV crédito fiscal de las compras |
| 42 Cuentas por pagar comerciales | Proveedores |
| 60 Compras | Compras del período |
| 61 Variación de existencias | Contrapartida del asiento de destino de compras |
| 69 Costo de ventas | Costo de lo vendido |
| 65 Otros gastos de gestión | Merma y desmedro (según el caso) |

La práctica peruana registra la compra en la 60 y la lleva a la 20 con asiento de destino contra la 61;
el costo de ventas se registra en la 69 contra la 20. Un sistema perpetuo genera esos asientos solos
desde cada capa de costo. Asientos genéricos:
[inventario/valorizacion.md › Asientos](../inventario/valorizacion.md#asientos-tipo).

## Importaciones

| Regla | Estado |
|---|---|
| Aranceles, flete, seguro y gastos de despacho forman parte del costo de la mercadería importada ([valorizacion.md › Costos de importación](../inventario/valorizacion.md#costos-de-importación-landed-costs)) | Verificar el tratamiento de cada concepto |
| El IGV y la percepción del IGV pagados en la importación son crédito o pago a cuenta, no costo | Verificar |
| Tipo de cambio para registrar la importación | Verificar la regla tributaria vigente |

## Fuentes

- [SUNAT – Nota de prensa 001-2025, guía de remisión electrónica](https://www.sunat.gob.pe/salaprensa/2025/enero/NotaPrensaN0012025.docx)
- [Edicom – Guía de remisión electrónica en Perú](https://edicomgroup.com/es/blog/guia-remision-electronica-gre-peru)
- [SUNAT – Carta 084-2012, métodos de valuación de existencias](https://www.sunat.gob.pe/legislacion/oficios/2012/informe-oficios/c084-2012.pdf)
- [SUNAT – Anexo de la RS 042-2018/SUNAT, formatos de inventario](https://www.sunat.gob.pe/legislacion/superin/2018/anexo-042-2018.pdf)
- [El Peruano – UIT 2026](https://elperuano.pe/noticia/285318-nueva-uit-2026-conoce-los-montos-que-afectan-sueldos-multas-y-beneficios-laborales)
