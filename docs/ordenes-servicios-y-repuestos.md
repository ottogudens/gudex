# Órdenes de trabajo: servicios y repuestos

Una orden agrupa uno o más servicios: inspección, scanner, mantención preventiva,
reparación correctiva, inspección precompra, prerevisión técnica u otro. La
administración abre la orden con un primer servicio y puede añadir servicios
del catálogo o trabajos manuales. Cada servicio conserva nombre, tipo, alcance,
responsable, hallazgos, estado y tiempo trabajado. El mecánico ve sus órdenes
asignadas y puede actualizar solo los servicios de los que es responsable.

Los servicios de ejecución (mantención y reparación) no pueden iniciar ni
terminar antes de la aprobación comercial de la orden. La orden no puede pasar
a lista o entregada mientras tenga servicios pendientes o bloqueados. Las
inspecciones, plantillas e informes de scanner pueden vincularse a un servicio;
los registros anteriores sin vínculo siguen disponibles a nivel de orden.

Los repuestos se registran contra un servicio y vehículo con origen cliente o
taller, categoría, marca, número de parte, OEM, especificaciones, cantidad,
imagen y evidencia de compatibilidad. El registro de una pieza nunca mueve
stock: el inventario se descuenta únicamente mediante el flujo comercial
existente. Esto evita descontar repuestos aportados por el cliente o duplicar
movimientos. La ficha muestra historial completo y referencias verificadas.
Si cambia la identidad técnica del vehículo, la compatibilidad previamente
verificada se marca para revisión y deja de figurar como referencia vigente.

El informe de uso de repuestos se basa en instalaciones efectivas de los
últimos 180 días (período ajustable en la API). Separa cantidades aportadas por
cliente y taller y permite planificar compras; no genera pedidos automáticos
ni interpreta una referencia registrada como compatibilidad universal.

La migración `20261018_0021` es aditiva. Conserva órdenes, inspecciones,
informes y sesiones existentes. Para desplegar en producción debe ejecutarse
Alembic antes de iniciar el backend. La compilación y revisión visual de
Flutter Web/PWA debe realizarse en un entorno con Flutter instalado.
