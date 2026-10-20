# Mapa de un POS

Los submódulos de un punto de venta (POS) profesional, en orden de dependencia, con su contenido, sus
menús y su equivalente en el mercado. Es la puerta de entrada al resto de esta base.

- **Regla de lectura:** los submódulos dependen unos de otros. No se vende sin catálogo, precios e
  impuestos; no se cobra sin una caja abierta; no se termina una venta sin comprobante. Se estudia y se
  construye en ese orden.
- **Modelo de datos:** las tablas citadas están en [schema/pos_schema.sql](schema/pos_schema.sql), el
  esquema del servidor. La caja tiene además su base local ([offline-y-dispositivos.md](offline-y-dispositivos.md)).
- **El stock no es del POS:** el POS consume y publica; el inventario, su costo y el almacén están en
  [logistica-knowledge](../logistica-knowledge/README.md).

## Índice

1. [Mapa en capas (orden de dependencia)](#1-mapa-en-capas-orden-de-dependencia)
2. [Cada submódulo en detalle](#2-cada-submódulo-en-detalle)
3. [Cómo se traduce a menús](#3-cómo-se-traduce-a-menús)
4. [Equivalencias con el mercado](#4-equivalencias-con-el-mercado)
5. [Orden de estudio y de construcción](#5-orden-de-estudio-y-de-construcción)
6. [Por profundizar](#6-por-profundizar)

---

## 1. Mapa en capas (orden de dependencia)

| Nivel | Submódulo | Pregunta que responde | Depende de |
|---|---|---|---|
| 0 | Plataforma | ¿Quién puede hacer qué, cómo se numera, cómo se sincroniza y cómo se registra? | — |
| 1 | Estructura | ¿Qué empresas, establecimientos, tiendas, cajas y series hay? | 0 |
| 2 | Catálogo de venta | ¿Qué se vende, en qué unidad y con qué código? | 0 |
| 3 | Impuestos | ¿Qué impuesto lleva cada producto en cada fecha? | 1, 2 |
| 4 | Precios y promociones | ¿A cuánto se vende, a quién, cuándo y con qué descuento? | 2, 3 |
| 5 | Clientes y saldos | ¿Quién compra y qué saldo tiene (crédito, tarjeta de regalo, puntos)? | 0 |
| 6 | Medios de pago | ¿Con qué se puede pagar en cada tienda? | 1 |
| 7 | **Caja y sesiones** | ¿Qué dinero entró y salió de cada caja, quién respondía y cuadra? | 1, 6 |
| 8 | **Venta** | ¿Qué se vendió, a cuánto, con qué impuesto y cómo se pagó? | 2–7 |
| 9 | Devoluciones y cambios | ¿Qué se devuelve, a cuánto y a qué medio? | 8 |
| 10 | **Comprobantes** | ¿Qué documento legal respalda cada venta y cada devolución? | 8, 9 |
| 11 | Integraciones | ¿Qué recibe el inventario, la contabilidad, la nómina y la tienda en línea? | 8–10 |
| 12 | Analítica | ¿Cuánto se vende por tienda, hora, vendedor y medio, y qué se pierde? | Todo |
| Transversal | Operación sin red y dispositivos | ¿Cómo sigue vendiendo la caja sin internet y con qué hardware? | Todo |

> La operación sin red no es un submódulo: es una **propiedad** de toda la caja. Cada nivel decide qué
> vive en la caja y qué solo en el servidor.

---

## 2. Cada submódulo en detalle

### Nivel 0. Plataforma

- **Contenido:** usuarios, roles y topes por rol, aprobaciones del supervisor, numeración, auditoría,
  sincronización de maestros por versión, registro de cajas.
- **Tablas:** `pos_user`, `pos_role_limit`, `pos_setting`, `legal_parameter`, `audit_log`,
  `catalog_version_seq` (y `v_catalog_changes`).

### Nivel 1. Estructura

- **Conceptos:** empresa (contribuyente), establecimiento (dirección declarada ante la autoridad),
  tienda (zona horaria, hora de inicio de la jornada, lista de precios), caja registrada con su token,
  series de comprobantes por caja.
- **Tablas:** `company`, `establishment`, `store`, `pos_terminal`, `document_series`.

### Nivel 2. Catálogo de venta

- **Conceptos:** producto vendible, tipo (con stock, consumible, servicio, kit, tarjeta de regalo),
  categoría de afectación del impuesto, códigos de barras (incluidos los de balanza), restricciones de
  venta (edad, horario).
- **Tablas:** `product_category`, `uom`, `product`, `product_barcode`, `product_kit_line`.
- El catálogo completo (variantes, unidades de compra, costos) es de logística; el POS replica lo que
  necesita para vender.

### Nivel 3. Impuestos

- **Conceptos:** categoría de afectación en el producto, impuesto porcentual incluido en el precio
  (IGV), impuesto por unidad (bolsas), tasa con vigencia por país o especial por empresa.
- **Tablas:** `tax_category`, `tax`, `tax_rate`, `tax_category_tax`, `product_tax`.
- Reglas de Perú: [localizacion/peru.md](localizacion/peru.md).

### Nivel 4. Precios y promociones

Detalle en [venta.md › Cómo se calcula una línea](venta.md#cómo-se-calcula-una-línea).

- **Conceptos:** lista de precios con vigencia y por cantidad, cambios programados, promociones
  (porcentaje, NxM, combos, umbral, cupones, por medio de pago), reglas de combinación, prorrateo.
- **Tablas:** `pricelist`, `pricelist_item`, `promotion`, `promotion_product`, `promotion_store`,
  `coupon`.

### Nivel 5. Clientes y saldos

- **Conceptos:** cliente con documento (define boleta o factura), lista de precios del cliente, límite
  de crédito, tarjeta de regalo y crédito como libros mayores.
- **Tablas:** `customer`, `customer_credit_ledger`, `gift_card`, `gift_card_ledger`.

### Nivel 6. Medios de pago

- **Conceptos:** efectivo (vuelto, redondeo), tarjeta con pinpad, billetera QR, transferencia, tarjeta
  de regalo, crédito; cuáles exigen red; medios aceptados por tienda.
- **Tablas:** `payment_method`, `store_payment_method`.

### Nivel 7. Caja y sesiones

Detalle en [caja-y-turnos.md](caja-y-turnos.md).

- **Conceptos:** día de negocio, sesión, turno del cajero, fondo inicial, retiros parciales, ingresos de
  sencillo, caja chica, cierre ciego, diferencias con aprobación, depósito, conciliación de tarjetas.
- **Tablas:** `business_day`, `pos_session`, `pos_session_status_log`, `cash_movement`,
  `session_declaration`, `card_settlement`, `card_settlement_line`.

### Nivel 8. Venta

Detalle en [venta.md](venta.md).

- **Conceptos:** venta con id generado en la caja, líneas con precio de lista, descuentos e impuestos
  guardados, pagos mixtos, vendedor, estados.
- **Tablas:** `pos_order`, `pos_order_line`, `pos_order_line_tax`, `pos_order_line_promotion`,
  `pos_payment`, `pos_sync_exception`.

### Nivel 9. Devoluciones y cambios

Detalle en [venta.md › Devoluciones](venta.md#devoluciones-cambios-y-anulaciones).

- **Conceptos:** devolución con ticket al neto pagado, sin ticket con supervisor, al mismo medio,
  cambio de producto, destino del stock devuelto.
- **Tablas:** `pos_order` con `refund_of_order_id`, `pos_order_line.refunded_line_id`,
  `v_order_refundable`.

### Nivel 10. Comprobantes

Detalle en [comprobantes.md](comprobantes.md) y [localizacion/peru.md](localizacion/peru.md).

- **Conceptos:** factura, boleta, notas de crédito y débito, serie por caja, correlativo sin huecos,
  envío a la autoridad, baja, contingencia.
- **Tablas:** `fiscal_document`, `fiscal_document_line`, `fiscal_submission`, `fiscal_daily_summary`,
  `fiscal_daily_summary_item`.

### Nivel 11. Integraciones

| Con | Qué se envía | Tabla |
|---|---|---|
| Inventario | Salidas y devoluciones de stock, con clave única | `stock_effect` ([logistica-knowledge](../logistica-knowledge/inventario/motor.md)) |
| Inventario (de vuelta) | Disponible por tienda, con su hora | `store_stock_level` |
| Contabilidad | Asiento resumen por sesión | `session_journal_entry`, `session_journal_line` |
| Nómina | Comisiones de vendedores | `commission_result` ([hr-knowledge](../hr-knowledge/schema/hr_schema.sql)) |
| Tienda en línea | Pedidos que se retiran o se pagan en tienda | Venta con origen web |

### Nivel 12. Analítica

- **Contenido:** ventas por tienda, hora, cajero, vendedor y medio de pago; ticket promedio; unidades por
  ticket; anulaciones, devoluciones y descuentos autorizados; diferencias de caja; comprobantes
  pendientes.
- **Datos:** `v_daily_sales`, `v_salesperson_net_sales`, `v_session_close`, `v_fiscal_pending`.

---

## 3. Cómo se traduce a menús

### Back-office del POS

```
Inicio

Tiendas y cajas
  Operación:  Tiendas · Cajas registradas · Series
  Config.:    Establecimientos · Horarios y jornada · Dispositivos

Catálogo de venta
  Operación:  Productos · Códigos de barras · Combos
  Config.:    Categorías · Categorías de afectación · Impuestos

Precios y promociones
  Operación:  Listas de precios · Cambios programados · Promociones · Cupones
  Reportes:   Efecto de promociones en el margen

Caja
  Operación:  Sesiones · Movimientos de efectivo · Diferencias por aprobar
  Procesos:   Cierre de tienda · Conciliación de tarjetas · Contabilización de sesiones
  Reportes:   Diferencias por cajero · Medios de pago · Depósitos

Ventas
  Operación:  Ventas · Devoluciones · Excepciones de sincronización
  Reportes:   Ventas por tienda y hora · Vendedores · Anulaciones y descuentos

Comprobantes
  Operación:  Emitidos · Pendientes de envío · Rechazados · Notas
  Procesos:   Reenvío · Resumen diario · Baja
  Reportes:   Huecos de numeración · Plazos

Clientes y saldos
  Operación:  Clientes · Tarjetas de regalo · Cuentas corrientes

Configuración global
  Usuarios y roles · Topes por rol · Medios de pago · Integraciones · Auditoría
```

### Aplicaciones de campo

| Caja (cajero) | Supervisor (celular o caja) |
|---|---|
| Vender | Ventas del día |
| Cobrar | Autorizar descuentos, anulaciones, devoluciones sin ticket |
| Devolver | Cajas abiertas y diferencias |
| Buscar cliente o ticket | Cierre de tienda |
| Caja: abrir, retirar, cerrar | Stock de la tienda y de otras tiendas |
| Estado de sincronización | Excepciones de sincronización |

---

## 4. Equivalencias con el mercado

| Concepto propio | Dynamics 365 Commerce | Oracle Retail Xstore | Odoo Point of Sale | Shopify POS | Square / Lightspeed |
|---|---|---|---|---|---|
| Caja | Register (Store Commerce) | Register / workstation | Point of sale (configuración) | Location + device | Device / register |
| Sesión de caja | Shift | Till session | POS session | Cash tracking session | Cash drawer session |
| Venta | Transaction | Transaction | POS order | Order | Sale |
| Cierre ciego | Blind close | Till count | Closing control | Cash count | Close-of-day count |
| Operación sin red | Offline database por caja | Base local en la caja y en la tienda | Navegador con datos locales | Limitada | Limitada |

### Lectura competitiva

- **Dynamics 365 Commerce y Oracle Xstore:** POS de retail grande: sin red de verdad, cajón por cajero,
  promociones complejas, a cambio de infraestructura e implementación caras.
- **Odoo:** POS integrado con inventario y contabilidad en un solo modelo, simple de poner en marcha; el
  modo sin red y el volumen de tiendas grandes son sus límites.
- **Shopify, Square, Lightspeed, Toast:** la mejor experiencia de caja y hardware listo, a cambio de
  localización fiscal latinoamericana débil, inventario superficial y poca configurabilidad.
- **Espacio para competir (en el medio):**
  - Comprobantes electrónicos nativos, con numeración por caja que no depende de la red.
  - Caja que vende sin red de verdad y sincroniza sin duplicar.
  - Control de caja serio (cierre ciego, aprobaciones, conciliación de tarjetas) para pymes.
  - Integración real con un inventario contable correcto.

> Las equivalencias son de nomenclatura general y pueden variar por versión y edición de cada producto.

---

## 5. Orden de estudio y de construcción

| # | Etapa | Niveles |
|---|---|---|
| 1 | Plataforma: usuarios, topes, numeración, auditoría | 0 |
| 2 | Tiendas, cajas, series, catálogo e impuestos | 1, 2, 3 |
| 3 | Precios con vigencia, medios de pago | 4, 6 |
| 4 | Sesión de caja con cierre ciego | 7 |
| 5 | Venta simple con efectivo y tarjeta | 8 |
| 6 | Comprobantes y su envío | 10 |
| 7 | Devoluciones con nota de crédito | 9 |
| 8 | Operación sin red | Transversal |
| 9 | Integraciones con inventario y contabilidad | 11 |
| 10 | Promociones, clientes y saldos, analítica | 4, 5, 12 |

### Fases de producto sugeridas

| Fase | Alcance |
|---|---|
| MVP | Una empresa con varias tiendas; catálogo e impuestos; precios por tienda; sesión con cierre ciego; efectivo, tarjeta y QR; boleta y factura electrónica; devoluciones con nota de crédito; sin red básico; publicación de stock; reporte diario |
| Fase 2 | Promociones combinables y cupones; tarjetas de regalo y crédito; conciliación de tarjetas; asiento de la sesión; resumen diario y baja; comisiones; retiro en tienda de pedidos web |
| Fase 3 | Fidelización; autoservicio de caja; modo restaurante; cobro con el teléfono (tap to pay); analítica avanzada |

---

## 6. Por profundizar

Temas que esta base todavía no cubre a fondo. Cuando se estudien, se escriben en su archivo y se
quitan de aquí.

- Motor de promociones en detalle: orden, combinación y casos de empate, con pruebas.
- Modo restaurante: mesas, comandas, cuentas divididas, propinas, pantalla de cocina, recetas.
- Fidelización: puntos, niveles y su pasivo contable.
- Pagos con tarjeta en profundidad: EMV, tokenización, PCI DSS, liquidación del adquirente.
- Contingencia fiscal y comunicación de baja de punta a punta.
- Localizaciones distintas de Perú.
