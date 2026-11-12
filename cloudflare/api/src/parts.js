const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" } });
const error = (detail, status) => json({ detail }, status);
const IDENTITY_KEYS = ["version", "engine_code", "displacement", "fuel", "transmission", "drive", "market"];
const PART_FIELDS = ["id", "work_order_id", "work_order_service_id", "vehicle_id", "product_id", "supplied_by", "name", "category", "brand", "part_number", "oem_number", "specifications", "quantity", "status", "fitment_status", "verification_source", "vehicle_identity_signature", "evidence_id", "notes", "recorded_by_email", "recorded_at", "installed_at"];
const INSPECTION_KINDS = new Set(["inspection", "scanner", "pre_purchase", "pre_technical_review"]);
function body(value) { if (!value || typeof value !== "object" || Array.isArray(value)) throw Error("Cuerpo JSON inválido"); return value; }
function integer(value, label) { const n = Number(value); if (!Number.isSafeInteger(n) || n < 1) throw Error(`${label} inválido`); return n; }
function string(value, label, max, required = false) { if (value == null && !required) return ""; if (typeof value !== "string" || value.trim().length > max || (required && value.trim().length < 2)) throw Error(`${label} inválido`); return value.trim(); }
function pyJsonString(value) { return JSON.stringify(value).replace(/[\u007f-\uffff]/g, c => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`); }
function pyJsonObject(value) { return `{${Object.keys(value).sort().map(key => `${pyJsonString(key)}: ${value[key] === null ? "null" : typeof value[key] === "string" ? pyJsonString(value[key]) : JSON.stringify(value[key])}`).join(", ")}}`; }
async function identitySignature(db, vehicleId) {
  const vehicle = await db.prepare("SELECT plate,make,model,year,engine,engine_number,engine_code,displacement_cc,vin,notes FROM vehicle WHERE id=?").bind(vehicleId).first();
  if (!vehicle) return "";
  const identity = { ...vehicle };
  const { results } = await db.prepare("SELECT key,value FROM vehicletechnicalentry WHERE vehicle_id=? ORDER BY id DESC").bind(vehicleId).all();
  const seen = new Set();
  for (const row of results) if (IDENTITY_KEYS.includes(row.key) && !seen.has(row.key)) { identity[row.key] = row.value; seen.add(row.key); }
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(pyJsonObject(identity)));
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("");
}
function payload(row, signature = null) { return { ...row, photo_url: null, needs_review: signature != null && row.fitment_status === "verified" && row.vehicle_identity_signature !== signature }; }
async function partList(db, rows) {
  const signatures = new Map();
  const result = [];
  for (const row of rows) {
    if (!signatures.has(row.vehicle_id)) signatures.set(row.vehicle_id, await identitySignature(db, row.vehicle_id));
    result.push(payload(row, signatures.get(row.vehicle_id)));
  }
  return result;
}
async function vehicleParts(db, vehicleId) {
  const { results } = await db.prepare("SELECT * FROM installedpart WHERE vehicle_id=? ORDER BY recorded_at DESC,id DESC").bind(vehicleId).all();
  const signature = await identitySignature(db, vehicleId), history = results.map(row => payload(row, signature));
  const references = [], seen = new Set();
  for (const row of results) {
    const key = `${String(row.category || "").toLowerCase()}\u0000${String(row.oem_number || row.part_number || "").toUpperCase()}`;
    if (row.status === "installed" && row.fitment_status === "verified" && row.vehicle_identity_signature === signature && key.split("\u0000")[1] && !seen.has(key)) { seen.add(key); references.push(payload(row, signature)); }
  }
  return { installed_parts: history, verified_part_references: references };
}
async function getOrder(db, id) { return db.prepare("SELECT id,vehicle_id,status FROM workorder WHERE id=?").bind(id).first(); }
async function listOrderParts(db, id) {
  if (!await getOrder(db, id)) return error("Orden de trabajo no encontrada", 404);
  const { results } = await db.prepare("SELECT * FROM installedpart WHERE work_order_id=? ORDER BY id").bind(id).all();
  return json(await partList(db, results));
}
async function addPart(request, db, user, orderId) {
  let data;
  try {
    data = body(await request.json());
    data.work_order_service_id = integer(data.work_order_service_id, "Trabajo");
    data.name = string(data.name, "Nombre", 160, true);
    data.supplied_by = data.supplied_by;
    if (!["customer", "workshop"].includes(data.supplied_by)) throw Error("Origen del repuesto inválido");
    for (const [key, label, max] of [["category", "Categoría", 80], ["brand", "Marca", 80], ["part_number", "Número de parte", 100], ["oem_number", "Número OEM", 100], ["specifications", "Especificaciones", 2000], ["notes", "Notas", 2000]]) data[key] = string(data[key] ?? "", label, max);
    data.quantity = Number(data.quantity ?? 1);
    if (!Number.isFinite(data.quantity) || data.quantity <= 0 || data.quantity > 1_000_000) throw Error("Cantidad inválida");
    if (data.product_id != null) data.product_id = integer(data.product_id, "Producto");
    if (data.evidence_id != null) data.evidence_id = integer(data.evidence_id, "Evidencia");
  } catch (e) { return error(e.message, 422); }
  const order = await getOrder(db, orderId);
  if (!order) return error("Orden de trabajo no encontrada", 404);
  if (["delivered", "cancelled"].includes(order.status)) return error("La orden ya está cerrada", 409);
  const service = await db.prepare("SELECT id,kind FROM workorderservice WHERE id=? AND work_order_id=?").bind(data.work_order_service_id, orderId).first();
  if (!service) return error("Servicio no encontrado en esta orden", 404);
  if (data.product_id != null && !await db.prepare("SELECT id FROM product WHERE id=?").bind(data.product_id).first()) return error("Producto del catálogo no encontrado", 422);
  if (data.evidence_id != null) {
    const evidence = await db.prepare("SELECT id,content_type FROM workorderevidence WHERE id=? AND work_order_id=?").bind(data.evidence_id, orderId).first();
    if (!evidence || !String(evidence.content_type).startsWith("image/")) return error("Selecciona una imagen de esta orden", 422);
  }
  const now = new Date().toISOString(), cols = ["work_order_id", "work_order_service_id", "vehicle_id", "product_id", "supplied_by", "name", "category", "brand", "part_number", "oem_number", "specifications", "quantity", "status", "fitment_status", "verification_source", "vehicle_identity_signature", "evidence_id", "notes", "recorded_by_email", "recorded_at", "installed_at"];
  const vals = [orderId, data.work_order_service_id, order.vehicle_id, data.product_id ?? null, data.supplied_by, data.name, data.category, data.brand, data.part_number, data.oem_number, data.specifications, data.quantity, "received", "pending", "", "", data.evidence_id ?? null, data.notes, user.email, now, null];
  try {
    const result = await db.prepare(`INSERT INTO installedpart(${cols.join(",")}) VALUES(${cols.map(() => "?").join(",")})`).bind(...vals).run();
    return json(payload(await db.prepare(`SELECT ${PART_FIELDS.join(",")} FROM installedpart WHERE id=?`).bind(result.meta.last_row_id).first()), 201);
  } catch { return error("No se pudo registrar el repuesto", 500); }
}
async function updatePart(request, db, orderId, partId) {
  const row = await db.prepare("SELECT * FROM installedpart WHERE id=? AND work_order_id=?").bind(partId, orderId).first();
  if (!row) return error("Repuesto no encontrado en esta orden", 404);
  const order = await getOrder(db, orderId);
  if (!order) return error("Orden de trabajo no encontrada", 404);
  if (["delivered", "cancelled"].includes(order.status)) return error("La orden ya está cerrada", 409);
  let data, updates = {};
  try {
    data = body(await request.json());
    const allowed = new Set(["status", "fitment_status", "verification_source", "evidence_id", "notes"]);
    if (Object.keys(data).some(key => !allowed.has(key))) throw Error("El repuesto contiene campos no editables");
    if (data.status != null) {
      if (!["received", "installed", "not_installed"].includes(data.status)) throw Error("Estado de repuesto inválido");
      if (data.status === "installed" && row.status !== "installed") {
        const service = await db.prepare("SELECT kind FROM workorderservice WHERE id=? AND work_order_id=?").bind(row.work_order_service_id, orderId).first();
        if (!service) return error("Servicio no encontrado en esta orden", 404);
        if (!INSPECTION_KINDS.has(service.kind) && !["approved", "in_progress", "ready"].includes(order.status)) return error("La instalación requiere aprobación previa", 409);
        updates.installed_at = new Date().toISOString();
      }
      updates.status = data.status;
    }
    if (data.fitment_status != null) {
      if (!["pending", "verified", "rejected"].includes(data.fitment_status)) throw Error("Verificación de compatibilidad inválida");
      const source = string(data.verification_source ?? row.verification_source, "Fuente técnica", 250);
      if (data.fitment_status === "verified" && !source) throw Error("Indica la fuente técnica de verificación");
      updates.fitment_status = data.fitment_status;
      updates.vehicle_identity_signature = data.fitment_status === "verified" ? await identitySignature(db, row.vehicle_id) : "";
    }
    if (data.verification_source != null) updates.verification_source = string(data.verification_source, "Fuente técnica", 250);
    if (data.evidence_id != null) {
      const evidenceId = integer(data.evidence_id, "Evidencia"), evidence = await db.prepare("SELECT id,content_type FROM workorderevidence WHERE id=? AND work_order_id=?").bind(evidenceId, orderId).first();
      if (!evidence || !String(evidence.content_type).startsWith("image/")) throw Error("Selecciona una imagen de esta orden");
      updates.evidence_id = evidenceId;
    }
    if (data.notes != null) updates.notes = string(data.notes, "Notas", 2000);
  } catch (e) { return error(e.message, 422); }
  const keys = Object.keys(updates);
  if (!keys.length) return json(payload(row, await identitySignature(db, row.vehicle_id)));
  try {
    await db.prepare(`UPDATE installedpart SET ${keys.map(key => `${key}=?`).join(",")} WHERE id=? AND work_order_id=?`).bind(...keys.map(key => updates[key]), partId, orderId).run();
    const updated = await db.prepare(`SELECT ${PART_FIELDS.join(",")} FROM installedpart WHERE id=?`).bind(partId).first();
    return json(payload(updated, await identitySignature(db, row.vehicle_id)));
  } catch { return error("No se pudo actualizar el repuesto", 500); }
}
async function usage(db, url) {
  const raw = Number(url.searchParams.get("days") || 180);
  if (!Number.isInteger(raw) || raw < 1 || raw > 1095) return error("El período debe estar entre 1 y 1095 días", 422);
  const cutoff = new Date(Date.now() - raw * 86400000).toISOString();
  const { results } = await db.prepare("SELECT category,name,brand,part_number,oem_number,quantity,supplied_by,fitment_status,vehicle_id FROM installedpart WHERE status='installed' AND installed_at>=?").bind(cutoff).all();
  const groups = new Map();
  for (const row of results) {
    const key = JSON.stringify([row.category, row.name, row.brand, row.part_number, row.oem_number]);
    const item = groups.get(key) || { category: row.category, name: row.name, brand: row.brand, part_number: row.part_number, oem_number: row.oem_number, total: 0, customer_supplied: 0, workshop_supplied: 0, verified: 0, vehicles: new Set() };
    item.total += Number(row.quantity);
    item[row.supplied_by === "customer" ? "customer_supplied" : "workshop_supplied"] += Number(row.quantity);
    if (row.fitment_status === "verified") item.verified += Number(row.quantity);
    item.vehicles.add(row.vehicle_id); groups.set(key, item);
  }
  return json([...groups.values()].map(({ vehicles, ...row }) => ({ ...row, vehicle_count: vehicles.size })).sort((a, b) => b.total - a.total));
}
export async function handleParts(request, env, user) {
  const url = new URL(request.url), path = url.pathname, method = request.method, db = env.DB;
  if (path === "/api/v1/parts/usage" && method === "GET") return user?.role === "admin" ? usage(db, url) : error("Se requiere el rol de administrador", 403);
  if (path === "/api/v1/parts/usage") return null;
  let match = path.match(/^\/api\/v1\/work-orders\/(\d+)\/parts(?:\/(\d+))?$/);
  if (match) {
    const orderId = Number(match[1]), partId = match[2] ? Number(match[2]) : null;
    if (!partId && method === "GET") return listOrderParts(db, orderId);
    if (!partId && method === "POST") return addPart(request, db, user, orderId);
    if (partId && method === "PATCH") return updatePart(request, db, orderId, partId);
    return null;
  }
  return null;
}
export { identitySignature, vehicleParts };
