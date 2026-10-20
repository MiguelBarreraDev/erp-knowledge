# Motor de nómina

Cómo se calcula una nómina, de la configuración a los resultados. Los períodos tienen su propio archivo
([periodos.md](periodos.md)); la boleta, el pago y la contabilidad también ([boleta.md](boleta.md),
[salidas-y-controles.md](salidas-y-controles.md)).

Tablas: [schema/hr_schema.sql](../schema/hr_schema.sql), sección 6.

> Las tasas, topes y plazos cambian por país y por año. Aquí las cifras son ilustrativas; las reales
> están en [localizacion/](../localizacion/peru.md).

Nómina es el proceso periódico que toma datos del empleado (salario, horas, ausencias, novedades) y reglas (conceptos, tasas, topes) y produce cuatro resultados: pago neto, retenciones y aportes a terceros, asiento contable y boleta. Todo lo demás (periodos, conceptos, estados, vistas) existe para que ese proceso sea repetible, auditable y corregible.

## Para qué existen los períodos

Un periodo es una ventana de tiempo con fechas fijas: inicio y fin, fecha de corte de novedades y fecha de pago. Sirven para cuatro cosas:
- **Delimitar** qué se paga: sin periodo no hay forma de prorratear un ingreso a mitad de mes ni saber qué asistencia entra.
- **Congelar** el pasado: al cerrar, los resultados son inmutables. Un cambio posterior se hace como ajuste o retroactivo en el periodo siguiente, no reescribiendo la historia.
- **Acumular**: los impuestos progresivos y los beneficios anuales (gratificaciones, vacaciones) necesitan sumar lo ya pagado en el año.
- **Ordenar** el trabajo del equipo con un ciclo de estados.

El ciclo completo combina el estado del período (`Futuro → Abierto → Novedades cerradas → En proceso → Cerrado`) y el de la corrida (`Borrador → Calculada → Aprobada → Pagada → Contabilizada`). Solo se retrocede con una reversa explícita, con permiso y auditoría. Detalle en [periodos.md](periodos.md).

## Quién define cada cosa

| Capa | Qué define | Ejemplos |
|---|---|---|
| Sistema (fijo) | Motor, tipos de concepto, estados, orden de cálculo, validaciones | Ingreso/descuento/aporte, secuencia de evaluación |
| Localización por país (versionada) | Reglas legales con vigencia | Tasas de seguridad social, tramos de impuesto, topes, conceptos legales |
| Admin de nómina del tenant | Su operación | Grupos de pago, calendarios, conceptos propios, fórmulas, cuentas contables, plantilla de boleta |
| Operador de nómina | Datos de cada periodo | Novedades, revisión, aprobación |
| Empleado | Solo consulta | Ver y descargar boletas |

## Orden de cálculo

1. Ingresos: sueldo, horas extra, bonos.
2. Base afecta de cada régimen (seguridad social, impuesto).
3. Aportes del empleado, según la base y su tope.
4. Impuesto retenido, por tramos y con acumulados.
5. Otros descuentos: préstamos, embargos, adelantos.
6. Neto = ingresos − descuentos.
7. Aportes del empleador y costo empresa.

Ejemplo numérico de referencia (porcentajes ilustrativos; los reales dependen del país, ver [localizacion/](../localizacion/peru.md)):

| Concepto | Cálculo | Monto |
|---|---|---|
| Sueldo básico | fijo | 3,000.00 |
| Horas extra | 10 h × 15.00 | 150.00 |
| Bono por desempeño | fijo | 200.00 |
| **Total ingresos** | | **3,350.00** |
| Seguridad social empleado | 3,350.00 × 9% | −301.50 |
| Impuesto retenido | por tramos | −120.00 |
| Préstamo, cuota 3/12 | fijo | −100.00 |
| **Neto a pagar** | | **2,828.50** |
| Seguridad social empleador | 3,350.00 × 11% | 368.50 |
| **Costo empresa** | | **3,718.50** |

## Nómina: el motor, paso a paso

### Configuración que existe antes de calcular

| Elemento | Tabla | Pregunta que responde |
|---|---|---|
| Grupo de pago | `pay_group`, `employee_pay_group` | Con qué frecuencia, moneda y calendario se paga a este empleado |
| Periodo | `pay_period` | Qué ventana, qué corte y qué fecha de pago |
| Conceptos | `payroll_concept` | Qué rubros existen y cómo se calculan |
| Esquemas legales | `statutory_scheme`, `statutory_rate` | Qué aportes e impuestos aplican, con qué tasa y tope en cada fecha |
| Afiliación | `employee_statutory_enrollment` | A qué esquemas está afiliado cada empleado |
| Conceptos recurrentes | `employee_recurring_concept` | Qué bonos o descuentos fijos tiene |
| Novedades | `payroll_input` | Qué variable ocurrió en este periodo |
| Préstamos | `loan`, `loan_installment` | Qué cuotas vencen |

