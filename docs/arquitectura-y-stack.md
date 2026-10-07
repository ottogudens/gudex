# Gudex: arquitectura, estructura y stack tecnológico

## 1. Descripción general

Gudex es una aplicación para administrar un lubricentro. Reúne clientes y vehículos, trabajo de taller, inspecciones, diagnósticos, cotizaciones, inventario, ventas, agenda e integraciones externas.

La solución se divide en una API backend y un cliente Flutter que puede ejecutarse en web y dispositivos móviles.

```text
Flutter Web / Android / iOS
             │
             │ REST + JSON + HTTPS
             ▼
       FastAPI en Railway
        ├── PostgreSQL
        ├── archivos e informes PDF
        └── servicios externos
             ├── Google Workspace
             ├── proveedor de IA
             └── Mercado Pago
```

La aplicación cliente no contiene secretos de proveedores. Las credenciales externas se administran en el backend mediante variables de entorno y, cuando se guardan credenciales OAuth, se cifran.

## 2. Stack tecnológico

| Área | Tecnología |
|---|---|
| Aplicación cliente | Flutter y Dart |
| Estado cliente | Riverpod |
| Almacenamiento seguro en cliente | Flutter Secure Storage |
| API | Python, FastAPI y Uvicorn |
| Modelos y validación | SQLModel y Pydantic |
| Base de datos | PostgreSQL en Railway; SQLite para desarrollo local y pruebas |
| Migraciones | Alembic |
| HTTP cliente | `http` en Flutter y `httpx` en Python |
| Autenticación | JWT Bearer, roles y contraseñas con Argon2 |
| PDF | ReportLab; pypdf para extracción de texto |
| Excel | openpyxl |
| Imágenes | Pillow |
| Pruebas backend | pytest y FastAPI TestClient |
| Despliegue backend | Railway |
| Despliegue Flutter Web | Vercel |

Las dependencias del backend están declaradas en `backend/pyproject.toml`; las del cliente en `mobile/pubspec.yaml`.

## 3. Estructura del repositorio

```text
Gudex/
├── backend/
│   ├── app/
│   │   ├── routers/       # rutas de integraciones, servicios y cargas masivas
│   │   ├── services/      # IA, Google, documentos, diagnósticos y catálogos
│   │   ├── assets/        # recursos para la API
│   │   ├── main.py        # rutas centrales de la API
│   │   ├── models.py      # modelos de datos
│   │   ├── schemas.py     # contratos y validación
│   │   ├── security.py    # autenticación y permisos
│   │   └── config.py      # configuración por entorno
│   ├── alembic/versions/  # historial de migraciones
│   └── tests/             # pruebas de backend
├── mobile/
│   ├── lib/
│   │   ├── screens/       # POS, inventario, taller, agenda, clientes, etc.
│   │   ├── providers/     # estado de autenticación y preferencias
│   │   ├── services/      # cliente API y almacenamiento de borradores
│   │   └── main.dart      # navegación y composición principal
│   ├── assets/            # logo y datos iniciales del catálogo
│   ├── web/               # entrada y recursos de Flutter Web
│   └── scripts/           # compilación para Vercel
├── docs/                  # manuales, alcance y estado del desarrollo
├── railway.json           # configuración de despliegue en raíz
└── README.md
```

La navegación principal de Flutter está en `mobile/lib/main.dart`. Las rutas centrales de la API están en `backend/app/main.py`; integraciones, catálogo de servicios y carga masiva están organizados en routers separados.

## 4. Módulos funcionales

- **Clientes y vehículos:** datos de clientes, vehículos, historial y portal de clientes.
- **Órdenes de trabajo:** estados del taller, asignación de mecánicos, inspecciones, evidencias y antecedentes.
- **Scanner:** informes PDF LAUNCH vinculados a vehículos y órdenes.
- **Diagnóstico con IA:** utiliza síntomas, datos del vehículo, órdenes, inspecciones e informes relacionados. Presenta hechos con referencias, hipótesis y pruebas sugeridas.
- **Cotizaciones:** creación, emisión de PDF y aprobación del cliente.
- **Servicios y categorías:** catálogo editable con precios en CLP.
- **Inventario:** productos, niveles de stock, mínimos y movimientos.
- **POS:** venta de productos y servicios, descuentos, medios de pago, descuento de inventario, comprobante interno y cobro de órdenes listas para pago.
- **Carga masiva:** exportación e importación de productos y servicios mediante Excel `.xlsx`, con vista previa, validación y confirmación.
- **Agenda:** citas y sincronización con Google Calendar.
- **Contenido y redes:** identidad de marca, borradores, generación de textos e imágenes, revisión y exportación de publicaciones.
- **Administración:** usuarios, roles, modelo de IA e integraciones.

## 5. Seguridad y persistencia

La API utiliza JWT Bearer y permisos según rol: administrador, mecánico o cliente. Las contraseñas se guardan con hash Argon2. El cliente almacena el token de sesión mediante almacenamiento seguro del sistema.

Alembic administra los cambios de esquema. Railway ejecuta las migraciones antes de iniciar la API mediante `preDeployCommand`. Los archivos subidos, como informes del scanner y evidencias, requieren almacenamiento persistente configurado en el entorno de producción.

Los PDFs de venta son comprobantes internos. Gudex no emite actualmente boletas electrónicas ni sustituye un documento tributario electrónico (DTE).

## 6. Integraciones externas

### Google Workspace

OAuth permite conectar Gmail, Drive y Calendar. Gmail y Drive se usan para buscar informes PDF; Calendar permite sincronizar citas. Los alcances y credenciales se configuran en Google Cloud y Railway.

### Inteligencia artificial

El backend consulta un proveedor compatible configurado por variables de entorno. El asistente puede responder preguntas del taller y generar diagnósticos a partir de información autorizada del sistema.

### Mercado Pago

Checkout Pro inicia pagos remotos y el backend confirma el resultado mediante un webhook verificado. Mercado Pago Point se registra como terminal externa.

### Redes sociales

Gudex permite preparar y exportar publicaciones para Instagram, Facebook y LinkedIn. La publicación en redes es manual. La pantalla de integraciones de Meta presenta el estado y la configuración prevista; el flujo OAuth de Meta y la publicación automática aún requieren implementación.

## 7. Despliegue

- **Railway** ejecuta FastAPI y puede alojar PostgreSQL. El predespliegue ejecuta Alembic antes del comando de inicio de Uvicorn.
- **Vercel** publica Flutter Web. El script `mobile/scripts/build_vercel.sh` descarga Flutter, obtiene dependencias y compila la salida `build/web`.
- La URL de la API del cliente se puede configurar mediante `API_URL` o `API_BASE_URL`.
- En desarrollo local, el backend se ejecuta desde `backend/` con Uvicorn; la API publica documentación interactiva en `/docs`.

La guía de operación está en `docs/despliegue-railway-vercel.md`. Los pasos para Google y Meta están en `docs/manual-integraciones-google-redes-sociales.md`.

## 8. Estado y límites conocidos

El repositorio contiene los módulos principales para operar el lubricentro. Las integraciones externas requieren credenciales y permisos configurados en sus respectivas plataformas. En particular, Meta todavía no cuenta con el flujo OAuth ni la publicación automática; se utiliza exportación y publicación manual.

La operación sin conexión, los respaldos de evidencias y la emisión de documentos tributarios electrónicos son temas separados que requieren implementación y definición adicionales.
