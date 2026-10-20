# Boleta de pago

La boleta es un documento, no una vista de la nómina: se emite, se congela, se entrega y, si hace falta
corregirla, se rectifica con otra. Su contenido legal mínimo depende del país
([localizacion/peru.md](../localizacion/peru.md#boleta-de-pago)).

Tablas: `payslip`, `document`, `document_template`, y de dónde salen los datos: `payroll_result`,
`payroll_result_line` en [schema/hr_schema.sql](../schema/hr_schema.sql).

## Qué debe cumplir

- **Contenido mínimo legal** del país: empleador, trabajador, período y jornada, montos, firma.
- **Cada concepto muestra cómo se calculó:** base, tasa o cantidad, e importe. Lo que no cabe en una
  fila (un impuesto con proyección, un parámetro que cambió) va como nota de cálculo.
- **Ingresos, descuentos y aportes del empleador separados.** Los aportes del empleador se informan,
  pero no restan del neto.
- **Firma del empleador y código de verificación** (hash y QR) para probar autenticidad.
- **Entrega con plazo y constancia:** cuándo se publicó, cuándo la vio el trabajador, cuándo confirmó
  recepción.
- **Idéntica en todos los canales**, porque sale de los mismos resultados guardados.

## Ciclo de vida

| Evento | Qué pasa con la boleta |
|---|---|
| Corrida aprobada | Se emite: número correlativo, contenido congelado (snapshot), hash |
| Aprobación revertida | Se anula con el motivo; el número no se reusa |
| Pago confirmado | Se publica al trabajador; empieza a correr el plazo de entrega |
| Error descubierto después del pago | Se emite una rectificación que referencia a la original; la original queda visible y marcada |

Reglas:
- Nunca se recalcula al mostrarla. Si cambian el sueldo, el cargo o la cuenta del trabajador, la boleta
  ya emitida no cambia: por eso guarda una foto de los datos del trabajador al momento del pago
  (`payroll_result.employee_snapshot`).
- La explicación de cada línea se guarda al calcular (`payroll_result_line.explanation`), no se
  reconstruye al imprimir.

## Según dónde se muestra

| Canal | Objetivo | Qué debe tener |
|---|---|---|
| PDF | Documento formal | Todo el contenido mínimo, columnas base / tasa / importe, notas de cálculo, neto en letras, firma, QR y hash, paginación con cabecera repetida, legible en blanco y negro |
| Web | Entender y verificar | Neto primero, secciones separadas, «ver cálculo» en cada línea, comparación con el mes anterior, historial, descarga, botón para consultar una línea a RRHH |
| Móvil | Consulta rápida | Neto en tarjeta, secciones plegables, descarga, confirmación de recepción |
| Correo | Aviso | Sin montos en el cuerpo; enlace al portal con login o PDF protegido |
| Impresión | Archivo físico | Igual al PDF; el significado no depende del color |

## De dónde sale cada parte

| Elemento | Columna en el esquema |
|---|---|
| Datos del trabajador al pagar (cargo, régimen, afiliación) | `payroll_result.employee_snapshot` |
| Base, tasa e importe | `payroll_result_line.base_amount`, `rate`, `amount` |
| Notas de cálculo | `payroll_result_line.explanation` y la versión del concepto usada |
| Sección y orden | sección de boleta y orden del concepto |
| Aportes del empleador | Líneas de fase de aporte del empleador |
| Formato por empresa e idioma, versionado | `document_template`, `payslip.template_id` |
| PDF e integridad | `payslip.document_id`, con hash en `document` |
| Firma del empleador | `employer_signed_at`, `signature_ref` |
| Verificación | `verification_code` |
| Plazo y constancias | `delivery_due_date`, `published_at`, `viewed_at`, `acknowledged_at` |
| Rectificación | `supersedes_id`: la nueva boleta apunta a la que reemplaza |
| Número y estado de emisión (emitida, anulada, publicada, rectificada) | **No está en el esquema de referencia.** Agregar `number` único y `status` a `payslip` |

Lo que queda del lado de la aplicación: renderizar el PDF desde la plantilla, firmar con el proveedor
de firma, notificar, calcular el plazo con el calendario de feriados y la página pública de
verificación del código.
