# Operaciones de almacén (WMS)

Cómo entra la mercadería, dónde se guarda, cómo se prepara y cómo sale. El inventario
([inventario/motor.md](../inventario/motor.md)) dice qué hay; el WMS decide y registra quién lo mueve,
desde dónde, hacia dónde y en qué orden.

Ubicación en el mapa: nivel 7 de [mapa.md](../mapa.md). Tablas: `picking_type`, `picking`, `package`,
`putaway_rule`, `wave`, `warehouse_task`, `shipment` en
[schema/logistica_schema.sql](../schema/logistica_schema.sql), secciones 5, 10 y 11.

## Tres niveles de madurez

| Nivel | Qué decide el sistema | Para quién |
|---|---|---|
| Sin ubicaciones internas | Nada: el stock está «en la tienda» | Tiendas, almacenes pequeños |
| Con ubicaciones | Dónde está cada cosa y desde dónde preparar | Almacenes medianos, trastiendas grandes |
| Dirigido por tareas | Qué hace cada operario, en qué orden y en qué ubicación | Centros de distribución, operadores logísticos |

El modelo de datos es el mismo en los tres ([patrones.md › 16](../patrones.md#16-el-mínimo-viable-es-un-subconjunto-del-modelo-completo)):
lo que cambia es cuántas decisiones toma el sistema y cuántas el operario.

## Flujo de entrada (inbound)

```
Aviso de despacho (ASN) → cita de muelle → recepción → control de calidad → etiquetado → ubicación (putaway)
```

1. **Aviso de despacho del proveedor:** qué viene, en qué bultos, con qué lotes. Permite preparar la
   recepción y recibir escaneando la etiqueta del pallet.
2. **Cita de muelle:** evita que diez camiones lleguen a la misma hora.
3. **Recepción:** contra la orden de compra o el aviso. Puede ser **ciega** (el operario cuenta sin ver
   lo esperado) o **con cantidades esperadas**. Las diferencias se registran con tolerancia: lo que
   falta queda pendiente o se cierra; lo que sobra se acepta o se rechaza según política.
4. **Control de calidad:** por muestreo o total; lo rechazado va a una ubicación de cuarentena o se
   devuelve.
5. **Etiquetado:** unidad de manipulación (pallet, caja) con su código (LPN o SSCC), lote y vencimiento.
6. **Ubicación dirigida (putaway):** el sistema propone dónde guardar según reglas.

### Reglas de ubicación

| Regla | Ejemplo |
|---|---|
| Por categoría o zona | Congelados a la cámara; químicos a su zona |
| Ubicación fija | Cada producto tiene su posición de picking |
| Ubicación dinámica (caótica) | Cualquier posición libre que cumpla capacidad y restricciones |
| Por rotación (ABC) | Lo que más sale, cerca del despacho y a la altura de la cintura |
| Por capacidad | Peso, volumen y número de pallets de la posición |
| Consolidar | Junto al mismo producto y lote si hay espacio |

**Cross-docking:** si la mercadería recibida ya tiene un pedido esperando, va directo de recepción a
despacho sin pasar por almacenamiento.

## Almacenamiento

- **Zonas de reserva y de picking:** la reserva guarda pallets completos; el picking, unidades sueltas o
  cajas. El reabastecimiento interno mueve de reserva a picking cuando la posición baja de su mínimo o
  antes de liberar una ola que la vaciaría.
- **Slotting:** reasignar posiciones según la rotación real. Lo más vendido en la «zona dorada»; lo que
  se vende junto, cerca.
- **Bloqueos:** una ubicación en conteo, dañada o en mantenimiento no recibe ni entrega.

## Flujo de salida (outbound)

```
Pedido liberado → ola → picking → consolidación → packing → etiqueta de envío → carga → despacho
```

1. **Liberación:** los pedidos con stock asignado y fecha de despacho se liberan al almacén.
2. **Ola:** agrupa pedidos que se preparan juntos (por ruta, transportista, hora de corte, zona).
3. **Picking:** el sistema genera tareas con la secuencia de ubicaciones más corta.
4. **Packing:** verificación por escaneo (lo preparado contra lo pedido), elección de caja, peso.
5. **Etiqueta de envío** y guía de remisión ([localizacion/peru.md › Guía de remisión](../localizacion/peru.md#guía-de-remisión)).
6. **Carga y despacho:** la confirmación del despacho es el movimiento que saca el stock y el que dispara
   la factura en muchos flujos.

### Estrategias de picking

| Estrategia | Cómo funciona | Cuándo conviene |
|---|---|---|
| Discreto (pedido a pedido) | Un operario prepara un pedido completo | Pocos pedidos grandes |
| Por lote (batch) | Un recorrido para varios pedidos; se separan después | Muchos pedidos pequeños con productos repetidos |
| Por zona | Cada operario prepara la parte de su zona; se consolida al final | Almacenes grandes o con zonas especiales (frío) |
| Por ola | Lotes de pedidos liberados por horario o ruta | Cortes de transportista |
| Cluster (carro con varias cajas) | Un recorrido llena varias cajas, una por pedido | Comercio electrónico |
| Put-wall | Picking por lote y luego reparto a casilleros por pedido | Alto volumen de pedidos de pocas unidades |
| Mercancía a la persona | Robots o transportadores traen la ubicación al operario | Automatización |

Medios de confirmación: escaneo con handheld (lo más común), luces en la ubicación (pick-to-light),
voz, o confirmación del robot. Confirmar por escaneo (de la ubicación y del producto) y no con un toque
en pantalla es lo que da la exactitud.

## Tareas

En un WMS dirigido, cada paso es una tarea (`warehouse_task`) con tipo (recibir, ubicar, reabastecer,
preparar, contar), prioridad, ubicación de origen y destino, y operario asignado.

- **Intercalado:** el operario que deja un pallet en reserva recibe, a la vuelta, una tarea de
  reabastecimiento cercana; menos recorridos vacíos.
- **Prioridad:** un pedido urgente o una posición de picking vacía pasan adelante.
- **Productividad:** cada tarea registra inicio y fin; de ahí salen las tasas por operario y por tipo.

## Paquetes y unidades de manipulación

- Un paquete (`package`) agrupa stock: pallet, caja, bolsa. Se mueve como unidad escaneando su código.
- Los paquetes se anidan: cajas en un pallet.
- Mover un pallet completo es un solo escaneo; abrirlo crea movimientos de su contenido.

## Devoluciones (logística inversa)

```
Autorización de devolución (RMA) → recepción → inspección → disposición
```

| Disposición | Destino |
|---|---|
| Vendible | Stock |
| Reacondicionar | Ubicación de reparación o reempaque |
| Devolver al proveedor | Ubicación de devolución a proveedores |
| Merma | Destrucción, con registro |

## Dispositivos de almacén

- **Handheld con lector:** el operario trabaja con una mano y escanea con la otra. Pantallas de una
  acción cada una, con botones grandes, confirmación por escaneo y aviso sonoro y vibración ante errores.
- **Etiquetas GS1-128:** un solo escaneo trae producto (identificador 01), lote (10), vencimiento (17),
  serie (21) o unidad de manipulación (00). El lector debe interpretarlas, no solo leer el número.
- **Impresoras de etiquetas** térmicas (lenguajes como ZPL) en recepción y despacho.
- **Sin red en el almacén:** las zonas sin cobertura (cámaras frías, rincones metálicos) son comunes; la
  aplicación de campo debe tolerar perder la conexión unos minutos.

## Indicadores

| Indicador | Qué mide |
|---|---|
| Tiempo de muelle a stock | De la llegada del camión a la mercadería ubicada y disponible |
| Ciclo del pedido | De la liberación al despacho |
| Líneas preparadas por hora | Productividad de picking |
| Exactitud de picking | Pedidos sin error de producto ni cantidad |
| OTIF | Pedidos entregados a tiempo y completos |
| Tasa de cumplimiento (fill rate) | Unidades despachadas sobre unidades pedidas |
| Exactitud de inventario (IRA) | Ubicaciones contadas sin diferencia |
| Ocupación | Posiciones usadas sobre disponibles |
