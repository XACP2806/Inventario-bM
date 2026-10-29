# bM — base de inventario v1.3

> Este documento conserva la revisión de la base anterior a la aplicación. Las secciones que describen usuarios o interfaz pendientes son históricas: la API y la aplicación ya se implementaron. Consulta README.md y VERIFICACION.md para el estado actual.

Estado: instalada en MB Project desde la conexión Xavier personal; pruebas funcionales locales y remotas correctas. La comprobación de concurrencia con dos conexiones solapadas sigue pendiente. No sustituye la aplicación ni la validación tributaria del negocio.

Proyecto de destino: `MB Project` (`zwxndokufvxwkubpsamj`). Organización observada: `Maria Bonita`. Motor remoto: PostgreSQL 17.11. Datos de negocio aislados en el esquema `bm`. No se modifica el repositorio ni la página web de María Bonita.

## Decisiones acordadas

- Se reconstruye el historial completo del inventario existente con compras, telas, costureras, recepciones y movimientos. No se agregó un origen alternativo de inventario inicial.
- Se permiten fechas de operación anteriores a la fecha de ingreso. El sistema impone `registrado_en`, `registrado_por` y `actualizado_en`; esos campos no se aceptan desde el cliente.
- Las fechas con hora deben enviarse en ISO 8601 con zona, por ejemplo `2026-10-20T14:00:00-05:00`. Los reportes diarios se agrupan en `America/Guayaquil`.
- El precio final de catálogo y venta incluye IVA. El total de línea es cantidad × precio final; se calcula primero la base redondeada de la línea y el IVA como diferencia. Así no aparece un centavo extra al sumar los componentes.
- Ejemplo ilustrativo: una prenda de $44 con 15% produce $38,26 de base y $5,74 de IVA. Con 12%, $39,29 + $4,71. La tasa no está fijada en código.
- `tarifa_iva_vigencia` contiene códigos, porcentajes y fechas inclusivas. No admite superposiciones para un mismo código. La venta conserva porcentaje, código y fecha tributaria. Una tarifa histórica utilizada no puede reescribirse.
- Operaciones `tarifa_0`, `exento` y `no_objeto` tienen clasificación separada y requieren motivo. No son un selector para omitir impuestos de una venta gravada.
- No se precargan tarifas reales, regímenes ni clasificaciones fiscales no verificadas. Las tarifas ficticias de las pruebas no se instalan como datos del negocio.

## Archivos

- `original_v1_2.sql` y `original_v1_2.md`: copias intactas de los documentos recibidos.
- `build.mjs`, `hardening.sql`, `rules.mjs`: fuentes de la versión revisada.
- `supabase/migrations/20261027060416_bm_inventario_v1_3.sql`: instalación completa sobre un esquema `bm` inexistente. No es una actualización incremental de una instalación v1.2 con datos.
- `supabase/migrations/20261027061132_bm_indices_y_acceso_interno.sql`: índices de claves compuestas y denegación explícita de acceso directo a tablas internas.
- `tests.sql`: regresión con datos ficticios dentro de una transacción y `ROLLBACK` final. No usar sus tarifas como referencia fiscal.
- `test.mjs`: ejecuta la migración y los casos en PostgreSQL embebido, después prueba copia/restauración local con datos ficticios.
- `package-lock.json`: versiones fijadas de herramientas de desarrollo.

## Operaciones atómicas e idempotencia

La aplicación llama a `public.bm_registrar_operacion(p_id uuid, p_acciones jsonb, p_motivo text)`. Una operación agrupa hasta 250 inserciones/actualizaciones. Todas deben pasar la validación o se revierte el conjunto. No hay borrados mediante esta interfaz.

El cliente genera un UUID por intención de guardar y reutiliza **el mismo UUID y el mismo contenido** al reintentar por conexión interrumpida. El servidor devuelve la respuesta original sin repetir cobros o movimientos. Reutilizar el UUID con otro contenido, usuario o motivo se rechaza. Crear otro UUID constituye otra operación; no puede deducirse que dos pagos del mismo importe sean necesariamente duplicados.

