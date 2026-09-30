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
- POS API y pantalla inicial para administración, con carrito, descuento, cliente opcional, selección de medio de pago, confirmación de venta, historial reciente y descuento de stock. El cobro Mercado Pago queda pendiente y no se marca como cobrado por la aplicación.
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

## Integraciones aún por conectar

- **Mercado Pago:** el taller no ha indicado si el cobro se realiza con una terminal Point física, un link/checkout o una API de pagos. La implementación actual registra la referencia y conserva el estado como pendiente; todavía no inicia ni confirma cargos.
- **Boleta electrónica:** el POS aún no emite DTE ni se conecta al SII o a un proveedor tributario. Debe definirse si se usará el portal/API del SII o un proveedor autorizado y configurarse el RUT, certificado y credenciales requeridos.
- **Gmail y Drive:** OAuth y la importación por acción de administrador ya están implementados. Se requiere configurar Google Cloud, scopes y variables en Railway; no hay lectura automática en segundo plano.
- **Google Calendar:** ya se sincronizan citas pendientes tras confirmación administrativa. Requiere credenciales Google y permisos Calendar.
- **Asistente IA:** la integración con OpenAI está implementada, apagada hasta configurar `AI_PROVIDER` y `AI_API_KEY`. Actualmente propone y ejecuta, tras confirmación, cambios de estado de órdenes como única acción mutante.
- **Móvil:** ya incluye recepción, listas guiadas, edición de resultados, cámara/archivos y resumen para el cliente. Falta generar un documento PDF final descargable, trabajo sin conexión y ampliar los formularios operativos restantes.

## Secuencia recomendada

Las fases 1 a 4 están implementadas. Las siguientes etapas propuestas son:

5. **Auditoría visual y de experiencia de usuario:** revisar pantallas y flujos de administración, mecánicos y clientes; establecer paleta de color, tipografía, jerarquía visual, componentes comunes, estados vacíos/errores/carga, contraste y accesibilidad; comprobar adaptación a móvil, tablet y web; documentar hallazgos priorizados y aplicar las mejoras acordadas. Entregables: inventario de pantallas, lista de problemas priorizada, guía visual/tokens y cambios de interfaz revisables.
6. **POS, pagos y documentos tributarios:** acordar terminal/flujo de Mercado Pago y proveedor o modalidad de boleta electrónica; ampliar venta para productos y servicios, y generar documentos fiscales según la integración definida.
7. **Operación móvil:** generar informe de inspección descargable, completar formularios restantes y agregar borradores/sincronización offline con resolución de conflictos.
8. **Operación y continuidad:** mover evidencias a almacenamiento de objetos protegido cuando aumente el volumen y definir respaldo, retención y recuperación.
