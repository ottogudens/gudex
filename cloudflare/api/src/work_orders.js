const STATUSES = new Set([
  "received", "inspecting", "quoted", "awaiting_approval", "quote_rejected",
  "approved", "in_progress", "ready", "delivered", "cancelled",
]);
const TRANSITIONS = {
  received: new Set(["inspecting", "cancelled"]),
  inspecting: new Set(["quoted", "awaiting_approval", "approved", "in_progress", "cancelled"]),
  quoted: new Set(["awaiting_approval", "approved", "quote_rejected", "cancelled"]),
  awaiting_approval: new Set(["approved", "quote_rejected", "cancelled"]),
  quote_rejected: new Set(["inspecting", "quoted", "cancelled"]),
  approved: new Set(["in_progress", "cancelled"]),
  in_progress: new Set(["ready", "cancelled"]),
  ready: new Set(["in_progress", "delivered", "cancelled"]),
  delivered: new Set(),
  cancelled: new Set(),
};
const SERVICE_KINDS = new Map([
  ["inspection", "Inspección"], ["scanner", "Diagnóstico con scanner"],
  ["preventive", "Mantención preventiva"], ["corrective", "Reparación correctiva"],
  ["pre_purchase", "Inspección precompra"],
  ["pre_technical_review", "Inspección prerevisión técnica"], ["other", "Otro servicio"],
]);
const INSPECTION_KINDS = new Set(["inspection", "scanner", "pre_purchase", "pre_technical_review"]);
const SERVICE_TRANSITIONS = {
  pending: new Set(["in_progress", "cancelled"]),
  in_progress: new Set(["blocked", "completed", "cancelled"]),
  blocked: new Set(["in_progress", "cancelled"]),
  completed: new Set(), cancelled: new Set(),
};
const ORDER_FIELDS = [
  "id", "code", "customer_id", "vehicle_id", "status", "opened_at", "promised_at",
  "mileage_km", "reported_symptoms", "initial_notes", "diagnosis", "technician_name", "total_clp",
];
const ORDER_UPDATES = new Set([
  "status", "promised_at", "diagnosis", "technician_name", "total_clp", "mileage_km",
  "reported_symptoms", "initial_notes",
]);
const SERVICE_FIELDS = [
  "id", "work_order_id", "catalog_service_id", "kind", "name", "description", "status",
  "assigned_user_id", "findings", "created_at", "started_at", "completed_at",
];

const json = (data, status = 200) => new Response(JSON.stringify(data), {
  status,
  headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" },
});
const detail = (message, status) => json({ detail: message }, status);
const int = (value, label, min = 0, max = Number.MAX_SAFE_INTEGER) => {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) throw Error(`${label} inválido`);
  return parsed;
};
const text = (value, label, max, min = 0) => {
  if (typeof value !== "string" || value.trim().length < min || value.length > max) throw Error(`${label} inválido`);
  return value.trim();
};
function nullableText(data, key, label, max) {
  if (!(key in data)) return undefined;
  if (data[key] == null || data[key] === "") return null;
  return text(data[key], label, max);
}
function dateValue(value, label) {
  if (value == null || value === "") return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) throw Error(`${label} inválida`);
  return date.toISOString();
}
function objectBody(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw Error("Cuerpo JSON inválido");
  return value;
}
async function rowById(db, table, id) {
  return db.prepare(`SELECT * FROM ${table} WHERE id=?`).bind(id).first();
}
async function normalizeServices(db, services) {
  if (!Array.isArray(services) || services.length > 50) throw Error("La orden admite hasta 50 trabajos");
  const normalized = [];
  for (const input of services) {
    const service = objectBody(input);
    if (!SERVICE_KINDS.has(service.kind)) throw Error("Tipo de servicio no reconocido");
    const name = text(service.name, "Nombre del trabajo", 160, 2);
    const description = service.description == null ? "" : text(service.description, "Descripción", 2000);
    const catalogId = service.catalog_service_id == null ? null : int(service.catalog_service_id, "Servicio de catálogo", 1);
    const assignedId = service.assigned_user_id == null ? null : int(service.assigned_user_id, "Mecánico", 1);
    if (catalogId && !(await rowById(db, "service", catalogId))) throw Error("Servicio de catálogo no encontrado");
    if (assignedId) {
      const assignee = await db.prepare("SELECT id FROM user WHERE id=? AND role='mechanic' AND active=1").bind(assignedId).first();
      if (!assignee) throw Error("Selecciona un mecánico activo");
    }
    normalized.push({ catalogId, kind: service.kind, name, description, assignedId });
  }
  return normalized;
}
function serviceStatements(db, orderId, services) {
  return services.map(service => db.prepare("INSERT INTO workorderservice(work_order_id,catalog_service_id,kind,name,description,status,assigned_user_id,findings,created_at,started_at,completed_at) VALUES(?,?,?,?,?,'pending',?,'',?,NULL,NULL)")
    .bind(orderId, service.catalogId, service.kind, service.name, service.description, service.assignedId, new Date().toISOString()));
}

