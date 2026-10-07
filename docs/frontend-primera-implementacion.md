# Frontend: primera implementación del rediseño

7 de octubre de 2026. Basada en [la auditoría de frontend](auditoria-frontend-redisenio.md).

## Cambios entregados

### Datos completos

`ApiClient.getAll` recorre páginas de endpoints con `limit` y `offset`, conserva filtros y elimina duplicados por ID. Un fallo de página invalida la carga completa; una respuesta repetida sin avance produce error en vez de un ciclo infinito. Se solicita hasta 200 registros por página y se continúa hasta respuesta vacía, incluso si el servidor aplica un límite menor.

POS carga completos productos, clientes y OTs listas; taller carga completos clientes, vehículos y OTs generales. La ruta `work-orders/mine` sigue su contrato sin paginación. Ventas recientes mantiene la consulta de una página (50 registros predeterminados) y ahora muestra esa página completa, no solamente diez.

Es una solución transitoria para búsquedas locales completas. Con volúmenes grandes debe evolucionar a búsqueda y filtros en servidor con paginación incremental; no se afirma que cargar todo sea adecuado para un inventario ilimitado. La paginación por offset no es un snapshot transaccional ante modificaciones simultáneas.

### Inventario adaptativo con Riverpod

- Consulta de inventario con `FutureProvider.autoDispose.family`, ligada al cliente API de la sesión.
- Recarga con datos previos visibles, error contextual y acción para reintentar; filtros y búsqueda permanecen.
- Filas por columnas desde 960 píxeles útiles, construidas bajo demanda. Cards en móvil y cuando el texto ampliado necesita más espacio.
- Acciones de historial, edición, ajuste, archivo y contenido conservadas según permisos; carga masiva conserva su flujo.
- Editor lateral en escritorio y hoja inferior en móvil, con campos desplazables y acciones fijas.
- Alta, edición y movimiento de stock cierran solo después de respuesta exitosa. Un error conserva los campos y muestra el motivo.
- Guardado bloquea nuevos envíos y salida; cerrar con cambios pide confirmación. Escape sigue la misma protección.
- Formato monetario CLP compartido y objetivos de botones/iconos de 48×48 en ambos temas.

### POS

- Actualizar stock no elimina líneas del carrito. Un producto desaparecido conserva la descripción/precio que tenía al agregarlo.
- Cantidades superiores al stock o una OT ya no disponible bloquean cobro con explicación. Se pueden reducir o quitar productos y quitar una OT no disponible.
- Selecciones de cliente/OT se reconcilian con la lista actual sin intentar mostrar valores inexistentes en dropdowns.
- Vista compacta de escritorio con proporción 60/40 y acción de cobro fuera del área desplazable. Móvil con resumen fijo que lleva a la sección de venta conservando el carrito.
- Aviso del resultado de venta/pago permanece en la pantalla, además del snackbar. No es persistencia local después de cerrar la app.
- Acceso a ventas recientes desde cabecera. “Continuar cobro” registra el saldo en la venta existente o reabre Checkout Pro; no crea otra venta ni descuenta stock otra vez.
- Los medios manuales se presentan como registro de dinero ya recibido. Checkout sigue pendiente hasta confirmación del backend; abrir el enlace no marca una venta como pagada.

## Validación

Suite en `mobile/test/frontend_regression_test.dart`:

1. Acceso al producto 251 con páginas limitadas a 50 y filtros preservados.
2. Fallo de página sin devolver un catálogo incompleto.
3. Búsqueda del producto 251 en móvil de 360 px.
4. Formulario conservado ante fallo y reintento exitoso.
5. Cantidad y motivo conservados ante fallo de movimiento de stock.
6. Conflicto de stock conservado con botón de cobro deshabilitado.
7. Recuperación de pago sobre el ID de venta existente.
8. Producto archivado conservado y removible del carrito.
9. Inventario anterior y búsqueda conservados tras error de recarga.
10. Carrito preservado al cambiar de escritorio a móvil, con resumen fijo.

Resultado local con Flutter 3.47.3: **10 pruebas aprobadas**, **`flutter analyze` sin incidencias** y **`flutter build web --release` completado** (salida JavaScript en `mobile/build/web`). El workflow de calidad ejecuta `flutter test` después de `flutter analyze`.

La compilación emitió avisos de incompatibilidad Wasm de `flutter_secure_storage_web` (usa `dart:html`/`dart:js_util`) y de fuente CupertinoIcons no incluida. No bloquearon la salida web JavaScript. No se actualizó el almacenamiento de sesión ni se habilitó Wasm como parte de esta entrega.

## Alcance pendiente

No se implementan en esta entrega el Kanban, la firma manuscrita, lectura de códigos por cámara, separación completa del estado del POS en Riverpod ni la consolidación del tema global. El carrito móvil todavía forma parte del flujo principal; el resumen fijo permite llegar a él, pero no es una hoja de carrito independiente.

Recuperar una venta con ID conocido evita recrearla desde este flujo. Un timeout al crear la venta sigue requiriendo comprobar su existencia: no se añadió idempotencia transaccional en backend. Los errores de guardado de inventario tampoco autorizan reintentos ciegos ante un resultado de red incierto. No hubo despliegue ni operaciones contra servicios reales.

Quedan pendientes comprobaciones en navegador/dispositivo con datos operativos, teclado virtual real, lector de pantalla, impresión, evidencia fotográfica y pagos sandbox. Las pruebas de widgets no sustituyen esas comprobaciones.
