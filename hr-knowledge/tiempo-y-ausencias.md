# Tiempo y ausencias

Lo que pasó en el período: cuánto trabajó cada persona y cuándo no trabajó. Ambos módulos alimentan la
nómina como novedades (`payroll_input`) y por eso se diseñan pensando en el corte de la planilla.

Ubicación en el mapa: niveles 3 y 4 de [mapa-hcm.md](mapa-hcm.md). Tablas en
[schema/hr_schema.sql](schema/hr_schema.sql), secciones 4 y 5. Qué rango de asistencia entra en cada
pago: [nomina/periodos.md › Ventana de insumos](nomina/periodos.md#la-ventana-de-insumos).

## Insumos de tiempo y asistencia

### Pipeline de asistencia

```
attendance_punch (crudo)  →  regularización  →  attendance_daily  →  clasificación de horas
        →  aprobación  →  payroll_input (concepto + cantidad)
```

1. **Marcaciones crudas:** biométrico, móvil con geocerca, web. Nunca se editan; se agregan correcciones (`is_adjusted`).
2. **Regularización:** marcaciones faltantes, duplicadas, fuera de geocerca, olvidos justificados.
3. **Consolidación diaria:** compara contra el turno programado y calcula minutos programados, trabajados, tardanza, salida anticipada, extra y nocturnos. Aplica reglas de tolerancia (por ejemplo 5 minutos) y redondeo (al cuarto de hora, hacia abajo, al más cercano).
4. **Clasificación:** horas normales, extra al 25%, al 35%, al 100%, nocturnas, en feriado, en día de descanso. Cada categoría es un `payroll_concept` distinto con su factor.
5. **Aprobación** por jefe o RRHH antes del corte.
6. **Entrega a nómina** como `payroll_input` con `source = 'attendance'`.

### Detalles que importan

- `work_date` es la fecha local del turno, no la del timestamp UTC. Un turno nocturno de 22:00 a 06:00 pertenece al día en que empieza.
- `shift.crosses_midnight` y las horas nocturnas se reparten entre dos días calendario.
- Jornadas especiales: acumulativa (por ejemplo 14×7), comprimida, rotativa; `work_schedule_day` con `week_no` modela rotaciones.
- Banco de horas o compensación en tiempo (`overtime_request.compensation = 'time_off'`): las horas no se pagan, alimentan un saldo de descanso compensatorio.
- Topes legales de horas extra por día, semana y mes: el sistema valida y bloquea o alerta.
- Corte (`cutoff`): lo aprobado después del corte no entra al periodo; pasa al siguiente o se paga fuera de ciclo.

### Excepciones

Marcaciones offline sincronizadas tarde, empleado que olvida marcar, trabajo remoto sin marcación (régimen por tareas), cambios por horario de verano, feriados decretados con poco aviso, turno que cruza el cierre del periodo (se divide en dos días), personal de confianza o dirección exento de control de jornada.

## Ausencias y vacaciones

### El libro mayor de saldos (`leave_ledger`)

El saldo nunca se guarda: se deriva con `SUM(quantity)`. Tipos de asiento:

| `entry_type` | Signo | Cuándo |
|---|---|---|
| `opening` | + | Saldo inicial por migración |
| `accrual` | + | Devengo periódico (ejemplo: 30 días al año son 2.5 al mes) |
| `usage` | − | Solicitud aprobada o gozada |
| `adjustment` | ± | Corrección manual con motivo |
| `carryover` | ± | Traspaso al año siguiente con tope |
| `expiry` | − | Vence lo que excede el tope o plazo |
| `payout` | − | Vacaciones pagadas en dinero (venta o liquidación) |

Ventaja del ledger: auditoría completa, reconstrucción del saldo a cualquier fecha y fácil de recalcular si cambia la política.

### Parámetros de política (`leave_policy`)

- Método de devengo: anual, mensual, por horas trabajadas, por antigüedad (tabla escalonada en `seniority_rules`).
- Periodo de espera (`waiting_period_days`): no se puede usar antes de cierto tiempo.
- Tope de traspaso (`carryover_max`) y vencimiento.
- Saldo negativo permitido (adelanto de vacaciones).
- Unidad: días o horas. Días calendario o hábiles (`count_calendar_days`): si cuentan calendario, un feriado dentro del rango consume saldo; si cuentan hábiles, no.

### Tipos de ausencia y su efecto en nómina

| Tipo | Pago | Quién paga | Efecto en nómina |
|---|---|---|---|
| Vacaciones | Normal | Empleador | Se paga el básico; a veces con promedio de variables |
| Licencia pagada (duelo, matrimonio) | Normal | Empleador | Sin descuento |
| Enfermedad con subsidio | Parcial o total | Empleador los primeros días, luego un ente | Se descuentan días y se registra el subsidio como ingreso informativo o con reembolso |
| Maternidad o paternidad | Subsidio | Ente de seguridad social | Se suspende el pago de sueldo y se informa subsidio |
| Licencia sin goce | No | — | Descuento por días; afecta antigüedad y devengo de vacaciones según ley |
| Falta injustificada | No | — | Descuento de días y a veces del día de descanso |
| Suspensión disciplinaria | No | — | Descuento por los días de sanción |

Las reglas finas: si la ausencia cuenta como tiempo de servicio, si genera devengo de vacaciones, si interrumpe aportes y cómo se calcula la base de cotización durante ella.

### Valorización de vacaciones

Se paga el valor del día del sueldo vigente al gozarlas. Algunos regímenes usan el promedio de los últimos meses para incluir variables (comisiones, horas extra). La base de promedio es una base acumulada propia (ver [nomina/motor.md › Bases](nomina/motor.md#bases-e-imponibilidad-la-matriz-concepto--base)). En la liquidación final se pagan las vacaciones truncas: saldo pendiente más el devengo proporcional del periodo en curso, valorizadas con la misma regla.

### Excepciones

Solicitud que cruza el cierre de periodo (se parte en dos asientos), vacaciones canceladas después de pagadas (reintegro), ausencia cargada tarde con el periodo cerrado (genera retroactivo), traslado entre entidades con saldo pendiente (traspaso de pasivo), empleado que sale con saldo negativo (descuento en liquidación según ley).