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

## Auditoría inicial y primera mejora aplicada

### Hallazgos priorizados

| Prioridad | Hallazgo | Estado |
|---|---|---|
| Alta | Navegación inferior usaba nombres largos en pantallas estrechas | Corregido con etiquetas compactas por módulo |
| Alta | El contenido de listas se extendía a todo el ancho en escritorio | Corregido con ancho máximo compartido de 1120 px para módulos y 1320 px para el shell |
| Media | Color, forma de tarjetas, campos y botones dependían en gran medida de valores predeterminados de Material | Corregido con tema y tokens comunes |
| Media | Los estados y los errores/estados vacíos no tenían jerarquía visual uniforme en listas generales | Corregido con chips semánticos, mensajes y acción para reintentar |
| Media | Pantalla de acceso no diferenciaba configuración de conexión del inicio de sesión cotidiano | Corregido: URL de API queda bajo “Configuración de conexión”; formulario renovado y campos con autofill |

### Tokens visuales iniciales

- Tinta / texto principal: `#163247`.
- Primario azul petróleo: `#0B7285`.
- Secundario turquesa: `#159A9C`.
- Fondo general: `#F3F7F9`; superficies de tarjetas/formularios: blanco.
- Bordes: `#DCE6EA`.
- Éxito: `#237A57`; pendiente/en curso usa ámbar; error utiliza los colores semánticos del `ColorScheme`.
- Tarjetas con esquinas de 16 px, formularios y botones de 12 px, diálogos de 20 px y objetivo mínimo de 44–48 px para acciones táctiles.

### Pantallas cubiertas en esta pasada

Acceso, contenedor principal y navegación para los tres perfiles; listas reutilizadas del portal/agenda; estados de carga, error y vacío; tema común aplicado a inventario, POS, órdenes, inspecciones, formularios, asistente e integraciones. Los módulos principales quedan centrados y limitados de ancho en tablet/escritorio. El shell utiliza navegación inferior compacta en móvil y una barra lateral extendida en viewports de 900 px o más.

### Pendiente de inspección visual

No fue posible lanzar Flutter local en este entorno porque el SDK no está instalado. El código y el build de Vercel deben revisarse visualmente a 360 px, 768 px y 1280 px o más. En esa revisión se deben corregir recortes puntuales del POS y formularios, comprobar contraste de todos los estados y comprobar teclado/lector de pantalla. La fase visual seguirá abierta hasta esa comprobación en navegador y dispositivo.
