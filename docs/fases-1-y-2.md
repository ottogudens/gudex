# Fases 1 y 2: estabilización, recepción e inspecciones

## Alcance entregado

La fase 1 agrega una base controlada de cambios de base de datos con Alembic, reglas de permisos explícitas, validaciones de datos y pruebas. La fase 2 incorpora recepción digital, listas configurables, evidencias e informe de inspección.

## Migraciones

Desde `backend`:

```bash
alembic -c alembic.ini upgrade head
alembic -c alembic.ini current
```

La revisión `20260930_0001` es una línea base compatible con la base que Gudex ya creó en Railway. Comprueba las tablas existentes antes de crear las faltantes. Su downgrade no elimina tablas porque una instalación anterior puede contener datos que Alembic no creó.

Para cambios futuros crea una revisión y revisa el SQL antes de aplicarlo:

```bash
alembic -c alembic.ini revision --autogenerate -m "descripcion del cambio"
alembic -c alembic.ini upgrade head
```

## Reglas de datos

- El RUT se almacena sin puntos y con guion, validando el dígito verificador.
- La patente se almacena en mayúsculas, sin espacios ni guiones.
- El VIN debe tener 17 caracteres y excluye `I`, `O` y `Q`.
- Año y kilometraje se validan antes de guardar.
- La API responde `409` ante RUT, correo, patente, VIN o SKU duplicado.
- Los mecánicos pueden completar el trabajo técnico, pero solo administración puede cambiar totales de la orden, usuarios, integraciones y stock.

## Flujo de recepción e inspección

1. Abre una orden desde Flutter.
2. Usa **Completar recepción** para registrar combustible, daños, accesorios y observaciones.
3. En **Inspecciones**, aplica una plantilla con el botón de lista o agrega un punto manual.
4. Toca cada punto para registrar resultado, medición y observaciones.
5. En **Evidencias**, toma una fotografía o elige una imagen/PDF.
6. Adjunta el PDF del LAUNCH a la misma orden desde el flujo de scanner.
7. Revisa **Resumen para el cliente**. La cuenta cliente puede abrir el informe desde sus trabajos anteriores.

La conformidad de recepción registra el nombre y la fecha. No representa una firma electrónica avanzada.

## API principal

| Método y ruta | Uso | Perfil |
|---|---|---|
| `GET /api/v1/inspection-templates` | Lista plantillas activas | Equipo |
| `POST /api/v1/inspection-templates` | Crea una plantilla | Administración |
| `POST /api/v1/work-orders/{id}/inspection-templates/{template_id}/apply` | Copia puntos pendientes a la orden | Equipo |
| `PATCH /api/v1/inspections/{id}` | Actualiza resultado, medición y notas | Equipo |
| `GET/PUT /api/v1/work-orders/{id}/reception` | Consulta o guarda recepción | Equipo |
| `POST /api/v1/work-orders/{id}/evidence` | Sube JPG, PNG, WebP o PDF | Equipo |
| `GET /api/v1/work-orders/{id}/inspection-report` | Informe consolidado | Equipo |
| `GET /api/v1/portal/work-orders/{id}/inspection-report` | Informe de una orden propia | Cliente |

Las descargas se autorizan en el backend. Un cliente solo puede obtener adjuntos e informes asociados a sus propias órdenes.

## Pruebas locales

```bash
cd backend
python -m venv .venv
.venv/bin/pip install -e '.[dev]'
.venv/bin/pytest -q
```

El conjunto actual comprueba validadores, perfiles, plantillas, recepción, carga de evidencia, informe del cliente y rechazo de patentes duplicadas.
