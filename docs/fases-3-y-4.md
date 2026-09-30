# Fases 3 y 4: Google Workspace y asistente de IA

## Fase 3: Google Workspace

La cuenta Google del taller se conecta desde la app con OAuth de servidor. El backend solicita `openid`, `email`, `gmail.readonly`, `drive.readonly` y `calendar.events`. Los refresh/access tokens se cifran con Fernet antes de guardarlos en PostgreSQL. El estado OAuth dura 10 minutos, es de un solo uso y se almacena como hash.

La integración ofrece:

- Búsqueda manual de PDFs en Gmail, con la búsqueda definida por `GOOGLE_GMAIL_QUERY` (por defecto adjuntos PDF recientes de hasta 30 días).
- Listado de PDFs dentro de una carpeta Drive configurada con `GOOGLE_DRIVE_FOLDER_ID`.
- Importación manual de un PDF LAUNCH tras elegir el vehículo y, opcionalmente, la orden. Se valida firma `%PDF-`, tamaño máximo e idempotencia; se guarda una copia en el volumen del taller.
- Sincronización explícita de hasta 50 citas pendientes a Calendar. Crear/actualizar el evento se realiza al pulsar “Sincronizar citas pendientes” y queda visible en Gudex.
- Renovación de access token y desconexión/revocación de la cuenta.

La aplicación consulta Gmail/Drive únicamente cuando un administrador lo solicita; no se configura un sondeo en segundo plano. No se envían correos a clientes todavía. Calendar sincroniza las citas pendientes al calendario configurado.

### Configuración de Google Cloud

1. Crea o selecciona un proyecto en Google Cloud y activa Gmail API, Google Drive API y Google Calendar API.
2. Configura la pantalla de consentimiento OAuth como aplicación externa o interna según la cuenta del taller. Durante pruebas, añade los correos administradores como usuarios de prueba.
3. Crea credenciales OAuth de tipo **Web application**. Añade el dominio del backend a los orígenes autorizados si corresponde y el callback exacto a **Authorized redirect URIs**:

   `https://<dominio-api-railway>/auth/google/callback`

4. En Railway, define `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` y el mismo URI en `GOOGLE_REDIRECT_URI`.
5. Genera una clave Fernet con `python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'` y guárdala como `INTEGRATION_ENCRYPTION_KEY` en Railway. Respalda esta clave en un gestor seguro: sin ella no se pueden descifrar los tokens guardados.
6. Define `GOOGLE_DRIVE_FOLDER_ID` si importarás informes desde Drive. Crea una carpeta exclusiva para informes del scanner y concede acceso a la cuenta OAuth.
7. Opcionalmente define `GOOGLE_GMAIL_QUERY`, `GOOGLE_CALENDAR_ID` (por defecto `primary`) y `GOOGLE_FRONTEND_REDIRECT_URL` (destino HTTPS luego del callback).
8. Inicia sesión como administrador, abre **Integraciones → Conectar o renovar Google** y completa el consentimiento. Luego prueba buscar PDFs en Gmail/Drive y sincroniza una cita de prueba.

Drive `drive.readonly` da lectura sobre Drive porque la aplicación recibe el ID de una carpeta ya existente. Si Google exige verificación de scopes para el tipo de cuenta, completa el proceso de consentimiento antes de usarlo en producción.

## Fase 4: asistente de IA

La capa de IA usa la API Responses de OpenAI mediante HTTP desde el backend. `AI_PROVIDER=openai`, `AI_API_KEY` y `AI_MODEL` se configuran solo en Railway. El request usa `store=false`, salida estructurada y un límite configurable.

El asistente se abre con el icono de destellos:

- **Cliente:** preguntas generales con sus propios vehículos y órdenes recientes. El backend aplica el aislamiento por `customer_id`; no entrega datos operativos internos.
- **Mecánico:** consultas generales o con contexto de orden, vehículo, inventario o agenda. No recibe costos de productos.
- **Administrador:** los mismos contextos; inventario incluye precios/costos autorizados.

