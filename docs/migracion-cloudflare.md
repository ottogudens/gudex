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

## Estado de Cloudflare (12-11-2026)

El usuario confirmó que la cuenta Cloudflare conectada es la cuenta destino. La zona `gudex.cl` está activa y tiene los proyectos Pages y Worker conectados a sus dominios. R2 continúa deshabilitado en la cuenta; por ello, los adjuntos no se han migrado.

El proyecto Pages `gudexapp-staging` está conectado a `ottogudens/gudex`, rama de producción `codex/cloudflare-migration-customer-backup`, raíz `/mobile`, comando `bash scripts/build_cloudflare.sh` y salida `build/web`. Aunque el proyecto conserva el nombre `staging`, su despliegue de producción atiende `admin.gudex.cl`. El despliegue `d6185d5d-c88e-4da1-94c1-1a93ec2351cb`, desde el commit `f4affbb51f862f22ee927ed1b2bd92c8c194ca0b`, terminó correctamente. Su `API_URL` de producción es `https://admin.gudex.cl`; la Pages Function reenvía las rutas API al Worker de producción y propaga la aserción Cloudflare Access.

La D1 `gudexapp-production` (UUID `01e28fec-5510-4370-aaf8-db07540eac78`) se creó separada de staging y contiene el esquema de la aplicación y los datos de negocio importados desde los respaldos existentes. Los conteos importados quedaron conciliados y `PRAGMA foreign_key_check` no detectó errores. No se importaron hashes de contraseñas, tokens de sesión/recuperación ni secretos de integración; por lo tanto, las cuentas históricas necesitan restablecer sus claves y las integraciones deben reautorizarse.

El Worker `gudexapp-api-production` está enlazado a esa D1 y tiene el dominio `bknd.gudex.cl`. `GET /health` responde `200 {"status":"ok","database":"ok"}`. `GET /tarjeta-aceite` atiende la tarjeta pública desde D1 solo para vehículos habilitados. La ruta se validó en el dominio con una patente autorizada, sin exponer datos personales. Se añadió el núcleo de órdenes de trabajo: listar, crear, consultar, editar con transiciones, asignar mecánicos, administrar trabajos asociados y eliminar conservando el historial. Las consultas protegidas sin aserción Access reciben `401`. Esto no equivale a migrar el backend completo: el Worker todavía cubre solo una fracción de las aproximadamente 230 operaciones FastAPI. No se debe apagar Railway hasta portar y validar los módulos restantes.

### Carga de respaldos a D1

El 12 de noviembre de 2026 se importaron a `gudexapp-staging` los respaldos entregados por el usuario: JSON de clientes/vehículos/trabajos y dos planillas XLSX de productos y servicios. Se cargaron 20 clientes, 18 vehículos, 7 órdenes, 6 servicios en órdenes, 21 inspecciones, 7 planes y 6 ejecuciones de mantención, 12 tarjetas de aceite, 82 entradas técnicas, 8 reportes de escáner, 8 sesiones de trabajo, 3 asignaciones, 1 recepción, 1 control de calidad, 2 cotizaciones, 19 productos, 60 servicios y 10 categorías. Los adjuntos no estaban incluidos en el JSON y no se migraron.

La importación se ejecutó en lotes desde un manifiesto temporal local excluido del repositorio. La lectura posterior confirmó los conteos esperados y `PRAGMA foreign_key_check` sin filas. Los usuarios históricos están inactivos o con contraseña pendiente; no se copiaron hashes ni tokens de acceso/recuperación. Los secretos de integración tampoco se copiaron.

Staging sigue disponible en D1 y en el Worker `gudexapp-api-staging`. Producción usa recursos separados. La aplicación Flutter publicada está protegida por Cloudflare Access: una solicitud externa sin sesión a `admin.gudex.cl` recibe `302`, comportamiento esperado; falta validar un flujo interno autenticado con la cuenta administradora.

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

Completar y validar autenticación de administrador en producción; después migrar los módulos funcionales por etapas, empezando por clientes/vehículos/taller e inventario, y habilitar R2 para adjuntos. Mantener Railway como rollback hasta que cada operación usada por la aplicación, las integraciones y los archivos estén en Cloudflare y se haya conciliado una carga final de datos. La tarjeta de aceite y el `health check` ya funcionan en Cloudflare, pero por sí solos no permiten retirar Railway.
