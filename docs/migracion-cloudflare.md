# Migración de GudexApp a Cloudflare

## Objetivo y decisión de arquitectura

La meta es trasladar frontend, API, base de datos, archivos y bridge de pruebas a servicios de Cloudflare, manteniendo los flujos y datos actuales. Esto no es un cambio directo de proveedor: el backend contiene 35 migraciones Alembic y usa FastAPI, SQLModel, PostgreSQL, filesystem, subprocesos y bibliotecas de documentos e imágenes.

**Arquitectura destino propuesta:**

| Componente actual | Destino Cloudflare | Trabajo requerido |
|---|---|---|
| Flutter Web en Vercel | Cloudflare Pages (staging inicial) | Compilar Flutter Web y servir `build/web` con fallback SPA. El build usa un script Bash y requiere `API_URL` HTTPS de staging. |
| FastAPI en Railway | Cloudflare Worker como API | Migrar los contratos y lógica a TypeScript/JavaScript Workers, preservando rutas, autenticación, roles y webhooks. Python Workers sirven para prototipos; el backend actual no se debe desplegar ahí sin validar dependencias y reemplazar filesystem/subprocesos. |
| PostgreSQL en Railway + SQLModel/Alembic | D1 | Reescribir el acceso SQL/ORM y convertir las 35 migraciones a migraciones D1/SQLite. Importar datos con un proceso controlado y reconciliar recuentos e invariantes. |
| Adjuntos en volumen Railway | R2 | Mover PDF, imágenes y evidencias a objetos R2; conservar claves y metadatos en D1 y servir descargas a través de endpoints autenticados. |
| Bridge Baileys de Railway | Cloudflare Containers, opcional | Adaptar la persistencia de la sesión: el disco de un Container es temporal. Confirmar que el bridge no oficial sigue siendo necesario antes de migrarlo. |
| Variables Railway/Vercel | Secrets y bindings de Workers | Migrar secretos, callbacks OAuth, URL API, CORS y webhook. Los proveedores Google, OpenAI y Mercado Pago siguen siendo servicios externos, aunque sus credenciales se administren en Cloudflare. |

Cloudflare documenta FastAPI en Python Workers, pero sus paquetes Python deben ser compatibles con Pyodide/PyEmscripten. En este repo, `diagnostics.py` ejecuta un subproceso y varias funciones leen/escriben archivos locales; eso hace que adaptar el backend completo a Python Workers sea incierto y no elimina la incompatibilidad de SQLModel/Alembic con el acceso por binding de D1. Para la meta de usar D1/R2, recomiendo una migración incremental de API a Workers con acceso D1 nativo. Una vía de Containers puede conservar el FastAPI durante una transición, pero por sí sola no completa el retiro de Railway/PostgreSQL.

