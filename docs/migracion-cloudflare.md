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
- Por decisión del usuario, no se migrarán hashes de contraseñas ni tokens de sesión/recuperación. Se conservarán perfiles y relaciones de usuario como inactivos, con contraseña pendiente, y se emitirán claves nuevas después de cargar y conciliar los datos.
- La API guarda archivos en `UPLOAD_DIR`; la configuración actual aprovecha un volumen Railway y reporta si falta persistencia en producción.
- Flutter Web compila mediante `mobile/scripts/build_vercel.sh`, que descarga Flutter SDK y usa `API_URL`; hay referencias directas a `https://bknd.gudex.cl` en la app.
- Se agregó `mobile/scripts/build_cloudflare.sh`, que reutiliza el build Flutter y exige una `API_URL` HTTPS para staging, más `mobile/web/_headers` para evitar caché obsoleta de la PWA.
- `baileys-bridge` guarda su sesión en filesystem persistente (`/data/baileys-auth`) y está documentado como conector no oficial limitado a pruebas.
- El checkout está en detached HEAD (`70b98f9`) y limpio al momento del levantamiento.

## Estado de la cuenta Cloudflare consultada (12-11-2026)

El usuario confirmó que esta es la cuenta destino. En la verificación más reciente, la zona `gudex.cl` todavía no aparece en esa cuenta. No se modificó DNS. R2 requiere habilitación desde el dashboard.

El proyecto Pages `gudexapp-staging` (`gudexapp-staging.pages.dev`) está conectado por GitHub al repositorio `ottogudens/gudex`, con rama de producción actual `codex/cloudflare-migration-customer-backup`, raíz `/mobile`, comando `bash scripts/build_cloudflare.sh` y salida `build/web`. El último build publicado desde el commit `ffcd0e0` terminó exitosamente. Staging apunta a la API staging, no a producción.

La base D1 `gudexapp-staging` (UUID `ba3fa019-fb27-4740-bb96-7a3504517099`) tiene el esquema inicial de 59 tablas y 118 índices, y los respaldos JSON/XLSX importados y conciliados; ver sección de carga y [plan de desarrollo por etapas](plan-desarrollo-migracion-cloudflare.md).

El Worker `gudexapp-api-staging` está vinculado a esa D1. `GET /health` responde `200 {"status":"ok","database":"ok"}`. En el Worker remoto aún no se han publicado las rutas de la app, por lo que el resto no está funcional.

### Carga de respaldos a D1 staging

El 12 de noviembre de 2026 se importaron a `gudexapp-staging` los respaldos entregados por el usuario: JSON de clientes/vehículos/trabajos y dos planillas XLSX de productos y servicios. Se cargaron 20 clientes, 18 vehículos, 7 órdenes, 6 servicios en órdenes, 21 inspecciones, 7 planes y 6 ejecuciones de mantención, 12 tarjetas de aceite, 82 entradas técnicas, 8 reportes de escáner, 8 sesiones de trabajo, 3 asignaciones, 1 recepción, 1 control de calidad, 2 cotizaciones, 19 productos, 60 servicios y 10 categorías. Los adjuntos no estaban incluidos en el JSON y no se migraron.

La importación se ejecutó en lotes desde un manifiesto temporal local excluido del repositorio. La lectura posterior confirmó los conteos esperados y `PRAGMA foreign_key_check` sin filas. Se preservaron cuatro IDs de usuarios históricos referenciados como cuentas mecánico inactivas con `RESET_REQUIRED`; no se copiaron hashes ni tokens de acceso/recuperación. Además, se creó en D1 staging la cuenta administrativa solicitada por el usuario con rol `admin` y activa. Su contraseña solo se guardó como hash Argon2id; no se documenta aquí.

La UI Pages de staging ya compila y está publicada. Aún no se puede iniciar sesión ni operar con estos datos hasta desplegar y conectar las rutas funcionales del Worker; el endpoint remoto confirmado es `/health`.

Se inició localmente la primera migración de autenticación, usuarios internos y CRUD básico de clientes en `cloudflare/api/src/index.js`, con verificación de Argon2id compatible y tokens HS256. El bundle compila, pero no se actualizó el Worker remoto: Cloudflare rechazó el aumento de CPU porque la cuenta está en el plan Free. El límite es necesario para verificar los parámetros Argon2id existentes; debilitarlos rompería compatibilidad y seguridad. La clave JWT temporal generada para este intento se eliminó después del rechazo. Para desplegar esta versión hay que habilitar un plan que permita configurar límites CPU y volver a generar el secreto JWT; todavía falta validar compatibilidad completa de datos y permisos antes de conectar Pages.

## Fases de migración

### 0. Congelar línea base y proteger retorno

1. Cuenta Cloudflare destino confirmada; confirmar acceso/control de DNS para `gudex.cl`, proyecto Railway/Vercel y ambientes productivos.
2. Usar el respaldo de datos confirmado por el usuario; antes de importarlo, verificar su formato, tamaño, recuentos por tabla y referencias. Transferir adjuntos por separado a R2.
3. Documentar secretos y callbacks configurados sin copiar sus valores al repositorio.
4. Mantener Railway y Vercel activos como rollback hasta completar el periodo de observación.

El plan operativo vigente por etapas, dominios y criterios de salida está en [plan-desarrollo-migracion-cloudflare.md](plan-desarrollo-migracion-cloudflare.md). Esta sección sustituye la hoja de ruta anterior que ya estaba desactualizada.

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
