# Guía de uso de bM

## Entrar y crear contraseña

Abre https://inventariobm.mariabonitaec.com con tu correo y contraseña. Para el primer acceso, usa el enlace privado que te entregue un administrador, elige una contraseña de al menos 12 caracteres y confírmala. Cada enlace sirve una vez y vence; no lo publiques.

Si vence, otro administrador puede generar uno nuevo en **Configuración → Personas del equipo → Nuevo enlace**. No se envían correos automáticamente. Si nadie puede entrar, el administrador del proyecto debe recuperar el acceso desde Supabase Auth; no se incluyen contraseñas maestras en la aplicación.

## Añadir personas

En **Configuración → Invitar persona**, escribe nombre y correo, elige sus permisos y pulsa **Crear acceso**. Copia el enlace y entrégalo únicamente a esa persona por un canal privado.

- Administrador: acceso completo, usuarios, tarifas y cierres.
- Operador: consultas y registro de operaciones del negocio.
- Consulta: lectura y exportaciones.

Puedes desactivar el acceso de otra persona sin borrar su historial. No puedes quitarte a ti mismo el acceso de administrador.

## Preparación inicial

1. En Inventario registra categoría, colores, tallas, productos y variantes. Cada combinación de color/talla tiene un SKU distinto.
2. Registra proveedores, telas, ubicaciones y costureras.
3. Ingresa el historial completo: compras de telas, traslados, encargos, consumos y recepciones. Usa las fechas reales, aunque sean anteriores a hoy. Los movimientos no pueden dejar stock histórico negativo.
4. En Impuestos configura las tarifas y vigencias verificadas. El precio de las prendas incluye IVA. Las operaciones con tarifa 0%, exentas o no objeto requieren motivo.
5. Revisa existencias, deudas y costos antes de comenzar el uso habitual. Los costos estimados se distinguen de los definitivos.

## Trabajo cotidiano

**Registrar venta** reúne pedido, prendas y cantidades, tratamiento tributario, cobro opcional y entrega o reserva. Revisa el resumen antes de confirmar. Un pedido pendiente no descuenta stock; despachar sí. Confirmar la entrega posterior no vuelve a descontarlo.

**Inventario y Producción** permiten comprar y trasladar tela, registrar consumo, encargar confección y recibir prendas. Los asistentes crean juntos los registros relacionados. Las operaciones menos frecuentes están en los selectores de registros y en **Registro combinado**, que guarda varios pasos como una sola operación.

**Dinero** separa gastos, cobros, pagos de cuentas y reembolsos. Registrar un gasto no implica que se haya pagado: marca el pago únicamente cuando haya ocurrido.

Para corregir hechos, usa devoluciones, anulaciones o ajustes con motivo. No borres el historial. No cierres un período hasta conciliarlo: la app no permite reabrirlo.

## Entender los números

- Ventas netas: prendas despachadas y ajustes, sin IVA.
- Resultado operativo: ingresos reconocidos menos costos y gastos; puede ser provisional mientras haya costos sin finalizar.
- Dinero recibido/pagado: caja registrada, que no equivale a utilidad ni a un saldo bancario conciliado.
- Stock y pendientes: saldos actuales, independientes del filtro de fechas.

El panel ofrece hoy, siete días, mes, año y fechas personalizadas, con comparación al período anterior de igual duración. La gráfica agrupa por día, mes o año. Reportes permite consultar las 20 vistas de la base y exportar CSV. Las tablas de historial completo tienen su propio buscador; no heredan el filtro del panel.

## Si falla internet

Mantén abierto el formulario y reintenta el mismo guardado sin cambiarlo: el identificador de operación evita duplicarlo. Si cerraste el formulario, comprueba los registros antes de repetir la operación. La aplicación necesita conexión; no guarda ventas sin conexión.

## Ejemplo completo: comprar tela y confeccionar camisas

Los importes y cantidades siguientes son ilustrativos. No se guardan automáticamente en la base.

### Preparación que haces una sola vez

En cada sección, elige el tipo de registro en **¿Qué quieres consultar?** y pulsa **Nuevo registro**. Los campos con asterisco son obligatorios. **Más detalles** contiene los opcionales. Describe brevemente cada alta en **Descripción para el historial**.

| Registro | Dónde | Qué llenar |
|---|---|---|
| Categoría | Inventario → Categorías | Nombre, por ejemplo Camisas. |
| Color y talla | Inventario → Colores / Tallas | Nombre del color; nombres S, M y L. No dupliques los ya creados. |
| Producto | Inventario → Productos | Categoría, nombre (LA VERDE), precio final de catálogo ($44), activo. Revisa los campos tributarios con la configuración del negocio. |
| Variante | Inventario → Colores y tallas de productos | Producto, color, talla y SKU único, por ejemplo BM-VERDE-M. Una variante por talla. |
| Proveedor | Dinero → Proveedores | Nombre legal; en Más detalles puedes completar nombre comercial, RUC, teléfono y dirección. |
| Tela | Producción → Telas | Nombre; puedes completar composición, color, ancho en centímetros y código. Este registro describe el material, todavía no añade metros. |
| Costurera | Producción → Talleres y costureras | Nombre; teléfono, documento y tarifa de referencia opcionales. La tarifa real se especifica en el encargo. |
| Bodega | Producción → Ubicaciones de tela | Nombre Bodega bM, tipo bodega, activa. No vincules costurera. |
| Taller | Producción → Ubicaciones de tela | Nombre Taller de Ana, tipo costurera, activa; en Más detalles selecciona la costurera correspondiente. |

