# bM — inventario y gestión del negocio

Aplicación web privada en español para gestionar ventas, telas, producción, inventario, cobros, gastos e impuestos. React + Vite en Cloudflare Pages; PostgreSQL, Auth y una Edge Function en Supabase. Adaptada a teléfono y computadora.

**Aplicación:** https://inventariobm.mariabonitaec.com

## Funciones

- Panel por día, semana, mes, año o rango personalizado; comparación con el período anterior y gráficas agrupadas.
- Ventas netas, resultado operativo, caja, stock, pendientes y resultados por producto.
- Asistentes para ventas, compras de tela, encargos, recepciones, traslados, consumo, cobros, gastos, despachos, entregas, devoluciones y cancelaciones.
- Consulta de las 49 tablas de negocio y 20 vistas, búsqueda, paginación y exportación CSV.
- Formularios detallados y registro combinado para operaciones especiales de varios pasos.
- Fechas históricas, impuestos con vigencias, precios finales con IVA incluido, auditoría, idempotencia y cierres de períodos.
- Cuentas individuales y roles administrador, operador y consulta. Invitaciones mediante enlaces privados, sin correo automático.

Consulta [GUIA.md](GUIA.md) para el uso cotidiano, [DATABASE.md](DATABASE.md) para las reglas de datos y [VERIFICACION.md](VERIFICACION.md) para evidencia y límites de las pruebas.

## Desarrollo local

Requiere Node.js 22.12 o posterior compatible con Vite 8.

```sh
npm ci
npm run dev
npm test
npm run build
```

Vite escucha en http://127.0.0.1:5173. `.env.example` describe las variables públicas. El cliente incluye únicamente la URL y clave publicable del proyecto; la autorización real se aplica en el servidor. Nunca añadas claves secretas, service-role, tokens de sesión ni enlaces de invitación a variables `VITE_*` o al repositorio.

## Base y backend

Las migraciones están en `supabase/migrations`. La primera requiere un esquema `bm` inexistente; no es una migración automática desde una instalación v1.2 con datos. La tercera añade la API de la app y la administración protegida de usuarios. Los originales v1.2 se conservan como referencia.

`bm` no está expuesto directamente en PostgREST. Las funciones públicas comprueban membresía y permisos. Las escrituras del negocio pasan por `bm_registrar_operacion`; las claves de idempotencia se reutilizan al reintentar la misma intención. Las tablas tienen RLS y no se conceden escrituras directas al cliente.

La función `supabase/functions/bm-admin-users/index.ts` valida el token de usuario y exige administrador activo antes de usar Auth Admin. `verify_jwt=false` permite validar los JWT actuales dentro de la propia función; **no significa acceso anónimo**. Las credenciales de servicio solo existen en el entorno de Supabase. Los orígenes permitidos están limitados a producción, Pages y desarrollo local.

Despliegue de esa función, con la CLI autenticada y el proyecto correcto:

```sh
npx supabase functions deploy bm-admin-users --project-ref zwxndokufvxwkubpsamj --no-verify-jwt
```

## Publicación

El proyecto independiente de Cloudflare Pages se llama `inventariobm`. El subdominio apunta a `inventariobm.pages.dev`. No se modifican los catálogos de María Bonita ni bM.

```sh
npm test
npm run build
npx wrangler pages deploy dist --project-name inventariobm --branch main
```

GitHub Actions verifica pruebas y compilación. **Subir código a GitHub no publica automáticamente en Cloudflare**: este proyecto usa carga directa. Para publicar cambios se ejecuta el comando anterior con una sesión autorizada de Cloudflare.

## Antes de operar

Registra el catálogo, tarifas verificadas y el historial completo de inventario; la app no incorpora datos ficticios ni una carga inicial alternativa. Concilia existencias y costos. La emisión fiscal electrónica queda fuera del alcance. Define una política de copias y recuperación del proyecto remoto: las pruebas de restauración local no la sustituyen. La prueba de concurrencia con conexiones realmente solapadas está documentada como pendiente en `concurrencia.md`.
