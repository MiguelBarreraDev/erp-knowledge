# Esquema de referencia

`hr_schema.sql`: esquema PostgreSQL 14+ de un HCM completo, en el schema `hr`, pensado para un ERP
multitenant con una base de datos por tenant. 112 tablas. Es el modelo contra el que se comparan los
diseños concretos: un producto puede implementar un subconjunto, pero con la misma forma
([patrones.md › 10](../patrones.md#10-el-mínimo-viable-es-un-subconjunto-del-modelo-completo)).

## Secciones

| Sección | Contenido |
|---|---|
| 0 | Catálogos genéricos (`lookup_*`) |
| 1 | Estructura organizacional |
| 2 | Persona y empleado |
| 3 | Relación laboral con vigencia (contrato, asignación, compensación) |
| 4 | Tiempo y asistencia |
| 5 | Ausencias y vacaciones |
| 6 | Nómina: 6.1 paquete legal · 6.2 conceptos y bases · 6.3 calendario y períodos · 6.4 políticas · 6.5 datos de nómina del empleado · 6.6 corridas · 6.7 novedades · 6.8 resultados · 6.9 salidas |
| 7 a 12 | Beneficios, reclutamiento, onboarding, desempeño, capacitación, disciplina y SST |
| 13 | Aprobaciones genéricas |
| 14 | Auditoría |
| 16 | Lógica de períodos: máquina de estados, bloqueos, detección de retroactivos, generador de períodos, vistas |

Las tablas de nómina llevan `[MVP]` o `[F2]` en su comentario: con las `[MVP]` alcanza para una primera
nómina mensual real; las `[F2]` se agregan sin romper el diseño.

## Cargarlo y probarlo

```bash
createdb hr_ref
psql -v ON_ERROR_STOP=1 -d hr_ref -f hr_schema.sql
psql -d hr_ref -f pruebas/smoke.sql   # ciclo de un período y bloqueo de corrida con novedades abiertas
psql -d hr_ref -f pruebas/peru.sql    # parámetros legales con vigencia (RMV) y bloqueo de tasas superpuestas
psql -d hr_ref -f pruebas/cross.sql   # calendario mensual del 16 al 15 y fechas de pago en día hábil
```

Resultado esperado (verificado el 2026-10-14 en PostgreSQL 16):
- `smoke.sql`: genera 4 períodos, cierra setiembre, rechaza una corrida con `RUN_INPUTS_OPEN`, detecta
  el retroactivo desde el 2026-09-01.
- `peru.sql`: asignación familiar 113.00 en setiembre y 123.00 en octubre; «solape de tasa bloqueado».
- `cross.sql`: 12 períodos del 16/12/2025–15/01/2026 al 16/11–15/12/2026.

Las pruebas usan datos ficticios y se pueden correr una vez por base limpia.

## Qué tablas lee y escribe cada proceso

| Proceso | Lee | Escribe |
|---|---|---|
| Alta de colaborador | `person`, `position` | `employee`, `assignment`, `compensation`, `contract`, `employee_checklist` |
| Cambio salarial | `employee_compensation` | Nueva fila de `employee_compensation`, `approval_*`, `audit_log` |
| Consolidar asistencia | `attendance_punch`, `employee_schedule`, `shift` | `attendance_daily` |
| Aprobar horas extra | `attendance_daily`, `overtime_request` | `overtime_request`, `payroll_input` |
| Solicitar vacaciones | `leave_ledger`, `leave_policy`, `holiday` | `leave_request`, `approval_*`, `leave_ledger` |
| Cargar novedades | `payroll_concept`, `employee` | `payroll_input` |
| Calcular nómina | Todo lo anterior más `statutory_*`, `loan_installment` | `payroll_run`, `payroll_result`, `payroll_result_line` |
| Aprobar y pagar | `payroll_result`, `person_bank_account` | `payment`, `payroll_run.status` |
| Publicar boleta | `payroll_result` | `payslip`, `document` |
| Liquidar | `termination`, `leave_ledger`, `loan`, `asset_assignment` | `payroll_run` de tipo `final_settlement`, `termination` |
| Cerrar periodo | Todo | `pay_period.status = closed` |

## Lo que el esquema todavía no tiene

| Falta | Para qué | Propuesta |
|---|---|---|
| Número y estado de emisión de la boleta | Boleta numerada, anulada o rectificada | `payslip.number` único y `payslip.status` |
| Cambios pendientes de aprobación | Un aumento o una cuenta nueva esperan aprobación sin que el motor los lea | `hr_change_request`; se aplica al aprobar |
| Definición de flujos de aprobación | Quién aprueba qué | `approval_workflow`, `approval_workflow_step` |
| Reparto de costo | Un empleado imputado a varios centros de costo | `employee_cost_allocation` con porcentajes y vigencia |
| Eventos de personal | Trazabilidad explícita de altas, cambios y bajas | `personnel_action` con tipo, fecha efectiva y motivo |
| Bitemporalidad | Qué creyó el sistema en cada fecha | `recorded_from`, `recorded_to` en tablas con vigencia |
| Ciclos de compensación | Revisiones salariales por lote | `comp_cycle`, `comp_budget`, `comp_proposal` |
| Carrera y sucesión | Talento clave y sucesores | `succession_plan`, `successor`, `talent_review` |
| Elegibilidad masiva de conceptos | «Movilidad para todos los obreros» sin asignar uno por uno | Reglas de elegibilidad por grupo |
