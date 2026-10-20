# UX de logística

Vistas por rol, componentes, flujos y reglas de diseño propias del almacén, las compras y el inventario.
Son patrones del dominio, no un sistema visual: el estilo lo pone cada producto.

Regla general de canal: el almacenero trabaja de pie, con prisa, con una mano ocupada y con el escáner
como entrada principal; cada segundo y cada toque cuentan. Compras, contabilidad y administración
trabajan en escritorio con tablas grandes y mucho contexto. El jefe de almacén alterna entre el tablero
y el piso. La experiencia de la caja está en [pos-knowledge › ux.md](../pos-knowledge/ux.md).

## Qué contiene cada vista

### Almacenero (handheld)

| Vista | Para qué sirve | Componentes clave |
|---|---|---|
| Mis tareas | Saber qué hacer ahora | Lista priorizada; una tarea a la vez |
| Recibir | Registrar lo que llega | Escaneo de pallet o producto, cantidad, lote y vencimiento leídos de la etiqueta |
| Ubicar | Guardar donde el sistema indica | Ubicación sugerida en grande; confirmación escaneando la ubicación |
| Preparar | Picking | Secuencia de ubicaciones; producto y cantidad en grande; confirmación por escaneo |
| Contar | Conteo cíclico o de inventario | Conteo ciego por ubicación |
| Consultar | Qué hay en una ubicación, dónde está un producto | Un escaneo, una respuesta |

### Jefe de almacén

| Vista | Para qué sirve | Componentes clave |
|---|---|---|
| Tablero del día | Ver si se llega a los cortes | Olas por estado, tareas atrasadas, pedidos en riesgo por hora de corte |
| Excepciones | Resolver lo que se trabó | Diferencias de recepción, ubicaciones vacías, stock negativo, lotes por vencer |
| Ajustes por aprobar | Controlar la merma | Comparador de conteo con valor de la diferencia, motivo, historial de la ubicación |
| Productividad | Dimensionar el turno | Líneas por hora por operario y por tipo de tarea |

### Comprador

| Vista | Para qué sirve | Componentes clave |
|---|---|---|
| Sugerencias de reposición | Decidir qué pedir hoy | Productos bajo el punto de reorden con la cantidad propuesta, agrupados por proveedor, editables |
| Órdenes de compra | Seguimiento | Estado, fecha prometida, recibido y facturado por línea |
| Conciliación | Liberar pagos | Tres vías con las diferencias resaltadas y la tolerancia aplicada |
| Proveedores | Evaluar | Cumplimiento real de plazo y cantidad, precios vigentes |

### Back-office

| Vista | Para qué sirve | Componentes clave |
|---|---|---|
| Productos | Catálogo | Tabla con filtros, edición masiva, variantes en matriz, códigos por empaque |
| Inventario | Stock y movimientos | Stock por ubicación y lote, kardex, valorización, vencimientos |
| Cierre | Cerrar el mes | Lista de verificación: recepciones sin factura, negativos, tránsito, conciliación contable |
| Configuración | Reglas | Almacenes, ubicaciones, rutas, categorías con método de costo, tolerancias, numeración |

## Biblioteca de componentes

| Componente | Dónde se usa | Detalle importante |
|---|---|---|
| Paso de tarea por escaneo | Handheld | Una instrucción, un escaneo esperado, error sonoro si no coincide |
| Lector GS1-128 | Handheld | Un escaneo llena producto, lote, vencimiento y cantidad |
| Semáforo de disponibilidad | Todas | Físico, reservado y disponible juntos; nunca solo «stock» |
| Árbol de ubicaciones | Configuración, consulta | Jerarquía con ocupación y bloqueos |
| Kardex | Back-office | Entradas, salidas y saldo con costo, enlazado a cada documento |
| Comparador de conteo | Jefe de almacén | Esperado contra contado por ubicación y lote, con valor de la diferencia |
| Tablero de olas | Jefe de almacén | Estado por ola y por corte de transportista |
| Matriz de tres vías | Comprador | Pedido, recibido y facturado por línea, con tolerancias |
| Importador masivo | Productos, saldos iniciales, precios de compra | Plantilla, vista previa, errores por fila, importar solo las válidas |
| Drawer de auditoría | Cualquier documento | Quién hizo qué y cuándo, sin salir de la pantalla |

## Flujos de usuario paso a paso

### Flujo A. Recepción con handheld

Escanear la orden de compra o el aviso de despacho, escanear cada pallet o producto, confirmar
cantidades (el lote y el vencimiento vienen de la etiqueta GS1-128), registrar diferencias, cerrar. El
sistema genera las tareas de ubicación al instante y lo que faltó queda pendiente.

### Flujo B. Picking por ola

El almacenero toma la siguiente tarea; la pantalla muestra una ubicación en grande; escanea la
ubicación, escanea el producto, confirma la cantidad; pasa a la siguiente. Si la ubicación está vacía,
reporta la excepción con un toque y el sistema busca otra ubicación o crea un reabastecimiento.

### Flujo C. Conteo cíclico

El sistema asigna las ubicaciones del día; el contador escanea la ubicación y cuenta sin ver lo esperado;
si la diferencia supera la tolerancia, el sistema pide recuento; el jefe aprueba el ajuste desde el
comparador.

### Flujo D. Reposición sugerida

El comprador abre las sugerencias del día, ajusta cantidades y genera las órdenes de compra en un paso;
las que superan el monto van a aprobación de otra persona.

### Flujo E. Cierre de mes

El contador abre la lista de verificación del cierre: recepciones sin factura, facturas sin recepción,
saldos negativos, tránsito abierto, costos de importación pendientes y la conciliación entre el valor
del inventario y la cuenta contable. Cuando todo está en verde, fija la fecha de cierre.

## Reglas de diseño específicas

- **El escáner es la entrada principal.** Todo flujo de almacén debe completarse escaneando, con la
  pantalla táctil como respaldo.
- **Confirmar escaneando, no tocando.** Un botón «Confirmar» invita a confirmar sin mirar.
- **Errores que se oyen.** Sonido y vibración distintos para éxito y error; el almacenero no mira la
  pantalla todo el tiempo.
- **Una acción por pantalla en el handheld.** Texto grande, contraste alto (cámaras frías, sol en el
  muelle), botones que se tocan con guantes.
- **Tolerar la mala señal.** Las zonas sin cobertura son comunes; la aplicación guarda y reintenta sin
  perder lo escaneado.
- **Siempre las tres cantidades.** Donde se muestra stock, se muestran físico, reservado y disponible.
- **El costo se ve con su origen.** Un costo unitario se explica en un clic: capas, ajustes y documento.
- **Mensajes accionables.** «El lote L-204 venció el 10/10; escanea otro lote», no «error de
  validación».
- **Formato local.** Unidades, decimales, moneda y fechas del país.
