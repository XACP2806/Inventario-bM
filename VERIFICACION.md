# Verificación de la aplicación — 27 de octubre de 2026

## Pruebas realizadas

`npm test` y `npm run build` terminan correctamente. Las pruebas Node verifican CSV seguro, comparación de fechas, separación de caja/resultados y flujos de la interfaz contra PostgreSQL embebido: venta a precio final con IVA histórico, idempotencia, reportes, permisos, encargos, recepción y cancelación parcial que conserva las unidades restantes reservadas.

El conjunto SQL verifica compra/traslado/consumo de tela, producción, stock histórico, reservas, despachos y entregas parciales, costos finales, devoluciones, reembolsos, ajustes, cancelaciones, impuestos históricos, cierre de períodos, RLS y prohibición de escrituras directas. La copia/restauración local conserva esquema, datos ficticios, existencias y funciones de integridad. Nunca se guardaron ventas ficticias en producción.

## Servicios instalados

- Base en MB Project, esquema bm, 55 tablas y 20 vistas. Migraciones de base, índices y API de la aplicación instaladas.
- Auth: Xavier y Chino tienen membresías activas de administrador; cada persona elige su contraseña mediante enlace privado.
- Edge Function bm-admin-users publicada con validación explícita de identidad y rol administrador.
- Cloudflare Pages inventariobm publicado. HTTPS del subdominio inventariobm.mariabonitaec.com devuelve 200.
- El acceso autenticado al dashboard y la lectura de métricas reales se comprobaron con la cuenta Xavier.
- Revisión visual a 390 × 844 y 1280 × 900: panel, menú, reportes y formulario de ventas. Los enlaces privados se generan desde Configuración; se verificó el formulario de contraseña de Xavier en el subdominio, sin introducir ni cambiar su contraseña.
- El JavaScript servido por el subdominio coincide con la compilación local. Hay cabeceras CSP y la función de usuarios responde 401 sin sesión. GitHub Actions completó correctamente las pruebas y compilación del primer despliegue.

## Límites y tareas operativas

La base empezó vacía en el primer despliegue y ya contiene registros reales. La configuración fiscal y la conciliación de existencias/costos requieren revisión del negocio. Los reportes son gerenciales, no estados financieros certificados ni emisión fiscal.

El ensayo remoto previo de concurrencia no demostró sesiones solapadas; no se presenta como aprobado. El protocolo está en concurrencia.md. PostgreSQL embebido prueba reglas pero no concurrencia entre clientes reales. Debe completarse antes de considerar validado ese escenario.

La restauración probada es local. No se ha configurado ni ensayado la recuperación del servicio remoto. El asesor de Supabase advierte que la protección de contraseñas filtradas está deshabilitada; la aplicación exige al menos 12 caracteres, pero eso no sustituye ese servicio.

La compilación avisa de un paquete JavaScript de aproximadamente 596 kB (158 kB comprimido) y de directivas use-client de la biblioteca de iconos; no bloquean el build. No se afirma una auditoría exhaustiva de seguridad, accesibilidad ni navegadores.

## Aislamiento

### Pagos regalados por terceros — 28 de octubre de 2026

Se verificaron compras y confección financiadas por terceros, pago mixto parcial con dinero de bM, saldos liquidados, conservación de costos, idempotencia, pagador obligatorio en frontend y base de datos, rechazo de modificaciones a pagos confirmados, anulación y reapertura de saldo, separación en caja/panel y RLS del reporte. Pasan las nueve pruebas JavaScript, las regresiones SQL y la restauración local. La compilación y el renderizado de los formularios se comprobaron; esta verificación de formularios no es una prueba de interacción en todos los navegadores.

`tests/remote-gift-smoke.sql` pasó en MB Project con el rol `authenticated`: una compra temporal quedó pagada por regalo sin alterar caja y se ejecutaron las comprobaciones diferidas. La transacción se revirtió; no se conservaron compras ni pagos ficticios.

El código y la publicación son independientes de los sitios de María Bonita y bM. Los documentos originales de Downloads no se editaron. No se publican contraseñas ni enlaces privados en GitHub.

## Varias telas en una factura — 29 de octubre de 2026

El formulario permite crear una compra o añadir otra tela a una factura existente. Conserva proveedor, fecha y número; añade un detalle, lote y entrada de tela, incrementa la misma cuenta y registra únicamente el pago de esa línea. Verifica que el importe previo de la cuenta corresponda a sus detalles. Los regalos siguen separados de caja.

Se añadió una precondición opcional de valores esperados al gateway existente, bajo su bloqueo de escritores y con la misma autorización, auditoría, validación diferida e idempotencia. Las revisiones desactualizadas abortan la operación completa y piden revisar de nuevo. Esto no sustituye el ensayo pendiente de sesiones realmente solapadas.

Pasan las diez pruebas JavaScript, regresiones SQL, restauración local y compilación. Se comprobó el renderizado del formulario y visibilidad de campos de compra existente/regalo. El ensayo tests/remote-multi-fabric-smoke.sql pasó en MB Project como authenticated: dos líneas en una compra, total y regalo conciliados, reintento sin duplicados y rechazo con reversión completa de una revisión desactualizada. La transacción de prueba se revirtió. No se modificaron los registros reales del usuario.
