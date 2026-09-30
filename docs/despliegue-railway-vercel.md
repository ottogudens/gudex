# Manual de despliegue y pruebas: Railway + Vercel

Esta guía despliega la API FastAPI y PostgreSQL en Railway, y la aplicación Flutter Web en Vercel. Los cambios del proyecto que habilitan este despliegue incluyen el driver psycopg, CORS configurable, configuración para el administrador inicial y el punto de entrada de Flutter Web.

## Antes de empezar

Necesitas:

- Acceso al repositorio GitHub `ottogudens/gudex`.
- Una cuenta en Railway y otra en Vercel, conectadas con GitHub.
- Una computadora con Git, Python y Flutter para ejecutar pruebas locales o compilar fuera de Vercel.
- Una URL pública para la API y otra para el frontend.

El SDK Flutter está fijado por defecto a la versión estable `3.47.3` en el script de compilación de Vercel. Puedes cambiar `FLUTTER_VERSION` en Vercel al actualizar Flutter.

## 1. Crear PostgreSQL y API en Railway

1. En Railway crea un proyecto y agrega un servicio **PostgreSQL**.
2. Agrega otro servicio desde el repositorio GitHub `ottogudens/gudex`, rama `main`.
3. En los ajustes del servicio API configura **Root Directory** como `/backend`. Este repositorio contiene backend y frontend en directorios separados.
4. En **Config as Code → Config File Path** configura `/backend/railway.json`. Railway no ajusta automáticamente esta ruta al Root Directory. Si queda usando `/railway.json`, el predeploy de Alembic no se ejecutará.
5. Deja que Railway/Railpack instale las dependencias declaradas en `requirements.txt` y `pyproject.toml`. El archivo `requirements.txt` hace explícitas las dependencias de ejecución, incluido Uvicorn.
6. El archivo `backend/railway.json` configura `alembic upgrade head` como comando previo, el inicio con `python -m uvicorn` y el health check `/health`. En los detalles confirma que Railway haya aplicado esos valores.
7. En Variables del servicio API añade:

   | Variable | Valor |
   |---|---|
   | `APP_ENV` | `production` |
   | `SEED_DEFAULT_USERS` | `false` |
   | `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` (usa el nombre real del servicio PostgreSQL) |
   | `UPLOAD_DIR` | `/app/uploads` |
   | `MAX_EVIDENCE_BYTES` | `20000000` (opcional; límite por fotografía o adjunto) |
   | `JWT_SECRET` | Secreto aleatorio de al menos 32 caracteres |
   | `BOOTSTRAP_ADMIN_EMAIL` | Correo que usarás para el primer administrador |
   | `BOOTSTRAP_ADMIN_PASSWORD` | Contraseña de al menos 12 caracteres |
   | `INTEGRATION_ENCRYPTION_KEY` | Clave Fernet para tokens Google; necesaria antes de conectar la cuenta |
   | `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Credenciales OAuth tipo Web de Google Cloud |
   | `GOOGLE_REDIRECT_URI` | `https://<dominio-api-railway>/auth/google/callback` (debe coincidir exactamente en Google Cloud) |
   | `GOOGLE_DRIVE_FOLDER_ID` | Opcional, ID de carpeta Drive que recibe PDFs LAUNCH |
   | `AI_PROVIDER` / `AI_API_KEY` | Opcional; usa `openai` y la clave del proveedor para habilitar el asistente |
   | `AI_MODEL` | Opcional; modelo permitido por tu cuenta, por defecto `gpt-5-mini` |
   | `CORS_ORIGINS` | `http://localhost:8000` inicialmente; se cambia al dominio Vercel en el paso 2 |

   Railway proporciona `DATABASE_URL` para que los servicios del mismo proyecto se conecten a PostgreSQL. No copies ni expongas la contraseña de la base de datos en el frontend.

8. Adjunta un **Volume** al servicio API y establece su mount path en `/app/uploads`. La aplicación guarda allí los PDFs del scanner. Sin volumen, esos archivos no se conservan después de reemplazar el contenedor.
9. Pulsa Deploy. Railway debe mostrar las migraciones `20260930_0001` y `20260930_0002` antes de iniciar Uvicorn. Como recuperación de instalaciones anteriores, el arranque puede crear únicamente tablas faltantes; los cambios posteriores deben seguir pasando por Alembic.
10. Confirma que puedes iniciar sesión con ese administrador y luego elimina `BOOTSTRAP_ADMIN_EMAIL` y `BOOTSTRAP_ADMIN_PASSWORD` de Railway. La cuenta creada permanece en PostgreSQL.
11. En Settings → Networking genera un dominio público para la API y guarda la URL HTTPS. Verifica:

   ```text
   https://<dominio-api>/health
   ```

   Debe responder con JSON y `"status":"ok"`.

