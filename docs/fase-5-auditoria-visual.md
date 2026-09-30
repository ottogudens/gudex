# Fase 5: auditoría visual y de experiencia de usuario

## Objetivo

Mejorar la claridad, consistencia y facilidad de uso de Gudex para administración, mecánicos y clientes en teléfonos, tabletas y web, antes de seguir ampliando los formularios operativos.

## Alcance de auditoría

- Inventariar pantallas y recorridos principales por perfil: autenticación, portal del cliente, órdenes/inspecciones, inventario, agenda, POS e integraciones/asistente.
- Revisar jerarquía visual, navegación, etiquetas, densidad de información, formularios, confirmaciones y feedback de acciones.
- Definir paleta y tokens de color con estados semánticos coherentes (éxito, observación, error, pendiente), además de tipografía, espaciado, radios e iconografía.
- Revisar contraste, tamaños de texto, áreas táctiles, foco/teclado, lectores de pantalla y mensajes de error para accesibilidad.
- Comprobar adaptación a teléfonos estrechos, tablets y navegador de escritorio; identificar tablas o flujos que necesiten diseños responsivos distintos.
- Revisar estados de carga, vacío, error, sin conexión y sincronización para que las acciones tengan resultados claros.

## Entregables

1. Mapa de pantallas y tareas por rol.
2. Hallazgos priorizados por impacto y esfuerzo, con capturas o referencias a las pantallas afectadas.
3. Guía visual breve y tokens de diseño compartidos para Flutter.
4. Cambios de interfaz aplicados por grupos de pantallas, manteniendo los permisos y flujos funcionales existentes.
5. Revisión en tamaños de pantalla representativos y lista de ajustes pendientes.

## Criterios para dar la fase por terminada

- Administración, mecánicos y clientes pueden identificar su acción principal en cada pantalla sin ambigüedad.
- Colores y componentes mantienen el mismo significado entre módulos.
- Texto, botones, formularios y navegación funcionan en teléfono, tablet y web sin recortes ni desbordamientos en las vistas auditadas.
- Contraste y tamaños táctiles se revisan en componentes principales; los estados de carga, error y vacío tienen presentación consistente.
- Los cambios no alteran reglas de permisos ni requieren mostrar a cada perfil datos ajenos.

## Método

Primero se realiza una revisión de la interfaz implementada y se entrega el inventario con prioridades. Después se acuerdan las correcciones visuales por grupos para facilitar su revisión. Las pruebas visuales se harán con tamaños de viewport representativos y los flujos existentes de cada perfil.
