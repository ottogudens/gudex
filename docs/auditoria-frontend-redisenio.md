# Gudex: auditoría frontend y especificación de rediseño

> Seguimiento: [primera implementación y validación](frontend-primera-implementacion.md). Los hallazgos siguientes describen el estado anterior a esa entrega.

Fecha: 7 de octubre de 2026. Alcance: POS, taller/OT e inventario, con revisión del shell, tema, persistencia y contratos REST relacionados.

## 1. Resultado y límites

La prioridad es corregir la cobertura de datos y la recuperación de operaciones antes de aumentar la densidad visual. Las pantallas ya tienen funcionalidad aprovechable: comprobantes, cobro de OT, formularios validados, listas bajo demanda, inspecciones, evidencias, borradores y carga masiva con revisión.

Esta es una auditoría estática del código local. No se ejecutaron la aplicación, operaciones reales, Flutter Analyze ni pruebas de navegador. `flutter` y `dart` no están disponibles en el PATH. Los riesgos de desbordamiento, contraste, foco y rendimiento requieren validación en ejecución; no se presentan como fallos visuales reproducidos. No se cambió código de producción.

La documentación histórica de fase 5 describe una paleta azul/turquesa, pero `mobile/lib/core/constants.dart:5` define rojo `#ED0606`, amarillo `#FFE600` y gris. La propuesta conserva esta identidad actual. El modo oscuro existe; no equivale a haber validado alto contraste.

## 2. Mapa de tareas y roles

| Rol | Recorrido actual relevante | Objetivo de rediseño |
|---|---|---|
| Administrador | POS: producto/servicio u OT → venta → pago → comprobante | Cobrar con total persistente y recuperar la misma venta si falla el pago |
| Administrador | Taller: creación → asignación → recepción/inspección → cotización → estados | Lista/Kanban y detalle contextual, sin perder posición |
| Mecánico | Mis trabajos / OTs → detalle → diagnóstico, inspecciones y evidencias | Lista por estados, acciones táctiles y progreso de carga |
| Administrador | Inventario: búsqueda → alta/edición/ajuste → movimientos; Excel → revisión → confirmación | Buscar en todos los registros, guardar sin perder formulario y comparar cambios |
| Mecánico | Inventario de consulta | Stock y disponibilidad sin acciones de administración |
| Cliente | Vehículos, trabajos anteriores, cotizaciones y citas del portal | Mantener aislamiento del portal; los módulos internos no se exponen |

Fuente: `mobile/lib/main.dart:164` y pantallas auditadas. La visibilidad del frontend no sustituye la autorización de la API. El detalle de permisos y transiciones se verificará por endpoint antes de cambiar acciones.

## 3. Hallazgos priorizados

P1: integridad del recorrido o información operativa incompleta. P2: fricción, adaptación o mantenibilidad. P3: consistencia. Esfuerzo relativo: S pequeño, M medio, L varias capas. “Confirmado” significa comprobado en código; los efectos visuales indicados como riesgo siguen pendientes.

