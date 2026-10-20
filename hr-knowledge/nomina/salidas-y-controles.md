# Salidas y controles

Lo que la nómina produce después de calcular (pago, asiento, declaraciones) y los controles que hacen
que el proceso sea auditable. La boleta tiene su propio archivo: [boleta.md](boleta.md).

Tablas: `payment_batch`, `payment`, `payroll_journal`, `payroll_journal_line`, `statutory_filing`,
`statutory_filing_run`, `approval_*`, `audit_log` en [schema/hr_schema.sql](../schema/hr_schema.sql).

### Pago

- Medios: transferencia bancaria (archivo por lote en el formato del banco), cheque, efectivo, tarjeta de nómina.
- Estados de `payment`: `pending → sent → paid`, o `failed` y `returned`.
- Se concilia el archivo enviado contra la respuesta del banco; los rechazos (cuenta cerrada, datos erróneos) se corrigen y se reenvían sin recalcular la nómina.

### Contabilidad

Asiento tipo de una corrida, agrupado por centro de costo:

```
Debe  Gasto sueldos y salarios                 (ingresos)
Debe  Gasto cargas sociales del empleador      (aportes empleador)
Debe  Gasto provisiones                        (vacaciones, gratificación)
  Haber  Remuneraciones por pagar              (neto)
  Haber  Retenciones por pagar                 (aportes trabajador, impuesto)
  Haber  Aportes por pagar                     (empleador)
  Haber  Provisiones                           (pasivo)
  Haber  Préstamos a empleados                 (cuotas descontadas)
```

El mapeo sale de la cuenta contable del concepto y del centro de costo; el asiento queda en `payroll_journal` y `payroll_journal_line`. La reversa genera el contra-asiento.

### Declaraciones

Planilla de seguridad social, retenciones tributarias mensuales, certificados anuales de ingresos y retenciones, reportes de plantilla a ministerios, aportes a fondos. Se generan desde los resultados persistidos, no recalculando.

### Controles internos

- **Segregación de funciones:** quien carga novedades no aprueba; quien aprueba no paga; quien paga no edita maestros de cuentas.
- **Maker-checker:** toda acción sensible (cambio salarial, alta de cuenta bancaria, aprobación) requiere dos personas. El flujo `approval_request` y `approval_step` lo soporta.
- **Conciliaciones:** suma de netos igual a suma de pagos; aportes calculados igual a planilla; nómina igual a mayor contable.
- **Validaciones pre-cálculo:** empleados sin cuenta, sin contrato vigente, sin afiliación, sin asistencia aprobada, con documentos vencidos.
- **Validaciones post-cálculo:** neto negativo, variación mayor al umbral, salario bajo mínimo, tope superado, concepto sin cuenta contable.
- **Auditoría:** quién, cuándo y qué cambió (`audit_log`), retención legal de boletas y registros por varios años, acceso por rol y enmascaramiento de datos sensibles.
