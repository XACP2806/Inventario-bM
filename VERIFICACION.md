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

La base de negocio empieza vacía. Faltan los datos reales, configuración fiscal verificada y conciliación de existencias/costos. Los reportes son gerenciales, no estados financieros certificados ni emisión fiscal.

El ensayo remoto previo de concurrencia no demostró sesiones solapadas; no se presenta como aprobado. El protocolo está en concurrencia.md. PostgreSQL embebido prueba reglas pero no concurrencia entre clientes reales. Debe completarse antes de considerar validado ese escenario.

La restauración probada es local. No se ha configurado ni ensayado la recuperación del servicio remoto. El asesor de Supabase advierte que la protección de contraseñas filtradas está deshabilitada; la aplicación exige al menos 12 caracteres, pero eso no sustituye ese servicio.

La compilación avisa de un paquete JavaScript de aproximadamente 596 kB (158 kB comprimido) y de directivas use-client de la biblioteca de iconos; no bloquean el build. No se afirma una auditoría exhaustiva de seguridad, accesibilidad ni navegadores.

## Aislamiento

El código y la publicación son independientes de los sitios de María Bonita y bM. Los documentos originales de Downloads no se editaron. No se publican contraseñas ni enlaces privados en GitHub.
