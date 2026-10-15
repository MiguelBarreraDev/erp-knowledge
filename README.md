# hr-knowledge

Base de conocimiento para entender, diseñar y construir un módulo de RRHH (HCM) profesional, con foco
en nómina. Es independiente de cualquier producto o cliente: lo que aquí está vale para cualquier
ERP multitenant que quiera competir con SAP, Workday, Oracle u Odoo.

## Qué hay

| Archivo | Para qué sirve | Léelo cuando… |
|---|---|---|
| [mapa-hcm.md](mapa-hcm.md) | Los submódulos de un HCM en orden de dependencia, menús, equivalencias con el mercado, orden de construcción | Empiezas, o necesitas ubicar algo en el todo |
| [core-hr.md](core-hr.md) | Persona, empleado, asignación, contrato, vigencias, ciclo de vida, plazas | Tocas datos del colaborador o cualquier dato con fecha efectiva |
| [tiempo-y-ausencias.md](tiempo-y-ausencias.md) | Asistencia, horas extra, ausencias, saldos de vacaciones | Algo de asistencia o vacaciones alimenta la nómina |
| [nomina/motor.md](nomina/motor.md) | Cómo calcula una nómina: configuración, pipeline, bases, prorrateos, impuesto, aportes, descuentos, tipos de corrida, retroactivos, liquidación | Diseñas o revisas el cálculo |
| [nomina/periodos.md](nomina/periodos.md) | Período de pago, ventana de insumos y período de cómputo; tipos, restricciones, estados, cómo lo hacen los grandes | Defines calendarios, cierres o cualquier cosa con «del / al» |
| [nomina/boleta.md](nomina/boleta.md) | La boleta como documento: contenido, canales, inmutabilidad, rectificación | Diseñas boletas o su entrega |
| [nomina/salidas-y-controles.md](nomina/salidas-y-controles.md) | Pagos, contabilidad, declaraciones, controles internos | Cierras el ciclo o diseñas auditoría |
| [nomina/casos-borde.md](nomina/casos-borde.md) | Checklist de situaciones difíciles y cómo se tratan | Revisas un diseño o un spec |
| [nomina/escenarios-de-prueba.md](nomina/escenarios-de-prueba.md) | Diez casos que, si los resuelves a mano y con el sistema, dominas el motor | Armas goldens o pruebas de regresión |
| [localizacion/peru.md](localizacion/peru.md) | Parámetros y reglas de Perú con fecha y fuente | Calculas algo legal en Perú |
| [ux.md](ux.md) | Vistas por rol, componentes, flujos y reglas de diseño propias de RRHH | Diseñas pantallas |
| [patrones.md](patrones.md) | Decisiones de diseño reutilizables y su porqué | Tomas una decisión de arquitectura |
| [schema/](schema/README.md) | El esquema PostgreSQL de referencia (`hr_schema.sql`) y sus pruebas | Necesitas el modelo de datos concreto |
| [glosario.md](glosario.md) | Términos y su equivalente en SAP, Workday, Oracle y Odoo | Una palabra no te queda clara |
| [skill/SKILL.md](skill/SKILL.md) | Instrucciones para que un agente use esta base | Configuras Claude, Cursor u otro agente |

## Reglas para que crezca sin desordenarse

1. **Un dato vive en un solo archivo.** Si algo ya está escrito, se enlaza; no se copia.
2. **Lo legal lleva fecha y fuente.** Todo valor legal indica desde cuándo rige, la norma y cuándo
   revisarlo. Sin eso no se agrega.
3. **Nada de clientes ni de proyectos.** Si un caso de un proyecto enseña algo, se escribe en
   genérico. Las decisiones de un producto concreto viven en el repo de ese producto.
4. **Se actualiza, no se acumula.** Al terminar una sesión de estudio o de diseño, lo nuevo se
   incorpora al archivo que corresponde. No se crean documentos por sesión.
5. **Ejemplo numérico siempre que se pueda**, con la aritmética verificada.
6. **Lo que no se sabe se marca** como «verificar» con la pregunta concreta, en vez de suponer.

## Cómo usarlo

- **Para estudiar:** sigue el orden de `mapa-hcm.md` › «Orden de estudio».
- **Para diseñar o revisar un requerimiento:** `patrones.md` y `nomina/casos-borde.md` son los
  checklists.
- **Con agentes:** instala la skill de `skill/SKILL.md`. El agente lee solo el archivo que el tema
  necesita.

## Aviso

Las reglas legales cambian por país y por año. Los valores de `localizacion/` están verificados a la
fecha que indica cada uno; antes de usarlos en producción, confírmalos con un especialista laboral o
tributario del país.
