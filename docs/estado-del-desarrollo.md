# Estado del desarrollo

## Base implementada

- API FastAPI y persistencia SQLModel/SQLite para desarrollo.
- Inicio de sesión con JWT, contraseñas Argon2 y alta de cuentas de equipo por administración.
- En desarrollo, creación única de cuentas de demostración para administrador, mecánico y cliente; contraseñas aleatorias emitidas al primer arranque y cambio de contraseña con invalidación de sesiones previas.
- Roles de administración, mecánico y cliente. La cuenta cliente queda acotada a rutas del portal y sus recursos.
- Clientes, vehículos, órdenes, inspecciones, diagnósticos en órdenes, cotizaciones, aprobación del cliente, citas, catálogo y movimientos de stock.
- En Flutter, administración puede registrar clientes y vehículos, abrir órdenes de trabajo, actualizar su estado y diagnóstico, y agregar puntos de inspección con resultados y mediciones; mecánicos pueden revisar y completar las órdenes.
- Desde el detalle de una orden, el equipo puede preparar cotizaciones con descripción, mano de obra, repuestos y observaciones, y publicarlas para aprobación del cliente con confirmación explícita. El cliente ve los importes en su portal y puede aprobar o rechazar.
- Inventario móvil: el equipo consulta y filtra productos por nombre/código y stock bajo; administración puede dar de alta productos y registrar ingresos o salidas con motivo. Los movimientos quedan consultables como historial y la API rechaza ajustes de stock hechos por otros roles.
- POS API y pantalla de administración, con carrito, descuentos, cliente opcional, productos y servicios, historial reciente, descuento de stock y comprobante interno PDF. Checkout Pro registra el pago como pendiente hasta que el backend valide el webhook y consulte a Mercado Pago.
- Fase 5: paleta y cabecera alineadas al logo oficial Gudex; el logo se usa en Flutter Web/móvil y en PDFs generados por la app. El cliente puede imprimir/guardar informes consolidados de inspección y comprobantes internos de venta desde la app.
- Fase 6 (primera integración): POS permite líneas manuales de servicio y productos de inventario. Checkout Pro crea preferencias desde el backend y confirma pagos solo al recibir webhook verificado y consultar el estado en Mercado Pago. La terminal Point se registra como pago externo confirmado por el operador.
- Recepción de informe PDF LAUNCH, asociado a vehículo y opcionalmente a una orden; el original se conserva en almacenamiento local privado.
- App Flutter para autenticación y módulos por rol. Clientes pueden revisar y responder cotizaciones; administración dispone de formularios de recepción, registro de clientes/vehículos, inspecciones, cotizaciones y un POS inicial.
- Preparación de despliegue: PostgreSQL/psycopg, CORS configurable, bootstrap admin para producción y compilación Flutter Web para Vercel.
- Migraciones Alembic ejecutadas antes de cada despliegue Railway. La primera revisión adopta instalaciones existentes sin borrar sus datos y crea las tablas nuevas.
- Validación y normalización de RUT chileno, patente y VIN; rechazo de kilometrajes negativos y duplicados de RUT, correo, patente, VIN y SKU.
- Permisos explícitos para administración y equipo en las operaciones críticas, además del aislamiento del portal del cliente.
- Recepción digital con combustible, daños visibles, accesorios, observaciones y registro de conformidad.
- Plantillas configurables de inspección. La instalación incluye mantención preventiva, mecánica rápida y scanner LAUNCH.
- Resultados de inspección editables: no inspeccionado, normal, observación, falla y no aplica.
- Fotografías, imágenes y PDF asociados a una orden, capturables desde cámara, galería o selector de archivos en Flutter.
- Informe consolidado de inspección para el equipo y el cliente, con recepción, resumen de resultados, evidencias e informes LAUNCH asociados.
- Pruebas automatizadas del backend para validaciones, permisos y el flujo completo de inspección.
- Fase 3: autorización OAuth Google de backend, almacenamiento cifrado de tokens, listado/importación manual de informes PDF desde Gmail/Drive y sincronización explícita de citas a Calendar.
- Fase 4: asistente Responses API con salida estructurada, contextos acotados por rol, portal de cliente aislado, registro de propuestas/confirmaciones y ejecución confirmada de cambios de estado permitidos.
- Flutter: pantalla de integraciones para administración y acceso al asistente para cada rol; Google OAuth abre en navegador externo.
- Fase 5 (primera pasada): tema visual compartido Gudex, acceso renovado, shell adaptable con contenido centrado, etiquetas de navegación compactas, tarjetas de estado y estados de carga/error/vacío más claros. Pendiente verificación visual en Flutter Web, Android y iOS.
- Auditoría de vistas: se documentó el inventario por rol y las pantallas faltantes o incompletas. La prioridad operativa es ficha de vehículo e historial, agenda, asignación de técnicos, flujo del scanner LAUNCH y solicitud de citas desde el portal. Ver `docs/auditoria-vistas-pendientes.md`.

