# POS sin red y dispositivos

Una caja que no cobra cuando se cae internet pierde la venta, la cola y la confianza del cliente. Este
archivo describe qué debe vivir en la caja, cómo se sincroniza sin duplicar, qué no puede hacerse sin
red y el hardware con el que trabaja el POS.

Principios: [patrones.md › 1, 2 y 8](patrones.md#1-la-caja-vende-sin-red). Del lado del servidor:
`pos_order` y `pos_payment` con el UUID de la caja, `pos_sync_exception`, `document_series`,
`v_fiscal_number_gaps` y `v_catalog_changes` en [schema/pos_schema.sql](schema/pos_schema.sql).

## Arquitecturas

| Arquitectura | Cómo funciona | Ventaja | Costo |
|---|---|---|---|
| Solo en línea | Cada operación va al servidor | Simple | Sin red no se vende |
| Servidor de tienda | Un servidor local atiende a las cajas por la red de la tienda y sincroniza con la nube | Las cajas comparten stock y clientes aunque se caiga internet | Hardware y mantenimiento en cada tienda |
| Caja autónoma | Cada caja tiene su base local (aplicación nativa o web con almacenamiento local) y sincroniza sola | Sin infraestructura en tienda | Las cajas no se ven entre sí sin internet |

Los POS grandes de retail usan servidor de tienda o una combinación (base local en cada caja y servidor
de tienda opcional); los POS en la nube para pymes usan caja autónoma. Lo que no es aceptable para
retail serio es «solo en línea».

## Qué vive en la caja

| Dato | Cómo se mantiene |
|---|---|
| Catálogo, códigos de barras, precios, promociones, impuestos | Descarga inicial y luego cambios incrementales |
| Cambios de precio programados | Llegan antes de su vigencia, con fecha, hora y zona horaria de la tienda; la caja los aplica sola. Una fecha sin zona se interpreta en la del servidor: «1 de noviembre» en UTC son las 19:00 del 31 de octubre en Lima |
| Clientes frecuentes | Subconjunto local; el resto se busca cuando hay red |
| Cajeros y permisos | Credenciales locales (PIN con hash), roles, topes de descuento |
| Series fiscales y siguiente correlativo | Propias de la caja ([abajo](#numeración-sin-coordinación)) |
| Estado de la sesión | Fondo, movimientos, ventas de la sesión |
| Cola de salida | Ventas, pagos, movimientos de caja y comprobantes por enviar |

La sincronización de maestros es incremental (cambios desde la última versión recibida), con recarga
completa como respaldo, y cada paquete lleva versión para saber qué tiene cada caja.

## Qué no puede hacerse sin red (o solo con riesgo)

| Operación | Riesgo sin red | Tratamiento |
|---|---|---|
| Cobro con tarjeta | El adquirente necesita red | Sin red no se cobra con tarjeta, salvo autorización diferida con tope y riesgo asumido |
| Tarjeta de regalo, puntos, saldo a favor | Usar el mismo saldo dos veces en dos cajas | Solo en línea, o tope por operación sin red |
| Crédito del cliente | Superar el límite | Solo en línea, o tope reducido sin red |
| Stock de otra tienda | Prometer lo que no hay | Se muestra con la hora del último dato |
| Validación contra el padrón fiscal | Documento inexistente | Dígito verificador local y validación al sincronizar |
| Devolución de una venta de otra caja | La venta no está en esta caja | Requiere red o servidor de tienda |

## Cola de salida e idempotencia

1. Cada venta nace con un identificador generado en la caja (UUID) y un correlativo fiscal propio.
2. Al cobrarse, la venta completa (líneas, pagos, comprobante) se escribe en una cola local en la misma
   transacción que la cierra.
3. Un proceso envía la cola en orden, con reintentos y espera creciente.
4. El servidor inserta por identificador: si ya existe, responde «ya recibido» y no duplica
   ([patrones.md › 2](patrones.md#2-toda-operación-que-viaja-por-red-es-idempotente)).
5. La caja borra de la cola solo lo que el servidor confirmó.
6. La caja muestra siempre cuántas operaciones tiene pendientes y desde cuándo.

## Conflictos al sincronizar

Regla general: **una venta ya cobrada nunca se rechaza.** Se acepta y se marca la excepción.

| Conflicto | Tratamiento |
|---|---|
| Se vendió más de lo que había | Stock negativo con alerta ([logistica-knowledge › motor.md › Stock negativo](../logistica-knowledge/inventario/motor.md#stock-negativo)) |
| El precio cambió mientras la caja estaba sin red | La venta conserva el precio que aplicó; se reporta como excepción si la diferencia supera un umbral |
| La promoción ya había vencido | Igual que el precio |
| La misma serie vendida en dos cajas | Se aceptan ambas ventas y se abre una investigación |
| Un cliente editado en la caja y en el servidor | Se combina campo por campo; si chocan, gana el servidor y se registra |
| El correlativo ya existe en el servidor | No debería ocurrir con series por caja; si ocurre, es un incidente fiscal, no un conflicto de datos |

## Numeración sin coordinación

Cada caja tiene sus propias series de comprobantes (por ejemplo, una serie de boletas y otra de
facturas por caja). Así cada caja genera correlativos sin huecos ni duplicados sin preguntarle a nadie.

- La serie se asigna a la caja al registrarla y no se comparte.
- El correlativo se toma al emitir, en la misma transacción que cierra la venta.
- Reemplazar una caja dañada exige saber su último correlativo (está en el servidor si sincronizó; si
  no, en el respaldo local); la caja nueva recibe una serie nueva o continúa la anterior desde ese
  número.
- Una serie compartida por varias cajas obliga a pedir números al servidor, y entonces la caja deja de
  vender sin red ([patrones.md › 8](patrones.md#8-cada-caja-numera-sola)).

En Perú la serie identifica el tipo de comprobante y el emisor puede crear las que necesite
([localizacion/peru.md › Comprobantes](localizacion/peru.md#comprobantes-de-pago)).

## Hora y fecha

- El reloj del terminal se desvía. La caja registra su hora y el servidor la hora de recepción.
- La fecha de emisión del comprobante sale de la hora del terminal, así que la caja verifica la hora
  contra el servidor al abrir sesión y bloquea si la desviación supera unos minutos.
- El día de negocio sale de la sesión, no del reloj ([caja-y-turnos.md](caja-y-turnos.md#las-tres-cosas-que-no-hay-que-mezclar)).

## Comprobantes sin red

El comprobante se genera y se firma donde está el certificado (en la caja, en el servidor de tienda o
en la nube) y se envía a la autoridad dentro del plazo legal. Mientras el plazo lo permita, la caja
emite sin red y envía después. Si la caja no puede generar el comprobante electrónico en absoluto, la
ley prevé un procedimiento de contingencia ([localizacion/peru.md › Contingencia](localizacion/peru.md#contingencia)).

## Dispositivos

| Dispositivo | Conexión habitual | Detalle importante |
|---|---|---|
| Lector de código de barras | USB como teclado, o integrado en el equipo | La caja distingue un escaneo de un tecleo por la velocidad y el sufijo |
| Impresora térmica de tickets | USB, red o Bluetooth; comandos ESC/POS | 80 mm o 58 mm; imprime el QR del comprobante; la impresión no debe bloquear la venta |
| Gaveta de dinero | Conectada a la impresora; se abre con un pulso | Cada apertura sin venta queda registrada |
| Balanza | Serie o USB | Lee el peso en la caja; o etiqueta con código de peso variable en la sección |
| Pinpad o terminal de tarjetas | USB, red o Bluetooth, con el SDK del adquirente | Semi-integrado: el POS manda el importe y recibe el resultado |
| Visor para el cliente | Segunda pantalla | Muestra líneas, total y QR de pago |
| Pantalla de cocina (KDS) | Red | Modo restaurante |

En un POS web, el navegador no habla directamente con todo el hardware: se usa un agente local (una
pequeña aplicación o caja de dispositivos en la tienda) o las API del navegador para USB, serie y
dispositivos de entrada, según el equipo.

## Seguridad de la caja

- **Registro del terminal:** cada caja se registra con un token propio; una caja robada se revoca desde
  el back-office.
- **Cajeros:** ingreso rápido con PIN o tarjeta; bloqueo de pantalla por inactividad.
- **Autorizaciones de supervisor:** descuentos sobre el tope, anulaciones, devoluciones sin ticket,
  apertura de gaveta sin venta; con PIN del supervisor y registro.
- **Datos de tarjeta:** el POS no los almacena ni los ve (pinpad semi-integrado, cifrado de punto a
  punto).
- **Datos locales:** cifrados en reposo, con lo mínimo necesario de clientes.

## Rendimiento

La caja trabaja contra sus datos locales: escanear y ver la línea debe sentirse instantáneo
(décimas de segundo) y cobrar en efectivo no debe esperar a la red. Cualquier llamada al servidor en el
camino de una venta normal es un error de diseño.
