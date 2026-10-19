# Auditoría de ficha técnica y tarjeta digital de mantención

Fecha: 18 de octubre de 2026. Alcance: código de GudexApp y enlace público de gudex-web. No incluye una validación real de catálogos para un VIN concreto ni confirma el estado de las credenciales de IA en Railway.

## Diagnóstico

| Área | Evidencia en el código | Impacto | Medida |
| --- | --- | --- | --- |
| Investigación técnica | `research_vehicle` exige `AI_PROVIDER=openai`, `AI_API_KEY`, modelo compatible con `web_search` y fuentes devueltas por la API. | Si falta cualquiera, no propone campos. Una respuesta sin fuentes verificables se rechaza intencionalmente. | Mostrar el fallo por sección; verificar configuración y cuota en Railway; mantener revisión humana. |
| Reintentos | `enrich_vehicle` omitía cualquier campo que ya tuviera una entrada, incluso si era una sugerencia de IA. | La primera sugerencia congelaba un dato incompleto. | Reintentar propuestas de IA sin sobrescribir datos manuales ni verificados; dividir la búsqueda por grupos. |
| Datos identificadores | La ficha usa marca/modelo/año/motor y campos de variante; VIN y códigos de motor pueden faltar. | No es seguro determinar filtros, fluidos o capacidades de una variante ambigua. | Pedir VIN, versión, código de motor y mercado; dejar sin completar lo no documentado. |
| Fuentes | `parse_proposals` acepta solo URL HTTPS efectivamente consultada por búsqueda web. | Evita equivalencias inventadas, pero puede dejar campos pendientes. | Mantener este control; distinguir ausencia de evidencia de fallo técnico. |
| Mantenciones | Los planes calculaban vencimiento por intervalo y las ejecuciones no conservaban una fecha/km explícitos. | Una tarjeta histórica podía cambiar si el plan se editaba después. | Guardar en cada servicio el próximo km/fecha como instantánea; aceptar ajuste manual validado. |
| Consulta pública | No había tarjeta por patente ni selección de datos publicables. | La antigua tarjeta de cartón no tenía equivalente digital público. | Activación voluntaria por vehículo, consulta limitada y sin datos de cliente/VIN. |
| Portal cliente | Ya existían planes y ejecuciones en el historial, pero sin tarjeta de aceite ni solicitud de cotización. | Información dispersa y poca autonomía del cliente. | Módulo visual de tarjeta y solicitud separada de la cotización con precio. |

## Diseño implementado

1. **Ficha técnica modular:** identidad, características, filtros, fluidos y mantenciones siguen separados. La cabecera muestra verificados/sugeridos; los campos incluyen estado, fuente y entrada animada. La IA nunca convierte automáticamente una propuesta en dato verificado.
2. **Mantención preventiva:** el plan se clasifica como aceite, filtros, preventiva o general. Cada ejecución registra kilometraje real, materiales/observaciones y próximo km o fecha; se calculan por intervalo si no se especifican. Se ve en la ficha y el portal.
3. **Tarjeta digital de aceite:** toma el último cambio realmente registrado en un plan de aceite. Muestra patente, modelo, servicio, fecha y km realizados, próxima fecha y próximo km. No publica nombres, contacto, VIN, órdenes, precios ni detalles mecánicos. Sin servicio registrado no hay tarjeta.
4. **Privacidad:** la tarjeta pública está desactivada por defecto; administración la habilita por vehículo. La consulta por patente tiene límite de solicitudes, respuesta genérica cuando no existe o no está habilitada y cabecera de no almacenamiento en caché. Con solo patente no se accede a la ficha completa.
5. **Solicitudes de cotización:** el cliente describe una necesidad para uno de sus vehículos. Administración la convierte en borrador y define precios; el cliente no puede publicar un precio ni aprobarse a sí mismo.

## Verificaciones pendientes de producción

- Confirmar en Railway `AI_PROVIDER`, `AI_API_KEY`, `VEHICLE_RESEARCH_MODEL`, cuota y permiso de búsqueda web. No registrar claves en la ficha ni en logs.
- Ejecutar migración `20261018_0024`; comprobar que haya una sola cabeza Alembic y que el backend arranque.
- Probar un VIN/variante real contra manuales y catálogos oficiales, revisar sugerencias, verificar manualmente las referencias y repetir la búsqueda.
- Registrar un cambio de aceite, habilitar tarjeta pública, consultar la patente desde el sitio y verificar que una patente no habilitada no exponga información.
- Validar legibilidad y teclado móvil de la ficha, formulario de solicitud y tarjeta en anchos de 375 y 1440 px.

## Mejoras siguientes

- Consentimiento registrable del cliente para publicar tarjeta, revocación y auditoría de consultas. La habilitación actual corresponde a administración.
- Recordatorios de próxima mantención por Gmail/WhatsApp con preferencias y consentimiento.
- Catálogo técnico curado por VIN/versión y sincronización con números OEM realmente instalados; no usar la IA como fuente única de compatibilidad.
- Si la API escala a varias réplicas, sustituir el limitador en memoria por un almacén compartido.
