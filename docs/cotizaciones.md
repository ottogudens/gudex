# Menú de cotizaciones

El perfil administrador dispone de **Cotizaciones** en el menú principal. En pantallas pequeñas, el menú inferior se puede desplazar horizontalmente.

1. Selecciona **Nueva cotización**, el cliente y una de sus órdenes de trabajo. Si todavía no tiene una orden, créala en **Órdenes de trabajo**.
2. Escribe el trabajo propuesto. Puedes agregar servicios del catálogo: se incorporan al detalle sin asignar precios automáticos.
3. Ingresa mano de obra/servicios y repuestos/insumos en CLP. Ambos campos requieren un valor explícito; usa 0 cuando no corresponda cobrar ese concepto. Agrega alcance, condiciones o vigencia en las observaciones.
4. Guarda el borrador. Puedes editarlo y revisar el documento con **Ver PDF**. Los PDF de borradores llevan una identificación visible.
5. Usa **Enviar al portal** para publicar la cotización. El cliente podrá verla y aprobarla o rechazarla desde su cuenta de portal. Una cotización publicada deja de ser editable.
6. Para enviarla por otro medio, usa **Compartir PDF** en un dispositivo compatible y elige la aplicación y el destinatario. En la web, **Descargar PDF para enviar** permite obtener el archivo y adjuntarlo en correo o WhatsApp.

Publicar en el portal no envía un correo ni un mensaje de WhatsApp. Compartir o descargar el PDF tampoco se registra como entrega confirmada al destinatario. No se requieren credenciales de mensajería para este flujo.

Las cotizaciones se pueden buscar por cliente, patente, orden, descripción o número, y filtrar por estado. El catálogo conserva sus valores sin definir; cada cotización recibe sus propios montos.

## API

- `GET /api/v1/quotes`: listado con cliente, orden y patente, disponible para administradores.
- `POST /api/v1/work-orders/{id}/quotes`: crea un borrador.
- `PUT /api/v1/quotes/{id}`: modifica exclusivamente borradores.
- `GET /api/v1/quotes/{id}/pdf`: genera un documento con marca Gudex y valores en CLP, disponible para administradores.
- `POST /api/v1/quotes/{id}/publish`: publica en el portal y actualiza el total de la orden.

Se reutilizan las tablas existentes, sin migraciones nuevas. El catálogo móvil se encuentra en `mobile/assets/catalogo-servicios.json`, derivado del CSV de servicios en `docs/catalogo-servicios.csv`.