| ID / prioridad / esfuerzo | Evidencia y diagnóstico | Cambio propuesto y aceptación |
|---|---|---|
| D01 · P1 · L | **Confirmado.** API con página predeterminada de 50 y máximo 200 (`backend/app/main.py:68`). POS (`pos_screen.dart:54`), inventario (`inventory_screen.dart:39`) y taller (`workshop_screen.dart:43`) piden listas sin recorrer páginas. `ApiClient.get` no agrega paginación. Productos/clientes/vehículos/OT generales pueden quedar incompletos. `/work-orders/mine` tiene un contrato distinto y no usa ese límite. | Repositorios paginados y búsqueda global. Productos no admite hoy `q`: agregar búsqueda en backend o cargar explícitamente todas las páginas como transición acotada. Validar con 251 registros y búsquedas del último registro; nunca presentar una búsqueda parcial como exhaustiva. |
| D02 · P1 · M | **Confirmado.** `PosScreen._refresh` elimina del carrito productos no encontrados o cuya cantidad supera stock, sin explicar el cambio (`pos_screen.dart:78`). La página incompleta de D01 puede agravar esto. | Conservar la línea marcada “requiere revisión”; resolver existencia por ID, actualizar disponibilidad y bloquear cobro hasta corregir. Reducir stock durante una venta debe producir un aviso visible y conservar la intención del operador. |
| D03 · P1 · M | **Confirmado.** Alta, edición y ajuste de inventario cierran el diálogo antes del POST/PATCH (`inventory_screen.dart:100`, `:172`, `:314`). Al fallar, solo se muestra un snackbar y se descartan controladores. | Guardar dentro del editor, conservar campos, mostrar error y permitir reintento. Cerrar después de éxito. Simular fallo y verificar que nombre, precio y motivo permanecen intactos. |
| D04 · P1 · M/L | **Confirmado.** Venta y pago son llamadas separadas. El carrito se limpia después de crear venta y antes de registrar pago (`pos_screen.dart:322`). Hay manejo de fallo parcial y listado de ventas, pero el mensaje es temporal; un fallo al abrir Checkout también termina bajo “no se pudo registrar el pago”. | Resultado persistente por venta: creada, pago pendiente, enlace disponible, verificada o error. Reanudar sobre el ID existente y diferenciar fallo de apertura de enlace de fallo de pago. Revisar deduplicación/resultado incierto en backend; no prometer que deshabilitar un botón evita duplicados ante timeout. |
| D05 · P2 · M | **Confirmado.** POS cambia a amplio con ancho local ≥920 y usa 7:5 en la variante compacta (`pos_screen.dart:396`, `:465`). Shell usa ancho de ventana ≥900 para navegación lateral (`main.dart:262`). | Decidir por ancho útil después de navegación. Colapsar lateral en tablet para permitir 60:40. Probar orientación y puntos de corte con carrito intacto. |
| D06 · P2 · M | **Confirmado.** Carrito completo dentro de `SingleChildScrollView`, líneas de escritorio en caja de 112 px (`pos_screen.dart:774`, `:816`). En móvil catálogo, cobro e historial comparten recorrido vertical. | Separar lista desplazable y pie fijo de total/cobro; móvil con resumen fijo y carrito en sheet. Total y CTA visibles con 20 líneas y teclado abierto. |
| D07 · P2 · L | **Confirmado.** Taller usa tarjetas para todos los anchos y abre OT en bottom sheet (`workshop_screen.dart:410`, `:443`). No hay selector Kanban/lista ni filtros por estado en esta vista. | Añadir vista dual en escritorio, lista filtrable por estados en móvil y drawer en ancho suficiente. Drag & drop con alternativa de menú; fallo de guardado restaura estado visible. |
| D08 · P2 · M | **Confirmado.** Inventario usa `ListView.builder` y `ListTile` en todos los tamaños (`inventory_screen.dart:256`, `:281`); texto largo compite con acciones laterales. Desbordamiento móvil es un **riesgo no ejecutado**. | Tabla de filas bajo demanda en escritorio; cards con nombre, SKU, stock/mínimo, precio y acciones en zonas separadas en móvil. Verificar nombres largos y texto al 200%. |
| D09 · P2 · M | **Confirmado.** `Future.wait` acopla cinco recursos del POS y tres del taller; refrescar reemplaza contenido por spinner (`pos_screen.dart:54`, `workshop_screen.dart:43`, `inventory_screen.dart:230`). | Estados independientes por sección, datos anteriores visibles durante actualización, error local y reintento. Fallo de historial de ventas no debe impedir consultar catálogo. |
| D10 · P2 · M | **Confirmado.** Tema claro define botones principales 48×48 y delineados 44×44 (`core/theme.dart:65`); oscuro no replica esas reglas. No se encontraron atajos propios en las tres pantallas. | Tokens compartidos para ambos temas, controles táctiles ≥48×48 y foco visible. Definir atajos sin interferir con edición de texto; medir controles reales en ejecución. |
| D11 · P2 · M | **Confirmado.** Captura/selección de evidencia existe, pero `_attachEvidence` no activa `_saving` ni ofrece progreso local (`workshop_screen.dart:909`). Recepción registra nombre y aceptación, no se encontró captura de firma manuscrita en este recorrido. | Estado de subida por archivo, error recuperable y prevención de repetición. Firma como entrega separada con contrato de almacenamiento y asociación a recepción; no presentar nombre de aceptación como firma digital implementada. |
| D12 · P2 · M | **Confirmado.** Estado de negocio permanece en pantallas `StatefulWidget`; tema tiene `ValueNotifier`, un `StateProvider` en auth y otro notifier en `providers/theme_provider.dart`. | Una fuente de tema; migrar carrito y consultas a providers por módulo, con modelos tipados. Estado de foco/expansión permanece local. |
| D13 · P2 · S/M | **Confirmado.** Shell limita contenido a 1320; el máximo interno POS de 1600 queda subordinado al padre (`main.dart:267`, `:317`). | Política de ancho por módulo: datos usan ancho disponible, formularios conservan ancho legible. Probar 1920 y 2560 sin estirar inputs innecesariamente. |
| D14 · P3 · S | **Confirmado.** Dinero POS se representa como `$123456 CLP` (`pos_screen.dart:373`); inventario concatena enteros. Paleta de documentación histórica diverge del código. | Formateador CLP único con agrupación de miles y cero decimales; documentación de tokens alineada con marca vigente. |

