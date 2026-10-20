---
name: logistica
description: Conocimiento de logística profesional (inventario, kardex, valorización, almacén/WMS, compras, reposición, pedidos, guías de remisión) desde la base logistica-knowledge, con su esquema PostgreSQL de referencia. Usar al diseñar, revisar o explicar módulos de inventario, costos, almacén, compras o normativa SUNAT de inventario y traslado.
---

# Logística

La fuente de verdad es la base de conocimiento `logistica-knowledge` (por defecto en
`~/dev/erp-knowledge/logistica-knowledge`). Antes de responder o diseñar, lee solo el archivo que el tema necesita:

| Tema | Archivo |
|---|---|
| Ubicar un submódulo, menús, equivalencias con SAP/Oracle/Dynamics 365/Odoo/NetSuite, orden de construcción | `mapa.md` |
| Revisar un diseño o un requerimiento | `patrones.md` y `casos-borde.md` |
| Producto, unidades, ubicaciones, movimientos, físico/reservado/disponible, reservas, lotes, conteos, merma | `inventario/motor.md` |
| Costo promedio, PEPS, estándar, kardex, costos de importación, devoluciones, asientos, cierre | `inventario/valorizacion.md` |
| Recepción, putaway, picking, packing, despacho, olas, tareas, handhelds | `almacen/operaciones.md` |
| Órdenes de compra, tres vías, mínimo y máximo, punto de reorden, stock de seguridad | `compras-y-abastecimiento.md` |
| Guía de remisión, métodos de costo permitidos, registros de inventario, PCGE | `localizacion/peru.md` |
| Pantallas, flujos y reglas de UX de almacén y compras | `ux.md` |
| Tablas, funciones, garantías y pruebas | `schema/README.md` y `schema/logistica_schema.sql` |
| Un término o su equivalente en otro producto | `glosario.md` |

## Reglas

1. **No inventes valores legales.** Usa los de `localizacion/` con su fecha y fuente. Si el valor no
   está o está marcado «verificar», dilo y busca la fuente oficial vigente.
2. **Revisa contra los patrones.** Si un diseño rompe uno de `patrones.md` (por ejemplo, guarda el stock
   como un número editable, calcula el costo al reportar o deja que un canal escriba saldos), señálalo
   con el número del patrón y el riesgo concreto.
3. **Separa lo genérico de lo del proyecto.** Esta base no guarda datos de clientes ni decisiones de un
   producto concreto; esas viven en el repo del producto.
4. **Ejemplos con números verificados.** Si das un ejemplo de costo o de reposición, haz la aritmética;
   si puedes, compruébalo con `schema/pruebas/`.
5. **Mantén la base.** Si aparece conocimiento nuevo y genérico, propón en qué archivo agregarlo, sin
   duplicar lo que ya existe (un dato vive en un solo archivo). Lo pendiente está en
   `mapa.md › Por profundizar` y en `schema/README.md › Lo que el esquema todavía no tiene`.
6. **Bases hermanas:** el punto de venta está en `pos-knowledge` (skill `pos`); RRHH y nómina en
   `hr-knowledge` (skill `hcm-nomina`).
