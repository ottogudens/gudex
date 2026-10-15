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