async function createOrder(request, env, user) {
  if (user.role !== "admin") return detail("Se requiere el rol de administrador", 403);
  let data;
  try { data = objectBody(await request.json()); }
  catch (error) { return detail(error.message || "Cuerpo JSON inválido", 422); }
  try {
    const customerId = int(data.customer_id, "Cliente", 1), vehicleId = int(data.vehicle_id, "Vehículo", 1);
    const customer = await env.DB.prepare("SELECT id,archived_at FROM customer WHERE id=?").bind(customerId).first();
    const vehicle = await env.DB.prepare("SELECT id,customer_id,current_mileage_km FROM vehicle WHERE id=?").bind(vehicleId).first();
    if (!customer || !vehicle) return detail("Cliente o vehículo no encontrado", 404);
    if (customer.archived_at) return detail("No se pueden crear órdenes para un cliente archivado", 409);
    if (vehicle.customer_id !== customerId) return detail("El vehículo no pertenece al cliente indicado", 409);
    const mileage = data.mileage_km == null ? null : int(data.mileage_km, "Kilometraje");
    const promisedAt = dateValue(data.promised_at, "Fecha prometida");
    const symptoms = nullableText(data, "reported_symptoms", "Síntomas", 4000) ?? null;
    const notes = nullableText(data, "initial_notes", "Notas iniciales", 4000) ?? null;
    const technician = nullableText(data, "technician_name", "Técnico", 120) ?? null;
    const serviceData = await normalizeServices(env.DB, data.services ?? []);
    const openedAt = new Date().toISOString();
    const code = `OT-${openedAt.slice(2, 10).replaceAll("-", "")}-${crypto.randomUUID().replaceAll("-", "").slice(0, 6).toUpperCase()}`;
    const statements = [env.DB.prepare("INSERT INTO workorder(code,customer_id,vehicle_id,status,opened_at,promised_at,mileage_km,reported_symptoms,initial_notes,diagnosis,technician_name,total_clp) VALUES(?,?,?,'received',?,?,?,?,?,NULL,?,0)")
      .bind(code, customerId, vehicleId, openedAt, promisedAt, mileage, symptoms, notes, technician)];
    const result = await env.DB.batch(statements);
    const orderId = result[0]?.meta?.last_row_id;
    const services = serviceStatements(env.DB, orderId, serviceData);
    if (services.length) await env.DB.batch(services);
    return json(await env.DB.prepare(`SELECT ${ORDER_FIELDS.join(",")} FROM workorder WHERE id=?`).bind(orderId).first(), 201);
  } catch (error) {
    if (/UNIQUE constraint failed/.test(String(error))) return detail("Ya existe un registro con esos datos", 409);
    return detail(error.message || "Datos inválidos", 422);
  }
}

async function listOrders(url, env) {
  const status = url.searchParams.get("status");
  let vehicleId = url.searchParams.get("vehicle_id");
  if (status && !STATUSES.has(status)) return detail("Estado de orden inválido", 422);
  let limit, offset;
  try {
    limit = Math.min(int(url.searchParams.get("limit") || 100, "Límite", 1, 500), 500);
    offset = int(url.searchParams.get("offset") || 0, "Desplazamiento");
    if (vehicleId != null && vehicleId !== "") vehicleId = int(vehicleId, "Vehículo", 1);
    else vehicleId = null;
  } catch (error) { return detail(error.message, 422); }
  const rows = await env.DB.prepare(`SELECT ${ORDER_FIELDS.join(",")} FROM workorder WHERE (? IS NULL OR status=?) AND (? IS NULL OR vehicle_id=?) ORDER BY opened_at DESC LIMIT ? OFFSET ?`)
    .bind(status, status, vehicleId, vehicleId, limit, offset).all();
  return json(rows.results);
}

