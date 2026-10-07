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
- POS de productos y servicios, con descuento de stock, Checkout Pro opcional y comprobante PDF interno.
- PDFs de inspección con marca Gudex para el equipo y el portal del cliente.
- Citas locales con campos para vincular eventos de Google Calendar.
- App Flutter inicial y portal de cliente restringido por cuenta.

## Contenido y redes

Administración dispone de marca, borradores desde productos o servicios, generación por plantilla o IA, revisión, calendario editorial y exportación PNG + texto. La publicación en redes es manual en esta etapa. Consulta la [guía del módulo](docs/contenido-y-redes.md).

## Integraciones externas

Las credenciales no se guardan en Flutter ni en el repositorio. Google Workspace (Gmail, Drive y Calendar), el asistente IA y Mercado Pago usan integraciones de backend configurables en Railway. Checkout Pro confirma pagos mediante webhook verificado. La aplicación no emite aún boletas electrónicas: sus PDFs se rotulan como comprobantes internos y no sustituyen un DTE.
Consulta el [manual de configuración de Google y redes sociales](docs/manual-integraciones-google-redes-sociales.md).

## Próximas etapas

Las fases 1 a 4 están implementadas; las fases 5 y 6 ya tienen una primera entrega. Lo siguiente es validar visualmente la aplicación en dispositivos y navegador, probar Mercado Pago con credenciales sandbox o reales, y avanzar con operación sin conexión, respaldo de evidencias y la decisión tributaria. Revisa [el estado del desarrollo](docs/estado-del-desarrollo.md) y [el alcance de la fase 5](docs/fase-5-auditoria-visual.md).

## Servicios y categorías

Administración → **Servicios** permite buscar, agregar, editar y eliminar servicios y categorías.
El catálogo se guarda en la base de datos y alimenta Cotizaciones y Contenido y redes.
La migración `20261006_0007` importa el catálogo inicial; los reinicios no restauran servicios eliminados.
Antes de eliminar una categoría, mueve o elimina sus servicios. Las cotizaciones ya emitidas mantienen sus descripciones.
El equipo mecánico puede consultar el catálogo; solo administración puede modificarlo.

## Diagnóstico de fallas con IA

En **Asistente Gudex**, activa **Diagnóstico de falla**, selecciona el vehículo o la orden y describe
los síntomas, las condiciones en que aparecen y las pruebas realizadas. El backend reúne los datos
del vehículo, hasta ocho órdenes con inspecciones y antecedentes, los informes de scanner del vehículo
(incluidos los que no tienen orden) y los adjuntos de sus órdenes. Los archivos importados de Drive que
estén guardados como informes de scanner participan del mismo modo.

La IA separa hechos con referencias, hipótesis y pruebas sugeridas. No sobrescribe el diagnóstico ni
cambia la orden. La pantalla muestra qué documentos se pudieron leer. Se extrae texto de hasta ocho
PDF de 10 MB como máximo, hasta veinte páginas y 4000 caracteres por documento. Las fotos solo aportan
su descripción; los PDF escaneados sin texto requieren OCR o transcripción previa. No consulta documentos
externos que no estén importados o vinculados al vehículo. Solo el equipo del taller accede a este modo.

Requiere `AI_PROVIDER=openai`, `AI_API_KEY` y un modelo compatible configurado en Integraciones.
El diagnóstico utiliza un máximo de 3000 tokens de respuesta. Los documentos se envían al proveedor como
contexto autorizado; las fuentes almacenadas en la auditoría incluyen metadatos, sin duplicar su texto.

## Carga masiva de productos y servicios

Administración dispone de **Carga masiva** en Inventario y Servicios. Descarga un Excel `.xlsx` con
los registros actuales (también productos archivados), edita la hoja **Datos**, sube el archivo,
revisa los cambios y confirma. Las filas nuevas llevan **ID** y la columna oculta **_version** vacíos.
Conserva ambas columnas en las filas existentes. No cambies los encabezados. Eliminar filas del Excel
no elimina registros. En productos, **Activo=No** archiva y **Activo=Sí** reactiva.

- Productos: ID, SKU, Nombre, Categoría, Unidad, Stock, Stock mínimo, Costo CLP, Precio CLP, Activo.
- Servicios: ID, Código, Nombre, Categoría, Descripción, Precio CLP.
- Códigos y SKU se escriben como texto para conservar ceros iniciales. Importes CLP: enteros sin símbolos;
  cantidades: números no negativos. No se admiten fórmulas ni macros. Máximo 5000 filas y 5 MB.
- La vista previa muestra errores por fila, valores anteriores/nuevos y categorías de servicios que se
  crearán. Nada se modifica hasta confirmar; cualquier error bloquea la importación completa.
- La referencia de versión detecta cambios desde la descarga. Al confirmar se vuelve a validar y se
  bloquean los registros durante la transacción para no sobrescribir ventas o ajustes concurrentes.
- Los cambios de stock generan movimientos `bulk_import` con referencia al ID de importación.
- Las revisiones vencen en 30 minutos y solo su administrador autor puede confirmarlas. Repetir una
  confirmación no duplica registros ni movimientos. El historial conserva autor, fecha, archivo y totales;
  el backend conserva también el detalle de cambios, sin guardar el archivo Excel original.

**Despliegue:** ejecutar `alembic -c alembic.ini upgrade head` desde el directorio del backend contra
la misma base que usa la API. La nueva revisión es `20261007_0008` y crea el historial de importaciones.
La ruta de predespliegue de Railway ya contiene este comando; verificar que se ejecute antes de iniciar
la API, especialmente si el entorno aún tenía pendiente la migración del catálogo `20261006_0007`.