### Pipeline de ejecución de una corrida

1. **Selección de población.** Empleados con asignación vigente en el periodo, incluidas altas y bajas dentro de él. Excluye a quienes no tienen relación activa en ninguna fecha del periodo. Los suspendidos o en licencia sin goce entran, porque pueden tener boleta en cero y obligaciones informativas.
2. **Segmentación temporal.** Si algo cambió dentro del periodo (salario, grupo, asignación, tasa legal), el periodo se parte en tramos y se calcula cada uno con los hechos vigentes en él.
3. **Recolección de insumos.** Compensación base, recurrentes vigentes, novedades de asistencia, horas extra, ausencias, cuotas de préstamo, bonos aprobados.
4. **Devengos (ingresos).** Sueldo prorrateado, horas extra, comisiones, bonos, asignaciones.
5. **Acumulación de bases.** Cada ingreso suma a las bases a las que pertenece (ver [Bases e imponibilidad](#bases-e-imponibilidad-la-matriz-concepto--base)).
6. **Aportes del trabajador.** Tasa × base, respetando piso y tope del esquema vigente.
7. **Impuesto.** Retención con proyección anual (ver [Impuesto](#impuesto-a-la-renta-del-trabajo-retención-con-proyección-anual)).
8. **Otros descuentos.** Préstamos, adelantos, embargos con prioridad y límites.
9. **Neto y redondeo.** Ingresos − descuentos, con política de redondeo y de neto negativo.
10. **Aportes del empleador y provisiones.** Calculados sobre sus propias bases; construyen el costo empresa.
11. **Persistencia.** Se graba `payroll_result` y `payroll_result_line` como snapshot.
12. **Validación y aprobación.** Reglas automáticas, revisión humana, aprobación.
13. **Salidas.** Archivo de pago, boletas, asiento contable, declaraciones.
14. **Cierre.** El periodo pasa a `closed` y queda inmutable.

La ejecución debe ser idempotente: recalcular un periodo no cerrado produce el mismo resultado si los insumos no cambiaron, y reemplaza el resultado anterior de esa versión de corrida.

### Bases e imponibilidad: la matriz concepto × base

Cada concepto pertenece o no a cada base. Esa pertenencia es configuración, no código. Ejemplo ilustrativo:

| Concepto | Base seguridad social | Base impuesto | Base vacaciones | Base indemnización |
|---|---|---|---|---|
| Sueldo básico | Sí | Sí | Sí | Sí |
| Horas extra | Sí | Sí | Promedio | Promedio |
| Bono por desempeño | Sí | Sí | No | Depende de la ley |
| Movilidad no remunerativa | No | No | No | No |
| Seguro médico en especie | No | Sí (valorizado) | No | No |
| Gratificación legal | Según ley | Sí | No | Proporcional |
| Reembolso de gastos | No | No | No | No |

Bases típicas: remunerativa o de cotización, imponible tributaria, base de vacaciones, base de indemnización o antigüedad, base de provisiones. En el esquema de referencia la matriz es `payroll_balance` (las bases con nombre: `GROSS`, `BASE_SS`, `BASE_TAX`…) más `payroll_balance_feed` (qué concepto suma a qué base, con su factor).

Bases promediadas: para variables se toma el promedio de los últimos N meses (o N periodos), con regla de cuántos meses mínimos deben existir para que cuente.

### Prorrateos y convenciones de días

El valor de un día de sueldo depende de la convención:

| Convención | Divisor | Ejemplo: sueldo 3,000, ingreso el 16 de octubre (mes de 31 días) |
|---|---|---|
| Comercial 30/360 | 30 siempre; días pagados = 30 − días previos al ingreso | 30 − 15 = 15 días → 3,000 / 30 × 15 = 1,500.00 |
| Calendario real | Días del mes | 3,000 / 31 × 16 = 1,548.39 |
| Días hábiles | Hábiles del mes | Depende del calendario |

Regla de oro con segmentación: en 30/360 el último tramo se calcula por diferencia hasta completar 30 días. Con sueldo de 3,000 hasta el 15 y de 3,300 desde el 16: tramo 1 = 15 × 100 = 1,500; tramo 2 = (30 − 15) × 110 = 1,650; total 3,150. Si se contaran 16 días en el segundo tramo se pagaría 31 días en un mes comercial.

Otros prorrateos: salida a mitad de mes, licencia sin goce parcial, cambio de FTE, cambio de jornada. Todos usan la misma convención definida en la política del tenant.

### Horas extra y recargos

`valor hora = sueldo base / divisor mensual de horas`. El divisor depende de la jornada y la ley (240 horas es el resultado de 30 días × 8 horas; en el ejemplo de las boletas usé 250 para que diera 12.00 exacto). Luego:

```
importe = horas × valor_hora × factor
```

Factores típicos ilustrativos: 1.25 las primeras horas, 1.35 las siguientes, 2.00 en día de descanso o feriado, más un recargo nocturno. Reglas: tope de horas por día, semana y mes; la base del valor hora puede incluir otros ingresos fijos; las horas extra pasan a formar parte de la base promediada de vacaciones.

### Impuesto a la renta del trabajo: retención con proyección anual

La mayoría de los regímenes usan retención sobre una proyección. Ejemplo ilustrativo coherente con las boletas anteriores:

```
Ingreso del mes                         3,350.00
Proyección anual (× 12 meses)          40,200.00
(−) Deducción fija anual ilustrativa   10,200.00
Base anual proyectada                  30,000.00

Tramos ilustrativos:
  0 – 12,000        0%       →     0.00
  12,000 – 30,000   8%       → 1,440.00   (18,000 × 8%)
Impuesto anual proyectado                1,440.00
Retención mensual (÷ 12)                   120.00
```

Mecánica real:
- **Acumulados:** el sistema guarda lo pagado y retenido en el año (`payroll_balance_value` en el esquema de referencia). Cada mes calcula `(impuesto anual proyectado − ya retenido) / meses restantes`.
- **Recalculo por variaciones:** si el ingreso sube (un bono), la proyección cambia y la retención del mes absorbe la diferencia.
- **Deducciones personales:** dependientes, intereses hipotecarios, gastos de salud, aportes voluntarios a pensión. Requieren un perfil tributario del empleado (`employee_tax_profile`).
- **Regularización:** en el último mes del año o al dar de baja, se compara el impuesto real del año con lo retenido y se devuelve o cobra la diferencia.
- **Empleado con varios empleadores:** la retención considera ingresos de otros empleadores si el empleado los declara.
- **No residentes:** tasa fija sin tramos ni deducciones.

### Aportes obligatorios y del empleador

Cada esquema (`statutory_scheme`) tiene `employee_rate` y `employer_rate` con vigencia (`statutory_rate`), `salary_floor` (mínimo cotizable) y `salary_ceiling` (tope). Cálculo: `min(max(base, piso), tope) × tasa`. Ejemplos de esquemas: pensión, salud, riesgos laborales, vivienda, formación profesional, caja de compensación. Las tasas pueden cambiar a mitad de periodo: al partir el periodo en tramos, cada tramo usa la tasa vigente en él.

Lo que paga el empleador no se descuenta al trabajador, pero forma parte del costo empresa y de las declaraciones.

### Descuentos judiciales, préstamos y adelantos

**Embargos y pensiones alimenticias:**
- Llegan como un mandato judicial con monto o porcentaje, vigencia y prioridad.
- Orden de aplicación habitual: alimentos primero, luego embargos de acreedores, luego descuentos voluntarios.
- Límite de embargabilidad: porcentaje máximo del neto embargable y un mínimo vital inembargable.
- Si el neto no alcanza para todos, se aplica la cascada por prioridad y el resto queda pendiente.
- En el esquema: `garnishment_order`; lo que no alcanza queda en `payroll_arrear`.

**Préstamos (`loan` y `loan_installment`):**
- Calendario de amortización: capital, interés, cuota.
- La cuota entra como `payroll_input` o genera línea de descuento del concepto `deduction_concept_id`.
- Tope de descuento como porcentaje del neto.
- Se pausa durante licencias sin goce y se retoma después.
- En liquidación final se cobra el saldo pendiente hasta el límite legal.

**Adelantos de sueldo:** se pagan fuera de ciclo y se descuentan en la corrida regular.

### Neto negativo y redondeo

Si descuentos superan ingresos hay cuatro políticas posibles (se configura por tenant):
1. No descontar lo que excede y dejar saldo pendiente para el siguiente periodo.
2. Reducir descuentos voluntarios por prioridad hasta neto cero.
3. Generar una deuda del empleado con cobro posterior.
4. Bloquear la corrida y exigir intervención.

Redondeo: se decide si se redondea por línea o por total, la unidad (centavo, entero) y quién absorbe la diferencia (línea de ajuste, normalmente al neto). Las cifras de aportes e impuestos suelen redondearse según reglas de la autoridad.

### Costo empresa y provisiones

```
Costo empresa = ingresos + aportes del empleador + provisiones del periodo
```

Provisiones típicas: vacaciones (1/12 del sueldo si son 30 días al año), gratificación o 13.º y 14.º (1/12 por cada uno), indemnización por antigüedad. Se contabilizan como gasto con pasivo aunque no se paguen aún. El esquema guarda `employer_cost` en `payroll_result`; las provisiones se modelan como conceptos informativos.

## Tipos de corrida y variaciones

| Tipo (`run_type`) | Para qué sirve | Particularidad |
|---|---|---|
| `regular` | Pago periódico normal | Pipeline completo |
| `off_cycle` | Pagos fuera del calendario (bono puntual, adelanto, corrección menor) | Periodo propio; no recalcula lo regular |
| `retroactive` | Corregir periodos cerrados | Ver [Retroactivos](#retroactivos) |
| `final_settlement` | Liquidación al terminar la relación | Ver [Liquidación final](#liquidación-final) |
| `bonus`, `thirteenth`, `profit_sharing` | Pagos anuales o por resultados | Bases promediadas y proporcionalidades |
| Simulación | Proyectar costo o probar cambios | No persiste ni afecta saldos |
| Corrida preliminar | Cálculo antes del corte para detectar problemas | Se descarta o reemplaza |

### Retroactivos

Caso: aumento de 3,000 a 3,300 con vigencia 1 de septiembre, registrado el 5 de octubre con septiembre cerrado.

Enfoques:
- **Delta por concepto:** diferencia simple (300) más recálculo manual de aportes. Sencillo pero falla con topes y tramos progresivos.
- **Recálculo en sombra (recomendado):** el motor re-ejecuta septiembre con los hechos corregidos sin grabarlo, compara línea a línea contra el resultado original y lleva la diferencia a octubre como conceptos "Reintegro de ingresos (sep)", "Ajuste de aportes (sep)", "Ajuste de impuesto".

Reglas:
- Cada línea retro debe llevar referencia al periodo origen (`for_period_id` en `payroll_input` y `payroll_result_line`; la detección automática vive en `payroll_retro_trigger`).
- Ajustan también aportes, impuesto proyectado y acumulados.
- El periodo origen no se reabre ni se modifica. La corrección vive en el periodo actual.
- Un retroactivo que cruza el año fiscal afecta declaraciones del año anterior (rectificativas).

### Liquidación final

Componentes habituales:
1. Sueldo pendiente hasta el último día trabajado (prorrateado).
2. Vacaciones truncas (saldo + proporcional).
3. Gratificación o 13.º y 14.º proporcionales.
4. Indemnización o desahucio, según causa de salida y antigüedad.
5. Preaviso no otorgado (pago sustitutivo) o descuento si el trabajador no lo cumplió.
6. Otros conceptos pendientes (comisiones devengadas, bonos proporcionales).
7. Descuentos: préstamos, adelantos, activos no devueltos (`asset_assignment`), con límites legales.
8. Impuesto con regularización anual y tratamiento especial de la indemnización (a menudo con exención parcial o tasa distinta).
9. Plazo legal de pago desde la salida, a veces con sanciones por mora.
10. Documentos: certificado de trabajo, constancia de pagos, baja en entes y devolución de aportes cuando corresponda.

Por causa de salida (`termination_type`) cambia qué conceptos aplican:

| Causa | Indemnización | Preaviso | Vacaciones y proporcionales |
|---|---|---|---|
| Renuncia | Normalmente no | El trabajador lo otorga | Sí |
| Despido sin causa | Sí, por antigüedad | Sí o su pago | Sí |
| Despido con causa justificada | No (según ley) | No | Sí |
| Fin de contrato a plazo | Depende (a veces compensación) | No | Sí |
| Mutuo acuerdo | Lo pactado | Lo pactado | Sí |
| Jubilación | Depende del régimen | No | Sí |
| Fallecimiento | Beneficiarios | No | Sí |

### Reversas

Una reversa no borra: genera contra-registros. Se invierte el resultado, el pago (si ya salió, se gestiona recupero o reintegro) y el asiento contable, y se emite una corrida nueva con los datos correctos. Exige permiso especial y queda auditada. El estado `reversed` de `payroll_run` y `payroll_result` existe para esto.
