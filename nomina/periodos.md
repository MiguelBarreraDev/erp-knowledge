# Períodos de nómina

Casi todos los errores de diseño de nómina vienen de mezclar tres fechas que parecen la misma. Este
archivo las separa, describe los tipos de período, sus restricciones, sus estados y cómo los resuelven
los productos grandes.

Tablas: `pay_calendar`, `pay_calendar_window_rule`, `pay_group`, `employee_pay_group`, `pay_period`,
`pay_period_window`, `pay_period_status_log` y la sección 16 (funciones y triggers) de
[schema/hr_schema.sql](../schema/hr_schema.sql).

## Las tres fechas que no hay que mezclar

| Concepto | Pregunta que responde | Ejemplo (octubre) |
|---|---|---|
| **Período de pago** | ¿Qué sueldo le corresponde en este pago? Define el sueldo fijo devengado, los prorrateos, los valores legales vigentes y el mes en que se declara | 01/10 al 31/10 |
| **Ventana de insumos** | ¿Qué eventos medidos entran en este pago? Horas extra, tardanzas, faltas, nocturnas | 21/09 al 20/10 |
| **Período de cómputo de un beneficio** | ¿Sobre qué meses se calcula un beneficio? No es un período de planilla: es un parámetro del concepto o de la corrida | Gratificación de julio: enero a junio |

Si el período de cómputo se modela como un período de planilla, aparecen solapes falsos con los
regulares. Si la ventana de insumos se modela con las mismas fechas que el período de pago, no se puede
pagar el día 30 con la asistencia cerrada el 20.

## El período de pago

Para qué existe:
- **Delimitar** qué se paga: sin período no hay prorrateo ni forma de saber qué asistencia entra.
- **Congelar** el pasado: al cerrar, los resultados son inmutables. Un cambio posterior entra como
  ajuste o retroactivo en el período siguiente.
- **Acumular:** impuestos progresivos y beneficios anuales suman lo ya pagado en el año.
- **Ordenar** el trabajo del equipo con un ciclo de estados.

Cada período lleva, como mínimo: inicio, fin, fecha de pago, mes y año al que pertenece, grupo de pago,
tipo (regular o fuera de ciclo) y estado. Los productos grandes agregan fecha de corte de novedades,
fecha de devengo y fecha de publicación de la boleta.

### Tipos de período

| Tipo | Inicio y fin | ¿Cruza meses? | Uso típico |
|---|---|---|---|
| Mensual calendario | 1 al último día | No | El más común en planilla de empleados |
| Mensual desplazado | Día N al día N−1 del mes siguiente (16–15, 21–20) | Sí | Empresas que liquidan alineadas a turnos o cierres propios |
| Quincenal | 1–15 y 16–fin | No | Pago dos veces al mes |
| Semanal | 7 días fijos | Sí, 4 o 5 veces al año | Obreros, construcción |
| Catorcenal | 14 días fijos | Sí, con frecuencia | Frecuente fuera de Perú |
| Fuera de ciclo | Libre: un día (bono) o un rango (liquidación) | Puede | Gratificación, depósito de beneficios, bono, adelanto, liquidación |
| Ajuste | Una fecha | No aplica | Saldos iniciales al migrar, correcciones contables |

### Restricciones

**Períodos regulares de un grupo:**
1. El fin es igual o posterior al inicio.
2. No se solapan. Lo ideal es que sean contiguos; si quedan huecos, el sistema avisa porque esos días
   no se pagan en ninguna planilla.
3. La duración corresponde a la frecuencia: mensual de 28 a 31 días, quincenal de 13 a 16, semanal 7,
   catorcenal 14.
4. Todos los de un grupo tienen la misma frecuencia. Cambiarla exige otro grupo.
5. Las fechas se pueden cambiar mientras nada se aprobó sobre el período.

**Períodos fuera de ciclo:** pueden solaparse con el regular y entre sí, pueden durar un día y no entran
en el orden de cierre de los regulares.

