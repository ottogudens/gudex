# Contenido y redes

MVP disponible para administración en **Contenido y redes**, con acceso adicional desde **Inventario → Acciones del producto → Crear publicación**.

## Uso

1. En **Marca**, configura nombre, colores, tono, público, llamada a la acción, contacto público y logo opcional. Cada nueva publicación conserva una copia de esa identidad, de modo que cambiar la marca no altera diseños ya revisados.
2. Crea una publicación desde un producto, un servicio del catálogo o una idea general. Selecciona red, objetivo y formato (cuadrado, vertical o historia).
3. Escribe una idea y sus condiciones. **Generar con plantilla** utiliza los datos guardados, incluido el precio del producto. **Generar con IA** utiliza la configuración existente del asistente; requiere proveedor, clave y modelo configurados en el backend. Esta generación envía solamente el contexto comercial del borrador y la marca, sin registros de clientes, vehículos u órdenes. Reemplaza texto y titular; permanece como borrador.
4. Edita texto, titular y fotografía opcional. **Guardar y actualizar vista previa** muestra el PNG que se exportará. Las imágenes se validan y normalizan; se aceptan PNG, JPEG y WebP de hasta 5 MB y 16 megapíxeles.
5. Envía a revisión y aprueba. Para modificar una publicación aprobada vuelve primero a borrador. Una publicación registrada como publicada queda cerrada; crea otra para una nueva pieza.
6. Descarga el ZIP con **publicacion.png**, **texto.txt** y las instrucciones. Publícalo manualmente en la red correspondiente y pulsa **Ya lo publiqué** para registrar esa confirmación.
7. Opcionalmente asigna una fecha futura desde **Planificar fecha**. El calendario permite recorrer meses y filtrar por día. Las fechas se almacenan en UTC y se muestran en la zona horaria del dispositivo.

## Alcance

- Instagram, Facebook y LinkedIn tienen borradores adaptados y estados separados por publicación.
- La imagen es una composición gráfica con identidad de marca, titular, CTA y fotografía opcional; no se genera una fotografía mediante IA.
- El calendario es planificación editorial: **no envía contenido automáticamente**. Cuentas muestra las integraciones pendientes sin simular conexiones.
- El estado **Publicado manualmente** es una confirmación del administrador, no una comprobación de la plataforma social.
- OAuth de redes, publicación automática, estadísticas, carruseles, video y campañas multired quedan para una siguiente etapa.
- No se requieren credenciales sociales para esta entrega. La generación con IA sí puede consumir la API configurada.

## Backend

Migración: `20261005_0006_social_content` (tablas `socialbrand` y `socialpost`). Ejecuta `alembic upgrade head` con la configuración del entorno antes del despliegue. El arranque también admite la creación aditiva de tablas siguiendo el mecanismo existente del proyecto.

Rutas bajo `/api/v1/social`, todas restringidas a administración:

- `GET/PUT /brand`: identidad de marca.
- `GET /accounts`: disponibilidad real de las integraciones.
- `GET/POST /posts`, `GET/PUT/DELETE /posts/{id}`: publicaciones.
- `POST /posts/{id}/generate`: plantilla o IA (`use_ai`).
- `POST /posts/{id}/status`: revisión, aprobación, planificación y confirmación manual.
- `GET /posts/{id}/preview.png`: vista previa autenticada.
- `GET /posts/{id}/export`: ZIP de una publicación aprobada, planificada o publicada.

Pruebas: `pytest -q tests/test_social_content.py`. Cubren permisos, validación de imágenes y fechas, datos comerciales, conservación de marca, transiciones, formatos PNG, exportación y fallos de IA sin pérdida del borrador.

Para verificar Flutter Web contra una API local sin cambiar la dirección de producción, compila o ejecuta con `--dart-define=API_BASE_URL=http://127.0.0.1:8017`. Sin esa variable se mantiene `https://bknd.gudex.cl`.
