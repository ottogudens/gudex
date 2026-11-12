# Plan de desarrollo: migración completa de Gudex a Cloudflare

**Alcance:** trasladar el sitio público, GudexApp, API, datos, archivos, integraciones, DNS y operación a Cloudflare; retirar Vercel y Railway solo al superar los criterios de salida. El destino de usuario es `gudex.cl` para el sitio de la empresa y `admin.gudex.cl` para GudexApp. Se recomienda `api.gudex.cl` para la API productiva.

## Estado base (12 de noviembre de 2026)

- **Pages de staging:** `gudexapp-staging`, enlazado a `ottogudens/gudex`; rama actual `codex/cloudflare-migration-customer-backup`; raíz `mobile`; build `bash scripts/build_cloudflare.sh`; salida `build/web`. El último commit `ffcd0e0` se publicó correctamente.
- **D1 de staging:** `gudexapp-staging`. Se importaron y conciliaron los respaldos recibidos: 20 clientes, 18 vehículos, 7 órdenes, 6 servicios de orden, 21 inspecciones, 7 planes, 6 ejecuciones de mantenimiento, 12 tarjetas de aceite, 82 entradas técnicas, 8 reportes de escáner, 8 sesiones, 3 asignaciones, 1 recepción, 1 control de calidad, 2 cotizaciones, 19 productos, 60 servicios y 10 categorías. `PRAGMA foreign_key_check` no reportó errores.
- **Cuentas:** no se copiaron hashes ni tokens de acceso/recuperación. Cuatro usuarios históricos requeridos por el historial están inactivos y pendientes de clave. Se creó en staging la cuenta administrativa solicitada, almacenando su contraseña como hash Argon2id.
- **Worker/API:** `gudexapp-api-staging` responde correctamente en `/health`; las demás rutas todavía no están disponibles en el Worker remoto. El código local inicial cubre autenticación, usuarios y CRUD básico de clientes, pero no el conjunto de contratos FastAPI.
- **DNS y dominios:** la cuenta consultada todavía no contiene la zona `gudex.cl`; Pages no tiene aún dominio personalizado. No se ha cambiado DNS.
- **R2 y archivos:** R2 estaba deshabilitado al último chequeo. El respaldo JSON no contenía adjuntos.
- **Aplicación origen:** backend FastAPI/SQLModel con 35 revisiones Alembic y 235 operaciones HTTP documentadas; frontend Flutter Web; bridge Baileys separado.

## Avance de las etapas 0–2 (12 de noviembre de 2026)

- **Etapa 0 — iniciada:** se generó [`inventario-api-cloudflare.md`](inventario-api-cloudflare.md) desde OpenAPI: 235 operaciones en 184 rutas, clasificadas por 30 dominios/etiquetas. Incluye método, ruta, resumen, rol/dependencia observable, `operationId` y ubicación del handler. Aún faltan el mapa ruta→pantalla Flutter, efectos laterales, tareas/eventos externos, formatos exactos y revisión de permisos por recurso; por eso el inventario no se considera aceptado ni cerrado.
- **Etapa 1 — validación estructural inicial:** SQLModel define 59 tablas y 118 índices. La comparación de nombres contra `sqlite_master` de D1 staging dio 177 objetos en ambos lados, sin nombres faltantes ni extras al excluir `_cf_KV` y `gudex_schema_migrations`. Esto no compara definición de columnas, tipos efectivos, defaults, nulabilidad, restricciones/acciones FK ni el resultado de las transformaciones históricas.
- **Alembic:** el repositorio tiene 35 revisiones, con único head `20261026_0035`. Se identificaron actualizaciones de datos en `0020` (traspaso de ítems de cotización) y `0032` (relleno de número de motor), además de cambios de esquema posteriores. El esquema creado desde metadata no demuestra por sí solo que esas transformaciones se ejecutaron ni que el historial D1 pueda reconstruirse reproduciblemente.
- **Etapa 2 — revisión de seguridad iniciada, bloqueada para puesta en servicio:** la API local implementa Argon2id (parámetros de 64 MiB, 3 iteraciones, paralelismo 4) y JWT HS256 de 8 horas, pero el Worker remoto solo tiene `/health`. Cloudflare documenta 10 ms de CPU por invocación en Free; Workers Paid ofrece 30 s por defecto, configurable hasta 5 min, y tiene mínimo de US$5/mes más consumos que excedan las cuotas. La cuenta Free rechazó la configuración CPU que requiere el Worker; no se redujeron los parámetros de hashing ni se habilitó facturación.
- **Hallazgos de paridad pendientes:** el Worker local no implementa el límite de intentos de login que tiene FastAPI (20 por minuto); su CORS está fijado a `gudexapp-staging.pages.dev` y falta parametrizarlo antes de `admin.gudex.cl`. Se añadió límite de 200 caracteres para claves nuevas (paridad con el contrato del origen) y respuesta 503 si falta `JWT_SECRET` o tiene menos de 32 caracteres. Aún se debe revisar expiración/revocación, permisos por propiedad, flujos de recuperación, formato OAuth2 y respuestas de error.

