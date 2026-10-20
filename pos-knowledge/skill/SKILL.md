---
name: pos
description: Conocimiento de punto de venta profesional (caja, sesiones y cierre ciego, venta, precios, promociones, impuestos, pagos, devoluciones, comprobantes electrónicos, operación sin red) desde la base pos-knowledge, con su esquema PostgreSQL de referencia. Usar al diseñar, revisar o explicar un POS, cierres de caja, boletas y facturas electrónicas o normativa SUNAT de ventas.
---

# Punto de venta

La fuente de verdad es la base de conocimiento `pos-knowledge` (por defecto en `~/dev/erp-knowledge/pos-knowledge`).
Antes de responder o diseñar, lee solo el archivo que el tema necesita:

| Tema | Archivo |
|---|---|
| Ubicar un submódulo, menús, equivalencias con Dynamics 365/Xstore/Odoo/Shopify/Square, orden de construcción | `mapa.md` |
| Revisar un diseño o un requerimiento | `patrones.md` y `casos-borde.md` |
| Venta en caja, precios, promociones, impuestos, pagos, devoluciones | `venta.md` |
| Sesión de caja, turnos, día de negocio, arqueo, cierre ciego, conciliación de tarjetas | `caja-y-turnos.md` |
| Caja sin red, sincronización, idempotencia, numeración por caja, hardware | `offline-y-dispositivos.md` |
| Comprobante como documento: ciclo de vida, notas, servicio fiscal | `comprobantes.md` |
| IGV, IGV reducido, ICBPER, boleta y factura, plazos, baja, redondeo, PCGE | `localizacion/peru.md` |
| Pantallas, flujos y reglas de UX de la caja | `ux.md` |
| Tablas, funciones, garantías y pruebas | `schema/README.md` y `schema/pos_schema.sql` |
| Un término o su equivalente en otro producto | `glosario.md` |

## Reglas

1. **No inventes valores legales.** Usa los de `localizacion/` con su fecha y fuente. Si el valor no
   está o está marcado «verificar», dilo y busca la fuente oficial vigente.
2. **Revisa contra los patrones.** Si un diseño rompe uno de `patrones.md` (por ejemplo, comparte una
   serie entre cajas, mezcla día de negocio con fecha de emisión o deja que la caja descuente su propio
   stock), señálalo con el número del patrón y el riesgo concreto.
3. **Separa lo genérico de lo del proyecto.** Esta base no guarda datos de clientes ni decisiones de un
   producto concreto; esas viven en el repo del producto.
4. **Ejemplos con números verificados.** Si das un ejemplo de impuesto, promoción o cierre de caja, haz
   la aritmética; si puedes, compruébalo con `schema/pruebas/`.
5. **Mantén la base.** Si aparece conocimiento nuevo y genérico, propón en qué archivo agregarlo, sin
   duplicar lo que ya existe (un dato vive en un solo archivo). Lo pendiente está en
   `mapa.md › Por profundizar` y en `schema/README.md › Lo que el esquema todavía no tiene`.
6. **Bases hermanas:** inventario, costos y almacén están en `logistica-knowledge` (skill `logistica`);
   comisiones, turnos de cajeros y descuentos por faltantes, en `hr-knowledge` (skill `hcm-nomina`).
