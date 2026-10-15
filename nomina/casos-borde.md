# Casos borde de nómina

Checklist para revisar un diseño, un requerimiento o una implementación. Si un caso no tiene respuesta,
el diseño está incompleto. El porqué de cada tratamiento está en [motor.md](motor.md) y
[periodos.md](periodos.md).

| Situación | Tratamiento esperado |
|---|---|
| Novedad llegada después del corte | Al periodo siguiente o fuera de ciclo, según política |
| Error descubierto con el periodo ya pagado | Retroactivo o ajuste; si hubo sobrepago, plan de recupero dentro del límite legal |
| Alta con fecha anterior al cierre | Retroactivo del periodo de inicio |
| Baja anticipada con boleta ya pagada | Recuperar el sobrepago o compensarlo en la liquidación |
| Cambio de tasa legal a mitad de periodo | Segmentar y aplicar cada tasa a su tramo |
| Cambio de grupo de pago a mitad de periodo | Cerrar la relación con el grupo anterior y pagar el tramo en cada uno |
| Empleado con dos relaciones laborales | Topes y base de aportes por persona o por empleador, según régimen |
| Licencia sin goce que cubre todo el periodo | Boleta en cero, obligaciones informativas |
| Embargo recibido después del cálculo | Se aplica desde el siguiente periodo salvo orden de retención inmediata |
| Neto menor que el mínimo vital | Se limita el embargo; se aplica la política de neto negativo |
| Salario menor al mínimo legal por prorrateo | Se compara contra el mínimo proporcional, no contra el mensual |
| Pago rechazado por el banco | Estado `failed` o `returned`, reintento o pago por otro medio, sin recalcular |
| Moneda distinta a la del grupo | Tipo de cambio por fecha de devengo o de pago, según política |
| Feriado decretado tardíamente | Recalcular asistencia y recargos afectados |
| Reingreso en el mismo periodo | Dos relaciones en un periodo; segmentar o fusionar según régimen |
| Fallecimiento durante el periodo | Liquidación a beneficiarios |

## De períodos y ventanas

| Situación | Tratamiento esperado |
|---|---|
| Período que cruza de mes y un valor legal cambia dentro de él | Segmentar el período en tramos; cada tramo usa el valor vigente |
| Cambio de fechas de un período con corrida en borrador | La corrida queda desactualizada y no se aprueba sin recalcular |
| Hueco entre dos períodos regulares | Avisar; los días sin período no se pagan en ninguna planilla |
| Ventana de asistencia desfasada y cese a fin de mes | La liquidación recoge el tramo de asistencia que no tendrá planilla siguiente |
| Ingreso dentro de la ventana desfasada | El sueldo se prorratea en el período; los variables entran en el siguiente |
| Novedad dirigida a un período cerrado | Se registra en el período abierto con `for_period_id` del período al que corresponde |
