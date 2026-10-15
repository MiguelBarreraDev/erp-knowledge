---
name: hcm-nomina
description: Conocimiento de RRHH (HCM) y nómina profesional desde la base hr-knowledge. Usar al diseñar, revisar o explicar módulos de RRHH, nómina, períodos, boletas, aportes o legislación laboral peruana.
---

# HCM y nómina

La fuente de verdad es la base de conocimiento `hr-knowledge` (por defecto en `~/dev/hr-knowledge`).
Antes de responder o diseñar, lee solo el archivo que el tema necesita:

| Tema | Archivo |
|---|---|
| Ubicar un submódulo, menús, equivalencias con SAP/Workday/Oracle/Odoo, orden de construcción | `mapa-hcm.md` |
| Persona, empleado, contrato, asignación, vigencias, ciclo de vida | `core-hr.md` |
| Asistencia, horas extra, ausencias, vacaciones | `tiempo-y-ausencias.md` |
| Cálculo de nómina, bases, prorrateos, impuesto, aportes, retroactivos, liquidación | `nomina/motor.md` |
| Período de pago, ventana de asistencia, período de cómputo, estados, «del / al» | `nomina/periodos.md` |
| Boleta: contenido, canales, emisión, rectificación | `nomina/boleta.md` |
| Pagos, contabilidad, declaraciones, controles | `nomina/salidas-y-controles.md` |
| Revisar un diseño o un requerimiento | `patrones.md` y `nomina/casos-borde.md` |
| Pruebas y goldens del motor | `nomina/escenarios-de-prueba.md` |
| Tasas, parámetros y reglas de Perú | `localizacion/peru.md` |
| Pantallas, flujos y reglas de UX | `ux.md` |
| Tablas y columnas concretas | `schema/README.md` y `schema/hr_schema.sql` |
| Un término | `glosario.md` |

## Reglas

1. **No inventes valores legales.** Usa los de `localizacion/` con su fecha y fuente. Si el valor no
   está o está marcado «verificar», dilo y busca la fuente oficial vigente.
2. **Revisa contra los patrones.** Si un diseño rompe uno de `patrones.md` (por ejemplo, mezcla período
   de pago con ventana de asistencia, o deja reglas solo en la pantalla), señálalo con el número del
   patrón y el riesgo concreto.
3. **Separa lo genérico de lo del proyecto.** Esta base no guarda datos de clientes ni decisiones de un
   producto concreto; esas viven en el repo del producto.
4. **Ejemplos con números verificados.** Si das un ejemplo de cálculo, haz la aritmética.
5. **Mantén la base.** Si en el trabajo aparece conocimiento nuevo y genérico, propón en qué archivo
   agregarlo, sin duplicar lo que ya existe (un dato vive en un solo archivo).
