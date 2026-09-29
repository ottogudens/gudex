# Estado del desarrollo

## Base implementada

- API FastAPI y persistencia SQLModel/SQLite para desarrollo.
- Inicio de sesión con JWT, contraseñas Argon2 y alta de cuentas de equipo por administración.
- En desarrollo, creación única de cuentas de demostración para administrador, mecánico y cliente; contraseñas aleatorias emitidas al primer arranque y cambio de contraseña con invalidación de sesiones previas.
- Roles de administración, mecánico y cliente. La cuenta cliente queda acotada a rutas del portal y sus recursos.
- Clientes, vehículos, órdenes, inspecciones, diagnósticos en órdenes, cotizaciones, aprobación del cliente, citas, catálogo y movimientos de stock.
- En Flutter, administración puede registrar clientes y vehículos, abrir órdenes de trabajo, actualizar su estado y diagnóstico, y agregar puntos de inspección con resultados y mediciones; mecánicos pueden revisar y completar las órdenes.
- POS API y pantalla inicial para administración, con carrito, descuento, cliente opcional, selección de medio de pago, confirmación de venta, historial reciente y descuento de stock. El cobro Mercado Pago queda pendiente y no se marca como cobrado por la aplicación.
- Recepción de informe PDF LAUNCH, asociado a vehículo y opcionalmente a una orden; el original se conserva en almacenamiento local privado.
- App Flutter para autenticación y módulos por rol. Clientes pueden responder cotizaciones; administración dispone de formularios de recepción, registro de clientes/vehículos, inspecciones y un POS inicial.
- Preparación de despliegue: PostgreSQL/psycopg, CORS configurable, bootstrap admin para producción y compilación Flutter Web para Vercel.

## Integraciones aún por conectar

- **Mercado Pago:** el taller no ha indicado si el cobro se realiza con una terminal Point física, un link/checkout o una API de pagos. La implementación actual registra la referencia y conserva el estado como pendiente; todavía no inicia ni confirma cargos.
- **Boleta electrónica:** el POS aún no emite DTE ni se conecta al SII o a un proveedor tributario. Debe definirse si se usará el portal/API del SII o un proveedor autorizado y configurarse el RUT, certificado y credenciales requeridos.
- **Gmail y Drive:** aún no hay autorización OAuth ni importador automático. El flujo manual de carga PDF ya funciona; la automatización podrá leer una etiqueta Gmail dedicada o una carpeta Drive elegida.
- **Google Calendar:** las citas se guardan en la aplicación; `sync_status` queda pendiente. Todavía no se sincronizan eventos con la agenda real.
- **Asistente IA:** la estructura conserva configuración de proveedor, pero no se envían datos a un modelo. Falta elegir proveedor y definir las herramientas por rol.
- **Móvil:** la app Flutter es una base de acceso y consulta. Faltan formularios de operación, POS visual, inspección guiada y experiencia móvil completa por perfil.

## Secuencia recomendada

1. Acordar el flujo tributario y el tipo de integración de Mercado Pago.
2. Completar la publicación de cotizaciones, listas de inspección predefinidas, edición de inventario y el resto de formularios operativos; ampliar el POS con servicios y documentos tributarios.
3. Autorizar Google por OAuth con permisos mínimos; importar reportes del scanner y sincronizar calendario/correos.
4. Agregar el asistente IA con herramientas de solo lectura primero y confirmación explícita para acciones.
5. Migrar a PostgreSQL, configurar almacenamiento protegido y desplegar; agregar migraciones antes de producción.