async function updateOrder(request, env, user, id) {
  let data;
  try { data = objectBody(await request.json()); }
  catch (error) { return detail(error.message || "Cuerpo JSON inválido", 422); }
  const keys = Object.keys(data);
  if (keys.some(key => !ORDER_UPDATES.has(key))) return detail("La orden contiene campos no editables", 422);
  if (user.role === "mechanic" && keys.some(key => !["status", "diagnosis", "mileage_km"].includes(key))) return detail("El mecánico solo puede registrar diagnóstico, kilometraje y avance de su orden", 403);
  try {
    const order = await env.DB.prepare(`SELECT ${ORDER_FIELDS.join(",")} FROM workorder WHERE id=?`).bind(id).first();
    if (!order) return detail("Orden de trabajo no encontrada", 404);
    const updates = {};
    if ("status" in data) {
      if (!STATUSES.has(data.status)) return detail("Estado de orden inválido", 422);
      if (data.status !== order.status && !TRANSITIONS[order.status]?.has(data.status)) return detail(`No se puede cambiar una orden de ${order.status} a ${data.status}`, 409);
      if (user.role === "mechanic" && !["inspecting", "in_progress", "ready"].includes(data.status)) return detail("El mecánico no puede cerrar, cancelar ni modificar etapas comerciales de una orden", 403);
      if (["ready", "delivered"].includes(data.status)) {
        const unfinished = await env.DB.prepare("SELECT id FROM workorderservice WHERE work_order_id=? AND status NOT IN ('completed','cancelled') LIMIT 1").bind(id).first();
        if (unfinished) return detail("Completa o cancela los servicios pendientes antes de cerrar la orden", 409);
      }
      if (data.status === "delivered") {
        const quality = await env.DB.prepare("SELECT id FROM workorderqualitycheck WHERE work_order_id=? AND result='passed' LIMIT 1").bind(id).first();
        if (!quality) return detail("Aprueba el control de calidad antes de marcar la orden como entregada", 409);
      }
      updates.status = data.status;
    }
    for (const [key, max] of [["diagnosis", 4000], ["technician_name", 120], ["reported_symptoms", 4000], ["initial_notes", 4000]]) {
      const value = nullableText(data, key, key, max);
      if (value !== undefined) updates[key] = value;
    }
    if ("promised_at" in data) updates.promised_at = dateValue(data.promised_at, "Fecha prometida");
    if ("mileage_km" in data) updates.mileage_km = data.mileage_km == null ? null : int(data.mileage_km, "Kilometraje");
    if ("total_clp" in data) updates.total_clp = int(data.total_clp, "Total", 0, 2_000_000_000);
    if (!Object.keys(updates).length) return json(order);
    const fields = Object.keys(updates);
    await env.DB.prepare(`UPDATE workorder SET ${fields.map(key => `${key}=?`).join(",")} WHERE id=?`).bind(...fields.map(key => updates[key]), id).run();
    return json(await env.DB.prepare(`SELECT ${ORDER_FIELDS.join(",")} FROM workorder WHERE id=?`).bind(id).first());
  } catch (error) { return detail(error.message || "Datos inválidos", 422); }
}

async function deleteOrder(env, user, orderId) {
  if (user.role !== "admin") return detail("Se requiere el rol de administrador", 403);
  const order = await rowById(env.DB, "workorder", orderId);
  if (!order) return detail("Orden de trabajo no encontrada", 404);
  const historyTables = ["maintenanceexecution", "inspection", "quote", "scannerreport", "sale", "worksession", "workorderreception", "workorderevidence", "installedpart"];
  for (const table of historyTables) {
    if (await env.DB.prepare(`SELECT id FROM ${table} WHERE work_order_id=? LIMIT 1`).bind(orderId).first()) {
      await env.DB.prepare("UPDATE workorder SET status='cancelled' WHERE id=?").bind(orderId).run();
      return json({ deleted: false, cancelled: true, message: "La orden tiene historial y fue cancelada para conservar trazabilidad" });
    }
  }
  const changedService = await env.DB.prepare("SELECT id FROM workorderservice WHERE work_order_id=? AND (status<>'pending' OR findings<>'' OR started_at IS NOT NULL OR completed_at IS NOT NULL) LIMIT 1").bind(orderId).first();
  if (changedService) {
    await env.DB.prepare("UPDATE workorder SET status='cancelled' WHERE id=?").bind(orderId).run();
    return json({ deleted: false, cancelled: true, message: "La orden tiene historial y fue cancelada para conservar trazabilidad" });
  }
  await env.DB.batch([
    env.DB.prepare("DELETE FROM workorderassignment WHERE work_order_id=?").bind(orderId),
    env.DB.prepare("DELETE FROM workorderservice WHERE work_order_id=?").bind(orderId),
    env.DB.prepare("DELETE FROM workorder WHERE id=?").bind(orderId),
  ]);
  return json({ deleted: true, cancelled: false });
}

