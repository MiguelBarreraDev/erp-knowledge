# UX de RRHH y nómina

Vistas por rol, componentes, flujos y reglas de diseño propias de RRHH. Son patrones del dominio, no un
sistema visual: el estilo lo pone cada producto.

Regla general de canal: el empleado y el jefe trabajan sobre todo desde el celular y en tareas cortas
(consultar, solicitar, aprobar); RRHH, nómina y administración trabajan en escritorio, con tablas
grandes y mucho contexto (conciliar, configurar, revisar).

## Qué contiene cada vista

### Empleado (autoservicio)

| Vista | Para qué sirve | Componentes clave |
|---|---|---|
| Inicio | Resumen accionable | Tarjetas: próxima boleta, saldo de vacaciones, solicitudes en curso, alertas (documento por vencer) |
| Mi perfil | Ver y pedir cambios de datos personales | Formulario por secciones; los cambios sensibles (cuenta bancaria, estado civil) generan una solicitud que RRHH aprueba |
| Mis boletas | Consultar y descargar | Lista por mes, detalle desplegable, PDF, "ver cálculo" |
| Vacaciones | Saldo, calendario, solicitud | Calendario con feriados, formulario de rango con validación de saldo, estado de aprobación |
| Asistencia | Ver marcaciones y horas | Línea de tiempo diaria, botón de marcar si aplica, solicitud de corrección |
| Documentos | Contratos, certificados, constancias | Lista con descarga y firma electrónica |
| Solicitudes | Certificados, correcciones, consultas | Formulario por tipo y seguimiento de estado |

### Jefe

| Vista | Para qué sirve | Componentes clave |
|---|---|---|
| Mi equipo | Ver quién reporta | Organigrama o lista, ficha resumida sin datos sensibles (sin sueldo salvo permiso) |
| Aprobaciones | Resolver pendientes | Bandeja única: vacaciones, horas extra, requisiciones, correcciones; aprobar o rechazar con comentario |
| Calendario del equipo | Evitar cruces de ausencias | Calendario con superposición y alerta de cobertura mínima |
| Asistencia del equipo | Revisar y aprobar horas | Tabla diaria con excepciones resaltadas |
| Evaluaciones | Evaluar a su equipo | Formularios por ciclo y competencia |
| Requisiciones | Pedir una contratación | Formulario ligado a una plaza |
| Reportes del equipo | Rotación, ausentismo, horas extra | Tableros simples |

### RRHH y nómina (back-office)

| Vista | Para qué sirve | Componentes clave |
|---|---|---|
| Colaboradores | Buscar y administrar | Tabla con filtros, vistas guardadas y acciones masivas; ficha 360 con pestañas (general, empleo, compensación, contratos, ausencias, documentos, historial) |
| Organización | Estructura y plazas | Organigrama, tabla de plazas con ocupadas y vacantes |
| Reclutamiento | Del requerimiento a la oferta | Tablero kanban por etapa, ficha de candidato, calendario de entrevistas |
| Asistencia | Consolidar y excepcionar | Cola de excepciones (marcaciones faltantes, tardanzas), consolidación diaria |
| Ausencias | Solicitudes, saldos y ajustes | Tabla de solicitudes, libro de saldos por empleado, ajuste con motivo |
| Nómina | Ciclo completo | Panel de periodos, novedades, corrida, revisión, pagos, boletas, liquidaciones, retroactivos, simulador |
| Reportes y auditoría | Costos, declaraciones, trazabilidad | Reportes por concepto y centro de costo, archivos para declaraciones, bitácora de cambios |

### Administración (configuración)

| Vista | Qué se configura | Quién lo hace |
|---|---|---|
| Estructura legal | Entidades, sedes, centros de costo | Admin del tenant |
| Calendarios y turnos | Feriados, turnos, horarios, rotaciones | Admin de RRHH |
| Conceptos | Rubros, métodos, fórmulas, bases, cuentas contables | Admin de nómina |
| Paquete legal | Tasas, tramos, topes (solo lectura con historial de versiones) | La plataforma, versionado por país |
| Políticas y flujos | Vacaciones, horas extra, redondeo, prorrateo, cadenas de aprobación | Admin de RRHH |
| Plantillas | Boleta, correos, contratos, certificados | Admin de RRHH |
| Roles e integraciones | Permisos por rol y campo, banco, contabilidad, biométricos | Admin de TI o del tenant |

## Biblioteca de componentes

Con esta docena de componentes se arma casi todo el módulo:

| Componente | Dónde se usa | Detalle importante |
|---|---|---|
| Tabla de datos | Todas las listas | Filtros, vistas guardadas, orden, selección múltiple, exportar, columnas configurables |
| Ficha 360 con pestañas | Colaborador | Cabecera fija con estado y acciones; cada pestaña carga solo lo suyo |
| Línea de tiempo con vigencias | Asignación, compensación, contratos | Muestra "Vigente", "Programado" e "Histórico"; todo cambio pide fecha efectiva |
| Selector de fecha efectiva | Cualquier cambio con vigencia | Avisa cuando la fecha es anterior a un periodo cerrado ("generará un retroactivo") |
| Stepper de estados | Periodo y corrida | Un solo estado actual; las acciones permitidas dependen de él |
| Bandeja de aprobaciones | Jefe y RRHH | Aprobar en lote, comentarios, historial de pasos |
| Panel de validaciones | Revisión de nómina | Error, advertencia y correcto, cada uno con enlace "Corregir" |
| Desglose de cálculo | Boleta y revisión | Muestra base × tasa = monto, con tope y fuente de la regla |
| Editor de conceptos | Configuración | Campos bloqueados por el paquete legal, editor de fórmula, vista previa en vivo |
| Matriz concepto × base | Configuración | Cuadrícula de casillas, una columna por base (seguridad social, impuesto, vacaciones) |
| Importador masivo | Novedades, colaboradores | Plantilla descargable, previsualización, errores fila por fila, importar solo las válidas |
| Comparador antes y después | Cambios sensibles y retroactivos | Dos columnas con diferencias resaltadas |
| Calendario | Ausencias, turnos | Capas (feriados, ausencias, turnos), arrastrar para solicitar |
| Boleta | Web, PDF, móvil | Un solo modelo de datos, tres presentaciones |
| Drawer de auditoría | Cualquier registro | Quién cambió qué y cuándo, sin salir de la pantalla |
| Confirmación con impacto | Acciones masivas o irreversibles | "Esto afecta 248 boletas" y motivo obligatorio |

## Flujos de usuario paso a paso

### Flujo A. Configuración inicial (una sola vez)

Se presenta como un asistente guiado con avance visible, porque cada paso depende del anterior:

1. Crear la entidad legal y las sedes.
2. Activar el paquete legal del país y revisar sus tasas.
3. Definir grupos de pago y calendario de periodos.
4. Revisar y completar conceptos, bases y cuentas contables.
5. Cargar calendarios de feriados, turnos y horarios.
6. Definir políticas: vacaciones, horas extra, redondeo, convención de días.
7. Personalizar plantilla de boleta.
8. Importar colaboradores con sus datos vigentes y saldos de vacaciones iniciales.
9. Asignar roles.
10. Corrida piloto en paralelo, comparada contra el sistema anterior, antes de poner el módulo en producción.

### Flujo B. Alta de un colaborador

Asistente de cinco pasos con guardado de borrador: datos personales y documentos, relación laboral (entidad, fecha de ingreso, contrato), puesto y organización (plaza, jefe, sede, centro de costo), compensación y pago (sueldo, grupo de pago, cuenta bancaria, afiliaciones), y revisión final con checklist de onboarding. Al terminar se crean `person`, `employee`, `assignment`, `compensation`, `contract` y las tareas de ingreso. Validaciones en línea: documento duplicado, plaza sin cupo, fecha anterior a un periodo cerrado.

### Flujo C. Cambio con fecha efectiva (ascenso, aumento, traslado)

Ficha del colaborador, pestaña "Compensación" o "Empleo", acción "Programar cambio". El usuario elige fecha efectiva y motivo; el sistema muestra el comparador antes y después, avisa si habrá retroactivo y envía a aprobación. Mientras tanto la línea de tiempo muestra el cambio como "Programado".

### Flujo D. Solicitud de vacaciones

Empleado elige rango en el calendario; el sistema valida saldo y días hábiles, y envía al jefe, que ve cobertura del equipo y aprueba o rechaza con comentario. RRHH solo interviene si hay excepción. Estados: borrador → pendiente → aprobada → tomada, o rechazada o cancelada. Cada paso notifica al siguiente actor y al empleado.

### Flujo E. Ciclo mensual de nómina (el flujo más importante)

| Paso | Pantalla | Actor | Acción principal | Salida |
|---|---|---|---|---|
| 1 | Panel de periodos | Operador | Abrir periodo | Periodo abierto |
| 2 | Asistencia y Ausencias | RRHH y jefes | Resolver excepciones, aprobar horas | Insumos aprobados |
| 3 | Novedades | Operador | Cargar o importar bonos, descuentos, variaciones | `payroll_input` |
| 4 | Panel de periodos | Operador | Cerrar novedades | Corte aplicado |
| 5 | Corrida | Operador | Calcular | Resultados |
| 6 | Revisión | Operador y supervisor | Resolver validaciones, revisar variaciones y casos | Corrida revisada |
| 7 | Revisión | Aprobador | Aprobar | Corrida aprobada |
| 8 | Pagos | Tesorería | Generar archivo y enviarlo | Pagos enviados |
| 9 | Boletas | Operador | Publicar | Boletas visibles al empleado |
| 10 | Contabilidad | Contador | Generar y revisar asiento | Asiento |
| 11 | Panel de periodos | Supervisor | Cerrar periodo | Periodo inmutable |