En un despliegue que ya contiene datos, crea primero un respaldo de PostgreSQL. Las migraciones conservan las tablas existentes y agregan las faltantes. Después del despliegue puedes comprobar la revisión desde el shell Railway con `alembic -c alembic.ini current`; debe indicar `20260930_0002 (head)`.

Para completar la configuración OAuth de Google y probar las integraciones y el asistente, sigue [la guía de fases 3 y 4](fases-3-y-4.md). Las credenciales se guardan únicamente en Railway; no agregues secretos en Vercel.

Para crear `JWT_SECRET` localmente, ejecuta `python -c 'import secrets; print(secrets.token_urlsafe(48))'` y guarda el resultado directamente en las variables de Railway. No lo agregues a GitHub.

## 2. Configurar CORS y desplegar Flutter Web en Vercel

1. Crea un proyecto en Vercel e importa el mismo repositorio.
2. Configura **Root Directory** en `mobile`.
3. El archivo `mobile/vercel.json` define el build, el directorio de salida y el fallback de rutas. Verifica en Build & Development Settings:
   - Framework Preset: **Other**.
   - Build Command: `bash scripts/build_vercel.sh`.
   - Output Directory: `build/web`.
4. Añade estas variables para Production (y Preview si también desplegarás previews):

   | Variable | Valor |
   |---|---|
   | `API_BASE_URL` | URL HTTPS pública de Railway, sin `/` al final |
   | `FLUTTER_VERSION` | `3.47.3` (opcional; es el valor predeterminado del script) |

   `API_BASE_URL` es pública y queda incorporada al cliente web durante la compilación. No pongas credenciales de Railway, Google, IA o Mercado Pago en Vercel.

5. Despliega desde `main` y copia el dominio HTTPS asignado por Vercel, por ejemplo `https://<proyecto>.vercel.app`.
6. Vuelve a Railway y cambia `CORS_ORIGINS` a ese origen exacto. Para permitir más de un origen, sepáralos con comas, sin comodines, por ejemplo:

   ```text
   https://<proyecto>.vercel.app,https://<dominio-personal>
   ```

7. Redepliega el servicio API. Si usas previews de Vercel, añade sus dominios exactos a `CORS_ORIGINS` o prueba desde el dominio de producción.

Vercel descarga Flutter SDK en el build y genera `build/web`. Flutter documenta `flutter build web` como el comando para compilar la app web. El almacenamiento seguro del paquete Flutter requiere HTTPS en navegador; el dominio HTTPS de Vercel cumple ese requisito.

## 3. Comprobar la API desde la terminal

Define en una terminal local las URLs reales:

```bash
export API_URL='https://<dominio-api>'
export WEB_URL='https://<proyecto>.vercel.app'
```

### Health check y documentación

```bash
curl -i "$API_URL/health"
curl -i "$API_URL/openapi.json"
```

Ambas respuestas deben ser HTTP 200. La documentación interactiva de FastAPI está en `$API_URL/docs`.

### Iniciar sesión como administrador

```bash
curl -sS -X POST "$API_URL/auth/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'username=<correo-admin>' \
  --data-urlencode 'password=<contraseña-admin>'
```

La respuesta debe incluir `access_token`. Guárdalo en una variable local, sin copiarlo a archivos versionados:

```bash
export TOKEN='<access_token>'
curl -i "$API_URL/api/v1/customers" \
  -H "Authorization: Bearer $TOKEN"
```

La API debe responder HTTP 200 (la lista puede estar vacía). Sin token, `/api/v1/customers` debe responder HTTP 401.

### Crear perfiles de mecánico y cliente

El cliente debe existir primero. Sustituye los datos de ejemplo:

```bash
curl -sS -X POST "$API_URL/api/v1/customers" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"full_name":"Cliente de prueba","email":"cliente.prueba@example.com","phone":"+56912345678"}'
```

Anota el `id` devuelto como `<CUSTOMER_ID>` y crea las cuentas:

```bash
curl -sS -X POST "$API_URL/api/v1/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"email":"mecanico@example.com","full_name":"Mecánico de prueba","password":"<contraseña-larga>","role":"mechanic"}'

curl -sS -X POST "$API_URL/api/v1/users" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"email":"cliente.prueba@example.com","full_name":"Cliente de prueba","password":"<otra-contraseña-larga>","role":"customer","customer_id":<CUSTOMER_ID>}'
```

