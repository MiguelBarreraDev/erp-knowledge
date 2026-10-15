# Escenarios de prueba del motor

Si puedes resolver a mano y con el sistema estos diez casos, dominas el módulo:

1. Mensual estándar, sin novedades.
2. Alta el 16 con convención 30/360 y con calendario real; compara resultados.
3. Cambio salarial el día 16 (segmentación) con complemento a 30.
4. Horas extra con dos factores y tope diario.
5. Vacaciones de 10 días que cruzan el cierre de periodo.
6. Aumento retroactivo de dos meses con recálculo de aportes e impuesto.
7. Embargo del 30% con préstamo activo y neto insuficiente.
8. Bono anual que dispara la retención por proyección.
9. Liquidación final por despido sin causa con vacaciones truncas y saldo de préstamo.
10. Reversa de una corrida ya pagada y emisión de la corrida correcta.

Los diez, ejecutados con datos reales y comparados entre el sistema y un cálculo manual, forman tu conjunto de pruebas de regresión del motor.

Si quieres, convierto todo esto en un documento de estudio navegable (con índice, tablas y los diagramas) para guardarlo o compartirlo con tu equipo.

## Cómo usarlos

- Cada escenario se resuelve primero a mano, con la aritmética escrita, y se guarda como golden.
- El mismo escenario se corre en el sistema y se compara línea por línea: base, tasa, cantidad e importe.
- Se repiten con dos convenciones de días (30/360 y calendario real) y con un período que cruza de mes.
- Para Perú, el ejemplo completo de una boleta con AFP, asignación familiar y renta de 5ta está en
  [localizacion/peru.md](../localizacion/peru.md#ejemplo-completo-de-una-boleta).
