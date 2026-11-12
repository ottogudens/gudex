# Gudex API en Cloudflare (staging)

El Worker desplegado `gudexapp-api-staging` está en
`https://gudexapp-api-staging.agenciaskalechile.workers.dev` y usa la D1
`gudexapp-staging`. Staging implementa `GET /health`, login por Cloudflare Access,
CRUD básico de clientes y vehículos, y lectura del historial del vehículo.
También gestiona planes de mantención, vencimientos y registro idempotente de
ejecuciones, actualizando kilometraje y la tarjeta de aceite dentro de una batch
de D1. No acepta llamadas de negocio sin una aserción JWT válida de Access. La
política de staging limita el acceso a una identidad propietaria; su aserción se
verifica con firma RS256, emisor y audiencias antes de mapearla al administrador
`admin@gudex.cl` en D1.

La entrada de staging es `src/access_staging.js`; la implementación que conserva
login Gudex por contraseña, usuarios y otros endpoints permanece en `src/index.js`.
No se migraron hashes. El frontend de staging llama a Pages Functions, que reenvía
las rutas de API al Worker junto con la aserción de Access. La pantalla de acceso
por contraseña sigue activa en los demás builds.

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

## Acceso temporal de staging

Cloudflare Access protege `https://gudexapp-staging.pages.dev` y los aliases
`*.gudexapp-staging.pages.dev` con una política que permite solo al correo
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
No subir `dist/`; es un artefacto generado.
