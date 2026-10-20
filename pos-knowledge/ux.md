# UX del POS

Vistas por rol, componentes, flujos y reglas de diseño propias de la caja. Son patrones del dominio, no
un sistema visual: el estilo lo pone cada producto.

Regla general de canal: el cajero trabaja de pie, con prisa, con una fila delante y con el escáner como
entrada principal; cada segundo y cada toque cuentan. El supervisor trabaja en el celular o en la misma
caja. La administración trabaja en escritorio con tablas grandes. La experiencia del almacén está en
[logistica-knowledge › ux.md](../logistica-knowledge/ux.md).

## Qué contiene cada vista

### Cajero

| Vista | Para qué sirve | Componentes clave |
|---|---|---|
| Venta | Armar el carrito lo más rápido posible | Escucha permanente del escáner, búsqueda predictiva, grilla táctil de favoritos y categorías, carrito con cantidades editables, total grande, cliente opcional |
| Cobro | Cobrar con uno o varios medios | Botones por medio, montos rápidos de billetes, vuelto calculado, estado del pinpad, saldo restante en pagos mixtos |
| Comprobante | Elegir boleta o factura y emitir | Campo de documento con validación inmediata, datos del cliente prellenados, envío por correo o mensajería |
| Devolución | Devolver con o sin ticket | Escaneo del QR del ticket, selección de líneas, neto a devolver por línea, medio de reembolso |
| Caja | Abrir, retirar, cerrar | Conteo por denominación, retiro parcial con sobre numerado, cierre ciego |
| Sincronización | Ver qué falta enviar | Pendientes, antigüedad del más viejo, estado de la red |

### Supervisor de tienda

| Vista | Para qué sirve | Componentes clave |
|---|---|---|
| Autorizaciones | Resolver lo que el cajero no puede | Solicitud en el propio POS con PIN del supervisor, o en su celular |
| Cajas | Sesiones abiertas y cierres | Diferencias por aprobar, cierre forzado, historial del cajero |
| Ventas del día | Saber cómo va la tienda | Ventas por hora frente al mismo día de la semana anterior, ticket promedio, anulaciones |
| Stock | Responder «¿hay en otra tienda?» | Disponible por tienda con la hora del dato |
| Excepciones | Ventas que llegaron tarde o con conflictos | Lista con la acción siguiente |

### Back-office

| Vista | Para qué sirve | Componentes clave |
|---|---|---|
| Precios y promociones | Qué se cobra | Listas con vigencia, cambios programados con zona horaria, simulador de promociones, calendario de campañas |
| Sesiones | Control de caja | Historial por tienda y fecha, diferencias, ajustes con motivo, asiento |
| Comprobantes | Estado fiscal | Pendientes con días que quedan, rechazados con su causa, huecos de numeración |
| Conciliación | Tarjetas y billeteras | Lotes del pinpad y abonos del adquirente contra ventas |
| Configuración | Reglas | Tiendas, cajas, series, medios de pago, topes por rol, impuestos (de la localización, solo lectura) |

## Biblioteca de componentes

| Componente | Dónde se usa | Detalle importante |
|---|---|---|
| Carrito | Caja | Última línea visible siempre; cantidad editable con teclado numérico; promociones aplicadas a la vista |
| Escucha de escáner | Caja | Distingue escaneo de tecleo; nunca pierde un escaneo por un diálogo abierto |
| Búsqueda predictiva | Caja, back-office | Por nombre, código, código interno; resultados locales instantáneos |
| Teclado numérico | Caja | Cantidades, montos, PIN |
| Pantalla de cobro | Caja | Montos rápidos de billetes; vuelto en grande; saldo restante en pagos mixtos |
| Selector de cliente | Caja | Documento con validación de dígito; creación rápida; boleta o factura según el documento |
| Diálogo de autorización | Caja | PIN del supervisor, motivo obligatorio, sin salir de la venta |
| Indicador de red y sincronización | Caja | Discreto en línea, evidente sin red, con número de pendientes |
| Estado del comprobante | Caja, back-office | Aceptado, pendiente, observado, rechazado, con la acción siguiente |
| Declaración ciega | Caja | Conteo por denominación; la diferencia aparece solo después de confirmar |
| Drawer de auditoría | Cualquier registro | Quién hizo qué y cuándo, sin salir de la pantalla |

## Flujos de usuario paso a paso

### Flujo A. Venta rápida en efectivo

Escanear, escanear, escanear, «Cobrar», tocar el billete con que paga, entregar el vuelto. Sin diálogos
en el camino feliz. El comprobante se emite y se imprime solo; la impresión no bloquea la siguiente
venta.

### Flujo B. Cobro con dos medios

En la pantalla de cobro el cajero elige tarjeta e ingresa el importe parcial; el pinpad autoriza; el
saldo restante se cobra en efectivo. Si la tarjeta es rechazada, la venta sigue abierta con el saldo
completo. Si el cliente abandona, el sistema anula la autorización ya aprobada antes de cerrar.

### Flujo C. Devolución con ticket

Escanear el QR del ticket, marcar las líneas devueltas, ver el neto a devolver por línea, elegir
destino del stock (vendible o inspección), reembolsar al medio original, emitir la nota de crédito. Si
la política exige autorización, el supervisor la da en la misma pantalla.

### Flujo D. Apertura y cierre ciego

Apertura: contar el fondo por denominación; si no coincide con el cierre anterior, registrar la
diferencia antes de vender. Cierre: sincronizar pendientes, declarar efectivo contado y totales de cada
medio sin ver lo esperado; el sistema muestra la diferencia solo después de confirmar; fuera de
tolerancia, pide motivo y aprobación del supervisor.

### Flujo E. Cierre de tienda

El supervisor ve todas las sesiones de la jornada, cierra las olvidadas con arqueo, cuenta la bóveda,
prepara el depósito y revisa el reporte del día (medios de pago, anulaciones, descuentos autorizados,
diferencias, comprobantes pendientes).

## Reglas de diseño específicas

- **El escáner es la entrada principal.** Todo flujo de caja debe completarse escaneando, con el teclado
  y la pantalla táctil como respaldo.
- **Nada de red en el camino feliz.** Escanear, cobrar en efectivo y emitir funcionan con datos locales
  ([offline-y-dispositivos.md](offline-y-dispositivos.md#rendimiento)).
- **Estados visibles y acciones acordes.** El botón primario cambia según el estado de la sesión; nunca
  conviven botones de etapas distintas ([caja-y-turnos.md](caja-y-turnos.md#dónde-va-cada-cosa-en-la-interfaz)).
- **El cajero no ve lo esperado al cerrar.** El cierre ciego es una regla de UX, no solo de datos.
- **Autorización sin salir de la venta.** El supervisor autoriza en la misma pantalla; motivo
  obligatorio y registro.
- **El disponible lleva su hora.** «3 en Miraflores (hace 5 min)»; un número sin hora parece exacto.
- **Mensajes accionables.** «La boleta supera S/ 700: ingresa el DNI del cliente», no «error de
  validación».
- **Formato local.** Moneda, separadores y fechas del país; el ticket legible en blanco y negro.
