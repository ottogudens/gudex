# Auditoría de vistas pendientes

Fecha de revisión: 30 de septiembre de 2026  
Alcance: aplicación Flutter actual, rutas de la API y flujos definidos para el lubricentro.

## Resultado

Gudex ya cubre el núcleo de recepción, órdenes, inspecciones, cotizaciones, inventario y venta. La brecha principal no está en crear más listados genéricos: está en convertir datos y rutas existentes en vistas operativas que permitan trabajar sin usar identificadores internos ni depender de otros sistemas.

La prioridad recomendada es completar primero la operación diaria del taller: agenda, ficha de vehículo, asignación de trabajo, scanner e historial. Después se deben incorporar gestión administrativa, cierre de caja y reportes. Las vistas tributarias quedan condicionadas a decidir el proveedor o modalidad de boleta electrónica.

## Avance posterior a la auditoría

Las cinco vistas P0 ya tienen una primera implementación en Flutter y API: ficha e historial de vehículo, agenda semanal, bandeja Mis trabajos con asignación por usuario, flujo de informes LAUNCH PDF y solicitud de cita desde el portal. Quedan en P1 los filtros avanzados, edición o movimiento de citas, recursos físicos del taller y la importación de candidatos Gmail/Drive directamente desde la nueva vista del scanner.

## Método y evidencia

Se revisaron:

- Los módulos visibles por perfil en `mobile/lib/main.dart`.
- Las vistas especiales de órdenes, inventario, POS, asistente e integraciones.
- Los endpoints disponibles en `backend/app/main.py` y `backend/app/routers/`.
- El alcance funcional vigente en `docs/estado-del-desarrollo.md`.

Una vista se clasifica como **faltante** cuando el flujo no puede completarse desde Flutter. Se clasifica como **incompleta** cuando existe un listado, formulario o endpoint, pero faltan acciones o contexto necesarios para el trabajo diario.

## Inventario actual

| Área | Administración | Mecánico | Cliente | Estado |
|---|---|---|---|---|
| Acceso | Inicio de sesión, alta de clientes con invitación | Inicio de sesión | Activación, recuperación e inicio de sesión | Disponible, falta recuperación iniciada desde la pantalla de acceso |
| Clientes y vehículos | Lista y alta | Consulta indirecta desde órdenes | Perfil y vehículos propios | Incompleta: no hay ficha navegable ni edición |
| Órdenes | Lista, alta y detalle operativo | Lista y detalle operativo | Lista e informe de inspección | Incompleta: falta bandeja por responsable, filtros y línea de tiempo |
| Recepción e inspección | Dentro del detalle de orden | Dentro del detalle de orden | Consulta resumida | Disponible para el flujo básico |
| Cotizaciones | Crea y publica desde una orden | Consulta en la orden | Lista, aprobación o rechazo | Incompleta: no hay vista global ni documento de cotización |
| Agenda | Listado genérico | Listado genérico | Listado de citas | Faltante como agenda operativa y solicitud de cita desde cliente |
| Inventario | Catálogo, alta, ajuste y movimientos | Consulta y movimientos | No aplica | Incompleta: no hay proveedores, compras ni conteo |
| Scanner LAUNCH | Importación desde Gmail/Drive en Integraciones | Sin vista de carga/consulta específica | Sin acceso directo al informe fuente | Faltante como flujo operativo del scanner |
| POS | Venta de productos/servicios y comprobante PDF | No aplica | No aplica | Incompleta: falta detalle, pagos, cierre y devoluciones |
| Integraciones e IA | Estado de Google, Mercado Pago e IA | Asistente | Asistente contextual | Disponible para configuración base |
| Usuarios y permisos | API de alta disponible | No aplica | No aplica | Faltante en Flutter |
| Reportes | No aplica | No aplica | No aplica | Faltante |

## Vistas faltantes priorizadas

### P0 — necesarias para operar el taller sin procesos manuales paralelos

| Vista | Perfiles | Qué debe resolver | Dependencias | Motivo de prioridad |
|---|---|---|---|---|
| Agenda operativa diaria/semanal | Administración, mecánico | Calendario por día, citas, órdenes prometidas, técnico y puesto/elevador; crear, mover, confirmar y cambiar estado | Ampliar modelo de recursos si se asignan elevadores | La agenda actual solo muestra registros y no permite planificar la carga de trabajo |
| Ficha de vehículo e historial | Administración, mecánico; lectura cliente | Datos técnicos, kilometraje, órdenes anteriores, diagnósticos, cotizaciones, inspecciones, informes LAUNCH y próximos mantenimientos | Endpoint de historial compuesto | Evita buscar información en listas separadas durante la recepción y el diagnóstico |
| Bandeja “Mis trabajos” y asignación | Mecánico, administración | Trabajos asignados, estado, fecha prometida, prioridad y acciones rápidas; administración asigna o reasigna responsable | Asociar técnico a un usuario, no solo texto libre | El campo de técnico existe, pero no hay una vista ni asignación por persona real |
| Flujo de scanner LAUNCH | Administración, mecánico | Adjuntar PDF desde dispositivo, seleccionar/importar desde Gmail o Drive, vincular vehículo/orden, registrar kilometraje y ver el informe | La API de carga/importación ya existe | El informe es parte del servicio ofrecido y ahora queda escondido en Integraciones o archivos adjuntos |
| Solicitud de cita del cliente | Cliente | Elegir vehículo, servicio, fecha/hora preferida y observaciones; ver solicitud pendiente o cambios | Endpoint de portal ya existe | El cliente puede ver sus citas, pero no completar el flujo de solicitud desde la app |

### P1 — necesarias para control administrativo y una atención consistente