**Fecha de pago:** puede caer antes del fin (pago el 28 por un mes que termina el 31; lo posterior se
ajusta en el siguiente) o después. Se mueve a día hábil.

**Mes al que pertenece un período que cruza:** se decide con una regla fija, no caso por caso. Lo
habitual es el mes en que termina o el de la fecha de pago. Esa regla define en qué declaración
mensual, en qué acumulado y en qué mes del impuesto cae. Conviene guardarlo explícito en el período en
lugar de recalcularlo.

### Cuando el período cruza de mes de verdad

Funciona, pero cuesta más que el mes calendario:
- **Declaraciones mensuales:** lo devengado del 16 al 30 de un mes se declara en el siguiente.
- **Cambios legales a mitad de período:** si un valor legal cambia el día 1 y el período va del 16 al
  15, el período se parte en dos tramos, cada uno con su valor. La boleta muestra dos líneas.
- **Prorrateos:** un ingreso el día 20 cuenta desde el 16, no desde el 1.
- **Comunicación:** «tu sueldo de octubre» cubre parte de septiembre y hay que explicarlo.

Recomendación por defecto: mes calendario con la ventana de asistencia desplazada (21–20) cuando lo
que se busca es tiempo para revisar asistencia. El período desplazado solo cuando el negocio realmente
liquida así.

### Cuántos días paga un período