- Vistas operativas P0: ficha navegable de vehículo con historial de órdenes, citas e informes LAUNCH; agenda semanal para equipo con confirmación de solicitudes; bandeja Mis trabajos para mecánicos y asignación de responsable real por administración; carga y consulta de PDF del scanner LAUNCH; y solicitud de cita desde el portal de clientes.
- Las asignaciones se guardan en una tabla independiente de órdenes para que la migración sea aditiva y mantenga las órdenes ya existentes. La API aplica los permisos: solo administración asigna, mientras cada mecánico solo consulta su propia bandeja.
- Panel principal de administración con órdenes activas o atrasadas, citas y solicitudes del día, alertas de stock, cotizaciones pendientes y ventas cobradas. Cada indicador abre el módulo operativo correspondiente.
- Administración puede seleccionar el modelo del asistente desde Integraciones. Gudex consulta los modelos disponibles para la cuenta configurada, filtra los compatibles con Responses y salida JSON estructurada, y conserva la selección sin exponer la clave de API.
- CRUD administrativo ampliado: usuarios, clientes, vehículos, órdenes, productos, citas, cotizaciones en borrador, inspecciones e informes scanner cuentan con rutas de creación, lectura, modificación y eliminación o archivo según su trazabilidad. Los productos se archivan, las citas y órdenes con historial se cancelan y los registros que tienen dependencias no se borran físicamente.
- Flutter: clientes y vehículos ya pueden editarse y eliminarse desde sus menús de acciones; el backend conserva las restricciones de integridad y devuelve un mensaje si existe historial asociado. El inventario permite editar productos y archivarlos sin borrar sus movimientos.
- Preferencia visual: toda la aplicación usa los textos visibles en español y traduce estados, perfiles y nombres de campos recibidos desde la API. El modo claro/oscuro se aplica globalmente, se guarda en el dispositivo y está disponible desde el inicio de sesión, activación del portal y la aplicación autenticada.

## Integraciones aún por conectar

- **Mercado Pago:** Checkout Pro está integrado como opción en línea. Falta configurar credenciales de prueba/producción y webhook en Railway y completar una transacción de prueba en la cuenta del taller. Point/terminal física se ingresa como tarjeta externa; la aplicación no recibe confirmación automática de ese terminal.
- **Boleta electrónica:** pendiente definir proveedor/modalidad, emisor y habilitación tributaria. El PDF Gudex es un comprobante interno claramente rotulado como no tributario; no sustituye ni se presenta como boleta electrónica. La emisión fiscal requiere el proceso/habilitación aplicable al contribuyente en SII o integrar un proveedor autorizado.
- **Gmail y Drive:** OAuth y la importación por acción de administrador ya están implementados. Se requiere configurar Google Cloud, scopes y variables en Railway; no hay lectura automática en segundo plano.
- **Google Calendar:** ya se sincronizan citas pendientes tras confirmación administrativa. Requiere credenciales Google y permisos Calendar.
- **Asistente IA:** la integración con OpenAI está implementada, apagada hasta configurar `AI_PROVIDER` y `AI_API_KEY`. Actualmente propone y ejecuta, tras confirmación, cambios de estado de órdenes como única acción mutante.
- **Portal de clientes:** administración puede crear una cuenta de portal al registrar el cliente. Gudex genera una invitación de un solo uso, con vencimiento, y puede enviarla desde Gmail cuando la cuenta Google autorice `gmail.send`; las contraseñas nunca se envían por correo. Incluye recuperación por enlace temporal.
- **Móvil:** ya incluye recepción, listas guiadas, edición de resultados, cámara/archivos, resumen para el cliente e impresión/guardado del informe de inspección PDF. El detalle de orden conserva localmente borradores de estado, diagnóstico, recepción y resultados de inspección existentes, y los recupera tras una conexión fallida. Faltan una cola de sincronización, resolución de conflictos y ampliar los formularios operativos restantes.

## Secuencia recomendada

Las fases 1 a 4 están implementadas. Las siguientes etapas propuestas son:

5. **Auditoría visual y de experiencia de usuario:** primera pasada aplicada con marca Gudex; pendiente revisión visual real en Android/iOS/Web y verificación de contraste/tamaños en dispositivos.
6. **POS, pagos y documentos tributarios:** POS de productos y servicios, comprobante PDF interno y Checkout Pro implementados; pendiente probar credenciales/webhook reales o sandbox. Falta definir e integrar boleta electrónica mediante la opción tributaria habilitada para el taller.
7. **Operación móvil:** completar formularios restantes, añadir borradores para nuevas inspecciones/evidencias y agregar sincronización con resolución de conflictos.
8. **Operación y continuidad:** mover evidencias a almacenamiento de objetos protegido cuando aumente el volumen y definir respaldo, retención y recuperación.
