# Manual de configuración de Google y redes sociales en Gudex

Este manual explica cómo preparar las cuentas externas, configurar Railway y validar las integraciones desde Gudex. Las credenciales secretas se guardan únicamente en el backend; nunca deben escribirse en Flutter, en una planilla ni en el repositorio.

## 1. Requisitos previos

Necesitas:

- Acceso de administrador en Gudex.
- Acceso de administrador al proyecto de Railway.
- Un dominio HTTPS público para el backend, por ejemplo `https://api.midominio.cl`.
- Una cuenta de Google Workspace o Google personal con acceso al Calendar, Drive y Gmail.
- Para Instagram y Facebook, una cuenta de Meta Business, una Página de Facebook y una cuenta profesional de Instagram vinculada a esa Página.

En la aplicación, abre **Configuración → Integraciones**. La pantalla muestra el estado de cada proveedor, pero los secretos se configuran en Railway.

## 2. Configurar Google Workspace

### 2.1 Crear el proyecto

1. Entra a [Google Cloud Console](https://console.cloud.google.com/).
2. Crea un proyecto o selecciona uno existente.
3. En **APIs y servicios → Biblioteca**, habilita Gmail API, Google Drive API y Google Calendar API.
4. En **APIs y servicios → Pantalla de consentimiento OAuth**, configura nombre, correo de soporte, correo del desarrollador, dominios autorizados, política de privacidad y términos de servicio.
5. Si la aplicación está en modo **Testing**, agrega como usuario de prueba la cuenta que conectará Gudex. Para producción, completa la verificación de Google si los alcances lo requieren.

### 2.2 Crear las credenciales

1. Ve a **APIs y servicios → Credenciales → Crear credenciales → ID de cliente OAuth**.
2. Selecciona **Aplicación web**.
3. En **URI de redireccionamiento autorizado**, agrega exactamente:

```text
https://TU_BACKEND/auth/google/callback
```

El protocolo, dominio, ruta y barra final deben coincidir con `GOOGLE_REDIRECT_URI`; de lo contrario aparece `redirect_uri_mismatch`.

4. Guarda el Client ID y Client Secret. El secreto solo se copia a Railway.

Gudex solicita:

```text
https://www.googleapis.com/auth/gmail.readonly
https://www.googleapis.com/auth/gmail.send
https://www.googleapis.com/auth/drive.readonly
https://www.googleapis.com/auth/calendar.events
```

Estos permisos permiten buscar informes PDF en Gmail, enviar correos, leer archivos de Drive y crear o actualizar eventos de Calendar.

### 2.3 Variables de Railway

En el servicio backend de Railway, abre **Variables** y agrega:

```text
GOOGLE_CLIENT_ID=valor-obtenido-en-google
GOOGLE_CLIENT_SECRET=valor-obtenido-en-google
GOOGLE_REDIRECT_URI=https://TU_BACKEND/auth/google/callback
GOOGLE_FRONTEND_REDIRECT_URL=https://TU_FRONTEND/configuracion/integraciones
GOOGLE_DRIVE_FOLDER_ID=id-opcional-de-la-carpeta-de-scanners
GOOGLE_CALENDAR_ID=primary
```

`GOOGLE_DRIVE_FOLDER_ID` es opcional. Para obtenerlo, abre la carpeta en Drive y copia el texto posterior a `/folders/` en la URL.

Después de guardar las variables, realiza un redeploy. En la consola de Railway puedes ejecutar:

```bash
cd /app
alembic -c alembic.ini upgrade head
```

### 2.4 Conectar la cuenta en Gudex

1. Inicia sesión como administrador.
2. Abre **Configuración → Integraciones → Google Workspace**.
3. Pulsa **Conectar o renovar Google**.
4. Selecciona la cuenta correcta y acepta los permisos.
5. Regresa a Gudex y pulsa actualizar.
6. Prueba buscar PDFs en Gmail, buscar PDFs en Drive y sincronizar citas pendientes.

Google exige que la URI de redirección coincida exactamente y recomienda HTTPS y `state` para proteger OAuth. Referencia: [OAuth 2.0 para aplicaciones de servidor web](https://developers.google.com/identity/protocols/oauth2/web-server).

## 3. Configurar Facebook e Instagram mediante Meta

La aplicación muestra el estado de Meta y mantiene la publicación con aprobación humana. El callback OAuth de Meta y la publicación automática todavía requieren una entrega posterior; no consideres la cuenta conectada hasta que Gudex muestre una autorización válida.

### 3.1 Preparar las cuentas

1. Entra a [Meta Business Suite](https://business.facebook.com/) y crea o selecciona el negocio.
2. Verifica que la Página de Facebook pertenezca al negocio.
3. Cambia Instagram a cuenta **Profesional** (Empresa o Creador).
4. Vincula Instagram con la Página de Facebook.
5. Anota el ID de la Página y el ID de la cuenta profesional de Instagram.

La cuenta de Instagram debe ser profesional; una cuenta personal no puede usar publicación de Instagram Graph API.

### 3.2 Crear la aplicación Meta

1. Entra a [Meta for Developers](https://developers.facebook.com/apps/) y selecciona **Create App**.
2. Elige un tipo orientado a negocios y agrega Facebook Login for Business e Instagram Graph API.
3. Cuando se habilite el callback Meta en Gudex, en la configuración OAuth agrega:

```text
https://TU_BACKEND/auth/meta/callback
```

4. Configura política de privacidad, términos, dominio y correo de contacto.
5. Durante las pruebas agrega como usuarios de la aplicación a los administradores que conectarán las cuentas.

Los permisos exactos dependen de la versión de Graph API y del flujo aprobado. Para publicación y lectura suelen solicitarse `instagram_basic`, `instagram_content_publish`, `pages_show_list`, `pages_read_engagement` y `pages_manage_posts`. Solicita solo los permisos necesarios.

Referencias: [Instagram Graph API](https://developers.facebook.com/docs/instagram-api/) y [Facebook Login](https://developers.facebook.com/docs/facebook-login/).

### 3.3 Variables de Railway

```text
META_APP_ID=id-de-la-aplicacion-meta
META_APP_SECRET=secreto-de-la-aplicacion-meta
META_REDIRECT_URI=https://TU_BACKEND/auth/meta/callback
META_ACCESS_TOKEN=token-de-pagina-o-sistema
META_INSTAGRAM_ACCOUNT_ID=id-de-instagram-profesional
META_FACEBOOK_PAGE_ID=id-de-la-pagina
```

No pegues secretos ni tokens en capturas, tickets, planillas o código. Si un token se expone, revócalo en Meta y genera uno nuevo.

### 3.4 Validar desde Gudex

1. Haz redeploy después de guardar las variables.
2. Abre **Configuración → Integraciones → Redes sociales**.
3. Comprueba que Meta aparezca configurado y que Instagram y Facebook muestren sus IDs.
4. En **Contenido y redes**, crea una publicación desde un producto.
5. Revisa la vista previa, mueve el contenido a revisión y apruébalo.
6. Hasta completar OAuth y la revisión de Meta, utiliza **Exportar** y publica manualmente.

## 4. Configuración de IA para contenido

En Railway agrega:

```text
AI_PROVIDER=openai
AI_API_KEY=clave-del-proveedor
AI_MODEL=gpt-5-mini
AI_BASE_URL=https://api.openai.com/v1
```

En **Configuración → Integraciones → Asistente de IA**, pulsa **Cambiar modelo** para seleccionar un modelo disponible.

## 5. Checklist de producción

- [ ] Las URLs OAuth usan HTTPS.
- [ ] Google y Meta tienen las mismas URI que Railway.
- [ ] Google aparece conectado en Gudex.
- [ ] Gmail, Drive y Calendar funcionan con datos de prueba.
- [ ] La Página y el Instagram profesional están vinculados.
- [ ] Los permisos de Meta están aprobados.
- [ ] Los IDs de ambas cuentas aparecen en Integraciones.
- [ ] Se probó crear, revisar, exportar y aprobar una publicación.
- [ ] No hay secretos en el repositorio ni en Flutter.

## 6. Problemas frecuentes

**`redirect_uri_mismatch`**: la URI de Railway no coincide carácter por carácter con la URI registrada. Revisa HTTPS, puerto, ruta y barra final.

**Google dice que la aplicación no está verificada**: agrega la cuenta como usuario de prueba o completa la verificación de la pantalla de consentimiento.

**No aparecen PDFs**: confirma APIs habilitadas, permisos concedidos y la consulta `GOOGLE_GMAIL_QUERY`.

**Instagram aparece sin cuenta**: verifica que sea profesional, esté vinculada a una Página y que el ID sea el de la cuenta profesional.

**Meta rechaza la publicación**: revisa permisos aprobados, token vigente, tipo de cuenta y formato de imagen.

**El menú indica que faltan credenciales**: revisa variables del backend, guarda cambios y redeploya. Las variables del frontend no sustituyen las del backend.

**La migración no se aplica**: desde Shell, estando en `/app`, ejecuta:

```bash
alembic -c alembic.ini upgrade head
alembic -c alembic.ini current
```

La revisión debe ser `20261007_0009` o posterior.

## 7. Seguridad y operación

Usa una cuenta administrativa separada, limita permisos, rota secretos y desconecta cuentas cuando se retire el acceso. Si Google o Meta revocan un token, vuelve a autorizar desde Integraciones; no edites credenciales directamente en la base de datos.