Rutas abreviadas de pantallas corresponden a `mobile/lib/screens/`. Las líneas son referencias de la revisión y pueden cambiar con futuras ediciones.

## 4. Propuesta UX y layouts

### Política responsive propuesta

Se calcula con ancho útil de contenido, no por identificación de dispositivo. Valores iniciales para validar: compacto <600, medio 600–959 y amplio ≥960 píxeles lógicos. POS dividido exige además espacio mínimo de catálogo y carrito; en tablet se colapsa la navegación para preservar ese espacio. En vertical estrecho se usa carrito en sheet. No se reduce el objetivo táctil para forzar dos columnas.

| Módulo | Escritorio / ultrawide | Tablet | Smartphone / PDA |
|---|---|---|---|
| POS | Catálogo 60%, carrito 40%; historial en panel secundario | Mismo 60:40 cuando cabe; categorías táctiles y navegación compacta | Catálogo principal, resumen fijo inferior, carrito en sheet casi completo |
| Taller | Filtros + selector lista/Kanban; detalle lateral | Lista o tablero desplazable con acciones por menú | Chips de estado y lista secuencial; detalle por secciones |
| Inventario | Búsqueda + filtros + tabla; editor lateral | Filas cómodas o cards según ancho útil | Cards; editor en sheet con scroll, teclado y área segura |

Wireframes funcionales (propuestas, no capturas de la aplicación):

```text
POS — escritorio / tablet horizontal
┌──────────────────────────────┬──────────────────────┐
│ Buscar producto / servicio   │ Venta · cliente / OT │
│ Categorías · OTs por cobrar  │ Líneas de venta      │
│                              │ ↕ scroll independiente│
│ Catálogo ↕                   ├──────────────────────┤
│ Nombre · stock · precio CLP  │ Descuento · medio    │
│ [+ Agregar]                  │ Total CLP   [Cobrar] │
└──────────── 60% ─────────────┴──────── 40% ─────────┘

POS — móvil                 Taller — móvil
┌──────────────────────┐    ┌──────────────────────┐
│ Buscar / escanear     │    │ Mis trabajos · buscar│
│ Categorías           │    │ [Estado] [Responsable]│
│ Catálogo ↕           │    │ OT · patente · estado│
│ Nombre / stock / CLP │    │ Próxima acción       │
├──────────────────────┤    │ OTs ↕                │
│ 3 líneas · total CLP │    └──────────────────────┘
│ [Revisar y cobrar]   │    Abrir → detalle / checklist
└──────────────────────┘    → evidencia / guardar

Taller — escritorio
┌─────────────────────────────────────────────────────┐
│ Buscar · responsable · estado     [Lista | Kanban]   │
├───────────┬────────────┬────────────┬────────────────┤
│ Recepción │ En proceso│ Lista pago │ Detalle OT     │
│ OT / auto │ OT / auto │ OT / auto  │ Historial      │
│ ...       │ ...        │ ...        │ Inspección     │
│           │            │            │ Evidencias     │
└───────────┴────────────┴────────────┴────────────────┘
Las columnas mostradas son una simplificación visual. Se conserva cada
estado real; agruparlo no crea ni autoriza nuevas transiciones.

Inventario — escritorio
┌─────────────────────────────────────────────────────┐
│ Buscar · stock bajo       [Excel] [Nuevo producto]   │
├──────────┬───────┬───────┬─────────┬─────────────────┤
│ Producto │ SKU   │ Stock │ Mínimo  │ Venta CLP       │
│ Filas bajo demanda y ordenamiento                   │
├─────────────────────────────────────────────────────┤
│ Cargar más / estado de página                       │
└─────────────────────────────────────────────────────┘
Seleccionar → editor lateral; móvil → card + editor inferior.
```

