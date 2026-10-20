# Mapa de un HCM

Los submódulos de un sistema de RRHH (HCM), en orden de dependencia, con su contenido, sus menús y su
equivalente en el mercado. Es la puerta de entrada al resto de esta base.

- **Regla de lectura:** los submódulos dependen unos de otros. No se calcula nómina sin tiempo y
  ausencias, no hay tiempo sin colaboradores y no hay colaboradores sin estructura organizacional.
  Se estudia y se construye en ese orden.
- **Modelo de datos:** las tablas citadas están en [schema/hr_schema.sql](schema/hr_schema.sql).
- **Profundidad:** cada nivel enlaza a su archivo cuando existe; nómina tiene su carpeta.

## Índice

1. [Mapa en capas (orden de dependencia)](#1-mapa-en-capas-orden-de-dependencia)
2. [Cada submódulo en detalle](#2-cada-submódulo-en-detalle)
3. [Cómo se traduce a menús](#3-cómo-se-traduce-a-menús)
4. [Equivalencias con el mercado](#4-equivalencias-con-el-mercado)
5. [Orden de estudio y de construcción](#5-orden-de-estudio-y-de-construcción)
6. [Por profundizar](#6-por-profundizar)

---

## 1. Mapa en capas (orden de dependencia)

| Nivel | Submódulo | Pregunta que responde | Depende de |
|---|---|---|---|
| 0 | Plataforma | ¿Quién puede hacer qué y cómo se registra? | — |
| 1 | Estructura organizacional | ¿Cómo está organizada la empresa? | 0 |
| 2 | Core HR (Colaboradores) | ¿Quién trabaja aquí, dónde y bajo qué condiciones? | 1 |
| 3 | Tiempo y asistencia | ¿Cuánto y cuándo trabajó? | 2 |
| 4 | Ausencias | ¿Cuándo no trabajó y por qué? | 2, 3 |
| 5 | Compensación | ¿Cuánto se le paga y cómo evoluciona? | 2 |
| 6 | **Nómina** | ¿Cuánto se le paga este periodo, neto, y a quién más se paga? | 2, 3, 4, 5 |
| 7 | Beneficios | ¿Qué recibe además del sueldo? | 2, 6 |
| 8 | Talento | ¿Cómo se atrae, incorpora, evalúa y desarrolla? | 1, 2 |
| 9 | Relaciones laborales y SST | ¿Qué incidentes, sanciones y riesgos hay? | 2 |
| 10 | Analítica y planificación | ¿Qué está pasando y qué necesitaremos? | Todo |
| Transversal | Autoservicio (empleado y jefe) | ¿Cómo interactúa cada persona con lo anterior? | Todo |

> El autoservicio no es un submódulo: es un **canal**. Cada submódulo expone una parte de sí mismo al empleado y al jefe.

---

## 2. Cada submódulo en detalle

### Nivel 0. Plataforma

- **Contenido:** tenant y aprovisionamiento de BD, usuarios, roles y permisos (por función, por campo y por alcance organizacional), motor de aprobaciones, documentos, notificaciones, auditoría, importación y exportación, integraciones, idioma, moneda y zona horaria.
- **Tablas:** `approval_request`, `approval_step`, `document`, `audit_log`, `lookup_type`, `lookup_value`.
- **Por qué primero:** sin permisos por alcance y sin auditoría no se puede vender nómina a una empresa seria.

### Nivel 1. Estructura organizacional

- **Conceptos:** entidad legal (empleador ante el Estado), sede o establecimiento, departamento (jerarquía), centro de costo (jerarquía contable, distinta de la de departamentos), familia de puestos, grado o banda salarial, cargo, plaza.
- **Gestión por plaza vs por cargo:** por plaza, cada persona ocupa una plaza presupuestada (típico de SAP y Workday); por cargo, es más simple (típico de Odoo). El esquema soporta ambas porque `position_id` es opcional en la asignación.
- **Naturaleza:** todo este nivel es configuración; lo define el admin una vez y lo mantiene.
- **Tablas:** `legal_entity`, `location`, `department`, `cost_center`, `job_family`, `job_grade`, `job`, `position`.

### Nivel 2. Core HR (administración de personal)

- **Conceptos:** persona, relación laboral, asignación, contrato, eventos de personal (alta, cambio, baja, recontratación), datos con vigencia, expediente digital, dependientes y beneficiarios, datos bancarios.
- **Procesos:** alta, cambio de puesto o jefe, traslado, cambio de jornada, renovación de contrato, baja, recontratación, actualización de datos por autoservicio.
- **Configuración:** catálogos (tipos de documento, tipos de contrato, motivos de cambio y baja), campos obligatorios por país, numeración del código de empleado, plantillas de contrato.
- **Tablas:** `person`, `person_identification`, `person_address`, `person_relative`, `person_bank_account`, `person_skill`, `person_education`, `person_certification`, `person_work_experience`, `employee`, `employment_contract`, `employee_assignment`, `termination`, `document`.

### Nivel 3. Tiempo y asistencia

- **Conceptos:** calendario laboral, feriados, turno, horario y rotación, marcación, jornada consolidada, tardanza, hora extra, recargo nocturno, banco de horas, hoja de tiempos por proyecto.
- **Procesos:** asignar horario → recibir marcaciones → regularizar → consolidar el día → aprobar horas extra → cerrar asistencia del periodo → enviar a nómina.
- **Configuración:** turnos, horarios, tolerancias, redondeos, reglas de clasificación de horas, topes legales, dispositivos.
- **Tablas:** `holiday_calendar`, `holiday`, `shift`, `work_schedule`, `work_schedule_day`, `employee_schedule`, `attendance_punch`, `attendance_daily`, `overtime_request`, `timesheet_entry`.

### Nivel 4. Ausencias

- **Conceptos:** tipo de ausencia, política, devengo, saldo, traspaso, vencimiento, solicitud, subsidio.
- **Procesos:** solicitar, aprobar, gozar, cancelar, ajustar saldo, devengar (proceso automático mensual), vencer saldos, pagar vacaciones.
- **Configuración:** tipos, políticas por grupo de empleados, reglas por antigüedad, días hábiles o calendario, documentos requeridos.
- **Tablas:** `leave_type`, `leave_policy`, `employee_leave_policy`, `leave_request`, `leave_ledger`.

### Nivel 5. Compensación

**Compensación no es nómina:**

- **Compensación** define qué *debería* ganar la persona: estructura salarial, bandas, sueldo base con vigencia, bonos pactados y ciclos anuales de aumento (presupuesto → propuesta del jefe → calibración → aprobación).
- **Nómina** toma eso y calcula qué se paga *este periodo*.

- **Tablas:** `job_grade` (bandas), `employee_compensation`, `employee_recurring_concept`.
- **Brecha:** no hay tablas para ciclos de revisión salarial (presupuesto por área, propuestas, aprobación por lote). Diferenciador de Workday y SAP; no necesario en el MVP.

### Nivel 6. Nómina

Detalle en [nomina/](nomina/motor.md): motor, períodos, boleta, salidas y casos borde.

Es el submódulo más profundo y se divide en sus propios subsubmódulos:

| # | Subsubmódulo | Contenido | Tablas principales |
|---|---|---|---|
| 6.1 | Estructura de nómina | Grupos de pago, calendarios, periodos, cortes, fechas de pago | `pay_calendar`, `pay_group`, `employee_pay_group`, `pay_period`, `pay_period_window` |
| 6.2 | Conceptos y reglas | Conceptos, métodos de cálculo, fórmulas, bases, orden de evaluación, cuentas contables | `payroll_concept`, `payroll_concept_version`, `payroll_balance`, `payroll_balance_feed` |
| 6.3 | Localización legal | Esquemas de seguridad social e impuesto, tasas, tramos, topes, conceptos legales, versionados por fecha | `legal_pack`, `legal_parameter`, `statutory_scheme`, `statutory_provider`, `statutory_rate` |
| 6.4 | Datos de nómina del empleado | Afiliaciones, perfil tributario, cuenta bancaria, recurrentes, préstamos, embargos | `employee_statutory_enrollment`, `employee_tax_profile`, `person_bank_account`, `employee_payment_method`, `employee_recurring_concept`, `loan`, `loan_installment`, `garnishment_order` |
| 6.5 | Novedades | Insumos del periodo: de asistencia, ausencias, manuales e importados | `payroll_input` |
| 6.6 | Procesamiento | Corridas regulares, fuera de ciclo, retroactivos, liquidaciones, simulación, reversas | `payroll_run`, `payroll_run_employee`, `payroll_result`, `payroll_result_segment`, `payroll_result_line`, `payroll_retro_trigger` |
| 6.7 | Revisión y control | Validaciones, comparación con el periodo anterior, aprobación, segregación de funciones | `approval_*`, `audit_log` |
| 6.8 | Pagos | Archivo bancario, conciliación, rechazos | `payment_batch`, `payment` |
| 6.9 | Contabilización | Asiento por centro de costo, provisiones | `payroll_journal`, `payroll_journal_line` |
| 6.10 | Declaraciones y certificados | Planillas a entes, retenciones, certificados anuales | `statutory_filing`, `statutory_filing_run` |
| 6.11 | Boletas | Generación, publicación, PDF, autoservicio | `payslip`, `document`, `document_template` |
| 6.12 | Acumulados y saldos | Acumulados anuales, bases promedio, saldos de préstamos | `payroll_balance_value`, `payroll_arrear` |

**Orden recomendado de construcción de nómina:**

```
6.1 → 6.2 → 6.3 → 6.4 → 6.5 → 6.6 (solo regular) → 6.7 → 6.11 → 6.8 → 6.9 → 6.12
    → 6.6 (retroactivos y liquidaciones) → 6.10
```

### Nivel 7. Beneficios

- **Contenido:** planes (salud, seguro de vida, alimentación, transporte, educación), elegibilidad, inscripción, dependientes cubiertos, aportes de empresa y empleado, eventos de vida (matrimonio, nacimiento) que abren ventanas de cambio.
- **Conexión con nómina:** por el concepto de descuento o de beneficio en especie.
- **Tablas:** `benefit_plan`, `benefit_enrollment`, `benefit_enrollment_dependent`.

### Nivel 8. Talento

| Submódulo | Contenido | Tablas |
|---|---|---|
| Reclutamiento | Requisición, aviso, candidato, postulación, etapas, entrevistas, oferta, contratación | `job_requisition`, `candidate`, `job_application`, `interview`, `job_offer` |
| Onboarding y offboarding | Plantillas de tareas por responsable, activos, accesos | `checklist_template`, `checklist_template_task`, `employee_checklist`, `employee_checklist_task`, `asset_assignment` |
| Desempeño | Ciclos, objetivos, competencias, evaluaciones (auto, jefe, 360), calibración | `review_cycle`, `goal`, `competency`, `performance_review`, `performance_review_rating` |
| Aprendizaje | Cursos, sesiones, inscripciones, certificaciones con vencimiento | `course`, `course_session`, `training_enrollment` |
| Carrera y sucesión | Planes de carrera, sucesores, talento clave, matriz de potencial | No existe en el esquema; diferenciador de suites grandes |

### Nivel 9. Relaciones laborales y SST

- **Contenido:** disciplina y sanciones, quejas y denuncias, casos de RRHH, accidentes e incidentes, exámenes médicos ocupacionales, comités.
- **Tablas:** `disciplinary_case`, `hr_case`, `occupational_incident`, `medical_exam`.

### Nivel 10. Analítica y planificación

- **Contenido:** plantilla, rotación, ausentismo, horas extra, costo de personal, brecha salarial, tiempo de cobertura de vacantes, planificación de plantilla y presupuesto.
- **Datos:** se construye sobre vistas y reportes (`v_employee_current`, `v_leave_balance` y otras); no requiere tablas nuevas hasta que haya planificación con escenarios.

---

## 3. Cómo se traduce a menús

### Patrón de cuatro grupos por submódulo

Cada submódulo tiene los mismos cuatro grupos de menú (Odoo lo hace muy explícito):

| Grupo | Contenido | Usuario |
|---|---|---|
| Operación | Día a día: listas, solicitudes, registros | Analista, operador |
| Procesos | Acciones por lote: calcular, devengar, cerrar, importar | Operador, supervisor |
| Reportes | Consultas y exportaciones | Todos según permiso |
| Configuración | Catálogos, reglas, políticas, plantillas | Admin |

### Menú principal del back-office

```
Inicio

Colaboradores
  Operación:  Directorio · Fichas · Eventos de personal · Contratos · Documentos
  Procesos:   Altas masivas · Cambios masivos · Vencimientos de contrato
  Reportes:   Plantilla · Rotación · Antigüedad
  Config.:    Catálogos · Campos por país · Plantillas de contrato

Organización
  Operación:  Organigrama · Departamentos · Plazas · Cargos
  Config.:    Entidades legales · Sedes · Centros de costo · Grados

Tiempo
  Operación:  Marcaciones · Jornadas · Horas extra · Hojas de tiempo
  Procesos:   Consolidar · Cerrar asistencia
  Config.:    Turnos · Horarios · Calendarios · Reglas · Dispositivos

Ausencias
  Operación:  Solicitudes · Saldos · Calendario
  Procesos:   Devengo · Vencimiento · Traspaso
  Config.:    Tipos · Políticas

Compensación
  Operación:  Sueldos vigentes · Historial
  Procesos:   Ciclo de aumentos
  Config.:    Bandas salariales

Nómina
  Operación:  Periodos · Novedades · Préstamos · Embargos
  Procesos:   Corridas · Retroactivos · Liquidaciones · Pagos · Contabilización · Cierre
  Reportes:   Resumen · Costo empresa · Declaraciones · Boletas
  Config.:    Grupos de pago · Calendarios · Conceptos · Bases · Paquete legal · Plantilla de boleta

Beneficios
  Operación:  Inscripciones
  Config.:    Planes

Talento
  Reclutamiento · Onboarding · Desempeño · Aprendizaje

Relaciones y SST
  Casos · Disciplina · Incidentes · Exámenes

Reportes
  Tableros transversales

Configuración global
  Roles y permisos · Aprobaciones · Notificaciones · Integraciones · Auditoría
```

### Portales de autoservicio

El empleado y el jefe no ven el menú del back-office; ven su propio portal, que es una proyección filtrada de los mismos datos.

| Portal empleado | Portal jefe |
|---|---|
| Inicio | Mi equipo |
| Mi perfil | Aprobaciones |
| Mis boletas | Calendario del equipo |
| Vacaciones | Asistencia del equipo |
| Asistencia | Evaluaciones |
| Documentos | Requisiciones |
| Solicitudes | Reportes del equipo |

---

## 4. Equivalencias con el mercado

| Submódulo propio | SAP | Workday | Odoo |
|---|---|---|---|
| Estructura organizacional | Organizational Management | Organizations, Supervisory Orgs | Departamentos dentro de Employees |
| Core HR | Personnel Administration, Employee Central | Core HCM | Employees |
| Tiempo | Time Management | Time Tracking | Attendances, Planning |
| Ausencias | Time Management (ausencias) | Absence Management | Time Off |
| Compensación | Compensation Management | Compensation, Advanced Compensation | Contratos dentro de Payroll |
| Nómina | Payroll (Employee Central Payroll) | Payroll (por país) | Payroll con localizaciones |
| Beneficios | Benefits | Benefits | No nativo |
| Reclutamiento | Recruiting | Recruiting | Recruitment, Referrals |
| Desempeño | Performance and Goals | Talent and Performance | Appraisals |
| Aprendizaje | Learning | Learning | eLearning |
| Concepto de nómina | Wage type | Earning y Deduction | Salary rule |

### Lectura competitiva

- **SAP y Workday:** ganan en profundidad, configurabilidad y empresas grandes, a cambio de implementaciones largas y caras.
- **Odoo:** gana en simplicidad y precio, a cambio de profundidad en nómina y localización.
- **Espacio para competir (en el medio):**
  - Localización legal sólida por país.
  - Nómina explicable: cada monto con su cálculo visible.
  - Implementación rápida con asistentes.
  - Buena experiencia móvil para empleados y jefes.

> Las equivalencias son de nomenclatura general y pueden variar por versión y edición de cada producto.

---

## 5. Orden de estudio y de construcción

| # | Etapa | Niveles |
|---|---|---|
| 1 | Plataforma: permisos, auditoría, aprobaciones | 0 |
| 2 | Estructura organizacional | 1 |
| 3 | Core HR con datos de vigencia y eventos de personal | 2 |
| 4 | Tiempo y ausencias (en paralelo; ambos alimentan nómina) | 3, 4 |
| 5 | Compensación básica: sueldo con vigencia y recurrentes | 5 |
| 6 | Nómina, en el orden de la sección 6 | 6 |
| 7 | Autoservicio de boletas y vacaciones | Transversal |
| 8 | Beneficios, onboarding y offboarding | 7, 8 |
| 9 | Reclutamiento, desempeño, aprendizaje | 8 |
| 10 | Relaciones laborales, SST, analítica | 9, 10 |

### Fases de producto sugeridas

| Fase | Alcance |
|---|---|
| MVP | Colaboradores (lista y ficha), organización básica, boletas del empleado, vacaciones con aprobación, asistencia consolidada, nómina regular con revisión, pagos y boleta PDF, conceptos y grupos de pago, roles |
| Fase 2 | Reclutamiento, onboarding y offboarding, liquidación final, retroactivos, importadores, contabilidad, declaraciones, evaluaciones |
| Fase 3 | Simulador, simulación de costos, analítica avanzada, flujos configurables por el cliente, documentos con firma electrónica, integraciones biométricas |

---

## 6. Por profundizar

Temas que esta base todavía no cubre a fondo. Cuando se estudien, se escriben en su archivo y se
quitan de aquí.

- Diagrama entidad-relación de tiempo, ausencias y nómina.
- Ciclos anuales de compensación (presupuesto, propuestas, calibración).
- Carrera y sucesión.
- Bitemporalidad: qué creyó el sistema en cada fecha.
- Integración bancaria directa frente a archivos de pago.
- Localizaciones distintas de Perú.
