# Ficha técnica digital del vehículo

Implementación del 15 de octubre de 2026.

Cinco pestañas disponibles para vehículos nuevos y existentes: información,
características y cuidados, filtros, lubricantes/fluidos y mantenciones/trabajos.
Administración edita identificación y especificaciones desde la ficha. Mecánicos
y clientes consultan; el portal conserva el aislamiento por propietario.

Los datos técnicos tienen valor, fuente, estado, fecha y revisión. La tabla
`vehicletechnicalentry` conserva versiones anteriores; una revisión desactualizada
se rechaza con 409. Verificar exige valor y fuente. Cambiar la identificación,
motor o variante hace que las especificaciones anteriores requieran revisión;
no altera lo registrado históricamente. La migración `20261015_0017` crea una
tabla aditiva y no modifica vehículos existentes.

Filtros: OEM, Mann, Tecfil, Wega y HK para aceite, aire, combustible y habitáculo.
Fluidos: motor, transmisión, diferenciales, transferencia, frenos, dirección y
refrigerante; normas, viscosidad/tipo, capacidades/procedimiento y producto.
Refrigerante incluye composición, concentración y color informativo.

## Asistencia y fuentes

Después de crear un vehículo, una tarea del proceso prepara el resumen y busca
datos faltantes usando Responses con búsqueda web. La creación no depende del
éxito de esa búsqueda. El botón «Buscar datos faltantes con IA» permite reintentar
en vehículos existentes. El estado de búsqueda queda visible en Cuidados.

Requiere `AI_PROVIDER=openai`, `AI_API_KEY` y un modelo con búsqueda web.
`VEHICLE_RESEARCH_MODEL` usa por defecto `gpt-5-mini`; es independiente del modelo
conversacional seleccionado en Integraciones. Hay límite de cinco solicitudes
manuales por cinco minutos según el limitador existente. La consulta no incluye
nombre del cliente, patente ni VIN. Se envían marca/modelo/año/motor y variante.

Se solicitan fuentes primarias y aplicación exacta. Solo se aceptan claves
conocidas y URLs HTTPS presentes en las fuentes/citas devueltas por la búsqueda.
Una cita no prueba compatibilidad: todas las propuestas son «Sugerido por IA» y
requieren revisión humana. Los datos existentes no se reemplazan. No se prometen
equivalencias para variantes ambiguas o catálogos que no sean accesibles.

Referencia de implementación:
https://developers.openai.com/api/docs/guides/tools-web-search

## Límites operativos

La tarea inicial es de mejor esfuerzo, no una cola durable. Si el proceso se
reinicia, se reintenta desde la ficha. El modelo/clave y la cobertura real de
catálogos requieren validación en el entorno del taller.

La pestaña Mantenciones usa planes y órdenes existentes, conserva informes PDF
de scanner y citas, y calcula próximo servicio por fecha y kilometraje. No
convierte una sugerencia en plan de mantención. No incluye en esta entrega un
PDF/QR nuevo de la ficha, conexión contractual a catálogos privados ni integración
automática de productos sugeridos al inventario.
