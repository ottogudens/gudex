# Auditoría de desarrollo pendiente — Gudex

Fecha: 15 de octubre de 2026, America/Santiago. Código base: `f822b1a` (main).

## 1. Dictamen y alcance

Gudex tiene una base funcional amplia de gestión de taller, pero todavía no constituye el ecosistema automatizado completo solicitado. Tener una pantalla, un endpoint o variables configuradas no demuestra que un proceso esté terminado ni que funcione de extremo a extremo en producción.

Esta auditoría revisa backend FastAPI/SQLModel, frontend Flutter, bridge Baileys, pruebas, CI, documentación y estado del despliegue web. No modifica datos de producción, no envía mensajes ni cobra pagos. No es una certificación de seguridad, tributaria o de compatibilidad mecánica. Las ausencias se refieren al repositorio inspeccionado; no prueban que una cuenta externa carezca de una configuración.

**Prioridad inmediata:** resolver la incidencia de clientes/vehículos y las diferencias de autorización entre acciones normales, inspecciones e IA. Después consolidar transacciones y trazabilidad antes de habilitar agentes que creen órdenes, cotizaciones o reservas.

Estados utilizados:

- **Implementado:** existe código identificable; no equivale a validación real con proveedores.
- **Parcial:** existe una base, pero faltan partes del flujo o controles.
- **Pendiente:** no se encontró implementación del alcance descrito.
- **No verificado:** requiere reproducción, credenciales, dispositivos o evidencia externa.

Las etapas de este informe reemplazan la numeración ambigua de fases anteriores para planificación. No se asigna un porcentaje global: faltan criterios de aceptación acordados y validaciones reales.

## 2. Evidencias y comprobaciones

| Comprobación | Resultado en esta auditoría | Alcance |
|---|---|---|
| `python -m pytest tests -q --strict-markers` | 77 aprobadas, una advertencia de deprecación Starlette/httpx | Base SQLite temporal explícita; no PostgreSQL de producción |
| Prueba aislada de confirmación IA | Reprodujo cambio de `delivered` a `in_progress` por mecánico sin asignación | Invocación de función con sesión en memoria; no explotación contra producción |
| `node --check baileys-bridge/index.mjs` | Correcto | Sintaxis, no emparejamiento ni entrega real |
| Configuración de URL Flutter | Cuatro casos aprobados en la entrega anterior: predeterminada, alias, prioridad y vacíos | Comprobación de Bash; no prueba del listado autenticado |
| Vercel | Despliegue `dpl_CtCCcASvhioSThxAQaMwbVv9tesa`, Ready, con alias `admin.gudex.cl` | Entrega del commit `f822b1a`; no certifica flujos de negocio |
| `flutter analyze` y `flutter test` | Sin incidencias de análisis; 15 pruebas aprobadas | SDK local `C:/flutter_sdk`, versión declarada 3.47.4; pruebas de widgets, no navegador productivo |

No se consultaron fichas personales ni se contó la base productiva. El incidente de registros invisibles permanece abierto. No se verificaron pagos reales, recuperación de backups, envíos WhatsApp, OAuth de cuentas externas ni Android/iOS físicos.

## 3. Arquitectura observada

- `backend/app/main.py`: 1.972 líneas; concentra clientes, vehículos, órdenes, agenda, fidelización, ventas y pagos.
- `backend/app/routers/`: separación parcial para inspecciones, integraciones, asistente, catálogo, importaciones, redes y ficha técnica.
- `backend/app/services/`: IA, búsqueda técnica, documentos, PDF, Google, catálogo e importación.
- `backend/app/models.py`: modelos operativos, integración y auditoría IA; migraciones Alembic en `backend/alembic`.
- `mobile/lib/main.dart`: shell, navegación y compatibilidad con código anterior; 660 líneas.
- `mobile/lib/screens/workshop_screen.dart`: 2.513 líneas; clientes, vehículos y trabajo operativo comparten pantalla y estado.
- `mobile/lib/screens/pos_screen.dart`: 1.581 líneas. Existen providers Riverpod, pero varias pantallas mantienen llamadas y estado local propios.
- `baileys-bridge/index.mjs`: servicio Node separado, sesión en archivos y rutas internas de pruebas.
- `.github/workflows/quality.yml`: pruebas backend en SQLite/PostgreSQL y análisis/pruebas Flutter. No contiene un job del bridge ni pruebas de navegador contra despliegues.