async function listMechanics(env, user) {
  if (user.role !== "admin") return detail("Se requiere el rol de administrador", 403);
  const { results } = await env.DB.prepare("SELECT id,full_name,email FROM user WHERE role='mechanic' AND active=1 ORDER BY full_name").all();
  return json(results);
}

async function assignOrder(request, env, user, orderId) {
  if (user.role !== "admin") return detail("Se requiere el rol de administrador", 403);
  const order = await rowById(env.DB, "workorder", orderId);
  if (!order) return detail("Orden de trabajo no encontrada", 404);
  let data;
  try { data = objectBody(await request.json()); }
  catch (error) { return detail(error.message || "Cuerpo JSON inválido", 422); }
  if (!("technician_user_id" in data)) return detail("Debes indicar el mecánico asignado o null para quitarlo", 422);
  if (data.technician_user_id == null) {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM workorderassignment WHERE work_order_id=?").bind(orderId),
      env.DB.prepare("UPDATE workorder SET technician_name=NULL WHERE id=?").bind(orderId),
    ]);
  } else {
    let mechanic;
    try { mechanic = await env.DB.prepare("SELECT id,full_name FROM user WHERE id=? AND role='mechanic' AND active=1").bind(int(data.technician_user_id, "Mecánico", 1)).first(); }
    catch (error) { return detail(error.message, 422); }
    if (!mechanic) return detail("Selecciona un mecánico activo", 422);
    const existing = await env.DB.prepare("SELECT id FROM workorderassignment WHERE work_order_id=?").bind(orderId).first();
    const now = new Date().toISOString();
    const statement = existing
      ? env.DB.prepare("UPDATE workorderassignment SET technician_user_id=?,assigned_by_email=?,assigned_at=? WHERE work_order_id=?").bind(mechanic.id, user.email, now, orderId)
      : env.DB.prepare("INSERT INTO workorderassignment(work_order_id,technician_user_id,assigned_by_email,assigned_at) VALUES(?,?,?,?)").bind(orderId, mechanic.id, user.email, now);
    await env.DB.batch([statement, env.DB.prepare("UPDATE workorder SET technician_name=? WHERE id=?").bind(mechanic.full_name, orderId)]);
  }
  return json(await env.DB.prepare(`SELECT ${ORDER_FIELDS.join(",")} FROM workorder WHERE id=?`).bind(orderId).first());
}