### 1. Comprar la tela

En **Dinero → Comprar tela** llena fecha, proveedor, tela, ubicación de recepción, metros, precio por metro sin IVA, IVA total del comprobante, porcentaje de ese IVA, costo inventariable por metro, documento y número de comprobante si existe. Indica si pagaste todo y la forma de pago.

El costo inventariable es el valor por metro que usarás para costear las camisas; la app no lo deduce automáticamente del tratamiento del IVA. Usa el costo revisado para el negocio. No escribas el total de toda la compra en ese campo.

Pulsa **Revisar registro → Confirmar y guardar**. Se crean juntos compra, detalle, lote de tela, ingreso de metros y cuenta por pagar; si marcaste pagada, también el pago completo. No vuelvas a crear esos registros manualmente. Si solo pagaste una parte, deja pendiente y registra el abono en **Dinero → Abonos a cuentas por pagar**.

Ejemplo: ingresas 30 metros a la bodega. Supongamos un costo inventariable confirmado de $10 por metro.

### 2. Crear el encargo

En **Producción → Nuevo encargo** llena fecha, costurera, prenda/variante, unidades y costo de costura por unidad. La entrega estimada y la vinculación a una prenda de un pedido específico son opcionales; para fabricar stock deja esa última vacía.

Ejemplo: 20 unidades de BM-VERDE-M a $5 de costura cada una. Crear el encargo no mueve tela ni añade camisas al stock.

Si hay varias tallas en el mismo encargo, añade las otras en **Producción → Prendas por producir → Nuevo registro**, seleccionando el encargo creado, la variante, unidades y tarifa. El asistente inicial crea una sola combinación por vez.

### 3. Entregar tela al taller

En **Producción → Trasladar tela** llena fecha, lote de tela, origen Bodega bM, destino Taller de Ana y metros entregados. Ejemplo: 25 metros. Quedan 5 en bodega y 25 en el taller; todavía no se han consumido.

Si la compra llegó directamente al taller y elegiste esa ubicación al comprar, no registres además un traslado desde bodega.

### 4. Registrar lo utilizado

En **Producción → Registrar consumo** llena fecha, lote, ubicación de la tela, prendas del encargo y metros realmente usados. Ejemplo: 25 metros para las 20 camisas M. Si hay distintas tallas, distribuye el consumo entre los detalles correspondientes. Si hubo sobrante en el taller, solo registra lo consumido y traslada el sobrante de vuelta cuando ocurra.

### 5. Recibir camisas

En **Producción → Recibir camisas** llena fecha, prendas del encargo, aceptadas, rechazadas, costo estimado de tela por camisa y otros costos por camisa. La mano de obra se toma de la tarifa del encargo.

Ejemplo: 20 aceptadas, 0 rechazadas, tela por camisa $12,50 (25 × $10 ÷ 20), otros costos $0. Se crea un lote y entran 20 camisas al inventario. El costo provisional es $17,50 por camisa, incluyendo los $5 de costura. No añadas otro movimiento manual de producción. Si recibes por partes, registra cada recepción con su fecha y cantidades reales.

### 6. Registrar el pago a la costurera

En **Dinero → Pagos de costura → Nuevo registro** selecciona encargo, fecha de pago, monto, método y estado confirmado. Referencia y notas son opcionales. Ejemplo: $100 por las 20 unidades aceptadas a $5. No registres además ese mismo desembolso como gasto general o en otra cuenta por pagar.

### 7. Revisar y finalizar

Consulta **Producción → Tela disponible por ubicación**, **Producción → Saldos de costura** e **Inventario → Existencias por prenda**. En el ejemplo deben quedar 5 metros en bodega, 0 en taller, 20 camisas y saldo de costura cero si se pagaron los $100.

Antes de considerar definitivos los costos, revisa el consumo real y los gastos asignados. Actualmente el cierre se hace con **Registro combinado**: actualizar el encargo a cerrado con fecha de cierre y actualizar sus lotes con los costos conciliados y **Costo revisado y definitivo = Sí**, guardando todo junto. Los gastos vinculados a producción deben asignarse al detalle correspondiente; no se deben contar dos veces. Este paso requiere una revisión cuidadosa y no ocurre automáticamente al recibir las camisas.

En todos los pasos puedes usar fechas anteriores, siempre que el período siga abierto y el historial de existencias sea coherente.

## Alcance

La aplicación registra y analiza el negocio. No emite ni autoriza facturas electrónicas ante el SRI. Los comprobantes emitidos por otro sistema pueden registrarse. Las copias CSV son útiles, pero no sustituyen una copia completa de la base de datos.