Con la convención comercial (30/360), un período completo paga 30 días en mensual y 15 en quincenal,
cruce o no de mes, tenga 28 o 31 días. Un período parcial (ingreso o cese) paga los días trabajados con
tope en 30 (15). El ciclo es la fila del período, no el mes calendario. Detalle de convenciones en
[motor.md › Prorrateos](motor.md#prorrateos-y-convenciones-de-días).

## La ventana de insumos

Existe porque el pago ocurre antes de que termine el período. Si se paga el 30 y el corte de novedades
es el 23, al calcular todavía no se sabe si alguien faltará el 27.

Entonces:
- El sueldo fijo se paga completo por el período, asumiendo que se trabaja.
- Los variables salen de una ventana ya cerrada y revisada (21/09 al 20/10).
- Lo que pase del 21 al 31 entra en la planilla siguiente.

| Línea de la boleta de octubre | Rango que usa |
|---|---|
| Sueldo básico, asignaciones fijas | Período de pago (01/10 al 31/10) |
| Vacaciones y licencias | Período de pago (se conocen con anticipación) |
| Horas extra, tardanzas, faltas | Ventana de insumos (21/09 al 20/10) |

Si la empresa paga después de terminar el período, la ventana puede coincidir con él.

**Reglas que trae separarlas:**
1. Las ventanas también son contiguas: ningún día se cuenta dos veces ni queda fuera.
2. Cada evento se valoriza con lo vigente el día en que ocurrió, aunque se pague en el período siguiente.
3. La liquidación por cese recoge el tramo de ventana que ya no tendrá planilla.
4. El ingreso tiene un tramo inicial: sueldo prorrateado en el período, variables en el siguiente.
5. La puesta en marcha empieza la primera ventana donde terminó la del sistema anterior.
6. La boleta muestra las fechas de los variables, o el trabajador reclamará una falta que recuerda de
   otro mes.
7. El mes de declaración de los variables desfasados se confirma con un especialista tributario.

**Cómo saber si un «del 15 al 15» es período o ventana:** si alguien ingresa el día 5, ¿se prorratea
desde el 1 o desde el 16 del mes anterior? ¿El sueldo fijo de «octubre» cubre del 1 al 31? ¿La planilla
declarada cuadra con el mes calendario? En la mayoría de empresas la respuesta es mes calendario más
ventana desplazada.

## Estados del período

Máquina de estados del esquema de referencia:

```
future ──► open ──► inputs_closed ──► processing ──► closed
            ▲            │                 │
            └────────────┴── (reabrir con motivo y permiso)
```

| Estado | Qué se puede hacer |
|---|---|
| `future` | Editar fechas, borrar si no tiene corridas |
| `open` | Registrar novedades, calcular corridas en borrador |
| `inputs_closed` | Novedades bloqueadas; lo que llega va al período siguiente con `for_period_id` |
| `processing` | Corrida aprobada; fechas fijas |
| `closed` | Inmutable. Se cierra al pagar y conciliar; las correcciones van como retroactivo al período abierto |

Reglas que la base hace cumplir aunque un script o integración intente saltárselas:
- Retroceder un estado exige motivo.
- Cerrar exige corridas pagadas, ventanas cerradas y el período anterior cerrado.
- No se calcula un período si el anterior sigue abierto.
- No se cargan novedades en un período cerrado.
- Los datos del empleado nunca se bloquean: un cambio con fecha en un período pagado se guarda y queda
  marcado para retroactivo (`payroll_retro_trigger`).

Un mínimo viable puede omitir `inputs_closed` (sin corte con fecha) y no permitir reabrir períodos
cerrados. Ambos se agregan después sin migrar datos.

## Quién crea los períodos: generados o editables

| Producto | Dónde se definen | Cómo se crean | Fechas | ¿Asistencia separada? | Control de estado |
|---|---|---|---|---|---|
| Oracle | Definición de nómina | Generados desde tipo de período y fin del primero | Inicio, fin y desfases: corte, devengo, ejecución, pago, publicación de boleta | Sí, en Tiempo | Flujos por período |
| Workday | Calendario de períodos del grupo de pago | Tarea «Generate Periods» (hasta 2 años) | Inicio, fin, pago ajustado a feriados | Sí, calendario de tiempo con desfase | Corridas por grupo |
| SAP | Parámetros de período y área de nómina | Generados desde parámetros | Inicio, fin, pago | Sí, evaluación de tiempos aparte | Registro de control: liberado, corrección, salida |
| Odoo | No hay maestro | El usuario escribe desde / hasta en cada lote | Solo desde y hasta | Sale de las mismas fechas | Estado del lote y de cada boleta |

Lo que comparten los grandes: la configuración guarda reglas y los períodos se generan; cada período
trae más fechas que del / al; el período de tiempo y el de pago son objetos distintos; el estado del
período bloquea cosas.

Ambos modelos son válidos si se respetan las mismas garantías. Un maestro editable (el usuario escribe
del / al) es aceptable cuando:
- la base impide solapes y garantiza un solo período abierto por grupo;
- las fechas quedan fijas desde que se aprueba algo sobre el período;
- el sistema propone el siguiente rango contiguo y avisa de huecos;
- existe un «generar año» que propone filas editables antes de abrirlas.

Lo que no conviene copiar de implementaciones mínimas: reglas que solo viven en la pantalla, procesos
programados que cierran «el último por id» en vez del último por fecha, unicidad por «mes de fin» que
impide dos quincenas en el mismo mes, y una sola planilla por período (impide corridas fuera de ciclo).

## Dónde va cada cosa en la interfaz

| Vista | Equivale a | Contiene |
|---|---|---|
| Configuración › Grupos de pago | Área de nómina (SAP), grupo de pago (Workday) | Empresa, moneda, frecuencia o calendario |
| Configuración › Calendarios | Definición de nómina (Oracle), calendario de períodos (Workday) | Reglas de generación y vista previa |
| Nómina › Períodos | Registro de control (SAP) | Períodos por grupo y año, estado, una acción siguiente por período, historial |
| Tiempo › Ventanas de asistencia | Calendario de tiempo (Workday) | Rango que alimenta cada pago y su bloqueo |
| Nómina › Corridas | Corridas y flujos | Corridas regulares y fuera de ciclo de cada período |

Mientras haya un solo grupo por empresa, la pantalla de grupos y la de calendarios pueden no existir;
el maestro de períodos vive en la operación de nómina porque abrir y cerrar es tarea de cada mes.
