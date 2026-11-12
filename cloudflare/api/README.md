# Gudex API en Cloudflare (staging)

El Worker desplegado `gudexapp-api-staging` está en
`https://gudexapp-api-staging.agenciaskalechile.workers.dev`. Ese despliegue
activo solo expone `GET /health`, que se verificó con D1 disponible. El código
local ya incluye una primera implementación de autenticación, usuarios internos
y operaciones básicas de clientes; todavía no se publicó porque Workers Free
limita cada invocación a 10 ms de CPU y Cloudflare rechazó la configuración CPU
requerida. El verificador conserva Argon2id (64 MiB, 3 iteraciones, paralelismo 4);
no se deben debilitar esos parámetros. Workers Paid permite 30 segundos por
defecto, ajustables hasta 5 minutos, y tiene un cargo mínimo de US$5/mes más
consumos que excedan las cuotas incluidas. No se activó facturación.
Fuentes vigentes: [límites de CPU](https://developers.cloudflare.com/workers/platform/limits/)
y [planes/precios](https://developers.cloudflare.com/workers/platform/pricing/).
El worker remoto no implementa esas rutas y el frontend no debe apuntarse a él
para pruebas funcionales.

El binding `DB` debe apuntar a la D1 `gudexapp-staging`. Nunca apuntar este
Worker a datos productivos. El CORS inicial solo admite
`https://gudexapp-staging.pages.dev`; se debe parametrizar antes de conectar
`admin.gudex.cl`. También faltan el rate limit del login (20 intentos por minuto
en el origen) y el resto de las rutas FastAPI. El Worker no está listo para uso
funcional ni producción.

El esquema inicial de 59 tablas y 118 índices se genera sin datos desde los
modelos actuales con `python cloudflare/d1/generate_initial_schema.py`.
Para compilar el Worker local: `npm ci` y `npm run build`. No subir el directorio
`dist/`; es un artefacto generado.
