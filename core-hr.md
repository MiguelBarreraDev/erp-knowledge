# Core HR

Quién trabaja, dónde, bajo qué condiciones y desde cuándo. Todo lo que la nómina lee del colaborador
sale de aquí, así que los errores de diseño en este nivel aparecen después como errores de pago.

Ubicación en el mapa: nivel 2 de [mapa-hcm.md](mapa-hcm.md). Tablas: `person*`, `employee`,
`employment_contract`, `employee_assignment`, `position`, `termination` en
[schema/hr_schema.sql](schema/hr_schema.sql) (secciones 1 a 3).

## Arquitectura conceptual: cómo se conecta todo

El módulo funciona como una tubería de cinco capas, y cada tabla del esquema pertenece a una:

1. **Maestros:** `legal_entity`, `location`, `department`, `job`, `position`, `person`, `employee`. Definen quién es quién y dónde está.
2. **Hechos con vigencia:** `employee_assignment`, `employee_compensation`, `employment_contract`, `employee_schedule`, `employee_recurring_concept`, `employee_pay_group`, `employee_statutory_enrollment`. Definen qué era cierto en cada fecha.
3. **Insumos del periodo:** `attendance_*`, `overtime_request`, `leave_request`, `leave_ledger`, `loan_installment`, `payroll_input`. Definen qué pasó en el periodo.
4. **Motor:** `payroll_concept`, `statutory_*`, `pay_period`, `payroll_run`. Convierte lo anterior en cálculo.
5. **Salidas inmutables:** `payroll_result(_line)`, `payment`, `payslip`, asiento contable, declaraciones.

Principio rector: la nómina es una función pura sobre el estado a una fecha. Dados los hechos vigentes, los insumos y las reglas vigentes, el resultado debe ser reproducible. Todo el diseño (vigencias, snapshots, cierre de periodo) existe para garantizar eso.

## Colaboradores (Core HR)

### Por qué `person`, `employee`, `assignment` y `contract` son cuatro cosas

| Entidad | Representa | Cambia cuando… | Por qué separada |
|---|---|---|---|
| `person` | El ser humano | Cambia su nombre, estado civil, domicilio | Sobrevive a la relación laboral: recontratación, ex-empleado, candidato |
| `employee` | Una relación laboral con una entidad legal | Hay alta o baja | Una persona puede tener varias relaciones, secuenciales o simultáneas |
| `employee_assignment` | Dónde y cómo trabaja (puesto, área, jefe, sede, FTE) | Hay promoción, traslado, cambio de jefe | Es el historial organizacional |
| `employment_contract` | El instrumento jurídico (tipo, plazo, jornada, prueba) | Hay renovación o adenda | Un contrato puede cubrir varias asignaciones y al revés |

### Effective dating (datos con vigencia)

Convención del esquema: el intervalo es semiabierto `[valid_from, valid_to)`. `valid_to` es el primer día en que la fila ya no rige y `NULL` significa vigente. Así dos filas consecutivas comparten una fecha límite sin solaparse, y el `EXCLUDE USING gist` garantiza por motor que no haya dos filas vigentes a la vez.

Hay que distinguir dos operaciones que se confunden:

- **Cambio (update con efectividad):** el hecho cambió en una fecha. Se cierra la fila vigente (`valid_to = fecha efectiva`) y se inserta una nueva. Ejemplo: aumento desde el 1 de octubre.
- **Corrección:** el dato estaba mal desde el origen. Se modifica el registro histórico con auditoría y no se crea versión nueva, pero puede disparar un retroactivo de nómina.

Consultas características:
- Estado "as of" una fecha: `valid_from <= d AND (valid_to IS NULL OR valid_to > d)`.
- Estado "as at" una fecha de registro (bitemporal): qué creía el sistema el día X. El esquema de referencia guarda vigencia pero no fecha de registro por versión; para auditoría fina se apoya en `audit_log`. La bitemporalidad completa está en [mapa-hcm.md › Por profundizar](mapa-hcm.md#6-por-profundizar).

Dato que une todo: los cambios con fecha efectiva anterior al periodo cerrado son el origen de casi todos los retroactivos.

### Ciclo de vida del colaborador

Estados de `employee.status`: `pre_hire → active → on_leave → suspended → terminated`. Un estado se mueve por eventos de personal (personnel actions):

| Evento | Efecto en datos | Efecto en nómina |
|---|---|---|
| Alta (hire) | `employee`, primera `assignment`, `compensation`, `contract` | Entra en la población; prorrateo del primer periodo |
| Alta anticipada (pre-hire) | Registro previo al inicio | No se paga hasta `hire_date` |
| Transferencia / promoción | Nueva `assignment` | Puede cambiar centro de costo, grado, bases |
| Cambio salarial | Nueva `compensation` | Segmentación intraperiodo; retroactivo si es anterior |
| Licencia (`on_leave`) | `leave_request` aprobada | Prorrateo, subsidio o suspensión del pago |
| Suspensión disciplinaria | `disciplinary_case` con días | Descuento de días no pagados |
| Baja (termination) | `termination`, cierre de vigencias | Liquidación final, retención regularizada |
| Recontratación (rehire) | Nuevo `employee` sobre el mismo `person`, `original_hire_date` | Antigüedad reconocida según política |

### Puesto, plaza y posición (position management)

- `job` es el cargo genérico del catálogo (Analista de finanzas).
- `position` es una plaza concreta con `headcount`, departamento, ubicación y a quién reporta.
- `employee_assignment` ocupa una plaza y define el FTE (0.5 = medio tiempo).

Esto permite planificar plantilla (plazas aprobadas vs ocupadas), detectar vacantes que alimentan `job_requisition` y controlar presupuesto de personal. Estados de plaza: `planned, open, filled, frozen, closed`. Una plaza `frozen` existe en presupuesto pero no se puede cubrir.

### Contratos: reglas y variaciones

- **Tipos:** indefinido, plazo fijo, por obra o servicio, temporal, aprendizaje o prácticas, tiempo parcial. Cada país restringe cuándo usar cada uno.
- **Periodo de prueba:** `probation_end_date`; durante la prueba suelen cambiar las reglas de desvinculación.
- **Renovaciones sucesivas:** `renewed_from_id` encadena contratos; muchas legislaciones limitan el número o la duración total y convierten el contrato en indefinido al superarla. El sistema debería alertar antes.
- **Adendas:** cambios de jornada o condiciones sin nuevo contrato; se versionan como `contract` nuevo o documento adjunto.
- **Jornada:** `weekly_hours` (y no solo FTE) determina el divisor de hora extra y la proporcionalidad.

### Excepciones típicas en maestros

- Dos personas con el mismo documento por error de digitación: el índice único `(doc_type_id, number)` lo evita; el flujo de fusión de duplicados debe existir.
- Una persona con dos empleos en dos entidades legales del mismo grupo: topes de seguridad social por persona, no por empleador, en algunos regímenes.
- Extranjeros: permiso de trabajo con vencimiento, régimen distinto de seguridad social, tributación como no residente en el primer año.
- Menores de edad: restricciones de jornada y horas extra.
- Teletrabajo transfronterizo: define qué ley aplica (la del lugar de trabajo efectivo).
- Fallecimiento: baja con beneficiarios (`person_relative.is_beneficiary`) y pago de lo adeudado a herederos.