Reestructuración recomendada: conservar un **monolito modular**, no reescribir todo ni introducir microservicios para cada módulo. Extraer servicios de dominio compartidos para permisos/transiciones, ventas/pagos, agenda, mantenciones y comunicaciones. Frontend por funcionalidades con repositorios de datos y tratamiento uniforme de sesión/error. Separar un worker durable para trabajos externos; mantener adaptadores de proveedores fuera de reglas de negocio.

## 4. Hallazgos prioritarios

### A01 — Alta: la IA evita controles del flujo normal de órdenes

Evidencia: `backend/app/routers/assistant.py:196`, comparado con `backend/app/main.py:866`.

La ruta normal comprueba asignación del mecánico y transiciones permitidas. La confirmación IA valida el autor y rol de la propuesta, pero asigna directamente el estado, sin reutilizar esas comprobaciones. La prueba aislada ejecutó una propuesta de mecánico sin asignación sobre una orden entregada y la volvió a `in_progress`.

Pendiente: servicio único de transición, autorización por orden, rechazo de propuestas obsoletas, control transaccional contra doble confirmación y pruebas HTTP negativas. Confirmar humanamente no sustituye autorización.

### A02 — Alta: la ficha del portal incluye cotizaciones en borrador

Evidencia: `backend/app/main.py:595` y `:741`. El historial genérico consulta todas las cotizaciones de las órdenes; el endpoint del portal reutiliza ese resultado sin filtrar `draft`. En contraste, `/portal/quotes` sí los excluye.

Es una exposición al propietario de su propio vehículo antes de publicar la cotización, no evidencia de acceso entre clientes. También se reutilizan modelos completos de órdenes/cliente; definir explícitamente campos internos y publicados.

Pendiente: DTO específico del portal, filtrado de borradores en todas las rutas y pruebas de respuestas completas, no solo de widgets. La invisibilidad en la interfaz no protege un campo enviado por la API.

### A03 — Alta: los controles de asignación no son uniformes en inspecciones

Evidencia: `backend/app/routers/inspections.py:91` y rutas de aplicación de plantilla/recepción/evidencias. El router exige perfil de equipo, pero editar una inspección no comprueba la asignación que sí exige editar la orden normal.

Pendiente: decidir y documentar si un mecánico puede colaborar en cualquier orden o únicamente en las asignadas; aplicar esa política a todos los subrecursos y al contexto IA. No confundir autenticación del equipo con autorización sobre cada orden.

### A04 — Alta operativa, causa no determinada: clientes y vehículos invisibles

Evidencia: `mobile/lib/screens/workshop_screen.dart:43`, `mobile/lib/services/api_client.dart:35`, listas en `backend/app/main.py:441` y `:543`.

La pantalla espera ambas consultas con `Future.wait`; el fallo de cualquiera lleva a una vista de error común. `getAll` recorre todas las páginas antes de mostrar datos. El cliente HTTP no establece un timeout explícito ni normaliza respuestas no JSON; un 401 no activa aquí un flujo central de reautenticación. Los clientes archivados están excluidos por defecto.

Son condiciones confirmadas del código, **no una causa raíz confirmada del incidente**. El contenedor de navegación tiene una clave por módulo, por lo que no se debe atribuir el problema a reutilización de estado sin reproducirlo.

Pendiente: capturar estado HTTP y mensaje real con sesión autorizada, comparar lectura con registros esperados, comprobar URL compilada/CORS/sesión y archivo de clientes. Separar carga/error de cada lista, conservar datos válidos, incorporar timeout y reintento, paginación visible y pruebas crear → listar → recargar. No recrear ni migrar datos para intentar resolverlo sin diagnóstico.

### A05 — Alta: fidelización incompleta ante cambios y concurrencia

Evidencia: `backend/app/main.py:1177`, `:1206`, `:1881`.

- El canje lee saldo y después inserta débito sin bloqueo visible: riesgo de saldo insuficiente con solicitudes simultáneas, pendiente de prueba PostgreSQL concurrente.
- Un canje `approved` puede pasar a `rejected`, pero el reembolso de puntos solo ocurre si estaba en `requested`.
- El webhook de reversión de pago actualiza pago/venta, sin reversar los puntos otorgados en ese tramo.

Pendiente: política de cancelación/reembolso, transacciones atómicas, idempotencia y movimientos compensatorios auditables. No borrar el historial para corregir saldos.

### A06 — Alta antes de escalar: concurrencia de agenda y pagos