Usa contraseñas de al menos 12 caracteres. Para verificar aislamiento, inicia sesión con el usuario cliente y consulta `/api/v1/portal/profile`; debe mostrar solamente sus vehículos y órdenes. Una ruta interna como `/api/v1/customers` debe responder HTTP 403 a la cuenta cliente.

### Flujo de mantención, cotización y aprobación

Con el `CUSTOMER_ID` creado arriba, registra el vehículo y anota `VEHICLE_ID`:

```bash
curl -sS -X POST "$API_URL/api/v1/vehicles" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"customer_id":<CUSTOMER_ID>,"plate":"ABCD12","make":"Toyota","model":"Yaris","year":2020,"current_mileage_km":85000}'
```

Abre una orden y anota `WORK_ORDER_ID`:

```bash
curl -sS -X POST "$API_URL/api/v1/work-orders" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"customer_id":<CUSTOMER_ID>,"vehicle_id":<VEHICLE_ID>,"mileage_km":85000,"reported_symptoms":"Mantención preventiva"}'
```

Adjunta una revisión y crea/publica una cotización:

```bash
curl -sS -X POST "$API_URL/api/v1/work-orders/<WORK_ORDER_ID>/inspections" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"category":"Motor","item":"Nivel de aceite","result":"normal","notes":"Nivel dentro de rango"}'

curl -sS -X POST "$API_URL/api/v1/work-orders/<WORK_ORDER_ID>/quotes" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"description":"Cambio de aceite y filtro","labor_clp":15000,"parts_clp":35000}'

curl -sS -X POST "$API_URL/api/v1/quotes/<QUOTE_ID>/publish" \
  -H "Authorization: Bearer $TOKEN"
```

Inicia sesión como cliente en `/auth/token`, usa ese token para consultar `/api/v1/portal/quotes` y abre la app Vercel como cliente para aprobar o rechazar. Comprueba que la cotización cambie de estado y que la orden aparezca en `/api/v1/portal/work-orders`.

### Flujo de inventario y POS

```bash
curl -sS -X POST "$API_URL/api/v1/products" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"sku":"ACEITE-5W30","name":"Aceite 5W-30","unit":"litro","stock_quantity":10,"minimum_quantity":2,"cost_clp":3000,"price_clp":5000}'
```

Anota `PRODUCT_ID`, crea una venta con una línea de ese producto y confirma que el stock baje:

```bash
curl -sS -X POST "$API_URL/api/v1/sales" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"customer_id":<CUSTOMER_ID>,"vehicle_id":<VEHICLE_ID>,"lines":[{"product_id":<PRODUCT_ID>,"description":"Aceite 5W-30","quantity":2,"unit_price_clp":5000}]}'
```

La respuesta debe incluir total `10000` CLP; `/api/v1/products` debe mostrar 8 litros. Registra una prueba de pago en efectivo con `POST /api/v1/sales/<SALE_ID>/payments` y el JSON `{"method":"cash","amount_clp":10000}`. Un pago enviado como `mercado_pago` queda pendiente y esta versión no verifica el cobro remoto.

### Verificar CORS

```bash
curl -i -X OPTIONS "$API_URL/api/v1/customers" \
  -H "Origin: $WEB_URL" \
  -H 'Access-Control-Request-Method: GET' \
  -H 'Access-Control-Request-Headers: authorization'
```

La respuesta debe incluir `Access-Control-Allow-Origin: $WEB_URL`. Si no aparece, revisa `CORS_ORIGINS` en Railway y redepliega la API.

## 4. Probar desde la interfaz web

1. Abre el dominio Vercel en HTTPS.
2. En el inicio de sesión confirma que **Dirección de la API** sea la URL HTTPS Railway.
3. Ingresa con el correo y contraseña del administrador configurados en Railway.
4. Comprueba que carguen las vistas de órdenes, clientes, inventario y agenda. En Inventario, administración debe poder crear un producto, ajustar stock con motivo y consultar el historial; intenta la misma operación con el perfil mecánico y confirma que el servidor la rechace. Si no hay datos, una lista vacía es válida.
5. Inicia sesión con las cuentas de mecánico y cliente para comprobar que el menú y el portal corresponden al perfil.
6. Abre una orden como administración o mecánico, crea una cotización con mano de obra y repuestos, y publícala confirmando el envío. Como cliente, abre Cotizaciones y comprueba que aparezca con sus importes; usa Aprobar/Rechazar y verifica el cambio de estado.
7. Revisa la consola del navegador si la pantalla indica error de conexión; un error CORS suele señalar un origen ausente en `CORS_ORIGINS`.
8. Abre una orden, completa la recepción, aplica una plantilla, edita un resultado y adjunta una foto. Ingresa como cliente vinculado y comprueba que el informe aparezca en **Trabajos anteriores**.