Referencias oficiales consultadas: [límites de CPU de Workers](https://developers.cloudflare.com/workers/platform/limits/) y [planes/precios de Workers](https://developers.cloudflare.com/workers/platform/pricing/).

**Estado de salida:** las etapas 0–2 están comenzadas y hay entregables de descubrimiento, pero ninguna se declara completada. No se modificó DNS ni producción y no se desplegó el Worker funcional.

## Reglas que se mantienen durante el proyecto

1. Trabajar primero en recursos `*-staging`; producción y DNS permanecen intactos hasta la etapa de corte.
2. No transferir contraseñas existentes, hashes, tokens de sesión/recuperación ni secretos OAuth/Fernet. Las cuentas históricas se reactivan después de emitir claves nuevas.
3. No hacer doble escritura a las bases de Railway y D1 sin un mecanismo de reconciliación probado.
4. Mantener respaldos recuperables del origen y de D1; registrar recuentos, sumas de negocio y checksums de adjuntos.
5. El plan no autoriza cambiar nameservers ni DNS. Esas acciones se hacen en la ventana de corte luego de verificar todos los registros y preparar rollback.

## Etapas de desarrollo

### Etapa 0 — Inventario funcional y contratos

**Trabajo**

- Generar un inventario de las 235 operaciones FastAPI: método, URL, modelo, rol, validaciones, efectos laterales, archivos y módulos Flutter que las consumen.
- Actualizar el reporte base con `python cloudflare/scripts/generate_api_inventory.py` y completar las verificaciones funcionales indicadas al final del documento.
- Clasificar rutas por dominio y frecuencia de uso; identificar operaciones sin pantalla activa, callbacks externos y tareas programadas.
- Definir contratos JSON, códigos de error, formato de fechas/moneda, paginación e idempotencia compartidos entre FastAPI y Workers.
- Confirmar qué funciones y flujos deben conservarse y cuáles pueden retirarse, en especial Baileys.

**Salida:** inventario revisado, mapa ruta→pantalla y una lista priorizada de aceptación por rol. No se cambia producción.

### Etapa 1 — Base de datos D1 y disciplina de migraciones

**Trabajo**

- Comparar de forma sistemática el SQL generado con las 35 revisiones Alembic y una instancia de origen: constraints, índices, defaults, cascadas, tipos, claves únicas y secuencias.
- Tratar `0001_initial_schema.sql` como esquema inicial, no como prueba de que todas las diferencias históricas estén resueltas. Convertir cambios futuros en migraciones D1 numeradas e idempotentes; probar migración desde una D1 vacía y desde la versión anterior.
- Revisar límites SQLite/D1 frente a operaciones que dependen de bloqueos, transacciones largas o concurrencia. Ajustar transacciones de venta, compra, stock y caja para ejecutarse de forma atómica.
- Preparar importadores reproducibles por dominio con modo de validación, conteos antes/después, retención de IDs y repetición segura.
- Crear respaldo y procedimiento de restauración de D1 staging y documentar cuotas/retención.

**Salida:** esquema validado contra producción, migraciones aplicables desde cero y documentación de restauración probada.

### Etapa 2 — Identidad, seguridad y administración

**Trabajo**

- Desplegar autenticación y autorización por rol (admin, mecánico, cliente), gestión de usuarios, expiración/revocación de JWT y recuperación de clave.
- Resolver con mediciones el bloqueo de CPU del verificador Argon2id en Workers Free. No bajar parámetros de seguridad para superar el límite: elegir un plan/límite compatible o diseñar un esquema moderno de clave nueva con transición y rehash seguro.
- Probar el inicio de sesión de la cuenta admin en staging, permisos administrativos, bloqueo de cuentas históricas, renovación de token y restablecimiento de claves.
- Guardar `JWT_SECRET` y otras llaves solo en secretos de Worker; validar CORS y límites de intentos.

**Salida:** pruebas de rol y sesión aprobadas; administrador puede acceder al staging; cuentas históricas no pueden autenticarse hasta tener clave emitida.

### Etapa 3 — API y UI de clientes, vehículos y taller

**Trabajo**

- Implementar operaciones de clientes/vehículos, ficha técnica, tarjetas de aceite, mantenciones, agenda/citas y portal de cliente.
- Implementar órdenes, servicios asociados, recepción, inspecciones, diagnósticos, asignaciones, sesiones de trabajo, control de calidad, cotizaciones y escáner.
- Conservar IDs y relaciones importadas; hacer paginación y consultas de historial sin leer tablas completas.
- Conectar pantallas Flutter existentes a la URL API de staging; eliminar valores de API hardcodeados donde impidan cambiar entre preview/staging/producción.

**Salida:** cada flujo de taller de uso diario se completa en staging y las relaciones históricas se muestran correctamente.

### Etapa 4 — Catálogo, inventario, compras, ventas y caja

**Trabajo**

- Migrar catálogo de servicios/productos y movimientos de stock; importar y conciliar inventario inicial.
- Migrar proveedores, compras, recepción y aprobación; bloquear aplicación cuando una línea no esté vinculada al catálogo.
- Migrar POS, ventas, descuentos, pagos, libro de caja, transferencias y cierres; proteger consistencia entre venta/pago/stock/caja.
- Añadir claves de idempotencia para webhooks y reintentos de pagos; comprobar que reintentar no duplique cargos o movimientos.

**Salida:** cantidades y saldos de stock/caja/ventas concilian con origen en datos de control y escenarios repetidos.

### Etapa 5 — Archivos privados en R2

**Trabajo**

- Habilitar R2 y crear buckets separados para staging y producción.
- Inventariar documentos e imágenes del volumen Railway; generar manifiesto con ruta lógica, tamaño, tipo, hash y entidad asociada.
- Copiar objetos, validar checksums, y actualizar metadatos en D1 sin romper IDs ni enlaces.
- Implementar carga/descarga con autorización en Worker y URLs firmadas de vida corta cuando corresponda; no hacer buckets públicos.
- Probar PDF de scanner, inspecciones, compras, imágenes de vehículos/tarjetas y exportaciones.

**Salida:** todos los adjuntos necesarios abren con los roles correctos y sus checksums coinciden; existe respaldo de objetos.

### Etapa 6 — Integraciones y servicios auxiliares

**Trabajo**

- Migrar integraciones necesarias: Google Calendar/Drive/Gmail, Meta, Mercado Pago, correo, OpenAI/IA y webhooks. Rotar y guardar secretos en Cloudflare; reautorizar OAuth y actualizar callback URLs.
- Confirmar decisión sobre Baileys. Si se conserva, migrar como servicio independiente compatible con persistencia duradera y establecer recuperación de sesión; si se elimina, retirar sus flujos y dependencias de forma deliberada.
- Migrar cron, tareas diferidas, notificaciones y telemetría; definir reintentos, DLQ/alertas donde aplique.

**Salida:** cada integración necesaria supera un ciclo completo en sandbox y sus callbacks externos apuntan a staging.

### Etapa 7 — Dominio, frontend público y dominios de la app

**Diseño de hostnames**

| Hostname | Destino |
|---|---|
| `gudex.cl` | Proyecto Cloudflare Pages del sitio corporativo (repo del sitio Gudex, por confirmar/conectar). |
| `www.gudex.cl` | Redirección HTTPS al dominio raíz `gudex.cl`, si se decide usar la forma canónica sin `www`. |
| `admin.gudex.cl` | Proyecto Pages de producción para GudexApp (separado de `gudexapp-staging`). |
| `api.gudex.cl` | Custom Domain del Worker de producción una vez que todas las rutas requeridas estén migradas. |
| `gudexapp-staging.pages.dev` | Entorno de prueba; no se usa para producción. |

**Trabajo**

- Crear/conectar el proyecto Pages del sitio corporativo y verificar contenido, formularios, SEO, analítica y versión móvil.
- Crear un proyecto Pages de producción para Flutter Web con rama `main`, API de producción y bindings/secrets correctos; mantener staging independiente.
- Incorporar `admin.gudex.cl` al proyecto Pages productivo y `api.gudex.cl` al Worker productivo desde la configuración de Cloudflare, de modo que Cloudflare cree los registros y certificados asociados.
- Antes de cambiar nameservers, agregar la zona raíz `gudex.cl`, copiar/revisar los DNS existentes (MX, SPF, DKIM, DMARC, verificaciones y servicios), resolver DNSSEC y validar la lista de registros. Cloudflare debe entregar los nameservers asignados a esta zona; esos valores exactos se configuran en el registrador. No apuntar el apex a una IP genérica ni inventar un A record para Pages.
- Cambiar nameservers solo durante el corte aprobado, luego confirmar resolución, TLS y correo.

**Salida:** sitio público, app administrativa y API responden por sus hostnames HTTPS correctos; correo y subdominios previos continúan operativos.

### Etapa 8 — Validación integral y ensayo de corte

**Trabajo**

- Ejecutar recorridos E2E por rol: admin, mecánico y cliente, tanto en escritorio como en móvil/PWA.
- Validar flujos completos: ingreso→orden→diagnóstico→cotización→aprobación→servicio→control→entrega; recepción de compra→vinculación→aprobación→stock; venta→pago→movimiento de caja→cierre.
- Revisar controles de acceso por tenant/cliente, privacidad de adjuntos, inyección SQL, CORS/CSRF, rate limits y secretos en logs.
- Ensayar carga y latencia, errores D1, reintentos, webhooks duplicados, restauración D1/R2 y rollback a Railway/Vercel.
- Conciliar recuentos, IDs, cantidades de inventario, saldos y documentos con un respaldo reciente de origen.

**Salida:** lista de aceptación firmada, sin defectos bloqueantes, rollback ensayado y ventana de corte aprobada.

### Etapa 9 — Corte productivo y observación

**Trabajo**

- Crear/configurar recursos productivos independientes (D1, Worker, R2, Pages y secretos); no reutilizar los de staging.
- Programar ventana, pausar escrituras del origen, crear respaldo final y cargar delta final. Conciliar datos y verificar accesos administrativos.
- Cambiar `API_URL` productiva y DNS/hostnames acordados; comprobar certificados, PWA, callbacks, pagos y correo desde redes externas.
- Observar logs, latencia, errores, uso de CPU/D1/R2 y flujos de caja/inventario; mantener Railway/Vercel disponibles para rollback durante el periodo acordado.

**Salida:** operación estable por el periodo acordado, datos sin divergencia y responsable de negocio acepta el resultado.

### Etapa 10 — Retiro y cierre

- Crear respaldo final de Railway/PostgreSQL y adjuntos, almacenarlo y probar su restauración.
- Confirmar que ningún DNS, webhook, OAuth, app móvil, PWA, usuario interno o proceso programado sigue llamando Railway/Vercel.
- Retirar servicios, dominios, volúmenes y variables del proveedor anterior solo después del periodo estable y aprobación de negocio.
- Actualizar manuales, arquitectura, respuesta a incidentes, rotación de secretos y responsable operativo.

**Salida:** servicios de aplicación, persistencia, archivos, publicación y DNS de producción ya no dependen de Railway ni Vercel; existe evidencia de recuperación y operación.

## Riesgos y decisiones que afectan calendario

- El bloqueo de CPU de Argon2 debe resolverse antes de habilitar inicio de sesión en Workers; no se debe debilitar el hasher para cumplir un plazo.
- La zona `gudex.cl` no aparece en la cuenta Cloudflare consultada. Se desconoce si el sitio/correo actual usa DNS records que deban conservarse; hay que inventariarlos antes de mover nameservers.
- R2 aún no estaba habilitado y los adjuntos no están dentro de los respaldos recibidos.
- Aproximadamente 230 rutas, 35 revisiones Alembic y muchos módulos externos impiden fijar una fecha fiable sin terminar Etapa 0 y medir el trabajo por dominio.
- El plan mantiene Railway/Vercel como producción hasta superar Etapa 8; Pages staging y D1 staging no constituyen por sí solos un reemplazo funcional.

## Criterio de “migración al 100%”

La migración se considera completa cuando cada flujo productivo que se decidió conservar está desplegado y operando en Cloudflare; los datos, relaciones y adjuntos se concilian; la seguridad por rol y las integraciones están verificadas; `gudex.cl`, `admin.gudex.cl` y `api.gudex.cl` resuelven al destino previsto; recuperación y rollback se han ensayado; y ya no existe tráfico operativo que dependa de Railway o Vercel.