Las referencias a registros creados antes en el mismo lote se expresan con `{"$ref":"alias"}`. Cada inserción puede declarar `"ref":"alias"`. Las actualizaciones usan `id` numérico o una referencia. Los nombres de tablas están limitados al registro de recursos y las columnas se verifican contra el catálogo PostgreSQL; no se admite SQL aportado por el cliente.

Ejemplo de forma de una acción:

```json
{
  "accion": "insertar",
  "tabla": "pago_pedido",
  "datos": {
    "pedido_id": 123,
    "fecha_pago": "2026-10-20T14:00:00-05:00",
    "monto": 44,
    "metodo": "transferencia"
  }
}
```

El ejemplo no crea un pedido ni presupone que exista el identificador 123.

Para este negocio pequeño, las escrituras se coordinan mediante una única fila de control transaccional. Se eligió una solución conservadora: dos dispositivos no pueden aprobar simultáneamente operaciones usando el mismo saldo antiguo. A mayor volumen debe medirse la espera y evolucionar hacia bloqueos por pedido/lote, conservando las pruebas de concurrencia. No realizar llamadas externas dentro de una operación de escritura.

## Inventario y entregas

- Recepción aceptada, lote y movimiento de producción se registran juntos, con cantidad y fecha coincidentes.
- Despacho y salida de stock se registran juntos. Confirmar la entrega al cliente no vuelve a descontar mercancía.
- Reservas activas no pueden exceder el stock disponible ni la cantidad pendiente del pedido.
- Se comprueba variante/talla, pertenencia al pedido, límites acumulados, fechas y correspondencia de los movimientos.
- Se comprueban también los saldos históricos de telas y prendas. Una salida antigua que cause saldo negativo en cualquier instante se rechaza aunque hoy exista stock.
- El historial antiguo se carga por orden lógico y cronológico, o en una operación atómica que incluya las entradas necesarias.
- Una devolución aprobada con reingreso requiere el movimiento positivo correcto; nunca se restituye el costo solo por marcar una casilla.
- Los hechos de inventario son inmutables. Las diferencias se registran como ajustes con motivo; no se borran movimientos.
- Un despacho realizado no se cambia a cancelado: se documenta devolución o incidencia.

## Precios, ajustes y reportes

- El precio negociado se introduce en `precio_unitario_final` mientras el pedido está en borrador. `precio_unitario_venta` se calcula como precio neto de alta precisión.
- Un pedido confirmado congela sus importes originales. Los descuentos o cargos posteriores se vinculan a una línea concreta (`destino=prenda`) o al envío (`destino=envio`).
- Los ajustes comerciales de prendas se admiten después de un despacho y se reconocen una sola vez en su propia fecha. Antes del despacho, el precio negociado se define en el borrador.
- Cancelar unidades no despachadas exige, en la misma operación, un ajuste de clase `cancelacion` por el precio final de esas unidades. La cancelación de mercancía no despachada ajusta la cuenta del cliente y no resta una venta inexistente del margen.
- `v_margen_diario` muestra el margen de prendas por fecha del hecho: venta al despachar, crédito al aprobar devolución, recuperación de costo al reingresar, descuento/cargo al registrar el ajuste.
- `v_resultado_operativo_diario` añade envíos, gastos generales no asignados y mermas. Es un reporte gerencial operativo, no un estado financiero certificado. Las políticas de reconocimiento y correcciones de períodos deben revisarse antes del cierre contable.
- `v_caja_diaria` resume pagos y reembolsos registrados. No equivale a utilidad ni a un saldo bancario conciliado. Un gasto no se considera pago automáticamente; el desembolso se registra en el mecanismo de pagos correspondiente, evitando duplicarlo.
- Los costos provisionales se identifican en los reportes. Para finalizar un lote se concilian tela consumida, cantidades aceptadas, tarifa de costura y gastos asignados; el encargo debe estar cerrado. Después no se permite reescribir el costo.
- Los importes de transporte del pedido continúan siendo valores netos, con campos tributarios separados; la convención de $44 final corresponde al precio de las prendas.

