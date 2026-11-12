# Gudex API en Cloudflare (staging)

El Worker desplegado `gudexapp-api-staging` está en
`https://gudexapp-api-staging.agenciaskalechile.workers.dev` y usa la D1
`gudexapp-staging`. Staging implementa `GET /health`, login por Cloudflare Access,
CRUD básico de clientes y vehículos, y lectura del historial del vehículo.
También gestiona planes de mantención, vencimientos y registro idempotente de
ejecuciones, actualizando kilometraje y la tarjeta de aceite dentro de una batch
de D1. La verificación live del 12-11-2026 confirmó `/health` con HTTP 200 y
`/api/v1/customers` directo sin aserción con HTTP 401. Pages devuelve HTTP 302
hacia Access para la app y sus rutas API. No se simuló un inicio interactivo con
PIN ni se validó el recorrido de negocio autenticado en Flutter. No acepta
llamadas de negocio sin una aserción JWT válida de Access. La
política de staging limita el acceso a una identidad propietaria; su aserción se
verifica con firma RS256, emisor y audiencias antes de mapearla al administrador
`admin@gudex.cl` en D1.

La entrada de staging es `src/access_staging.js`; la implementación que conserva
login Gudex por contraseña, usuarios y otros endpoints permanece en `src/index.js`.
No se migraron hashes. El frontend de staging usa el hostname actual como base
de API y llama a Pages Functions en el mismo origen; Pages reenvía las rutas al
Worker junto con la aserción de Access. Así puede funcionar desde
`gudexapp-staging.pages.dev` y `admin.gudex.cl`. La pantalla de acceso por
contraseña sigue activa en los demás builds.

