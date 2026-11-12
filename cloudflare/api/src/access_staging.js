const WEB_ORIGIN = "https://gudexapp-staging.pages.dev";
import { publicOilCard } from "./public_oil_card.js";
import { handleWorkOrders } from "./work_orders.js";
import { handleCatalog } from "./catalog.js";
import { handleInventoryCounts } from "./inventory_counts.js";
import { handleParts, vehicleParts } from "./parts.js";
import { handleDashboard } from "./dashboard.js";
const encoder = new TextEncoder();
const jwksPromises = new Map();

function json(data, status = 200, origin = null) {
  const headers = { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" };
  if (origin === WEB_ORIGIN) headers["Access-Control-Allow-Origin"] = WEB_ORIGIN;
  return new Response(JSON.stringify(data), { status, headers });
}
function decodeBase64Url(value) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  return Uint8Array.from(atob(normalized), c => c.charCodeAt(0));
}
async function keys(team) {
  if (!jwksPromises.has(team)) jwksPromises.set(team, fetch(`${team}/cdn-cgi/access/certs`, { cf: { cacheTtl: 300, cacheEverything: true } }).then(async r => {
    if (!r.ok) throw Error("Access key service unavailable");
    return (await r.json()).keys;
  }).catch(error => { jwksPromises.delete(team); throw error; }));
  return jwksPromises.get(team);
}
async function authorizedUser(request, env) {
  const token = request.headers.get("Cf-Access-Jwt-Assertion");
  if (!token) return null;
  try {
    const team = String(env.ACCESS_TEAM_DOMAIN || "").replace(/\/$/, "");
    const audiences = new Set(String(env.ACCESS_AUDS || "").split(",").map(value => value.trim()).filter(Boolean));
    if (!team || !audiences.size || !env.ACCESS_EMAIL || !env.ACCESS_ADMIN_EMAIL) return null;
    const [encodedHeader, encodedPayload, encodedSignature] = token.split(".");
    if (!encodedHeader || !encodedPayload || !encodedSignature) return null;
    const header = JSON.parse(new TextDecoder().decode(decodeBase64Url(encodedHeader)));
    const claims = JSON.parse(new TextDecoder().decode(decodeBase64Url(encodedPayload)));
    if (header.alg !== "RS256" || claims.iss !== team || claims.email?.toLowerCase() !== String(env.ACCESS_EMAIL).toLowerCase()) return null;
    if (!(Array.isArray(claims.aud) ? claims.aud : [claims.aud]).some(aud => audiences.has(aud))) return null;
    const now = Math.floor(Date.now() / 1000);
    if (!claims.exp || claims.exp <= now || (claims.nbf && claims.nbf > now)) return null;
    const jwk = (await keys(team)).find(key => key.kid === header.kid && key.kty === "RSA");
    if (!jwk) return null;
    const publicKey = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
    const valid = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", publicKey, decodeBase64Url(encodedSignature), encoder.encode(`${encodedHeader}.${encodedPayload}`));
    if (!valid) return null;
    return await env.DB.prepare("SELECT id,email,full_name,role,customer_id,active,created_at FROM user WHERE email=? AND role='admin' AND active=1").bind(String(env.ACCESS_ADMIN_EMAIL).toLowerCase()).first();
  } catch {
    return null;
  }
}
function validateCustomer(data, partial = false) {
  if (!data || typeof data !== "object" || Array.isArray(data)) throw Error("Cuerpo JSON inválido");
  const out = {};
  if (!partial || "full_name" in data) {
    out.full_name = String(data.full_name || "").trim().replace(/\s+/g, " ");
    if (out.full_name.length < 2 || out.full_name.length > 120) throw Error("Ingresa el nombre del cliente");
  }
  if (!partial || "rut" in data) {
    const raw = data.rut == null ? "" : String(data.rut).replace(/[^0-9kK]/g, "").toUpperCase();
    if (!raw) out.rut = null;
    else {
      if (raw.length < 2 || raw.length > 9 || !/^\d+$/.test(raw.slice(0, -1))) throw Error("RUT chileno inválido");
      let sum = 0, factor = 2;
      for (const digit of [...raw.slice(0, -1)].reverse()) { sum += Number(digit) * factor; factor = factor === 7 ? 2 : factor + 1; }
      const n = 11 - sum % 11, expected = n === 11 ? "0" : n === 10 ? "K" : String(n);
      if (raw.at(-1) !== expected) throw Error("Dígito verificador del RUT inválido");
      out.rut = `${Number(raw.slice(0, -1))}-${expected}`;
    }
  }
  if (!partial || "email" in data) { const email = typeof data.email === "string" ? data.email.trim().toLowerCase() : ""; if (email.length > 254) throw Error("Correo inválido"); out.email = email || null; }
  for (const key of ["phone", "notes"]) if (!partial || key in data) out[key] = data[key] == null || data[key] === "" ? null : String(data[key]);
  return out;
}
function validateVehicle(data, partial = false) {
  if (!data || typeof data !== "object" || Array.isArray(data)) throw Error("Cuerpo JSON inválido");
  const out = {};
  for (const key of ["customer_id", "year", "displacement_cc", "current_mileage_km"]) {
    if (!partial || key in data) {
      const value = data[key];
      if (value == null || value === "") out[key] = key === "customer_id" ? null : null;
      else {
        const parsed = Number(value);
        if (!Number.isInteger(parsed)) throw Error("Revisa el cliente, año, cilindrada y kilometraje");
        out[key] = parsed;
      }
    }
  }
  if (!partial || "plate" in data) {
    out.plate = String(data.plate || "").replace(/[^A-Za-z0-9]/g, "").toUpperCase();
    if (out.plate.length < 4 || out.plate.length > 8 || !/[A-Z]/.test(out.plate) || !/[0-9]/.test(out.plate)) throw Error("Patente inválida");
  }
  if (!partial || "vin" in data) {
    const vin = data.vin == null ? "" : String(data.vin).replace(/[\s-]/g, "").toUpperCase();
    if (vin && !/^[A-HJ-NPR-Z0-9]{17}$/.test(vin)) throw Error("El VIN debe tener 17 caracteres y no puede contener I, O o Q");
    out.vin = vin || null;
  }
  for (const key of ["make", "model"]) if (!partial || key in data) {
    out[key] = String(data[key] || "").trim();
    if (out[key].length < 1 || out[key].length > 60) throw Error("Ingresa marca y modelo del vehículo");
  }
  for (const key of ["engine", "engine_number", "engine_code", "notes"]) if (!partial || key in data) out[key] = data[key] == null || data[key] === "" ? null : String(data[key]).trim();
  if (!partial || "public_service_card_enabled" in data) out.public_service_card_enabled = data.public_service_card_enabled === true || data.public_service_card_enabled === 1;
  const year = out.year;
  if (year != null && (year < 1886 || year > new Date().getUTCFullYear() + 1)) throw Error("Año del vehículo fuera de rango");
  if (out.displacement_cc != null && (out.displacement_cc < 0 || out.displacement_cc > 20000)) throw Error("Cilindrada fuera de rango");
  if (out.current_mileage_km != null && out.current_mileage_km < 0) throw Error("El kilometraje no puede ser negativo");
  if (!out.engine_number && out.engine) out.engine_number = out.engine;
  return out;
}
async function vehicleHistory(env, vehicle) {
  const db = env.DB, vehicleId = vehicle.id;
  const all = async sql => (await db.prepare(sql).bind(vehicleId).all()).results;
  const customer = await db.prepare("SELECT id,full_name,rut,email,phone,notes,created_at,archived_at FROM customer WHERE id=?").bind(vehicle.customer_id).first();
  const plans = await all("SELECT * FROM maintenanceplan WHERE vehicle_id=? ORDER BY active DESC,name");
  const executions = await all("SELECT * FROM maintenanceexecution WHERE vehicle_id=? ORDER BY performed_at DESC,id DESC");
  const orders = await all("SELECT * FROM workorder WHERE vehicle_id=? ORDER BY opened_at DESC");
  const orderIds = orders.map(row => row.id).filter(Number.isInteger);
  let services = [], quotes = [];
  if (orderIds.length) {
    const marks = orderIds.map(() => "?").join(",");
    services = (await db.prepare(`SELECT * FROM workorderservice WHERE work_order_id IN (${marks}) ORDER BY created_at DESC`).bind(...orderIds).all()).results;
  }
  const technicalRows = await all("SELECT id,key,value,source,status,revision,changed_by,created_at FROM vehicletechnicalentry WHERE vehicle_id=? ORDER BY id DESC");
  const values = {}, fieldMap = new Map();
  for (const row of technicalRows) {
    if (values[row.key]) continue;
    values[row.key] = { ...row, needs_review: false };
    const group = row.key.startsWith("filter_") ? "filters" : /^(engine|transmission|differential|transfer|brake|steering|coolant)_/.test(row.key) ? "fluids" : "information";
    fieldMap.set(row.key, { group, key: row.key, label: row.key.replaceAll("_", " ") });
  }
  const fields = [...fieldMap.values()];
  let oilCard = await db.prepare("SELECT * FROM oilservicecard WHERE vehicle_id=?").bind(vehicleId).first();
  if (oilCard) {
    delete oilCard.oil_image_path; delete oilCard.oil_image_content_type;
    delete oilCard.filter_image_path; delete oilCard.filter_image_content_type; delete oilCard.updated_by;
    oilCard.oil_image_url = null; oilCard.filter_image_url = null;
  } else {
    const oilExecution = executions.find(row => plans.some(plan => plan.id === row.plan_id && plan.category === "oil"));
    oilCard = oilExecution ? { id: null, vehicle_id: vehicleId, source_execution_id: oilExecution.id, service_name: oilExecution.plan_name, performed_at: oilExecution.performed_at, mileage_km: oilExecution.mileage_km, next_due_km: oilExecution.next_due_km, next_due_at: oilExecution.next_due_at, oil_used: oilExecution.oil_used, filters_used: oilExecution.filters_used, customer_note: "", oil_image_url: null, filter_image_url: null } : null;
  }
  const { installed_parts, verified_part_references } = await vehicleParts(db, vehicleId);
  const appointments = await all("SELECT id,customer_id,vehicle_id,bay_id,technician_user_id,starts_at,ends_at,service_type,notes,status,sync_status,created_at FROM appointment WHERE vehicle_id=? ORDER BY starts_at DESC");
  quotes = await all("SELECT * FROM quote WHERE vehicle_id=? ORDER BY counted_at DESC");
  const diagnostics = await all("SELECT * FROM diagnosticfinding WHERE vehicle_id=? ORDER BY created_at DESC");
  const reports = (await db.prepare("SELECT id,vehicle_id,work_order_id,work_order_service_id,filename,source,scanned_at,mileage_km,summary FROM scannerreport WHERE vehicle_id=? ORDER BY scanned_at DESC").bind(vehicleId).all()).results;
  return { vehicle, technical: { fields, values }, maintenance_plans: plans, maintenance_executions: executions, oil_card: oilCard, installed_parts, verified_part_references, customer, work_orders: orders, work_order_services: services, diagnostic_findings: diagnostics, quotes, appointments, scanner_reports: reports.map(row => ({ ...row, download_url: null })) };
}
async function completeMaintenance(env, planId, data, actor) {
  const plan = await env.DB.prepare("SELECT * FROM maintenanceplan WHERE id=?").bind(planId).first();
  if (!plan) return { error: { status: 404, detail: "Plan de mantención no encontrado" } };
  if (typeof data.request_key !== "string" || data.request_key.length < 8 || data.request_key.length > 80) return { error: { status: 422, detail: "Identificador de solicitud inválido" } };
  const mileage = Number(data.mileage_km);
  if (!Number.isInteger(mileage) || mileage < 0) return { error: { status: 422, detail: "Registra un kilometraje válido para completar la mantención" } };
  const textLimits = { materials: 4000, oil_used: 1000, filters_used: 2000, notes: 4000 };
  for (const [key, max] of Object.entries(textLimits)) if (data[key] != null && (typeof data[key] !== "string" || data[key].length > max)) return { error: { status: 422, detail: "Los detalles de la mantención superan el largo permitido" } };
  const text = Object.fromEntries(Object.keys(textLimits).map(key => [key, data[key] || ""]));
  const existing = await env.DB.prepare("SELECT * FROM maintenanceexecution WHERE plan_id=? AND request_key=?").bind(planId, data.request_key).first();
  if (existing) {
    if (["mileage_km", "work_order_id", ...Object.keys(textLimits)].some(key => (existing[key] ?? null) !== (key === "work_order_id" ? (data[key] ?? null) : key === "mileage_km" ? mileage : text[key]))) return { error: { status: 409, detail: "La solicitud ya fue utilizada con otros datos" } };
    return { execution: existing, existing: true };
  }
  if (!plan.active) return { error: { status: 409, detail: "El plan está archivado" } };
  const vehicle = await env.DB.prepare("SELECT * FROM vehicle WHERE id=?").bind(plan.vehicle_id).first();
  if (!vehicle) return { error: { status: 404, detail: "Vehículo no encontrado" } };
  if (mileage < Math.max(vehicle.current_mileage_km || 0, plan.last_service_km || 0)) return { error: { status: 409, detail: "El kilometraje no puede ser menor al último registrado" } };
  let workOrderId = data.work_order_id == null ? null : Number(data.work_order_id);
  if (workOrderId != null) {
    if (!Number.isInteger(workOrderId)) return { error: { status: 422, detail: "Orden de trabajo inválida" } };
    const order = await env.DB.prepare("SELECT vehicle_id,status FROM workorder WHERE id=?").bind(workOrderId).first();
    if (!order || order.vehicle_id !== vehicle.id || !["in_progress", "ready", "delivered"].includes(order.status)) return { error: { status: 409, detail: "Selecciona una orden del vehículo en trabajo, lista o entregada" } };
  }
  const now = new Date(), nextKm = data.next_due_km == null ? (plan.interval_km ? mileage + plan.interval_km : null) : Number(data.next_due_km);
  const nextAt = data.next_due_at == null ? (plan.interval_days ? new Date(now.getTime() + plan.interval_days * 86400000).toISOString() : null) : new Date(data.next_due_at).toISOString();
  if (nextKm != null && (!Number.isInteger(nextKm) || nextKm <= mileage)) return { error: { status: 422, detail: "La próxima mantención debe tener mayor kilometraje" } };
  if (data.next_due_at != null && (!Number.isFinite(Date.parse(data.next_due_at)) || Date.parse(nextAt) <= now.getTime())) return { error: { status: 422, detail: "La próxima mantención debe tener una fecha futura" } };
  if (nextKm == null && nextAt == null) return { error: { status: 422, detail: "Registra kilometraje o fecha de próxima mantención" } };
  const performedAt = now.toISOString(), executionColumns = ["plan_id", "vehicle_id", "work_order_id", "request_key", "plan_name", "mileage_km", "interval_km", "interval_days", "next_due_km", "next_due_at", "materials", "oil_used", "filters_used", "notes", "recorded_by", "performed_at"];
  const executionValues = [plan.id, vehicle.id, workOrderId, data.request_key, plan.name, mileage, plan.interval_km, plan.interval_days, nextKm, nextAt, text.materials, text.oil_used, text.filters_used, text.notes, actor, performedAt];
  const batch = [
    env.DB.prepare(`INSERT INTO maintenanceexecution(${executionColumns.join(",")}) VALUES(${executionColumns.map(() => "?").join(",")})`).bind(...executionValues),
    env.DB.prepare("UPDATE maintenanceplan SET last_service_km=?,last_service_at=? WHERE id=?").bind(mileage, performedAt, plan.id),
    env.DB.prepare("UPDATE vehicle SET current_mileage_km=? WHERE id=?").bind(mileage, vehicle.id),
  ];
  if (plan.category === "oil") batch.push(env.DB.prepare("INSERT INTO oilservicecard(vehicle_id,source_execution_id,service_name,performed_at,mileage_km,next_due_km,next_due_at,oil_used,filters_used,customer_note,oil_image_path,oil_image_content_type,filter_image_path,filter_image_content_type,updated_by,updated_at) VALUES(?,(SELECT id FROM maintenanceexecution WHERE plan_id=? AND request_key=?),?,?,?,?,?,?,?, '',NULL,NULL,NULL,NULL,?,?) ON CONFLICT(vehicle_id) DO UPDATE SET source_execution_id=excluded.source_execution_id,service_name=excluded.service_name,performed_at=excluded.performed_at,mileage_km=excluded.mileage_km,next_due_km=excluded.next_due_km,next_due_at=excluded.next_due_at,oil_used=excluded.oil_used,filters_used=excluded.filters_used,customer_note='',oil_image_path=NULL,oil_image_content_type=NULL,filter_image_path=NULL,filter_image_content_type=NULL,updated_by=excluded.updated_by,updated_at=excluded.updated_at").bind(vehicle.id, plan.id, data.request_key, plan.name, performedAt, mileage, nextKm, nextAt, text.oil_used, text.filters_used, actor, performedAt));
  try {
    const results = await env.DB.batch(batch), executionId = results[0]?.meta?.last_row_id;
    return { execution: await env.DB.prepare("SELECT * FROM maintenanceexecution WHERE id=?").bind(executionId).first(), existing: false };
  } catch (error) {
    if (/UNIQUE constraint failed/.test(String(error))) {
      const raced = await env.DB.prepare("SELECT * FROM maintenanceexecution WHERE plan_id=? AND request_key=?").bind(planId, data.request_key).first();
      if (raced) return { execution: raced, existing: true };
    }
    throw error;
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url), path = url.pathname, method = request.method, origin = request.headers.get("Origin");
    if (method === "OPTIONS") return new Response(null, { status: 204, headers: { "Access-Control-Allow-Origin": WEB_ORIGIN, "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS", "Access-Control-Allow-Headers": "Authorization, Content-Type", "Access-Control-Max-Age": "600", "Vary": "Origin" } });
    if (method === "GET" && path === "/health") {
      try { await env.DB.prepare("SELECT 1").first(); return json({ status: "ok", database: "ok" }, 200, origin); }
      catch { return json({ status: "unavailable", database: "error" }, 503, origin); }
    }
    if (method === "GET" && path === "/tarjeta-aceite") return publicOilCard(request, env);
    const user = await authorizedUser(request, env);
    if (!user) return json({ detail: "Inicia sesión con Cloudflare Access para continuar" }, 401, origin);
    if (method === "POST" && path === "/auth/access") return json({ access_token: "cloudflare-access", token_type: "bearer", role: user.role, full_name: user.full_name, expires_in: 28800 }, 200, origin);
    try {
      const dashboardResponse = await handleDashboard(request, env, user);
      if (dashboardResponse) return dashboardResponse;
      const inventoryResponse = await handleInventoryCounts(request, env, user);
      if (inventoryResponse) return inventoryResponse;
      const partsResponse = await handleParts(request, env, user);
      if (partsResponse) return partsResponse;
      const catalogResponse = await handleCatalog(request, env, user);
      if (catalogResponse) return catalogResponse;
      const workOrdersResponse = await handleWorkOrders(request, env, user);
      if (workOrdersResponse) return workOrdersResponse;
      const fields = "id,full_name,rut,email,phone,notes,created_at,archived_at";
      if (method === "GET" && path === "/api/v1/customers") {
        const limit = Math.min(Math.max(Number(url.searchParams.get("limit") || 100), 1), 500);
        const offset = Math.max(Number(url.searchParams.get("offset") || 0), 0);
        const q = url.searchParams.get("q"), include = url.searchParams.get("include_archived") === "true";
        const { results } = await env.DB.prepare(`SELECT ${fields} FROM customer WHERE (?=1 OR archived_at IS NULL) AND (? IS NULL OR full_name LIKE '%'||?||'%') ORDER BY full_name LIMIT ? OFFSET ?`).bind(include ? 1 : 0, q, q, limit, offset).all();
        return json(results, 200, origin);
      }
      if (method === "GET" && path === "/api/v1/vehicles") {
        const limit = Math.min(Math.max(Number(url.searchParams.get("limit") || 100), 1), 500), offset = Math.max(Number(url.searchParams.get("offset") || 0), 0);
        const customerId = Number(url.searchParams.get("customer_id") || 0), plate = url.searchParams.get("plate");
        const { results } = await env.DB.prepare("SELECT * FROM vehicle WHERE (?=0 OR customer_id=?) AND (? IS NULL OR plate LIKE '%'||?||'%') ORDER BY plate LIMIT ? OFFSET ?").bind(customerId, customerId, plate, plate ? plate.toUpperCase() : null, limit, offset).all();
        return json(results, 200, origin);
      }
      if (method === "POST" && path === "/api/v1/vehicles") {
        const data = validateVehicle(await request.json());
        if (!data.customer_id) return json({ detail: "Cliente no encontrado" }, 404, origin);
        const customer = await env.DB.prepare("SELECT id,archived_at FROM customer WHERE id=?").bind(data.customer_id).first();
        if (!customer) return json({ detail: "Cliente no encontrado" }, 404, origin);
        if (customer.archived_at) return json({ detail: "No se pueden registrar vehículos para un cliente archivado" }, 409, origin);
        if (await env.DB.prepare("SELECT id FROM vehicle WHERE plate=?").bind(data.plate).first()) return json({ detail: "Ya existe un vehículo con esa patente" }, 409, origin);
        if (data.vin && await env.DB.prepare("SELECT id FROM vehicle WHERE vin=?").bind(data.vin).first()) return json({ detail: "Ya existe un vehículo con ese VIN" }, 409, origin);
        const columns = ["customer_id", "plate", "vin", "make", "model", "year", "engine", "engine_number", "engine_code", "displacement_cc", "current_mileage_km", "notes", "public_service_card_enabled"];
        const values = columns.map(column => data[column] ?? (column === "public_service_card_enabled" ? 0 : null));
        const result = await env.DB.prepare(`INSERT INTO vehicle(${columns.join(",")}) VALUES(${columns.map(() => "?").join(",")})`).bind(...values).run();
        return json(await env.DB.prepare("SELECT * FROM vehicle WHERE id=?").bind(result.meta.last_row_id).first(), 201, origin);
      }
      const vehicleMatch = path.match(/^\/api\/v1\/vehicles\/(\d+)(?:\/(history))?$/);
      if (vehicleMatch && method === "GET" && vehicleMatch[2] === "history") {
        const vehicle = await env.DB.prepare("SELECT * FROM vehicle WHERE id=?").bind(Number(vehicleMatch[1])).first();
        if (!vehicle) return json({ detail: "Vehículo no encontrado" }, 404, origin);
        return json(await vehicleHistory(env, vehicle), 200, origin);
      }
      if (vehicleMatch && method === "PATCH" && !vehicleMatch[2]) {
        const id = Number(vehicleMatch[1]), old = await env.DB.prepare("SELECT * FROM vehicle WHERE id=?").bind(Number(vehicleMatch[1])).first();
        if (!old) return json({ detail: "Vehículo no encontrado" }, 404, origin);
        const data = validateVehicle(await request.json(), true), next = { ...old, ...data };
        if (!next.customer_id || !next.make || !next.model) return json({ detail: "Revisa patente, VIN, año, kilometraje y datos obligatorios del vehículo" }, 422, origin);
        if ("customer_id" in data) {
          const customer = await env.DB.prepare("SELECT id FROM customer WHERE id=?").bind(data.customer_id).first();
          if (!customer) return json({ detail: "Cliente no encontrado" }, 422, origin);
        }
        for (const field of ["plate", "vin"]) if (data[field] && await env.DB.prepare(`SELECT id FROM vehicle WHERE ${field}=? AND id<>?`).bind(data[field], id).first()) return json({ detail: `Ya existe un vehículo con ese ${field}` }, 409, origin);
        const columns = ["customer_id", "plate", "vin", "make", "model", "year", "engine", "engine_number", "engine_code", "displacement_cc", "current_mileage_km", "notes", "public_service_card_enabled"];
        await env.DB.prepare(`UPDATE vehicle SET ${columns.map(column => `${column}=?`).join(",")} WHERE id=?`).bind(...columns.map(column => next[column] ?? (column === "public_service_card_enabled" ? 0 : null)), id).run();
        return json(await env.DB.prepare("SELECT * FROM vehicle WHERE id=?").bind(id).first(), 200, origin);
      }
      if (vehicleMatch && method === "DELETE" && !vehicleMatch[2]) {
        const id = Number(vehicleMatch[1]), vehicle = await env.DB.prepare("SELECT id FROM vehicle WHERE id=?").bind(Number(vehicleMatch[1])).first();
        if (!vehicle) return json({ detail: "Vehículo no encontrado" }, 404, origin);
        for (const [table, label] of [["vehicletechnicalentry", "ficha técnica"], ["maintenanceplan", "historial de mantención"], ["workorder", "historial de trabajo"], ["quote", "historial de trabajo"], ["scannerreport", "historial de scanner"], ["appointment", "citas"]]) {
          if (await env.DB.prepare(`SELECT id FROM ${table} WHERE vehicle_id=? LIMIT 1`).bind(id).first()) return json({ detail: `No se puede eliminar un vehículo con ${label} registrada` }, 409, origin);
        }
        await env.DB.prepare("DELETE FROM vehicle WHERE id=?").bind(id).run();
        return json({ deleted: true }, 200, origin);
      }
      if (method === "GET" && path === "/api/v1/maintenance-plans") {
        const { results } = await env.DB.prepare("SELECT * FROM maintenanceplan ORDER BY active DESC,name").all();
        return json(results, 200, origin);
      }
      if (method === "POST" && path === "/api/v1/maintenance-plans") {
        const data = await request.json(), vehicleId = Number(data?.vehicle_id), name = String(data?.name || "").trim(), category = data?.category || "general";
        const intervalKm = data?.interval_km == null ? null : Number(data.interval_km), intervalDays = data?.interval_days == null ? null : Number(data.interval_days);
        if (!Number.isInteger(vehicleId) || !name || name.length < 2 || name.length > 120 || !["oil", "filters", "preventive", "general"].includes(category) || (intervalKm != null && (!Number.isInteger(intervalKm) || intervalKm < 1)) || (intervalDays != null && (!Number.isInteger(intervalDays) || intervalDays < 1)) || (!intervalKm && !intervalDays)) return json({ detail: "Define un nombre y un intervalo válido por kilometraje, tiempo o ambos" }, 422, origin);
        const vehicle = await env.DB.prepare("SELECT id,current_mileage_km FROM vehicle WHERE id=?").bind(vehicleId).first();
        if (!vehicle) return json({ detail: "Vehículo no encontrado" }, 404, origin);
        const lastKm = data.last_service_km == null ? vehicle.current_mileage_km : Number(data.last_service_km);
        if (lastKm != null && (!Number.isInteger(lastKm) || lastKm < 0)) return json({ detail: "Kilometraje de última mantención inválido" }, 422, origin);
        const now = new Date().toISOString(), result = await env.DB.prepare("INSERT INTO maintenanceplan(vehicle_id,name,category,interval_km,interval_days,last_service_km,last_service_at,active) VALUES(?,?,?,?,?,?,?,1)").bind(vehicleId, name, category, intervalKm, intervalDays, lastKm, now).run();
        return json(await env.DB.prepare("SELECT * FROM maintenanceplan WHERE id=?").bind(result.meta.last_row_id).first(), 201, origin);
      }
      if (method === "GET" && path === "/api/v1/maintenance-plans/due") {
        const plans = (await env.DB.prepare("SELECT * FROM maintenanceplan WHERE active=1 ORDER BY name").all()).results, now = Date.now(), due = [];
        for (const plan of plans) {
          const vehicle = await env.DB.prepare("SELECT * FROM vehicle WHERE id=?").bind(plan.vehicle_id).first();
          if (!vehicle) continue;
          const latest = await env.DB.prepare("SELECT next_due_km,next_due_at FROM maintenanceexecution WHERE plan_id=? ORDER BY performed_at DESC,id DESC LIMIT 1").bind(plan.id).first();
          const nextKm = latest?.next_due_km ?? (plan.last_service_km != null && plan.interval_km ? plan.last_service_km + plan.interval_km : null);
          const nextAt = latest?.next_due_at ?? (plan.interval_days ? new Date(Date.parse(plan.last_service_at) + plan.interval_days * 86400000).toISOString() : null);
          const dueByKm = nextKm != null && vehicle.current_mileage_km != null && vehicle.current_mileage_km >= nextKm;
          const dueByDate = nextAt != null && Number.isFinite(Date.parse(nextAt)) && now >= Date.parse(nextAt);
          if (dueByKm || dueByDate) {
            const customer = await env.DB.prepare("SELECT id,full_name,rut,email,phone,notes,created_at,archived_at FROM customer WHERE id=?").bind(vehicle.customer_id).first();
            due.push({ plan, vehicle, customer, due_by_km: Boolean(dueByKm), due_by_date: Boolean(dueByDate) });
          }
        }
        return json(due, 200, origin);
      }
      const planMatch = path.match(/^\/api\/v1\/maintenance-plans\/(\d+)(?:\/(executions|complete))?$/);
      if (planMatch && method === "PATCH" && !planMatch[2]) {
        const id = Number(planMatch[1]), old = await env.DB.prepare("SELECT * FROM maintenanceplan WHERE id=?").bind(id).first();
        if (!old) return json({ detail: "Plan de mantención no encontrado" }, 404, origin);
        const data = await request.json(), next = { ...old };
        for (const key of ["name", "category", "interval_km", "interval_days", "active"]) if (key in data) next[key] = data[key];
        if (typeof next.name !== "string" || next.name.trim().length < 2 || next.name.trim().length > 120 || !["oil", "filters", "preventive", "general"].includes(next.category) || (next.interval_km != null && (!Number.isInteger(Number(next.interval_km)) || Number(next.interval_km) < 1)) || (next.interval_days != null && (!Number.isInteger(Number(next.interval_days)) || Number(next.interval_days) < 1)) || (!next.interval_km && !next.interval_days)) return json({ detail: "Define un nombre y un intervalo válido por kilometraje, tiempo o ambos" }, 422, origin);
        await env.DB.prepare("UPDATE maintenanceplan SET name=?,category=?,interval_km=?,interval_days=?,active=? WHERE id=?").bind(next.name.trim(), next.category, next.interval_km == null ? null : Number(next.interval_km), next.interval_days == null ? null : Number(next.interval_days), next.active ? 1 : 0, id).run();
        return json(await env.DB.prepare("SELECT * FROM maintenanceplan WHERE id=?").bind(id).first(), 200, origin);
      }
      if (planMatch && method === "DELETE" && !planMatch[2]) {
        const id = Number(planMatch[1]), result = await env.DB.prepare("UPDATE maintenanceplan SET active=0 WHERE id=?").bind(id).run();
        if (!result.meta.changes) return json({ detail: "Plan de mantención no encontrado" }, 404, origin);
        return json({ archived: true }, 200, origin);
      }
      if (planMatch && method === "POST" && planMatch[2] === "executions") {
        const result = await completeMaintenance(env, Number(planMatch[1]), await request.json(), user.email);
        if (result.error) return json({ detail: result.error.detail }, result.error.status, origin);
        return json(result.execution, 200, origin);
      }
      if (planMatch && method === "POST" && planMatch[2] === "complete") {
        const mileageParam = url.searchParams.get("mileage_km"), vehiclePlan = await env.DB.prepare("SELECT v.current_mileage_km FROM maintenanceplan p JOIN vehicle v ON v.id=p.vehicle_id WHERE p.id=?").bind(Number(planMatch[1])).first();
        const mileage = mileageParam == null ? vehiclePlan?.current_mileage_km : Number(mileageParam);
        const result = await completeMaintenance(env, Number(planMatch[1]), { request_key: crypto.randomUUID(), mileage_km: mileage }, user.email);
        if (result.error) return json({ detail: result.error.detail }, result.error.status, origin);
        return json(await env.DB.prepare("SELECT * FROM maintenanceplan WHERE id=?").bind(Number(planMatch[1])).first(), 200, origin);
      }
      if (method === "POST" && path === "/api/v1/customers") {
        const data = validateCustomer(await request.json());
        for (const field of ["rut", "email"]) if (data[field] && await env.DB.prepare(`SELECT id FROM customer WHERE ${field}=?`).bind(data[field]).first()) return json({ detail: `Ya existe un cliente con ese ${field}` }, 409, origin);
        const result = await env.DB.prepare("INSERT INTO customer(full_name,rut,email,phone,notes,created_at,archived_at) VALUES(?,?,?,?,?,?,NULL)").bind(data.full_name, data.rut, data.email, data.phone, data.notes, new Date().toISOString()).run();
        return json(await env.DB.prepare(`SELECT ${fields} FROM customer WHERE id=?`).bind(result.meta.last_row_id).first(), 201, origin);
      }
      const match = path.match(/^\/api\/v1\/customers\/(\d+)$/);
      if (match && method === "PATCH") {
        const id = Number(match[1]), old = await env.DB.prepare("SELECT * FROM customer WHERE id=?").bind(id).first();
        if (!old) return json({ detail: "Cliente no encontrado" }, 404, origin);
        if (old.archived_at) return json({ detail: "El cliente está archivado y no puede modificarse" }, 409, origin);
        const data = validateCustomer(await request.json(), true), next = { ...old, ...data };
        for (const field of ["rut", "email"]) if (data[field] && await env.DB.prepare(`SELECT id FROM customer WHERE ${field}=? AND id<>?`).bind(data[field], id).first()) return json({ detail: `Ya existe un cliente con ese ${field}` }, 409, origin);
        await env.DB.prepare("UPDATE customer SET full_name=?,rut=?,email=?,phone=?,notes=? WHERE id=?").bind(next.full_name, next.rut, next.email, next.phone, next.notes, id).run();
        return json(await env.DB.prepare(`SELECT ${fields} FROM customer WHERE id=?`).bind(id).first(), 200, origin);
      }
      if (match && method === "DELETE") {
        const id = Number(match[1]), old = await env.DB.prepare("SELECT id,archived_at FROM customer WHERE id=?").bind(id).first();
        if (!old) return json({ detail: "Cliente no encontrado" }, 404, origin);
        if (old.archived_at) return json({ deleted: false, archived: true }, 200, origin);
        await env.DB.prepare("UPDATE customer SET archived_at=? WHERE id=?").bind(new Date().toISOString(), id).run();
        return json({ deleted: false, archived: true }, 200, origin);
      }
      return json({ detail: "No encontrado" }, 404, origin);
    } catch (error) {
      if (/UNIQUE constraint failed/.test(String(error))) return json({ detail: "Ya existe un registro con esos datos" }, 409, origin);
      if (error instanceof SyntaxError || error instanceof TypeError || error instanceof Error && !String(error).includes("D1")) return json({ detail: error.message }, 422, origin);
      return json({ detail: "Error interno" }, 500, origin);
    }
  },
};