Referencias oficiales: [FastAPI en Python Workers](https://developers.cloudflare.com/workers/languages/python/packages/fastapi/), [paquetes Python soportados](https://developers.cloudflare.com/workers/languages/python/packages/), [D1](https://developers.cloudflare.com/d1/), [Workers Static Assets para SPA](https://developers.cloudflare.com/workers/static-assets/routing/single-page-application/), [Cloudflare Pages build](https://developers.cloudflare.com/pages/configuration/build-configuration/), [R2](https://developers.cloudflare.com/r2/) y [almacenamiento temporal de Containers](https://developers.cloudflare.com/containers/concepts/).

## Descubrimiento del checkout

- Backend FastAPI: dependencias SQLModel, Pydantic, psycopg, Alembic, ReportLab, Pillow, pypdf, openpyxl, defusedxml, cryptography y Sentry.
- `backend/app/main.py` centraliza una cantidad amplia de rutas; hay routers separados para compras, caja, inspecciones, importaciones, operaciones e integraciones.
- El backend declara aproximadamente 230 operaciones HTTP entre rutas centrales y routers. La autenticación usa JWT HS256 de 8 horas y `pwdlib` con su hasher recomendado (Argon2); la migración debe decidir cómo verificar esos hashes en Workers o cómo forzar un restablecimiento seguro de contraseña.
- Credenciales OAuth e integración se cifran con Fernet. Hay que preservar de forma segura la clave o planificar la reautorización; no copiar secretos al frontend ni al repositorio.
- La API guarda archivos en `UPLOAD_DIR`; la configuración actual aprovecha un volumen Railway y reporta si falta persistencia en producción.
- Flutter Web compila mediante `mobile/scripts/build_vercel.sh`, que descarga Flutter SDK y usa `API_URL`; hay referencias directas a `https://bknd.gudex.cl` en la app.
- Se agregó `mobile/scripts/build_cloudflare.sh`, que reutiliza el build Flutter y exige una `API_URL` HTTPS para staging, más `mobile/web/_headers` para evitar caché obsoleta de la PWA.
- `baileys-bridge` guarda su sesión en filesystem persistente (`/data/baileys-auth`) y está documentado como conector no oficial limitado a pruebas.
- El checkout está en detached HEAD (`70b98f9`) y limpio al momento del levantamiento.

## Estado de la cuenta Cloudflare consultada

El usuario confirmó que esta es la cuenta destino. La cuenta muestra la zona `fibrapucon.cl` como pendiente, dos Workers y dos bases D1 de otros proyectos; todavía no aparece `gudex.cl`. La API de R2 indica que R2 debe habilitarse desde el dashboard.

Se creó el proyecto Pages `gudexapp-staging` (`gudexapp-staging.pages.dev`) como proyecto de carga directa, con raíz `/mobile`, comando documentado `bash scripts/build_cloudflare.sh` y salida `build/web`. Los proyectos de carga directa no ejecutan builds Git y no se pueden convertir después a Git integration; este proyecto deberá recibir el artefacto compilado desde CI o desde un equipo local. Todavía no tiene despliegue (`latest_deployment: null`); no se le configuró una API para evitar apuntarlo al backend productivo. No se modificó DNS.

También se creó la base D1 `gudexapp-staging` (UUID `ba3fa019-fb27-4740-bb96-7a3504517099`). Se generó y aplicó el esquema inicial desde los modelos SQLModel: 59 tablas de aplicación, 118 índices y un registro de migraciones. La base no contiene filas ni datos de producción. El generador y el SQL resultante están en `cloudflare/d1/`.

Se desplegó el Worker `gudexapp-api-staging` en `https://gudexapp-api-staging.agenciaskalechile.workers.dev`, ligado a esa D1, con logs de invocación habilitados y previews desactivadas. `GET /health` respondió `200 {"status":"ok","database":"ok"}`. El Worker aún no implementa rutas funcionales: el resto responde 501.

Se inició localmente la primera migración de autenticación, usuarios internos y CRUD básico de clientes en `cloudflare/api/src/index.js`, con verificación de Argon2id compatible y tokens HS256. El bundle compila, pero no se actualizó el Worker remoto: Cloudflare rechazó el aumento de CPU porque la cuenta está en el plan Free. El límite es necesario para verificar los parámetros Argon2id existentes; debilitarlos rompería compatibilidad y seguridad. La clave JWT temporal generada para este intento se eliminó después del rechazo. Para desplegar esta versión hay que habilitar un plan que permita configurar límites CPU y volver a generar el secreto JWT; todavía falta validar compatibilidad completa de datos y permisos antes de conectar Pages.

## Fases de migración

### 0. Congelar línea base y proteger retorno

1. Cuenta Cloudflare destino confirmada; confirmar acceso/control de DNS para `gudex.cl`, proyecto Railway/Vercel y ambientes productivos.
2. Guardar respaldo verificado de PostgreSQL y de todos los adjuntos; medir tamaños, recuentos por tabla y referencias entre registros.
3. Documentar secretos y callbacks configurados sin copiar sus valores al repositorio.
4. Mantener Railway y Vercel activos como rollback hasta completar el periodo de observación.

### 1. Frontend de prueba en Cloudflare Pages

1. El proyecto Pages `gudexapp-staging` y la base D1 `gudexapp-staging` ya están creados y separados de producción. D1 tiene esquema inicial sin datos. Pages aún no tiene despliegue y es de carga directa; publicar el artefacto Flutter desde CI/local o crear un proyecto separado con Git integration para builds automáticos.
2. Definir `API_URL` como variable HTTPS de una API de staging. El script falla si falta para evitar publicar por accidente una versión de pruebas apuntando a producción.
3. Pages aplica fallback SPA cuando el output tiene `index.html`; los encabezados de caché están en `mobile/web/_headers`.
4. Usar hostname `pages.dev`; no cambiar DNS de producción todavía.

### 2. Capa de datos y almacenamiento

1. Revisar el esquema inicial generado desde SQLModel y mapear sus 59 tablas a las operaciones de D1; validar constraints, índices y transacciones con cada dominio.
2. Convertir las 35 revisiones Alembic en migraciones D1 aditivas. Respetar secuencias de estados, atomicidad de venta/caja/stock, importaciones y recepción de compras.
3. Migrar adjuntos a R2 con manifiesto de origen/destino, checksum y verificación de descargas con autorización.
4. Ensayar exportación/importación en staging y reconciliar conteos, sumas de caja/stock y referencias de archivos.

### 3. API por dominios

1. Empezar con autenticación, usuarios, clientes y vehículos; conservar formato de token y contratos consumidos por Flutter.
   - Resolver antes la verificación de hashes Argon2 existentes. Si el runtime destino no puede verificarlos, planificar renovación de credenciales y expiración de sesiones sin bloquear permanentemente cuentas.
2. Migrar órdenes, inspecciones, cotizaciones, inventario, compras, caja y POS en grupos con pruebas de regresión de permisos y efectos contables.
3. Migrar pagos/webhooks, Google OAuth, asistente IA, campañas, fidelización y operaciones de taller; actualizar callbacks y secretos en los proveedores externos.
4. Reemplazar rutas locales de archivos por objetos R2, con autorización antes de leer o emitir enlaces limitados.
5. Mantener API antigua y nueva en paralelo durante pruebas, con datos de staging aislados. Evitar doble escritura en producción salvo que se diseñe una reconciliación explícita.

### 4. Bridge opcional y dominios

1. Decidir si se mantiene Baileys. Si sí, migrarlo en una fase separada a Containers y diseñar persistencia duradera de credenciales; no confiar en el disco local del Container.
2. Activar R2 y crear recursos D1/Workers en la cuenta que controlará `gudex.cl`.
3. Configurar dominios personalizados para web y API, TLS, CORS/orígenes permitidos, redirects OAuth y webhooks de pagos.

### 5. Corte y retirada

1. Ejecutar migración final con ventana de escritura controlada, respaldar y congelar cambios en el origen.
2. Importar delta final, validar salud, autenticación por rol, portal cliente, inventario, caja, compra y venta con datos de control.
3. Cambiar DNS y URLs públicas; monitorear errores y latencia. Mantener rollback disponible.
4. Retirar Railway/Vercel solo tras periodo estable, respaldo final y confirmación de que archivos y callbacks antiguos ya no reciben tráfico.

## Criterios de aceptación

- Recuentos de filas y relaciones coherentes entre origen y destino; claves de negocio únicas preservadas.
- Adjuntos con checksum coincidente y acceso autorizado por los mismos roles que hoy.
- El libro de caja, stock, compras y ventas concilia antes/después; reintentar webhooks no duplica pagos.
- Pruebas de aislamiento de portal cliente, permisos administrativos y mecánico, recuperación de contraseña y expiración de sesión.
- OAuth, Mercado Pago y enlaces de correo apuntan a los dominios Cloudflare y completan el flujo en sandbox.
- PWA descarga versiones nuevas y la aplicación móvil apunta a la URL API nueva.
- Health check, logs y alertas activos; backups y procedimiento de rollback documentados.

## Próximo paso recomendado

En Cloudflare, habilitar R2 y agregar/activar la zona `gudex.cl`, conservando los registros DNS existentes antes de cambiar nameservers. En paralelo, crear una API de staging y conectarla a Pages con `API_URL`; luego levantar el inventario técnico de rutas/modelos para estimar el port. No cambiar producción ni apagar Railway/Vercel hasta superar los criterios de aceptación.
