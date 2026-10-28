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

## Alcance

La aplicación registra y analiza el negocio. No emite ni autoriza facturas electrónicas ante el SRI. Los comprobantes emitidos por otro sistema pueden registrarse. Las copias CSV son útiles, pero no sustituyen una copia completa de la base de datos.