Evidencia: `ensure_appointment_slot` (`main.py:1273`) comprueba solapamiento antes de guardar; `Payment.provider_reference` está indexado pero no es único (`models.py:306`); el webhook busca un pago antes de insertarlo.

Riesgos por revisión estática, no incidentes demostrados: reservas simultáneas del mismo cupo, webhooks concurrentes repetidos y cobros manuales concurrentes. Las pruebas secuenciales no bastan. El stock sí utiliza actualización condicional atómica: conservar ese patrón, no declararlo ausente.

Pendiente: restricciones/transacciones adecuadas, claves de idempotencia y pruebas con sesiones independientes sobre PostgreSQL.

### A07 — Media: estado «configurado» no significa conexión funcional

Evidencia: `backend/app/routers/integrations.py` construye varios indicadores con presencia de claves/tokens; WhatsApp oficial devuelve `configured: False`; `routers/social.py:58` declara publicación automática no disponible.

Pendiente: distinguir configuración, conectividad comprobada, autorización expirada, sesión conectada y última operación correcta. Mostrar último chequeo y errores accionables sin secretos. No resolver un botón deshabilitado eliminando su control de seguridad.

### A08 — Media: tareas y sesiones sin recuperación automática completa

Evidencia: enriquecimiento de vehículo mediante `BackgroundTasks`; Baileys no registra mensajes entrantes y en desconexión cambia estado sin programar reconexión. La promesa `connecting` protege creación inicial, no todo el ciclo hasta conexión/QR.

Pendiente: jobs persistentes con reintentos, deduplicación y estado; ciclo único de sesión del bridge, reconexión limitada, recuperación tras reinicio y tratamiento explícito de `logged_out`. No afirmar que un 202 de envío sea entrega al destinatario.

### A09 — Media: deuda de seguridad y operación por verificar

El limitador (`backend/app/rate_limit.py`) vive en memoria por proceso y usa el primer `X-Forwarded-For`: revisar confianza del proxy antes de atribuir un bypass. No escala como límite distribuido. Revisar cuotas IA por usuario, límites de archivos, retención, permisos mínimos, restauración, registros de auditoría generales y separación de entornos.

La autenticación sí incluye roles, hash de contraseñas e invalidación por versión de token. No se debe presentar el sistema como carente de autenticación ni afirmar cumplimiento normativo sin revisión especializada.

## 5. Matriz funcional del alcance solicitado

| Área | Base existente | Desarrollo o validación pendiente |
|---|---|---|
| Clientes y vehículos | CRUD, normalización, archivo, acceso al portal, importación masiva | Incidente de visualización, búsqueda/paginación escalable, recuperación de archivados y duplicados con historial |
| Órdenes y mecánicos | Asignación administrativa, bandeja propia, estados, diagnóstico, recepción, fotos, sesiones de tiempo | Autorización homogénea, toma de órdenes disponibles si se aprueba esa política, control de calidad/entrega y garantías/retrabajos |
| Inspecciones | Plantillas, resultados, mediciones, archivos y PDF | Autor por cambio, edición concurrente, permisos por orden y aceptación verificable del cliente |
| Ficha digital | Cinco pestañas, OEM/equivalencias, fluidos, fuentes, revisión y versiones | Cobertura real de catálogos, identidad/variante precisa, PDF/QR seguro, vínculo a productos e historial de ejecución de planes |
| Diagnóstico | Síntomas, inspecciones, historial y extracción de texto PDF; hipótesis IA | DTC/mediciones estructuradas, OCR, trazabilidad prueba→resultado→conclusión, aprobación técnica; no integración directa con hardware scanner |
| Mantenciones | Intervalos km/días, consulta de vencimientos y marcado de realización | Historial inmutable de cada ejecución, vínculo con orden y materiales, uso severo y recordatorios enviados |
| Cotizaciones | Creación, edición, PDF, publicación y aprobación/rechazo | Líneas estructuradas con servicios/repuestos, versiones comerciales, vigencia, solicitud del cliente y conversión trazable a venta/orden |
| Agenda | Citas, portal, reprogramación/cancelación, bloqueo global de solapamiento | Recursos/bahías/técnicos, capacidad paralela, horarios/feriados, concurrencia y recordatorios |
| Inventario y ventas | Catálogo, stock/movimientos, POS, servicios, pagos, PDF interno | Compras/proveedores, devoluciones, caja, conciliación, costos/márgenes, consumo de repuestos por orden |
| Pagos | Checkout y verificación de webhook, medios manuales | Prueba sandbox real, concurrencia, devoluciones operativas y conciliación; Point automático no implementado |
| Documentos tributarios | Comprobante interno explícitamente no tributario | Definir proveedor/emisor y desarrollar emisión, estados, contingencias y conciliación; requiere validación especializada |
| Portal cliente | Vehículos/historial, cotizaciones, citas, documentos, puntos y avisos | Eliminar borradores/datos internos, solicitudes de cotización, pagos integrados según permisos y preferencias de comunicación |
| IA administrativa | Consulta contextual y una acción mutante confirmada: cambiar estado de orden | Herramientas transaccionales autorizadas para clientes/citas/cotizaciones, evaluación, presupuesto, memoria y trazabilidad |
| WhatsApp | Bridge Baileys privado, QR, estado y envío de texto a lista permitida | Recepción, persistencia de conversaciones, adjuntos, derivación, agente de ventas y adaptador oficial |
| Marketing/fidelización | CRUD de campañas, contenido social, puntos y canjes | Segmentación ejecutable, consentimiento/baja, envío programado, métricas, correcciones de saldo y vencimiento de beneficios |
| Google/redes | OAuth Google, importación manual, sincronización explícita Calendar, exportación de contenido | Automatización durable y pruebas de cuenta real; OAuth/publicación Meta completos y métricas no implementados |
| UI/UX y móvil | Tema compartido, navegación adaptable, formularios, estados y borradores locales | Auditoría visual real por rol/dispositivo, accesibilidad, notificaciones, cola offline, distribución Android/iOS |