## Acceso y auditoría

- Los visitantes (`anon`) no tienen acceso al esquema ni a la función de escritura.
- Iniciar sesión no otorga acceso automáticamente. El UUID de Supabase Auth debe existir en `bm.usuario_bm`, activo, con rol `administrador`, `operador` o `consulta`.
- Miembros activos pueden consultar las tablas de negocio; solo administrador y operador pueden registrar operaciones. Los recursos tributarios están restringidos al administrador.
- No se conceden INSERT/UPDATE/DELETE directos a `authenticated`. Se escribe a través de la función validada e idempotente.
- Las vistas usan `security_invoker` y respetan las políticas de lectura.
- Auditoría registra el antes/después, usuario, fecha real e identificador de operación. La aplicación no tiene permisos para borrar ni modificar auditorías o membresías.
- El esquema `bm` no se añade automáticamente a los esquemas expuestos de la API. Cuando se construya la interfaz se decidirá la consulta mediante funciones específicas o exposición explícita protegida por RLS. No colocar una clave secreta/service-role en el navegador.
- Actualmente no se crean usuarios reales ni se asigna un administrador ficticio. La cuenta del dashboard de Supabase y los usuarios de Supabase Auth son conceptos distintos.

## Antes de operar con datos reales

1. Crear el usuario de la aplicación y asignar su membresía por un administrador del proyecto.
2. Registrar las tarifas, vigencias y motivos fiscales reales; confirmar el tratamiento con quien lleva la contabilidad.
3. Construir la interfaz de registro y probar sus flujos completos en móvil y computadora, incluidas dos conexiones escribiendo simultáneamente. La base no incluye esa interfaz. Ver `concurrencia.md` para la comprobación pendiente del bloqueo transaccional.
4. Definir y probar la copia de seguridad del servicio remoto, con retención y recuperación. La restauración local probada no configura respaldos automáticos de Supabase.
5. Cargar el historial completo, reconciliar existencias físicas y saldos, finalizar costos y entonces cerrar períodos.

`bm.periodo_cerrado` bloquea la incorporación o modificación de hechos con fechas de períodos cerrados, incluidos detalles dependientes de sus cabeceras. Los cierres se administran de forma controlada desde SQL hasta que exista la interfaz administrativa. Cerrar solo períodos conciliados; no reescribir historia para ocultar una corrección posterior.

## Verificación

Los pagos de costura y abonos a cuentas por pagar admiten `origen_fondos` (`bm` o `regalo_tercero`). Un regalo exige `pagador_nombre`, liquida la obligación, no genera deuda hacia el pagador y se excluye de `v_caja_diaria`. La vista `v_pagos_regalados` y la serie `regalos` del panel lo informan por separado; no se suman a ventas, cobros o resultado operativo. Las reglas de costos, auditoría, períodos cerrados e inmutabilidad de pagos confirmados siguen vigentes. La clasificación es de gestión y no decide crédito tributario ni tratamiento contable legal del regalo.

```powershell
npm ci
npm run build
npm test
```

Los casos incluyen 12%/15% ficticios, exenciones y tarifa cero justificadas, redondeo de líneas, fechas históricas, stock actual/histórico negativo, reservas excesivas, variantes erróneas, entregas parciales y excesivas, idempotencia, costos cerrados, devoluciones y reingreso, reembolsos excesivos, descuentos, cancelaciones, cierres, RLS y bloqueo de escritura directa. El entorno local se descarta al terminar; el script SQL remoto termina en `ROLLBACK`.
