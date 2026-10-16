# Avance de etapas 1 a 4 — 15 octubre 2026

Referencia: [auditoría](auditoria-desarrollo-pendiente-2026-10-15.md). Este registro distingue entregas de código de cierre integral de etapas.

## Entrega 1 — estabilización y transacciones

- Servicio compartido de autorización y transiciones de órdenes: edición normal e IA. Confirmación IA bloquea la propuesta y la orden durante su actualización en PostgreSQL.
- Asignación de mecánico exigida para crear/editar/borrar inspecciones, aplicar plantillas, recepción y evidencias.
- Historial del portal filtra cotizaciones en borrador y notas internas de la orden, nombre interno de técnico e importe interno.
- Listados independientes de clientes/vehículos: conserva datos disponibles, muestra error parcial y permite reintentar. Consulta HTTP con timeout explícito, mensajes de sesión vencida y respuesta no JSON.
- Canjes serializados por cliente en PostgreSQL; rechazo tras aprobación devuelve puntos una sola vez. Reversión de pago compensada en puntos.
- Pagos manuales y webhook serializados por venta en PostgreSQL. Reservas usan bloqueo transaccional de agenda global acorde a la capacidad única actual; reconfirmar una cita vuelve a comprobar conflictos.
- Pruebas de regresión para permisos IA, transición terminal, doble confirmación, inspecciones, portal, devolución de puntos y carga parcial de listas.

### Límites que siguen abiertos

- El incidente concreto de registros invisibles necesita reproducción con sesión productiva; mejorar la carga no demuestra por sí solo su causa.
- Docker local no está iniciado: pruebas concurrentes reales PostgreSQL pendientes; las pruebas SQLite no validan bloqueos PostgreSQL.
- Falta completar DTO explícito en todas las respuestas del portal y revisar todas las rutas de scanner/IA para la política de acceso acordada.
- Faltan cola durable/worker, auditoría general, restauración ensayada, staging, idempotencia transversal y prueba end-to-end Baileys.
- No se declara completa la etapa 1 ni la 2. Las mejoras de etapas 3/4 no eliminan esos pendientes.

## Entrega 2 — historial de mantenciones y ficha operativa

- Tabla aditiva `maintenanceexecution`, migración `20261015_0018`. Conserva plan/intervalos del momento, kilometraje, materiales descriptivos, notas, autor y orden opcional. Sin modificación ni borrado público del registro.
- Nuevo registro idempotente por plan y clave de solicitud; rechaza reutilización de clave con otro contenido, retroceso de kilometraje, plan archivado y orden incompatible con el vehículo o su estado.
- La acción anterior de completar plan también registra historial; no se inventan ejecuciones históricas a partir de la última fecha conocida.
- Administración crea planes y registra mantenciones desde la quinta pestaña. Los intervalos no se rellenan automáticamente sin una fuente. El portal consulta el historial sin identificador de solicitud ni correo del autor.
- Los materiales registrados son descriptivos y visibles para el cliente: aún no generan movimientos de inventario.
- Búsqueda en clientes/vehículos por nombre, RUT, correo, teléfono, patente, marca, modelo, VIN y nombre del propietario.
- Protegida la eliminación de vehículos con planes y órdenes con ejecuciones vinculadas.

### Verificación y pendientes de cierre

- 85 pruebas backend aprobadas en SQLite temporal. Migración completa hasta `20261015_0018` aplicada en otra base temporal.
- Flutter: análisis sin incidencias; 17 pruebas de la suite aprobadas, más una nueva prueba de reintento de mantención (las 4 pruebas de ficha vuelven a pasar). Total cubierto: 18 pruebas, incluyendo creación de plan, portal de solo lectura y clave de solicitud estable tras un fallo.
- Pendientes de etapas 3/4: PDF/QR de ficha, catálogos/licencias, OCR y DTC estructurados, control de calidad/garantías, solicitudes de cotización, capacidad por técnico/bahía, cola offline, validación visual/nativa y automatización de recordatorios.
- Las etapas 3 y 4 son parciales. No se ejecutaron cobros, mensajes WhatsApp ni cambios de configuración de cuentas externas.
