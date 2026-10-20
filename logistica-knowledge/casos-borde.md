# Casos borde

Checklist para revisar un diseño, un requerimiento o una implementación de logística. Si un caso no
tiene respuesta, el diseño está incompleto. El porqué de cada tratamiento está en el archivo enlazado y
en [patrones.md](patrones.md). Los marcados con ✔ los prueba [schema/pruebas/](schema/README.md#cargarlo-y-probarlo).

## Inventario

| Situación | Tratamiento esperado |
|---|---|
| ✔ Venta de un canal con stock cero en el sistema | Se acepta en la ubicación que admite negativo (piso de venta); alerta; costo provisional que se corrige al recibir |
| ✔ Salida mayor al stock en un almacén | Bloqueada (`STOCK_NEGATIVE_NOT_ALLOWED`) salvo permiso puntual con motivo |
| ✔ Reserva mayor a lo disponible | Bloqueada (`RESERVE_EXCEEDS_STOCK`); se reserva lo que hay y el resto queda pendiente |
| ✔ La misma venta llega dos veces desde la integración | Un solo movimiento por clave externa |
| ✔ Producto con lote movido sin lote | Bloqueado (`LOT_REQUIRED`) |
| ✔ Lote vencido en stock | No se reserva ni se vende; aparece en vencimientos |
| ✔ Conteo con movimientos durante el conteo | Foto al iniciar y diferencia contra la foto más los movimientos posteriores |
| Diferencia de conteo grande | Recuento antes de ajustar; ajuste con motivo y aprobación por umbral de cantidad o de valor |
| Retiro de un lote del mercado | Trazabilidad del lote a todos los clientes y tiendas; bloqueo del stock restante |
| Venta de mostrador sobre stock reservado para un pedido | Se acepta; el quant queda sobre-reservado (`v_quant_over_reserved`) y el pedido se reasigna |
| La misma serie vendida dos veces (canales sin red) | Se aceptan ambas; la serie aparece en `v_serial_anomalies` para investigar |
| Cambiar la unidad base de un producto con stock | No se permite; producto nuevo o migración con ajuste formal |
| Transferencia que llega incompleta | La diferencia queda en tránsito hasta investigar; ajuste con responsable |
| Kit vendido | Se descuentan sus componentes; disponibilidad del kit = mínimo entre componentes |
| Mercadería de terceros (consignación) en el almacén | Suma al físico del propietario, no al disponible ni al valor; no se reserva |
| ✔ Movimiento con fecha de un mes cerrado | Bloqueado (`INVENTORY_PERIOD_LOCKED`); se registra en el período abierto |

## Costos

| Situación | Tratamiento esperado |
|---|---|
| ✔ Factura del proveedor con otro precio cuando ya se vendió parte | La diferencia se reparte entre costo de ventas (lo vendido) e inventario (lo que queda) |
| ✔ Flete o arancel que llega después de recibir | Se reparte entre las recepciones por peso, volumen, valor o cantidad |
| ✔ Devolución de cliente | Reingresa al costo con que salió en la venta original, no al costo de hoy |
| ✔ Entrada después de vender en negativo (promedio) | Corrección del costo provisional de lo vendido a costo de ventas |
| ✔ Cantidad en cero con valor residual de céntimos | La última salida se lleva todo el valor restante |
| Devolución a proveedor con costo promedio | Al promedio vigente o al costo de la recepción original; política fija |
| Cambiar el método de costo con stock | Revalorización formal en una fecha; en Perú, con autorización de SUNAT |
| Compra en moneda extranjera | Recepción al tipo de cambio de su fecha; la diferencia con el pago es resultado financiero |
| Inventario a un precio de venta menor que su costo | Estimación por valor neto realizable, sin mover stock |
| ✔ Valor del inventario distinto del saldo contable | Error de cierre: `v_valuation_check` debe dar cero |

## Almacén, pedidos y compras

| Situación | Tratamiento esperado |
|---|---|
| ✔ Llega menos de lo pedido | Se recibe lo que llegó; el resto queda como pendiente (backorder) o se cierra |
| Llega más de lo pedido | Tolerancia por proveedor o categoría; lo que sobra se acepta o se rechaza |
| ✔ Orden de compra sobre el límite creada y aprobada por la misma persona | Bloqueada (`PO_SELF_APPROVAL`) |
| ✔ Factura con precio fuera de tolerancia | Tres vías en `price_mismatch`; el pago se bloquea hasta aprobar |
| ✔ Regla de reorden | Calculada sobre la posición (físico + entrante − saliente), no sobre el físico |
| Pedido que un solo almacén no puede completar | División del envío o espera, según política del cliente y del canal |
| Tienda y web venden del mismo stock | Stock de seguridad por canal y prometible por canal |
| Posición de picking vacía al liberar una ola | Tarea de reabastecimiento prioritaria antes de liberar |
| Producto escaneado distinto al de la tarea | Bloqueo con aviso sonoro; no se confirma con un toque |
| Reserva de un pedido web no pagado | Expira y libera el stock |
| Proveedor que entrega tarde de forma sistemática | El tiempo de entrega real (no el pactado) alimenta el punto de reorden |

## Traslado (Perú)

| Situación | Tratamiento esperado |
|---|---|
| Transferencia entre almacenes por vía pública | Guía de remisión con motivo «traslado entre establecimientos de la misma empresa» |
| Despacho de una venta | Guía de remisión de venta emitida antes de iniciar el traslado |
| Traslado con transporte de un tercero | GRE remitente y GRE del transportista |
| Mercadería que vuelve porque el cliente no la recibió | Movimiento de devolución y guía de retorno; el pedido queda pendiente |
