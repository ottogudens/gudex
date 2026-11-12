# Gudex API en Cloudflare (staging)

El Worker desplegado `gudexapp-api-staging` está en
`https://gudexapp-api-staging.agenciaskalechile.workers.dev`. Ese despliegue
activo solo expone `GET /health`, que se verificó con D1 disponible. El código
local ya incluye una primera implementación de autenticación, usuarios internos
y operaciones básicas de clientes; todavía no se publicó porque el plan Free
no admite el límite de CPU necesario para verificar los hashes Argon2id actuales.
El worker remoto no implementa esas rutas y el frontend no debe apuntarse a él
para pruebas funcionales.

El binding `DB` debe apuntar a la D1 `gudexapp-staging`. Nunca apuntar este
Worker a datos productivos. El CORS inicial solo admite
`https://gudexapp-staging.pages.dev`.

El esquema inicial de 59 tablas y 118 índices se genera sin datos desde los
modelos actuales con `python cloudflare/d1/generate_initial_schema.py`.
Para compilar el Worker local: `npm ci` y `npm run build`. No subir el directorio
`dist/`; es un artefacto generado.