## 6. Plan por etapas y criterios de cierre

### Etapa 1 — Estabilización y autorización (P0; bloquea expansión)

1. Resolver A04 con evidencia de las solicitudes reales y pruebas de regresión.
2. Corregir A01–A03 mediante una política común de acceso y proyecciones del portal.
3. Unificar errores HTTP, sesión vencida, timeout y recuperación de carga; no mostrar error como lista vacía.
4. Verificar Baileys configurado/deshabilitado/desconectado/QR/expirado sin enviar fuera de la lista de pruebas.

**Cierre:** admin crea y vuelve a ver cliente/vehículo tras recargar; portal solo ve sus datos publicados; mecánico no modifica una orden ajena por ninguna ruta; orden entregada no retrocede por IA. Evidencia HTTP y pruebas automatizadas. Incidencias reales reproducidas y cerradas, no solo código desplegado.

### Etapa 2 — Integridad transaccional, continuidad y modularización mínima (P0/P1)

1. Resolver A05–A06 con pruebas concurrentes PostgreSQL.
2. Extraer permisos/transiciones a servicios de dominio usados por UI, API e IA.
3. Registro de auditoría general con actor, entidad, cambio y correlación, sin secretos.
4. Worker y tabla/cola de trabajos para IA, importaciones y comunicaciones; reintentos con límite y estados de fallo.
5. Confirmar backups de base y archivos, realizar restauración de ensayo y acordar RPO/RTO. Separar staging y producción.

**Cierre:** dos solicitudes simultáneas no duplican cobros, canjes ni reservas; reiniciar un worker no pierde trabajos; restauración documentada; controles de negocio compartidos. Dependencia: etapa 1.

### Etapa 3 — Ficha técnica y operación automotriz completa (P1)

1. Identificación por versión, motor, transmisión y mercado; VIN validado sin asumir decodificación universal.
2. Fuentes de fabricante/catálogos con licencia cuando corresponda. Validar aplicaciones de Mann/Tecfil/Wega/HK; un enlace citado no demuestra equivalencia.
3. Aprobación técnica de normas, viscosidades, capacidades/procedimiento y química del refrigerante; color solo informativo. No autocompletar datos ambiguos como hechos.
4. Planes por km/tiempo y condición de uso, con ejecuciones inmutables asociadas a orden, kilometraje, fecha, técnico, filtros y fluidos utilizados.
5. DTC por módulo y estado, síntomas, freeze frame/mediciones/unidades, prueba realizada, resultado y diagnóstico confirmado por técnico. OCR separado y validación de PDF escaneados.
6. PDF de ficha y tarjeta de próxima mantención; QR con autenticación o enlace limitado/revocable, nunca historial público completo por defecto.
7. Checklist de control de calidad, entrega, garantía y retrabajo.