El scanner de código de barras del wireframe es una capacidad objetivo: separar lector que escribe como teclado de captura por cámara, que requiere implementación y validación de permisos. El scanner LAUNCH sigue siendo el flujo de informes PDF y no se confunde con lectura de códigos.

Estados de OT se toman del dominio actual: received, inspecting, quoted, awaiting_approval, quote_rejected, approved, in_progress, ready, delivered y cancelled. “Lista para pago” es una etiqueta contextual de `ready`; no implica que exista pago confirmado. Estado de trabajo y estado de pago se muestran por separado.

## 5. Componentes Flutter y Riverpod

```text
core/
  theme/       GudexTokens, temas claro/oscuro, densidad
  adaptive/    GudexAdaptiveScaffold, AdaptiveEditor
  widgets/     StatusBadge, AsyncContent, MoneyText, QuantityInput
features/<modulo>/
  screens/     composición responsive
  widgets/     catálogo, carrito, tabla/cards, detalle
  models/      DTO y estado tipados
  providers/   consultas, filtros y comandos
  services/    repositorios sobre ApiClient
services/      HTTP y persistencia compartidos
```

| Componente / proveedor | Responsabilidad y estados |
|---|---|
| `catalogProvider(query, filters)` | Páginas y búsqueda completa; carga inicial, más resultados, error parcial y fin de resultados |
| `cartProvider` | Líneas, cantidades, descuentos y conflictos; único estado aunque cambie layout |
| `checkoutProvider` | Venta creada, registro de pago, checkout pendiente y confirmación desde backend |
| `workOrdersProvider(filters)` | Lista y tablero consumen las mismas órdenes; actualización por ID |
| `inventoryProvider(filters)` | Consulta y reconciliación después de cambios, sin vaciar toda la vista |
| `AdaptiveEditor` | Drawer/sheet con mismos campos y controller; guardar, error, éxito y cierre con cambios pendientes |
| `AsyncContent` | Diferencia vacío inicial, búsqueda sin resultados, error inicial y error durante actualización |

Migrar de forma incremental usando la versión Riverpod del proyecto; no actualizar dependencias como requisito del rediseño. Separar DTO, repositorio y estado antes de duplicar una pantalla por tamaño. El primer corte Dart debe ser vertical: inventario con formulario recuperable y base adaptativa, no una colección de componentes sin uso.

No se incluye código Dart sin compilar como si fuese una implementación validada. La entrega actual especifica contratos y criterios; la siguiente implementación debe compilar contra el SDK fijado por el proyecto y cubrir fallos reales.

## 6. Ergonomía, persistencia y rendimiento

- Preservar rojo/amarillo de marca, pero usar tokens semánticos para éxito, advertencia y error. Cada estado lleva texto/icono; medir contraste en ambos temas. Objetivo de contraste del proyecto: 4.5:1 para texto normal y 3:1 para texto grande y controles esenciales.
- Objetivos táctiles ≥48×48; espaciado suficiente entre quitar y aumentar cantidad. Densidad compacta solo con puntero/teclado y sin degradar operación táctil.
- `Tab` recorre acciones en orden; `Enter` envía solo el formulario enfocado; `Esc` cierra overlays con protección de cambios. Atajo propuesto Ctrl/Cmd+K para búsqueda, sujeto a comprobar conflicto con navegador. No asignar Enter global a cobro.
- Al abrir drawer/sheet mover foco al encabezado o primer campo; al cerrar devolverlo al control de origen. Etiquetas semánticas completas en iconos y cantidades.
- Listas bajo demanda ya existen y deben conservarse. Virtualización visual no resuelve D01: paginación y búsqueda son otra capa. Indexar clientes/vehículos por ID para evitar búsquedas repetidas por fila.
- Conservar datos previos durante refresco. Cancelar/descartar respuestas obsoletas de búsquedas y aislar reconstrucciones del carrito respecto del catálogo.
- `flutter_secure_storage` ya guarda sesión y borradores OT. No tratarlo como base masiva de catálogo ni suponer garantías idénticas en web y móvil. Validar el backend de almacenamiento de cada plataforma.
- Caché de consultas en memoria con invalidación después de venta/edición. Persistencia offline de catálogo y cola de evidencias son trabajos separados; no simular éxito cuando no se ha sincronizado.
- No afirmar tiempos de respuesta sin medición. Registrar latencia de API, tiempo de búsqueda, reconstrucciones, memoria y fluidez de scroll en build de perfil/release con dispositivo identificado.

