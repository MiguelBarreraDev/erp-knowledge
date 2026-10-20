# pos-knowledge

Base de conocimiento para entender, diseñar y construir un punto de venta (POS) profesional: caja,
sesiones, venta, precios, promociones, impuestos, pagos, devoluciones, comprobantes electrónicos y
operación sin red. Es independiente de cualquier producto o cliente: lo que aquí está vale para
cualquier ERP multitenant que quiera competir con Dynamics 365 Commerce, Oracle Xstore, Odoo o los POS
en la nube como Shopify, Square o Lightspeed.

Es hermana de [hr-knowledge](../hr-knowledge/README.md) y de
[logistica-knowledge](../logistica-knowledge/README.md), y sigue sus mismas reglas.

## Qué hay

| Archivo | Para qué sirve | Léelo cuando… |
|---|---|---|
| [mapa.md](mapa.md) | Los submódulos en orden de dependencia, menús, equivalencias con el mercado, orden de construcción | Empiezas, o necesitas ubicar algo en el todo |
| [patrones.md](patrones.md) | Dieciséis decisiones de diseño reutilizables y su porqué | Tomas una decisión de arquitectura o revisas un diseño |
| [venta.md](venta.md) | Precio, promociones, impuestos, pagos y devoluciones en caja | Diseñas o revisas la venta |
| [caja-y-turnos.md](caja-y-turnos.md) | Día de negocio, sesión y turno; arqueo, cierre ciego, conciliación, asiento | Defines aperturas, cierres o reportes diarios |
| [offline-y-dispositivos.md](offline-y-dispositivos.md) | Vender sin red, sincronizar sin duplicar, numeración por caja, hardware | Defines la arquitectura del POS |
| [comprobantes.md](comprobantes.md) | El comprobante como documento: ciclo de vida, notas, servicio fiscal | Diseñas la emisión electrónica |
| [localizacion/peru.md](localizacion/peru.md) | IGV, ICBPER, comprobantes, plazos, baja, redondeo, con fecha y fuente | Calculas o emites algo legal en Perú |
| [casos-borde.md](casos-borde.md) | Checklist de situaciones difíciles y cómo se tratan | Revisas un diseño o un spec |
| [ux.md](ux.md) | Vistas por rol, componentes, flujos y reglas de UX de la caja | Diseñas pantallas |
| [schema/](schema/README.md) | El esquema PostgreSQL de referencia del servidor (`pos_schema.sql`), su diagrama entidad-relación y sus pruebas | Necesitas el modelo de datos concreto |
| [glosario.md](glosario.md) | Términos y su equivalente en Dynamics 365 y Odoo | Una palabra no te queda clara |
| [skill/SKILL.md](skill/SKILL.md) | Instrucciones para que un agente use esta base | Configuras Claude, Cursor u otro agente |

## Reglas para que crezca sin desordenarse

1. **Un dato vive en un solo archivo.** Si algo ya está escrito, se enlaza; no se copia.
2. **Lo legal lleva fecha y fuente.** Todo valor legal indica desde cuándo rige, la norma y cuándo
   revisarlo. Sin eso no se agrega.
3. **Nada de clientes ni de proyectos.** Si un caso de un proyecto enseña algo, se escribe en
   genérico. Las decisiones de un producto concreto viven en el repo de ese producto.
4. **Se actualiza, no se acumula.** Al terminar una sesión de estudio o de diseño, lo nuevo se
   incorpora al archivo que corresponde. No se crean documentos por sesión.
5. **Ejemplo numérico siempre que se pueda**, con la aritmética verificada; si el esquema lo puede
   calcular, la prueba lo reproduce.
6. **Lo que no se sabe se marca** como «verificar» con la pregunta concreta, en vez de suponer.

## Cómo usarlo

- **Para estudiar:** sigue el orden de `mapa.md` › «Orden de estudio».
- **Para diseñar o revisar un requerimiento:** `patrones.md` y `casos-borde.md` son los checklists.
- **Para el modelo de datos:** `schema/README.md`; las pruebas reproducen los ejemplos de los documentos.
- **Con agentes:** instala la skill de `skill/SKILL.md`. El agente lee solo el archivo que el tema
  necesita.

## Relación con las bases hermanas

- **logistica-knowledge:** el POS publica efectos de stock con una clave única y el inventario los
  convierte en movimientos valorizados ([patrones.md › 10](patrones.md#10-el-pos-no-es-dueño-del-stock-lo-consume-y-lo-publica)).
- **hr-knowledge:** las comisiones de vendedores son novedades de nómina, los turnos de cajeros son
  tiempo y asistencia, y los faltantes de caja se descuentan solo con los límites legales.

## Aviso

Las reglas tributarias cambian por país y por año. Los valores de `localizacion/` están verificados a
la fecha que indica cada uno; antes de usarlos en producción, confírmalos con un especialista
tributario del país.