**Cierre:** vehículo ambiguo pide datos; vehículo conocido conserva fuente y aprobación; cada trabajo permite reconstruir qué se hizo y qué material se usó; ficha cliente y PDF coinciden. Dependencias: 1–2. Los conocimientos mecánicos deben convertirse en reglas y evidencia, no en promesas de diagnósticos infalibles.

### Etapa 4 — Portales, agenda y UI/UX profesional (P1)

1. Cliente: solicitud de cotización, seguimiento claro, citas según capacidad real, preferencias de contacto y documentos publicados.
2. Mecánico: recepción de asignación, inicio/pausa/fin, pendientes, fotos con contexto, mediciones y cierre técnico. Definir si toma libre de órdenes o asignación central.
3. Administración: búsqueda global por patente/cliente/orden, filtros persistentes, archivados, acciones masivas seguras y estados consistentes.
4. Agenda por bahía/técnico/duración, zona horaria Chile, feriados y reprogramación con trazabilidad.
5. Sustituir IDs manuales por selectores buscables en importaciones; validar formularios y explicar errores.
6. Pruebas visuales claro/oscuro, teclado, lector de pantalla, contraste, 390 px/móvil y escritorio; funcionamiento con red lenta y sesión expirada.
7. Cola offline explícita, separación de borradores por usuario/entorno, política de cierre de sesión y conflictos; no confundir borrador local con sincronización completa.

**Cierre:** tres recorridos E2E por rol sin intervención técnica, sin desbordes y con recuperación de fallos; pruebas reales de dispositivos antes de declarar Android/iOS listos. Dependencias: 1–3; diseño visual puede adelantarse.

### Etapa 5 — Comunicaciones y WhatsApp (P1)

1. Estabilizar Baileys como adaptador de pruebas: sesión única, reconexión, volumen, errores, pruebas de desconexión/QR y estado real de envío.
2. Modelo de conversación, mensaje, adjunto, contacto, consentimiento y responsable; bandeja del equipo y derivación humana.
3. Entrada autenticada/verificada según proveedor, deduplicación de eventos y colas de envío. Archivos privados con controles de tipo/tamaño y acceso.
4. Adaptador oficial WhatsApp Business para producción; plantillas y políticas del proveedor se validarán al implementar. Mantener intercambiable el adaptador de pruebas.
5. Notificaciones de cita, cotización, aprobación, vehículo listo y mantención; preferencias, bajas y auditoría de entregas.

**Cierre:** conversación de prueba recibe texto/archivo, identifica correctamente al cliente, deriva al equipo y no duplica eventos; fallo/reinicio no pierde mensajes. Un número de teléfono por sí solo no debe dar acceso al historial completo. Dependencia: 2 y contratos de identidad de 4.

### Etapa 6 — IA comercial y administrativa con acciones seguras (P1/P2)

1. Herramientas limitadas para consultar catálogo/stock/precios, preparar cotización, proponer cupo y registrar solicitudes.
2. Ejecutar solo mediante los servicios de dominio de etapa 2, con permisos, validación de precios, capacidad e idempotencia.
3. Confirmación explícita para compromisos comerciales; aprobación administrativa para descuentos/cambios sensibles; derivación ante duda o reclamo.
4. Contexto aislado por cliente/conversación; datos mínimos hacia el proveedor, retención y protección contra instrucciones en archivos.
5. Evaluaciones de exactitud, acceso indebido, prompt injection, precios inventados, ambigüedad de vehículo, duplicados y caída de proveedor.
6. Límites de gasto/usuario, métricas de uso, latencia, tasa de derivación y revisiones humanas.

**Cierre:** agente cotiza con catálogo vigente y agenda cupo real sin saltarse permisos; no inventa repuestos ni diagnostica definitivamente por chat; pruebas negativas y aprobaciones auditables. Dependencias: 2, 4 y 5. No habilitar autonomía ampliada antes de corregir A01.

### Etapa 7 — Fidelización, promociones y marketing ejecutable (P2)

1. Completar administración de premios y reglas; resolver saldos, devoluciones y concurrencia antes de campañas.
2. Segmentación por historial, próxima mantención y preferencias; consentimiento y baja por canal.
3. Programación durable, límites de frecuencia, exclusión de duplicados, vista previa y aprobación de campaña.
4. Entrega/rebote/respuesta, conversión a cita/venta y medición de retorno; no usar «active» como equivalente de «enviada».
5. Publicación real a redes si se aprueban cuentas/permisos; exportación manual sigue siendo alternativa válida.