El login original usa Argon2id (64 MiB, 3 iteraciones, paralelismo 4). No se deben
debilitar esos parámetros para caber en Workers Free, que limita cada invocación
a 10 ms de CPU. Workers Paid ofrece 30 segundos por defecto, ajustables hasta 5
minutos, y tiene un cargo mínimo de US$5/mes más consumos sobre las cuotas. No se
activó facturación. Fuentes: [límites de CPU](https://developers.cloudflare.com/workers/platform/limits/)
y [planes/precios](https://developers.cloudflare.com/workers/platform/pricing/).

Las variables `ACCESS_TEAM_DOMAIN`, `ACCESS_AUDS`, `ACCESS_EMAIL` y
`ACCESS_ADMIN_EMAIL` deben concordar con las aplicaciones y la política de
Cloudflare Access. Nunca apuntar este Worker a datos productivos. Esta modalidad
es solo para staging y un administrador; faltan usuarios internos, rate-limits,
las otras escrituras del historial de vehículos, flujo de órdenes/servicios y la
mayoría de las rutas FastAPI. Los
adjuntos de scanner/fotos aún no están en R2 y el historial no expone sus archivos.
No usar en producción.

## API y base de datos de producción

Se creó `gudexapp-production` y se importaron los datos de negocio disponibles
desde la D1 de staging: clientes, vehículos, historial y planes de mantención,
tarjetas de aceite, productos y servicios. Se conservaron IDs y claves foráneas.
La conciliación registró 296 filas en 19 tablas con datos y cero violaciones de
claves foráneas. No se copiaron hashes de contraseña, tokens de autenticación ni
credenciales cifradas de integraciones. Los usuarios históricos permanecen
inactivos con clave pendiente; el administrador se autentica mediante la política
de Cloudflare Access existente.

El Worker `gudexapp-api-production` usa esa D1 y tiene el hostname
`bknd.gudex.cl`. Además de clientes, vehículos, historial y mantenciones, ya
incluye el núcleo de órdenes: `GET/POST /api/v1/work-orders`, lectura por ID,
edición con transiciones de estado, asignación (`PUT .../{id}/assignment`),
listado de mecánicos, listado/alta/actualización de trabajos asociados y baja
segura de órdenes. Una orden con historial se cancela para conservar trazabilidad;
solo una orden sin actividad asociada se elimina. `GET /tarjeta-aceite` es público,
consulta únicamente vehículos con `public_service_card_enabled=1` y no entrega
información de contacto ni historial completo. El resto de rutas requiere una
aserción válida de Cloudflare Access. Los adjuntos de imágenes no se copiaron a
R2; la tarjeta sirve sus campos de texto y kilometraje.

Esta versión añade lectura y mantenimiento del catálogo: productos,
movimientos de stock, servicios y categorías; también altas/ediciones y archivo
seguro de productos. El conteo físico permite crear sesiones ciegas, registrar
SKU escaneados, enviar diferencias a revisión y aplicarlas por el administrador
en una transacción D1. El stock esperado se oculta mientras el conteo ciego está
abierto; toda diferencia aplicada deja movimientos de inventario. Se migró el
registro de repuestos por trabajo, verificación de compatibilidad vinculada a
la identidad del vehículo, historial/referencias verificadas y resumen de uso.
Registrar o instalar un repuesto conserva la regla actual y no descuenta stock;
la evidencia adjunta seguirá sin abrirse hasta completar R2. Aún faltan compras,
ventas, caja y uso de repuestos integrado a inventario.

La ruta `/api/v1/dashboard` entrega las métricas operativas que usa el panel
principal (órdenes atrasadas/activas, citas, stock bajo, cotizaciones y ventas
del día). La navegación de escritorio inicia con todos los grupos del menú
abiertos y los accesos del panel dirigen a sus módulos correspondientes.

El flujo de taller también cubre recepción del vehículo, listas de inspección y
plantillas, diagnósticos estructurados y revisión de control de calidad. Los
adjuntos, informes PDF y bahías del taller aún no están migrados; inspección y
diagnóstico funcionan sin adjuntar archivos.

Pages de `admin.gudex.cl` reenvía las rutas API al Worker de producción. La
versión actual se desplegó el 12-11-2026; las consultas sin aserción a órdenes
responden HTTP 401, mientras `/health` y la tarjeta pública responden HTTP 200.
No se validó un recorrido interno autenticado de punta a punta. La cobertura de
la API sigue siendo parcial: inspecciones, cotizaciones, sesiones, control de
calidad, repuestos, caja, compras, ventas, portal, integraciones y archivos,
además de las operaciones de inventario distintas del catálogo y conteo descritos
arriba, todavía requieren portar y validar. Railway permanece como rollback y
esta API de Cloudflare no lo llama.

## Acceso temporal de staging

Cloudflare Access protege `https://gudexapp-staging.pages.dev`, los aliases
`*.gudexapp-staging.pages.dev` y `admin.gudex.cl` con una política que permite solo al correo
propietario de la cuenta, usando PIN por correo y sesiones de 8 horas. Se verificó
que el hostname canónico y el alias de la última publicación redirigen a Access.
En staging, la pantalla canjea la aserción Access por una sesión de interfaz; cada
solicitud de API vuelve a validar la aserción firmada en el Worker. Es una vía
temporal de un solo administrador, no reemplaza la identidad multiusuario Gudex.

El esquema inicial de 59 tablas y 118 índices se genera sin datos desde los
modelos actuales con `python cloudflare/d1/generate_initial_schema.py`.
Para compilar la versión completa local: `npm ci` y `npm run build`. La entrada
reducida de staging se compila con `npm run build:staging`. El Worker todavía se
despliega manualmente; Workers Builds no está conectado a esta ruta del repo.
El workflow `.github/workflows/cloudflare-api-staging.yml` está preparado para
ejecución manual. Para activarlo, agrega `CLOUDFLARE_API_TOKEN` como Actions
secret del repositorio `ottogudens/gudex`, con permisos limitados para Workers
Scripts y lectura del binding D1, y luego ejecútalo desde GitHub Actions. No se
pudo configurar el secreto desde este entorno (no hay sesión de Wrangler ni CLI
`gh`). El token no se almacena en el repo ni se solicita en el chat. El workflow
solo despliega staging, y `wrangler.toml` solo apunta al Worker y D1 de staging;
producción continúa separada. No subir `dist/`; es un artefacto generado.