La respuesta separa hechos registrados, causas posibles, verificaciones sugeridas y advertencias de seguridad. El modelo no obtiene acceso SQL ni puede ejecutar funciones arbitrarias. Actualmente solo puede proponer `update_work_order_status` en contexto de una orden; el usuario debe pulsar **Confirmar acción**, y el backend vuelve a validar rol, estado y permiso mecánico antes de cambiarlo. Rechazos, propuestas y resultados quedan auditados.

El backend retiene solicitud, respuesta y resultado de acciones durante 90 días por defecto (`AI_AUDIT_RETENTION_DAYS`), incluidas las fallas del proveedor. La limpieza oportunista se ejecuta al recibir nuevas consultas. Evita incluir datos personales innecesarios en las preguntas. La disponibilidad del proveedor no afecta los módulos normales: una llamada sin configuración o con error devuelve un mensaje controlado.

### Variables nuevas de Railway

| Variable | Uso |
|---|---|
| `INTEGRATION_ENCRYPTION_KEY` | Clave Fernet para cifrar tokens Google guardados en PostgreSQL |
| `GOOGLE_CLIENT_ID` | ID de cliente OAuth Web |
| `GOOGLE_CLIENT_SECRET` | Secreto OAuth Web |
| `GOOGLE_REDIRECT_URI` | Callback HTTPS exacto registrado en Google Cloud |
| `GOOGLE_FRONTEND_REDIRECT_URL` | Opcional; retorno HTTPS al frontend tras el callback |
| `GOOGLE_DRIVE_FOLDER_ID` | Opcional; carpeta de PDFs del scanner |
| `GOOGLE_CALENDAR_ID` | Opcional; por defecto `primary` |
| `GOOGLE_GMAIL_QUERY` | Opcional; filtro de mensajes con adjuntos PDF |
| `AI_PROVIDER` | `openai` para habilitar el asistente |
| `AI_API_KEY` | Clave privada del proveedor, solo en Railway |
| `AI_MODEL` | Modelo habilitado en la cuenta; predeterminado `gpt-5-mini` |
| `AI_BASE_URL` | Opcional; por defecto `https://api.openai.com/v1` |
| `AI_MAX_OUTPUT_TOKENS` | Límite de generación; predeterminado 900 |
| `AI_AUDIT_RETENTION_DAYS` | Retención de auditoría, predeterminado 90 días |

Si los servicios Google o IA no se van a utilizar todavía, deja sus credenciales sin definir: el backend seguirá funcionando y las pantallas indicarán que falta configuración.

## Verificación manual

1. Inicia sesión con administrador y abre `/api/v1/integrations/status`; verifica que indique las configuraciones presentes y el estado real de Google.
2. Conecta Google. Si el callback devuelve `redirect_uri_mismatch`, compara el valor exacto de Railway con el URI autorizado en Google Cloud.
3. Importa un PDF de prueba de Gmail o Drive, asígnalo a vehículo/orden y comprueba que aparezca en inspección/informes LAUNCH. Intenta importar el mismo archivo de nuevo; Gudex debe responder conflicto.
4. Registra una cita, pulsa la sincronización desde Integraciones y verifica `google_event_id` y `sync_status=synced` en `/api/v1/appointments`.
5. Consulta el asistente con una orden. Comprueba que diferencia síntomas e hipótesis. Si propone un estado, descártalo y luego repite confirmándolo; el registro solo debe cambiar en la segunda ocasión.
6. Inicia sesión como cliente: el asistente solo debe consultar sus vehículos/órdenes. Una llamada directa con ID ajeno debe responder 404. Intenta usar rutas de equipo con ese token; deben seguir bloqueadas.

## Migración

La revisión `20260930_0002` agrega tablas de credenciales OAuth, estados OAuth, importaciones externas y auditoría de IA. Antes del despliegue se ejecuta `alembic upgrade head`; comprueba que la revisión reportada sea `20260930_0002`.