**Cierre:** campaña de prueba llega solo a destinatarios autorizados, permite baja y deja trazabilidad; un canje rechazado/reembolsado conserva saldo correcto. Dependencias: 2, 5 y 6 cuando use IA.

### Etapa 8 — Administración comercial y puesta en producción controlada (P1/P2)

1. Compras/proveedores, recepción de mercadería, costos, consumo por orden, devoluciones y reposición.
2. Caja/apertura/cierre, pagos parciales, conciliación, reembolsos, trazabilidad de descuentos y márgenes.
3. Cotizaciones por líneas y conexión cotización→orden→consumo→venta; evitar duplicación de importes ingresados manualmente.
4. Emisión tributaria: decisión del taller sobre proveedor y habilitación, pruebas de emisión/consulta/corrección y contingencias. El comprobante actual no sustituye este desarrollo.
5. Indicadores de capacidad, productividad, margen, recurrencia y trabajos repetidos; acordar definiciones y contrastar con operaciones reales.
6. CI con bridge, E2E, seguridad/dependencias, pruebas de migración/restauración, contratos de proveedor y gate de release. Evitar divergencia entre SDK local 3.47.4 y CI/build 3.47.3 sin decisión explícita.
7. Observabilidad, alertas, runbooks, soporte, piloto del taller, formación y criterios de rollback.

**Cierre:** ciclo comercial completo conciliado y probado, documentos correctamente identificados, recuperación comprobada y piloto aceptado por administración/mecánicos/clientes. El control financiero puede adelantarse tras etapa 2; no depende de terminar marketing. La parte tributaria depende de decisión externa y no tiene fecha cerrada todavía.

## 7. Orden práctico y dependencias

Ruta crítica: **1 → 2 → 3/4 → 5 → 6 → 7**. Etapa 8 comienza tras 2 en caja/inventario y cierra la salida operativa general. Seguridad, pruebas, observabilidad y accesibilidad se aplican durante todas las etapas, no solo al final.

Primer lote recomendado:

| Orden | Entregable | Responsable funcional | Validación |
|---|---|---|---|
| 1 | Reproducir y cerrar listados invisibles | Backend + frontend + usuario del taller | Solicitudes reales y prueba crear/listar/recargar |
| 2 | Unificar permisos IA y órdenes | Backend | Pruebas de asignación y transición por API e IA |
| 3 | DTO seguro del portal | Backend + frontend | Borradores y campos internos ausentes del JSON |
| 4 | Inspecciones con política explícita de acceso | Taller + backend | Mecánico autorizado/no autorizado |
| 5 | Saldo de puntos y reversión | Backend + administración | Rechazo tras aprobación y reversión de pago |
| 6 | Concurrencia y sesión HTTP | Backend + frontend | PostgreSQL simultáneo, 401, 500 HTML y timeout |

No se comprometen fechas sin acordar responsables, disponibilidad y pruebas con proveedores. Estimar por lote después de criterios de aceptación; revisar avance por evidencias, no por número de pantallas o commits.

## 8. Decisiones necesarias del taller

- Política de acceso de mecánicos y colaboración/toma de órdenes.
- Qué información interna se publica al cliente y quién aprueba el diagnóstico/ficha.
- Bahías, técnicos, horarios, duración de servicios y capacidad simultánea.
- Catálogos técnicos disponibles/licencias y vehículos prioritarios para validar cobertura.
- Cuenta y modalidad WhatsApp productiva; identidad, consentimiento y responsables de derivación.
- Reglas de puntos, descuentos, devoluciones, garantías y reembolsos.
- Proveedor tributario, datos del emisor y alcance contable.
- Objetivos de recuperación, retención, presupuesto IA y canales de alerta.
- Prioridad Web/PWA frente a aplicaciones nativas: en el árbol revisado hay `mobile/web`, no proyectos `android`/`ios`.

## 9. Definición de terminado

Una etapa se cierra cuando: código revisado, pruebas relevantes aprobadas, migración reversible o recuperación documentada, permisos negativos probados, UX validada por rol, integración real ensayada cuando aplique, monitoreo y manual actualizados, despliegue identificado y aceptación funcional registrada.

Los documentos anteriores se conservan como historial. La afirmación «fases 1–4 implementadas» de `estado-del-desarrollo.md` describe una entrega previa, no el cumplimiento completo del alcance actual. Este informe tampoco cierra por sí mismo ninguno de los defectos: documenta el backlog y la evidencia para resolverlos.