## 7. Validación y datos de prueba

Matriz pendiente de ejecución: 360×800, 390×844, 768×1024, 1024×768, 1280×800, 1920×1080 y 2560×1440. Probar además anchos cercanos a los cortes 600, 900, 920 y 960; la coexistencia de cortes actuales y propuestos requiere especial atención. Repetir modos claro/oscuro, texto normal/200%, teclado físico/virtual y orientación.

| Caso | Resultado esperado |
|---|---|
| 251 productos, clientes y vehículos; 75 OTs generales | Acceso a registros fuera de primera página, relaciones completas y búsqueda sin falsos vacíos |
| Cambiar tamaño con carrito de 20 líneas | Cantidades/descuento intactos, total y CTA accesibles |
| Bajar stock mientras hay carrito | Línea preservada con conflicto explícito; cobro bloqueado hasta resolver |
| Fallar guardado de producto/ajuste | Editor abierto con valores preservados y error contextual |
| Crear venta y fallar pago o apertura de enlace | ID visible, estado preciso y recuperación sin crear otra venta |
| Timeout con resultado desconocido | Consultar/reconciliar operación; no repetir una mutación ciegamente |
| Fallar historial de ventas | Catálogo disponible y error acotado al historial |
| Subir foto/PDF con red lenta o error | Progreso o estado ocupado, reintento explícito y resultado verificable |
| Cambiar estado de OT y recibir rechazo | Estado anterior restaurado y explicación; alternativa al arrastre accesible |
| Excel con errores, revisión vencida o conflicto | Confirmación bloqueada y diferencias comprensibles; mantener garantías del backend |
| Roles admin/mecánico/cliente | Acciones visibles correctas y rechazo de llamadas sin autorización |
| Nombres largos, montos altos y teclado virtual | Sin pérdida de acciones, texto esencial ni guardado |

Pruebas automatizadas futuras: providers/repositorios con respuestas paginadas y fallos parciales; widgets para conservación de formulario y carrito al cambiar tamaño; integración para venta/pago/stock y permisos. `flutter analyze` existe en CI, pero no se encontró carpeta `mobile/test`. No se atribuye al CI una ejecución exitosa que no se consultó.

## 8. Orden de implementación y salida de esta auditoría

1. **Datos y recuperación:** D01–D04. Acordar contrato de búsqueda/paginación y reconciliación de pagos a partir de API actual; pruebas de regresión sobre más de 50 registros y fallos.
2. **Piloto inventario:** D03, D08–D10 y D12. Editor recuperable, estado en Riverpod, cards/tabla y tokens compartidos. Debe funcionar con teclado y error de red antes de replicarse.
3. **POS adaptativo:** D02, D04–D06 y D13–D14. 60:40, pie persistente y recuperación de cobro; validar OTs y stock.
4. **Taller:** D07 y D11. Lista/Kanban, drawer, evidencias; firma con contrato explícito en una entrega posterior.
5. **Cierre visual:** ejecutar matriz, capturas reales por rol/tamaño, resolver defectos y verificar compilación web antes de publicar.

No se requiere rehacer FastAPI ni migrar fuera de Flutter. Sí pueden requerirse cambios acotados de API para búsqueda completa y recuperación segura de mutaciones. La auditoría estática queda entregada; la fase visual continúa abierta hasta ejecutar la matriz y obtener evidencia.
