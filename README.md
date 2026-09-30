# Gestión de lubricentro

Aplicación para administrar clientes, vehículos, inspecciones, diagnósticos, cotizaciones, órdenes de trabajo, scanner, ventas e inventario. La solución se desarrollará por etapas, con API Python y clientes Flutter para el personal y los clientes.

## Estado

Primera base en desarrollo: API REST con persistencia SQLite, autenticación por roles, operaciones iniciales y carga de informes PDF del scanner LAUNCH. La app Flutter tiene inicio de sesión y vistas de consulta por rol. Consulta [estado del desarrollo](docs/estado-del-desarrollo.md) para ver las funciones que todavía requieren implementación o acceso externo.

## Requisitos

- Python 3.11 o superior.
- Flutter estable para ejecutar las aplicaciones móviles (no está instalado en el entorno actual).

## Ejecutar la API

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
cp .env.example .env
# Edita .env: define una clave JWT aleatoria y una contraseña inicial segura.
pip install -e .
uvicorn app.main:app --reload
```

La API se sirve en `http://127.0.0.1:8000`; la documentación interactiva está en `/docs`. En `APP_ENV=development`, el primer arranque crea un administrador, un mecánico y un cliente con contraseñas aleatorias, que se muestran una sola vez en la terminal. Anótalas y cámbialas después del primer acceso. En producción configura `APP_ENV=production`; las cuentas de demostración no se crearán. El acceso a módulos requiere Bearer JWT. La base SQLite y los archivos adjuntos se crean localmente. Para despliegue se debe configurar PostgreSQL, almacenamiento privado, HTTPS y secretos del proveedor en el servidor.

## Aplicación Flutter

Instala Flutter, entra a `mobile/`, ejecuta `flutter pub get` y `flutter run`. En el emulador Android, la dirección inicial de API es `http://10.0.2.2:8000`; para un teléfono físico, ingresa la dirección local del servidor que ambos dispositivos puedan alcanzar.

Para desplegar backend y PostgreSQL en Railway, y Flutter Web en Vercel, sigue el [manual de despliegue y pruebas](docs/despliegue-railway-vercel.md).

## Módulos MVP

- Clientes y vehículos.
- Órdenes de trabajo, inspecciones, diagnósticos y cotizaciones.
- Informes PDF del scanner, vinculados a vehículo y orden.
- Catálogo y movimientos de inventario.
- POS con registro de pagos y separación del estado del pago externo.
- Citas locales con campos para vincular eventos de Google Calendar.
- App Flutter inicial y portal de cliente restringido por cuenta.

## Integraciones externas

Las credenciales no se guardan en Flutter ni en el repositorio. Google Workspace (Gmail, Drive y Calendar) y el asistente IA tienen integración de backend configurable con secretos en Railway. El POS puede registrar pagos, pero todavía no confirma cobros Mercado Pago ni emite boletas electrónicas.

## Próximas etapas

Las fases 1 a 4 están implementadas. La fase 5 auditará y mejorará el diseño visual y la experiencia de uso por perfil y tamaño de pantalla. Revisa [el estado del desarrollo](docs/estado-del-desarrollo.md) y [el alcance de la fase 5](docs/fase-5-auditoria-visual.md).