Regla de UX central: el botón primario cambia según el estado. En "Calculado" el botón dominante es "Aprobar corrida"; en "Aprobado" pasa a ser "Generar archivo de pago". Nunca se muestran juntos botones de etapas distintas.

### Flujo F. Corrección posterior al cierre (retroactivo)

Se detecta el error, se corrige el dato con fecha efectiva anterior (flujo C), el sistema avisa "afecta periodos cerrados: septiembre", el operador abre el asistente de retroactivo, ve el comparador (original vs recalculado, línea por línea), confirma con motivo y las diferencias aparecen como conceptos "Reintegro" en la corrida abierta, con referencia al periodo de origen.

### Flujo G. Liquidación final

Asistente de siete pasos: causa de salida y fecha, conceptos pendientes (sueldo, vacaciones truncas, proporcionales), indemnización y preaviso, descuentos (préstamos, activos), impuesto y regularización, revisión con comparación contra una estimación previa, emisión de documentos (liquidación, certificado de trabajo) y envío a pago.

### Flujo H. El empleado consulta y reclama

Entra a "Mis boletas", abre octubre, toca "Ver cálculo" en un concepto, y si algo no cuadra pulsa "Consultar a RRHH" con el concepto ya prellenado. RRHH recibe el caso (`hr_case`) con la boleta adjunta y responde dentro de la plataforma.

## Reglas de diseño específicas de RRHH y nómina

- **Siempre mostrar fecha efectiva.** Cualquier dato con vigencia muestra desde cuándo rige y hasta cuándo.
- **Estados visibles y acciones acordes.** Un periodo cerrado no muestra botones de edición; muestra por qué está bloqueado.
- **Transparencia del cálculo.** Todo monto debe poder explicarse en un clic: base, tasa, tope, fuente de la regla.
- **Vista previa antes de aplicar.** Cambios masivos, retroactivos y simulaciones se previsualizan y se confirman con el impacto explícito.
- **Deshacer no es reversa.** Antes de enviar a aprobar se puede descartar; después de aprobar solo se corrige con ajuste o reversa formal.
- **Motivo obligatorio en acciones sensibles.** Quedan en auditoría.
- **Datos sensibles protegidos.** Sueldo, cuenta, salud y documentos se enmascaran por defecto y se revelan por permiso; se registra cada revelado.
- **Permisos por rol, por campo y por alcance.** Un jefe ve su línea de mando y no ve sueldos; un analista ve una entidad legal y no otra.
- **Móvil para tareas cortas, escritorio para análisis.** Aprobar, consultar y solicitar funcionan bien en celular; conciliar y configurar no.
- **Mensajes de error accionables.** Qué pasó, qué empleado, cómo corregirlo, con un enlace directo.
- **Accesibilidad y multi-formato.** Contraste suficiente, no depender solo del color, números con formato local, multi-moneda e idioma.

## Patrones de UX para períodos

- **El período se ve en todos lados donde importa:** en la lista de períodos, en la tarjeta de nómina y
  en el detalle de cada corrida, con el mismo nombre de estado (nunca el código técnico).
- **Crear cuesta un clic:** «generar año» con vista previa de lo que crea y lo que omite; el formulario
  individual viene prellenado con el siguiente rango contiguo, la fecha de pago y el mes de declaración.
- **Lo prohibido no se puede intentar:** las acciones dependen del estado; si una no aplica, se explica
  por qué en vez de mostrar un error después.
- **Los errores nombran el conflicto:** «se cruza con el período X (del … al …); empieza el … o
  después», no «rango inválido».
- **Los avisos no bloquean lo que no es error:** un hueco entre períodos se avisa; un solape se impide.
- **La ventana de asistencia se esconde cuando es igual al período** y se muestra al desplegarla,
  porque dos rangos visibles a la vez parecen el mismo.
- **Las consecuencias se ven donde se deciden:** si se editan las fechas de un período con corrida
  calculada, la corrida muestra que quedó desactualizada y no deja aprobar hasta recalcular.
- **Cerrar no es un botón:** el período se cierra cuando se confirma el pago; reabrir, si existe, exige
  motivo y permiso.