async function orderServices(request, env, user, orderId, serviceId) {
  const order = await rowById(env.DB, "workorder", orderId);
  if (!order) return detail("Orden de trabajo no encontrada", 404);
  if (!serviceId && request.method === "GET") {
    const rows = await env.DB.prepare(`SELECT ${SERVICE_FIELDS.join(",")} FROM workorderservice WHERE work_order_id=? ORDER BY id`).bind(orderId).all();
    return json(rows.results.map(row => ({ ...row, can_edit: user.role === "admin" })));
  }
  if (!serviceId && request.method === "POST") {
    if (user.role !== "admin") return detail("Se requiere el rol de administrador", 403);
    if (["delivered", "cancelled"].includes(order.status)) return detail("No se pueden agregar servicios a una orden cerrada", 409);
    try {
      const services = await normalizeServices(env.DB, [await request.json()]);
      const statements = serviceStatements(env.DB, orderId, services);
      const results = await env.DB.batch(statements), id = results[0]?.meta?.last_row_id;
      return json(await env.DB.prepare(`SELECT ${SERVICE_FIELDS.join(",")} FROM workorderservice WHERE id=?`).bind(id).first(), 201);
    } catch (error) { return detail(error.message || "Datos inválidos", 422); }
  }
  if (serviceId && request.method === "PATCH") {
    let data;
    try { data = objectBody(await request.json()); }
    catch (error) { return detail(error.message || "Cuerpo JSON inválido", 422); }
    const row = await env.DB.prepare(`SELECT ${SERVICE_FIELDS.join(",")} FROM workorderservice WHERE id=? AND work_order_id=?`).bind(serviceId, orderId).first();
    if (!row) return detail("Servicio no encontrado en esta orden", 404);
    if (user.role !== "admin") return detail("La edición de trabajos requiere asignación de mecánico", 403);
    if (["delivered", "cancelled"].includes(order.status)) return detail("La orden ya está cerrada", 409);
    const updates = {};
    if ("assigned_user_id" in data) {
      if (data.assigned_user_id == null) updates.assigned_user_id = null;
      else {
        const assignedId = int(data.assigned_user_id, "Mecánico", 1);
        if (!(await env.DB.prepare("SELECT id FROM user WHERE id=? AND role='mechanic' AND active=1").bind(assignedId).first())) return detail("Selecciona un mecánico activo", 422);
        updates.assigned_user_id = assignedId;
      }
    }
    if (data.status != null && data.status !== row.status) {
      if (!SERVICE_TRANSITIONS[row.status]?.has(data.status)) return detail("Transición de servicio no permitida", 409);
      if (["in_progress", "completed"].includes(data.status) && !INSPECTION_KINDS.has(row.kind) && !["approved", "in_progress", "ready"].includes(order.status)) return detail("El trabajo requiere aprobación comercial previa", 409);
      if (data.status === "completed") {
        const active = await env.DB.prepare("SELECT id FROM worksession WHERE work_order_service_id=? AND ended_at IS NULL LIMIT 1").bind(serviceId).first();
        if (active) return detail("Detén el registro de tiempo antes de completar el servicio", 409);
      }
      updates.status = data.status;
      if (data.status === "in_progress" && !row.started_at) updates.started_at = new Date().toISOString();
      if (data.status === "completed") updates.completed_at = new Date().toISOString();
    } else if (data.status != null && !SERVICE_TRANSITIONS[data.status]) return detail("Estado de servicio inválido", 422);
    if ("findings" in data) {
      if (data.findings != null && (typeof data.findings !== "string" || data.findings.length > 4000)) return detail("Hallazgos inválidos", 422);
      updates.findings = data.findings ?? "";
    }
    const fields = Object.keys(updates);
    if (!fields.length) return json({ ...row, can_edit: true });
    await env.DB.prepare(`UPDATE workorderservice SET ${fields.map(key => `${key}=?`).join(",")} WHERE id=? AND work_order_id=?`).bind(...fields.map(key => updates[key]), serviceId, orderId).run();
    return json(await env.DB.prepare(`SELECT ${SERVICE_FIELDS.join(",")} FROM workorderservice WHERE id=?`).bind(serviceId).first());
  }
  return null;
}

export async function handleWorkOrders(request, env, user) {
  const url = new URL(request.url), path = url.pathname, method = request.method;
  if (path === "/api/v1/work-order-service-kinds" && method === "GET") return json([...SERVICE_KINDS].map(([key, name]) => ({ key, name })));
  if (path === "/api/v1/team/mechanics" && method === "GET") return listMechanics(env, user);
  if (path === "/api/v1/work-orders" && method === "GET") return listOrders(url, env);
  if (path === "/api/v1/work-orders" && method === "POST") return createOrder(request, env, user);
  const match = path.match(/^\/api\/v1\/work-orders\/(\d+)(?:\/(services(?:\/(\d+))?|assignment))?$/);
  if (!match) return null;
  const orderId = Number(match[1]);
  if (match[2]?.startsWith("services")) return orderServices(request, env, user, orderId, match[3] ? Number(match[3]) : null);
  if (match[2] === "assignment" && method === "PUT") return assignOrder(request, env, user, orderId);
  if (method === "GET") {
    const row = await env.DB.prepare(`SELECT ${ORDER_FIELDS.join(",")} FROM workorder WHERE id=?`).bind(orderId).first();
    return row ? json(row) : detail("Orden de trabajo no encontrada", 404);
  }
  if (method === "PATCH") return updateOrder(request, env, user, orderId);
  if (method === "DELETE") return deleteOrder(env, user, orderId);
  return null;
}