| Vista | Perfiles | Qué debe resolver | Dependencias |
|---|---|---|---|
| Panel de inicio operativo | Administración | Órdenes por estado, citas del día, trabajos atrasados, stock bajo, cotizaciones sin respuesta y ventas del día | Consultas agregadas de backend |
| Detalle de cliente | Administración | Datos de contacto, vehículos, historial consolidado, documentos, cotizaciones y acciones de portal | Endpoint de detalle compuesto |
| Gestión de usuarios y roles | Administración | Listar, crear, activar/desactivar, restablecer acceso y relacionar cliente con portal | Endpoints de lectura/edición de usuarios; las acciones críticas requieren confirmación |
| Gestión completa de cotizaciones | Administración, mecánico; lectura cliente | Bandeja de borradores/enviadas/aceptadas, vigencia, PDF con logo, reenvío y trazabilidad de aprobación | Modelo de vigencia y documento PDF |
| Detalle de venta y pagos | Administración | Venta, líneas, pagos pendientes/aprobados, referencia Mercado Pago, comprobante y vínculo con cliente, vehículo u orden | Lectura por venta y actualización por webhook ya disponible en parte |
| Cierre de caja | Administración | Totales por medio de pago, diferencias, ventas abiertas, pagos externos pendientes y exportación del turno | Modelo de turno/cierre y auditoría |
| Movimientos de inventario por producto | Administración, mecánico lectura | Historial legible, filtros por fecha/motivo, stock disponible y alertas | El endpoint ya existe; falta una vista dedicada y filtros |
| Búsqueda global | Administración, mecánico | Buscar patente, VIN, RUT, cliente, código de orden o producto desde cualquier módulo | Endpoint de búsqueda controlado por rol |

### P2 — completan el producto y reducen trabajo administrativo

| Vista | Perfiles | Qué debe resolver | Dependencias |
|---|---|---|---|
| Proveedores y órdenes de compra | Administración | Proveedores, costos, reposición, recepción de compra y actualización de stock | Nuevos modelos y endpoints |
| Conteo y ajustes guiados de inventario | Administración | Inventario físico, diferencias, motivo, aprobación y trazabilidad | Sesiones de conteo y permisos |
| Reportes e indicadores | Administración | Ventas, margen, mano de obra, productividad, trabajos pendientes, rotación y stock bajo | Consultas agregadas y definición de métricas |
| Garantías y retrabajos | Administración, mecánico | Registrar garantía, vincular orden original, aprobar y seguir el trabajo | Modelo de garantía |
| Centro de documentos | Administración, cliente | Ver y descargar informes, comprobantes, cotizaciones y documentos tributarios emitidos | Índice de documentos y emisión fiscal definida |
| Preferencias del taller | Administración | Perfil comercial, datos de documentos, horarios, reglas de agenda, plantillas, notificaciones y configuración de IA | Configuración persistente y permiso de administración |
| Notificaciones y comunicaciones | Todos según rol | Bandeja de notificaciones, mensajes de progreso, recordatorios y consentimiento del cliente | Canal de envío elegido, plantillas y auditoría |

## Vistas existentes que deben completarse

| Vista actual | Falta concreta | Prioridad |
|---|---|---|
| Inicio de sesión | Enlace visible para “Olvidé mi contraseña” del portal de cliente; actualmente existe backend de recuperación pero no el acceso desde la UI | P1 |
| Clientes / vehículos | Abrir ficha al tocar una tarjeta, editar datos, ver historial y acceder a scanner/documentos | P0 |
| Lista de órdenes | Filtros por estado, técnico, fecha y cliente; búsqueda por patente/código; indicadores de atraso y prioridad | P0 |
| Detalle de orden | Asignar técnico real, registrar horas y tareas, adjuntar/ver informe LAUNCH explícitamente, ver historial previo del vehículo y cerrar/entregar con confirmación | P0 |
| Agenda | Crear/editar/confirmar citas desde Flutter, selector de horario, vehículo y servicio | P0 |
| Inventario | Ver detalle de producto, filtros, historial de movimientos y alta desde compra | P1 |
| Portal de cliente | Solicitar/modificar cita, ficha de vehículo, documentos, contacto y recomendaciones de mantenimiento | P0/P2 |
| POS | Buscar por SKU o código, asociar vehículo/orden, administrar pago pendiente, reimprimir y anular/devolver bajo confirmación | P1 |
| Integraciones | Mostrar última sincronización, errores recuperables y guía de configuración; no exponer secretos | P2 |

## Orden de implementación sugerido

1. Ficha de vehículo e historial, más la apertura de fichas desde Clientes/Vehículos.
2. Agenda operativa y solicitud de cita del cliente.
3. Asignación de técnicos y bandeja “Mis trabajos”.
4. Vista de scanner LAUNCH dentro de la orden y la ficha del vehículo.
5. Panel operativo de administración, gestión de usuarios y detalle de venta/pagos.
6. Cierre de caja, cotizaciones globales e inventario ampliado.
7. Proveedores, compras, reportes, garantías, centro documental y preferencias.

## Fuera de alcance hasta definir una integración externa

- Emisión, anulación y consulta de boletas electrónicas/DTE. Requiere elegir el sistema tributario que usará el taller y no debe diseñarse como si un comprobante interno fuera fiscal.
- Confirmación automática de pagos por terminal Mercado Pago Point. Depende de la solución Point específica; Checkout Pro ya tiene una ruta de integración distinta.
- Notificaciones push, WhatsApp o SMS. Requieren proveedor, consentimiento y políticas de retención.

## Criterio para cerrar esta auditoría

La auditoría se considerará resuelta cuando cada vista P0 tenga una historia de usuario aprobada, una definición de datos/permisos y una posición en el plan de desarrollo. La implementación debe comenzar por la ficha de vehículo e historial, porque conecta recepción, diagnóstico, scanner, órdenes y atención al cliente.