## 5. Prueba de persistencia y scanner

1. Crea un cliente y un vehículo de prueba por la API autenticada.
2. Guarda los IDs. Reinicia el servicio API desde Railway.
3. Vuelve a consultar `/api/v1/customers` y `/api/v1/vehicles`; los registros deben seguir presentes en PostgreSQL.
4. Adjunta un informe PDF Launch a un vehículo y una orden:

   ```bash
   curl -sS -X POST "$API_URL/api/v1/scanner-reports?vehicle_id=<VEHICLE_ID>&work_order_id=<WORK_ORDER_ID>&mileage_km=85000" \
     -H "Authorization: Bearer $TOKEN" \
     -F 'file=@/ruta/al/informe-launch.pdf;type=application/pdf'
   ```

5. Consulta `/api/v1/vehicles/<VEHICLE_ID>/scanner-reports` y abre el `download_url` devuelto. Tras otro reinicio, el PDF debe seguir disponible gracias al volumen Railway.

## 6. Problemas frecuentes

| Síntoma | Qué revisar |
|---|---|
| Railway indica `No module named uvicorn` | Confirma Root Directory `/backend` y revisa que el build instale `backend/requirements.txt`, donde se declara `uvicorn[standard]`. El comando versionado usa `python -m uvicorn`. |
| Railway no encuentra `app.main` | Root Directory debe ser `/backend`; el código de la API vive en `backend/app`. |
| Error de conexión PostgreSQL | Revisa `DATABASE_URL=${{Postgres.DATABASE_URL}}`, que el nombre de servicio sea correcto y que `psycopg` se instale desde `pyproject.toml`. |
| El servicio termina al arrancar en producción | Define `JWT_SECRET` aleatorio de 32+ caracteres, `SEED_DEFAULT_USERS=false` y una clave admin de 12+ caracteres. |
| Falla el comando previo de Alembic | Confirma Root Directory `/backend`, `DATABASE_URL` y que `alembic` aparezca instalado. No cambies el start command para saltar la migración. |
| API funciona con curl pero falla desde Vercel | Añade el origen HTTPS exacto del frontend a `CORS_ORIGINS` y espera el redeploy de Railway. |
| Vercel no encuentra Flutter o tarda demasiado | Revisa logs del build, el archivo `mobile/vercel.json`, `API_BASE_URL` y espacio/tiempo de compilación. El build instala Flutter 3.47.3 cada vez que no hay caché. |
| PDF o fotografía desaparece tras desplegar de nuevo | Confirma que el volumen de Railway esté conectado al backend en `/app/uploads` y que `UPLOAD_DIR` use esa ruta. |
| Login cliente da 403 en rutas internas | Es el comportamiento esperado: las cuentas cliente solo usan `/api/v1/portal/*` y `/api/v1/account/password`. |

## Límites actuales

El despliegue incluye gestión base, POS de productos, importación de PDF desde Google bajo acción administrativa, sincronización de citas confirmada y el asistente IA (este último requiere credenciales). Todavía no emite boletas electrónicas ni inicia cobros directos de Mercado Pago. No registres pagos como cobrados hasta confirmar el pago por el medio externo correspondiente.

## Referencias oficiales

- [Desplegar FastAPI en Railway](https://docs.railway.com/guides/fastapi)
- [Desplegar monorepos en Railway](https://docs.railway.com/deployments/monorepo)
- [PostgreSQL en Railway](https://docs.railway.com/databases/postgresql)
- [Volúmenes persistentes de Railway](https://docs.railway.com/volumes)
- [Variables Railway](https://docs.railway.com/variables/reference)
- [Builds y directorio raíz en Vercel](https://vercel.com/docs/builds/configure-a-build)
- [Rutas SPA en Vercel](https://vercel.com/docs/project-configuration/vercel-json)
- [Build y despliegue web de Flutter](https://docs.flutter.dev/deployment/web)
- [Instalar Flutter manualmente](https://docs.flutter.dev/install/manual)
- [flutter_secure_storage y requisito HTTPS](https://pub.dev/packages/flutter_secure_storage)
