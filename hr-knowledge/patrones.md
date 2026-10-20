# Patrones de diseño

Decisiones que se repiten en cualquier HCM serio, con su porqué. Sirven como checklist al revisar un
diseño: si un requerimiento rompe uno de estos patrones, debe justificar por qué.

## 1. La nómina es una función pura sobre el estado a una fecha

Dados los hechos vigentes, los insumos del período y las reglas vigentes, el resultado debe ser
reproducible. Por eso cada corrida guarda la versión de reglas y del motor que usó (`legal_pack_id`,
`engine_version`, `config_hash`) y cada resultado guarda una foto de los datos del trabajador.

**Por qué:** una auditoría, un reclamo o una inspección laboral preguntan «¿por qué se pagó esto?» años
después. Si el resultado depende del estado actual de las tablas, no hay respuesta.

## 2. Todo lo que cambia en el tiempo tiene vigencia

Intervalo semiabierto `[valid_from, valid_to)`, `NULL` = vigente, y la base impide dos filas vigentes a
la vez (`EXCLUDE USING gist`). Se distingue **cambio** (cierra la fila vigente y abre otra) de
**corrección** (el dato estaba mal desde el origen; se corrige con auditoría).

**Por qué:** sueldos, cargos, afiliaciones, tasas y parámetros legales cambian a mitad de período. Sin
vigencias, el motor aplica el valor de hoy a meses pasados. Los cambios con fecha anterior a un período
cerrado son el origen de casi todos los retroactivos.

## 3. Período, corrida y resultado son cosas distintas

El período es la ventana de tiempo; la corrida es una ejecución del cálculo sobre un período; el
resultado es lo que produjo. Un período tiene varias corridas: la regular, sus recálculos, las fuera de
ciclo (gratificación, bono, liquidación) y las de ajuste.

**Por qué:** si el período vive dentro de la corrida (o la planilla tiene «una fila por trabajador y
período»), no caben las corridas fuera de ciclo ni los recálculos versionados, y el estado del período
se confunde con el de la corrida.

## 4. Período de pago, ventana de insumos y período de cómputo no se mezclan

Ver [nomina/periodos.md](nomina/periodos.md). El período define el sueldo fijo y el mes de declaración;
la ventana, qué asistencia entra; el período de cómputo, sobre qué meses se calcula un beneficio.

**Por qué:** mezclarlos produce solapes falsos, obliga a pagar con asistencia incompleta o hace que una
gratificación «choque» con la planilla regular.

## 5. Las garantías viven en la base, no en la pantalla

Solapes, un solo período abierto, fechas fijas tras aprobar, transiciones válidas, novedades bloqueadas
en períodos cerrados: lo hace cumplir la base de datos (restricciones y triggers) y el backend lo
traduce a mensajes legibles. La pantalla solo evita que el usuario lo intente.

**Por qué:** importaciones, integraciones, scripts y otras pantallas escriben en las mismas tablas. Una
regla que solo está en un formulario se rompe en la primera carga masiva.

## 6. La configuración tiene capas y cada una tiene dueño

| Capa | Qué define | Quién |
|---|---|---|
| Sistema | Motor, tipos de concepto, estados, orden de cálculo | El producto |
| Localización | Tasas, tramos, topes, parámetros, conceptos legales, versionados por fecha | El producto, por país |
| Tenant | Grupos de pago, calendarios, conceptos propios, políticas, plantillas, cuentas | Admin de nómina |
| Período | Novedades, revisión, aprobación | Operador |
| Empleado | Consulta | Autoservicio |

**Por qué:** si el cliente puede editar una tasa legal, tarde o temprano paga mal; si el producto
congela una política del cliente, no se puede vender a dos empresas distintas.

## 7. Los conceptos se calculan por reglas, no se escriben montos

Cada concepto declara su método (fijo, porcentaje, cantidad × tarifa, fórmula, tramos), su base, su
tasa y quién paga, con vigencia. La pertenencia de cada concepto a cada base (pensión, salud, impuesto,
vacaciones) es una matriz configurable. Los tipos de trabajador se resuelven con la afiliación y el
régimen, no duplicando conceptos.

**Por qué:** los aportes y el impuesto son porcentajes con topes y pisos que cambian por ley; un monto
fijo queda mal el día que cambia la tasa, y no se puede explicar en la boleta.

## 8. Lo cerrado no se edita: se corrige hacia adelante

Un período cerrado y sus resultados son inmutables. Un error se corrige con un retroactivo (recálculo en
sombra del período original y diferencias en el período abierto, con referencia al período de origen) o
con una reversa formal (contra-registros y corrida nueva). Las novedades tardías llevan el período al
que corresponden (`for_period_id`) y se pagan en el abierto.

**Por qué:** lo pagado ya salió del banco, se declaró y se entregó en una boleta. Reescribirlo deja
inconsistentes el pago, la contabilidad y la declaración.

## 9. Los saldos se derivan de un libro mayor

Vacaciones, préstamos, acumulados anuales: el saldo es la suma de movimientos, nunca un número que se
sobrescribe.

**Por qué:** auditoría completa, reconstrucción a cualquier fecha y recálculo si cambia la política.

## 10. El mínimo viable es un subconjunto del modelo completo

Cuando se construye menos de lo que el modelo de referencia tiene, se usa la misma forma y los mismos
nombres: mismas entidades, mismas relaciones, mismos estados. Lo que falta se agrega después como
columnas o tablas nuevas.

**Por qué:** así cada mejora es aditiva y la migración es gradual. Un atajo con otra forma obliga a
reescribir datos más adelante.

## 11. Las migraciones son expand / contract

1. Agregar lo nuevo como opcional.
2. Rellenar los datos existentes.
3. El código lee lo nuevo, con respaldo en lo viejo.
4. Endurecer la restricción (`NOT VALID` y luego `VALIDATE`).
5. Quitar lo viejo cuando todos los tenants migraron.

Cada paso es idempotente y reversible, porque con una base por tenant conviven versiones distintas.

**Lo que sí es difícil de deshacer** y conviene decidir bien desde el inicio:
- guardar la identidad del período dentro de la corrida;
- usar las fechas del período como ventana de asistencia;
- permitir editar fechas o reabrir después de aprobar o pagar;
- dejar reglas solo en la interfaz;
- nombres de estados que luego habría que renombrar en todas las bases.

## 12. Nadie se aprueba a sí mismo

Segregación de funciones (quien carga novedades no aprueba; quien aprueba no paga) y doble control
para acciones sensibles (cambio salarial, cuenta bancaria nueva, aprobación de corrida), con motivo
obligatorio y auditoría.

**Por qué:** nómina mueve dinero. Es el control que pide cualquier auditor y el primero que falta en los
sistemas pequeños.

## 13. La boleta es un documento emitido

Se emite con número y contenido congelado, se anula si se revierte la aprobación, se publica al pagar y
se rectifica con otra si hay error. Ver [nomina/boleta.md](nomina/boleta.md).

**Por qué:** es la prueba legal del pago y lo que el trabajador usa para reclamar. Si se recalcula al
abrirla, deja de ser prueba.
