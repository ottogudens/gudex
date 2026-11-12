const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" } });
const error = (detail, status) => json({ detail }, status);
const RESULT_VALUES = new Set(["not_inspected", "normal", "observation", "failed", "not_applicable"]);
const INSPECTION_KINDS = new Set(["inspection", "scanner", "pre_purchase", "pre_technical_review"]);
const INSPECTION_FIELDS = ["id", "work_order_id", "work_order_service_id", "category", "item", "result", "notes", "measured_value", "created_at"];
const DIAGNOSTIC_FIELDS = ["id", "work_order_id", "work_order_service_id", "scanner_report_id", "vehicle_id", "module", "dtc_code", "symptom", "freeze_frame", "measurements", "test_performed", "test_result", "conclusion", "technician_confirmed_at", "recorded_by_email", "created_at", "updated_at"];
const QUALITY_FIELDS = ["id", "work_order_id", "fluids_checked", "leaks_checked", "fasteners_checked", "road_test_done", "technician_completed_at", "technician_notes", "reviewed_by_email", "reviewed_at", "result", "review_notes", "updated_at"];
function obj(value) { if (!value || typeof value !== "object" || Array.isArray(value)) throw Error("Cuerpo JSON inválido"); return value; }
function id(value, label) { const n = Number(value); if (!Number.isSafeInteger(n) || n < 1) throw Error(`${label} inválido`); return n; }
function text(value, label, max, nullable = false) { if (value == null && nullable) return null; if (typeof value !== "string" || value.length > max) throw Error(`${label} inválido`); return value.trim(); }
function bool(value, label) { if (typeof value !== "boolean") throw Error(`${label} inválido`); return value; }
async function editableOrder(db, orderId) { return db.prepare("SELECT id,vehicle_id FROM workorder WHERE id=?").bind(orderId).first(); }
async function getService(db, orderId, serviceId) { return db.prepare("SELECT id,kind FROM workorderservice WHERE id=? AND work_order_id=?").bind(serviceId, orderId).first(); }
async function listInspections(db, orderId) {
  if (!await editableOrder(db, orderId)) return error("Orden de trabajo no encontrada", 404);
  return json((await db.prepare(`SELECT ${INSPECTION_FIELDS.join(",")} FROM inspection WHERE work_order_id=? ORDER BY id`).bind(orderId).all()).results);
}
async function createInspection(request, db, user, orderId) {
  let data;
  try {
    data = obj(await request.json());
    const category = text(data.category, "Categoría", 80), item = text(data.item, "Elemento", 120);
    if (!category || !item) throw Error("Indica una categoría y un elemento");
    const result = typeof data.result === "string" ? data.result.trim().toLowerCase() : "";
    if (!RESULT_VALUES.has(result)) throw Error("Resultado de inspección no permitido");
    if (data.work_order_service_id != null) data.work_order_service_id = id(data.work_order_service_id, "Trabajo");
    data = { category, item, result, notes: text(data.notes ?? "", "Observaciones", 4000, true), measured_value: text(data.measured_value ?? "", "Medición", 80, true), work_order_service_id: data.work_order_service_id ?? null };
  } catch (e) { return error(e.message, 422); }
  const order = await editableOrder(db, orderId);
  if (!order) return error("Orden de trabajo no encontrada", 404);
  if (data.work_order_service_id != null && !await getService(db, orderId, data.work_order_service_id)) return error("Servicio no encontrado en esta orden", 404);
  try {
    const result = await db.prepare("INSERT INTO inspection(work_order_id,work_order_service_id,category,item,result,notes,measured_value,created_at) VALUES(?,?,?,?,?,?,?,?)").bind(orderId, data.work_order_service_id, data.category, data.item, data.result, data.notes, data.measured_value, new Date().toISOString()).run();
    return json(await db.prepare(`SELECT ${INSPECTION_FIELDS.join(",")} FROM inspection WHERE id=?`).bind(result.meta.last_row_id).first(), 201);
  } catch { return error("No se pudo guardar la inspección", 500); }
}
async function updateInspection(request, db, inspectionId) {
  const row = await db.prepare("SELECT * FROM inspection WHERE id=?").bind(inspectionId).first();
  if (!row) return error("Inspección no encontrada", 404);
  let data, changes = {};
  try {
    data = obj(await request.json());
    if ("result" in data) { const result = typeof data.result === "string" ? data.result.trim().toLowerCase() : ""; if (!RESULT_VALUES.has(result)) throw Error("Resultado de inspección no permitido"); changes.result = result; }
    if ("notes" in data) changes.notes = text(data.notes, "Observaciones", 4000, true);
    if ("measured_value" in data) changes.measured_value = text(data.measured_value, "Medición", 80, true);
  } catch (e) { return error(e.message, 422); }
  if (!Object.keys(changes).length) return json(row);
  const assignments = Object.keys(changes);
  try {
    await db.prepare(`UPDATE inspection SET ${assignments.map(key => `${key}=?`).join(",")} WHERE id=?`).bind(...assignments.map(key => changes[key]), inspectionId).run();
    return json(await db.prepare(`SELECT ${INSPECTION_FIELDS.join(",")} FROM inspection WHERE id=?`).bind(inspectionId).first());
  } catch { return error("No se pudo actualizar la inspección", 500); }
}
async function deleteInspection(db, inspectionId) {
  const row = await db.prepare("SELECT id FROM inspection WHERE id=?").bind(inspectionId).first();
  if (!row) return error("Inspección no encontrada", 404);
  if (await db.prepare("SELECT id FROM workorderevidence WHERE inspection_id=? LIMIT 1").bind(inspectionId).first()) return error("La inspección conserva evidencias y no se puede eliminar", 409);
  await db.prepare("DELETE FROM inspection WHERE id=?").bind(inspectionId).run();
  return json({ deleted: true });
}
async function listTemplates(db) {
  const templates = (await db.prepare("SELECT * FROM inspectiontemplate WHERE active=1 ORDER BY name").all()).results, result = [];
  for (const template of templates) {
    const items = (await db.prepare("SELECT * FROM inspectiontemplateitem WHERE template_id=? ORDER BY sort_order,id").bind(template.id).all()).results;
    result.push({ ...template, items });
  }
  return json(result);
}
async function createTemplate(request, db, user) {
  if (user?.role !== "admin") return error("Se requiere el rol de administrador", 403);
  let d;
  try {
    d = obj(await request.json());
    d.key = text(d.key, "Clave", 60).toLowerCase().replaceAll(" ", "-");
    d.name = text(d.name, "Nombre", 120); d.service_type = text(d.service_type, "Tipo de servicio", 80);
    d.description = text(d.description ?? "", "Descripción", 2000, true);
    if (d.key.length < 3 || !/^[a-z0-9_-]+$/.test(d.key) || d.name.length < 3 || d.service_type.length < 3) throw Error("Completa una clave, nombre y tipo de servicio válidos");
    if (typeof d.active !== "boolean" && d.active != null) throw Error("Estado de plantilla inválido");
    if (!Array.isArray(d.items) || d.items.length < 1 || d.items.length > 300) throw Error("La plantilla debe incluir al menos un punto de inspección");
    d.items = d.items.map((item, index) => {
      obj(item); const category = text(item.category, "Categoría", 80), name = text(item.item, "Punto", 120);
      const sort = Number(item.sort_order ?? index); if (!category || !name || !Number.isSafeInteger(sort)) throw Error("Punto de inspección inválido");
      return { category, item: name, sort_order: sort, required: item.required == null ? 1 : bool(item.required, "Obligatorio") ? 1 : 0 };
    });
  } catch (e) { return error(e.message, 422); }
  const now = new Date().toISOString(), batch = [db.prepare("INSERT INTO inspectiontemplate(key,name,service_type,description,active,created_at) VALUES(?,?,?,?,?,?)").bind(d.key,d.name,d.service_type,d.description,d.active === false ? 0 : 1,now)];
  for (const item of d.items) batch.push(db.prepare("INSERT INTO inspectiontemplateitem(template_id,category,item,sort_order,required) SELECT last_insert_rowid(),?,?,?,? WHERE changes()=1").bind(item.category,item.item,item.sort_order,item.required));
  try {
    const result = await db.batch(batch), template = await db.prepare("SELECT * FROM inspectiontemplate WHERE id=?").bind(result[0]?.meta?.last_row_id).first();
    const items = (await db.prepare("SELECT * FROM inspectiontemplateitem WHERE template_id=? ORDER BY sort_order,id").bind(template.id).all()).results;
    return json({ ...template, items }, 201);
  } catch (e) { return /UNIQUE constraint failed/.test(String(e)) ? error("Ya existe una plantilla con esa clave", 409) : error("No se pudo guardar la plantilla", 500); }
}
async function applyTemplate(db, orderId, templateId, serviceId) {
  if (!await editableOrder(db, orderId)) return error("Orden de trabajo no encontrada", 404);
  if (serviceId != null && !await getService(db, orderId, serviceId)) return error("Servicio no encontrado en esta orden", 404);
  const template = await db.prepare("SELECT id FROM inspectiontemplate WHERE id=? AND active=1").bind(templateId).first();
  if (!template) return error("Plantilla no encontrada", 404);
  const existing = (await db.prepare("SELECT category,item FROM inspection WHERE work_order_id=? AND work_order_service_id IS ?").bind(orderId, serviceId).all()).results;
  const seen = new Set(existing.map(row => `${row.category}\u0000${row.item}`));
  const items = (await db.prepare("SELECT category,item,sort_order FROM inspectiontemplateitem WHERE template_id=? ORDER BY sort_order,id").bind(templateId).all()).results;
  const added = items.filter(row => { const key = `${row.category}\u0000${row.item}`; if (seen.has(key)) return false; seen.add(key); return true; });
  if (added.length) await db.batch(added.map(row => db.prepare("INSERT INTO inspection(work_order_id,work_order_service_id,category,item,result,notes,measured_value,created_at) VALUES(?,?,?,?,'not_inspected',NULL,NULL,?)").bind(orderId,serviceId,row.category,row.item,new Date().toISOString())));
  const inspections = (await db.prepare(`SELECT ${INSPECTION_FIELDS.join(",")} FROM inspection WHERE work_order_id=? AND work_order_service_id IS ? ORDER BY id`).bind(orderId,serviceId).all()).results;
  return json({ template_id: templateId, work_order_service_id: serviceId, created_count: added.length, inspections }, 201);
}
async function reception(request, db, user, orderId, method) {
  if (method === "GET") {
    if (!await editableOrder(db, orderId)) return error("Orden no encontrada", 404);
    return json(await db.prepare("SELECT * FROM workorderreception WHERE work_order_id=?").bind(orderId).first());
  }
  if (method !== "PUT") return null;
  if (!await editableOrder(db, orderId)) return error("Orden de trabajo no encontrada", 404);
  let d;
  try {
    d = obj(await request.json());
    d.fuel_level_percent = d.fuel_level_percent == null ? null : Number(d.fuel_level_percent);
    if (d.fuel_level_percent != null && (!Number.isInteger(d.fuel_level_percent) || d.fuel_level_percent < 0 || d.fuel_level_percent > 100)) throw Error("Nivel de combustible inválido");
    for (const key of ["visible_damage", "accessories", "customer_observations"]) d[key] = text(d[key] ?? "", key, 4000, true);
    d.terms_accepted = bool(d.terms_accepted ?? false, "Aceptación de condiciones");
    d.accepted_by_name = text(d.accepted_by_name ?? "", "Nombre de quien acepta", 120, true);
    if (d.terms_accepted && !d.accepted_by_name) throw Error("Indica quién acepta la recepción");
  } catch (e) { return error(e.message, 422); }
  const old = await db.prepare("SELECT * FROM workorderreception WHERE work_order_id=?").bind(orderId).first(), now = new Date().toISOString();
  const acceptedAt = d.terms_accepted ? (old?.accepted_at || now) : null;
  try {
    await db.prepare("INSERT INTO workorderreception(work_order_id,fuel_level_percent,visible_damage,accessories,customer_observations,terms_accepted,accepted_by_name,accepted_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(work_order_id) DO UPDATE SET fuel_level_percent=excluded.fuel_level_percent,visible_damage=excluded.visible_damage,accessories=excluded.accessories,customer_observations=excluded.customer_observations,terms_accepted=excluded.terms_accepted,accepted_by_name=excluded.accepted_by_name,accepted_at=excluded.accepted_at,updated_at=excluded.updated_at")
      .bind(orderId,d.fuel_level_percent,d.visible_damage,d.accessories,d.customer_observations,d.terms_accepted?1:0,d.accepted_by_name,acceptedAt,old?.created_at||now,now).run();
    return json(await db.prepare("SELECT * FROM workorderreception WHERE work_order_id=?").bind(orderId).first());
  } catch { return error("No se pudo guardar la recepción", 500); }
}
async function getQuality(db, orderId) {
  if (!await editableOrder(db, orderId)) return error("Orden de trabajo no encontrada", 404);
  const row = await db.prepare("SELECT * FROM workorderqualitycheck WHERE work_order_id=?").bind(orderId).first();
  return json(row || { work_order_id: orderId, result: "pending", fluids_checked: false, leaks_checked: false, fasteners_checked: false, road_test_done: false, technician_completed_at: null, technician_notes: "", review_notes: "" });
}
async function saveQuality(request, db, orderId) {
  if (!await editableOrder(db, orderId)) return error("Orden de trabajo no encontrada", 404);
  let d;
  try {
    d = obj(await request.json());
    const allowed = new Set(["fluids_checked", "leaks_checked", "fasteners_checked", "road_test_done", "technician_completed", "technician_notes"]);
    if (Object.keys(d).some(key => !allowed.has(key))) throw Error("El control contiene campos no editables");
    for (const key of ["fluids_checked", "leaks_checked", "fasteners_checked", "road_test_done", "technician_completed"]) if (key in d) d[key] = bool(d[key], key);
    if ("technician_notes" in d) d.technician_notes = text(d.technician_notes ?? "", "Observaciones", 4000);
  } catch (e) { return error(e.message, 422); }
  const current = await db.prepare("SELECT * FROM workorderqualitycheck WHERE work_order_id=?").bind(orderId).first();
  if (current?.result === "passed") return error("El control de calidad aprobado no se puede modificar; registra una nueva orden si corresponde", 409);
  const now = new Date().toISOString(), value = key => key in d ? d[key] : current?.[key] ?? (key === "technician_notes" ? "" : 0);
  const completedAt = "technician_completed" in d ? (d.technician_completed ? now : null) : current?.technician_completed_at ?? null;
  try {
    await db.prepare("INSERT INTO workorderqualitycheck(work_order_id,fluids_checked,leaks_checked,fasteners_checked,road_test_done,technician_completed_at,technician_notes,reviewed_by_email,reviewed_at,result,review_notes,updated_at) VALUES(?,?,?,?,?,?,?,NULL,NULL,'pending','',?) ON CONFLICT(work_order_id) DO UPDATE SET fluids_checked=excluded.fluids_checked,leaks_checked=excluded.leaks_checked,fasteners_checked=excluded.fasteners_checked,road_test_done=excluded.road_test_done,technician_completed_at=excluded.technician_completed_at,technician_notes=excluded.technician_notes,reviewed_by_email=NULL,reviewed_at=NULL,result='pending',review_notes='',updated_at=excluded.updated_at WHERE workorderqualitycheck.result<>'passed'")
      .bind(orderId,value("fluids_checked"),value("leaks_checked"),value("fasteners_checked"),value("road_test_done"),completedAt,value("technician_notes"),now).run();
    const saved = await db.prepare("SELECT * FROM workorderqualitycheck WHERE work_order_id=?").bind(orderId).first();
    if (saved?.result === "passed") return error("El control de calidad aprobado no se puede modificar; registra una nueva orden si corresponde", 409);
    return json(saved);
  } catch { return error("No se pudo guardar el control de calidad", 500); }
}
async function reviewQuality(request, db, user, orderId) {
  if (user?.role !== "admin") return error("Se requiere el rol de administrador", 403);
  if (!await editableOrder(db, orderId)) return error("Orden de trabajo no encontrada", 404);
  let d;
  try { d = obj(await request.json()); if (!["passed", "failed"].includes(d.result)) throw Error("Resultado de revisión inválido"); d.review_notes = text(d.review_notes ?? "", "Comentario", 4000); }
  catch (e) { return error(e.message, 422); }
  const current = await db.prepare("SELECT * FROM workorderqualitycheck WHERE work_order_id=?").bind(orderId).first();
  if (d.result === "passed" && !(current?.fluids_checked && current?.leaks_checked && current?.fasteners_checked && current?.road_test_done && current?.technician_completed_at)) return error("Completa los controles técnicos antes de aprobar la calidad", 409);
  const now = new Date().toISOString();
  try {
    await db.prepare("INSERT INTO workorderqualitycheck(work_order_id,fluids_checked,leaks_checked,fasteners_checked,road_test_done,technician_completed_at,technician_notes,reviewed_by_email,reviewed_at,result,review_notes,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(work_order_id) DO UPDATE SET reviewed_by_email=excluded.reviewed_by_email,reviewed_at=excluded.reviewed_at,result=excluded.result,review_notes=excluded.review_notes,updated_at=excluded.updated_at")
      .bind(orderId,current?.fluids_checked||0,current?.leaks_checked||0,current?.fasteners_checked||0,current?.road_test_done||0,current?.technician_completed_at??null,current?.technician_notes||"",user.email,now,d.result,d.review_notes,now).run();
    return json(await db.prepare("SELECT * FROM workorderqualitycheck WHERE work_order_id=?").bind(orderId).first());
  } catch { return error("No se pudo revisar el control de calidad", 500); }
}
function diagnosticData(raw) {
  const d = obj(raw), out = {};
  for (const [key,max] of [["module",120],["dtc_code",32],["symptom",1000],["freeze_frame",4000],["measurements",4000],["test_performed",4000],["test_result",4000],["conclusion",4000]]) out[key] = text(d[key] ?? "", key, max);
  out.work_order_service_id = d.work_order_service_id == null ? null : id(d.work_order_service_id,"Trabajo");
  out.scanner_report_id = d.scanner_report_id == null ? null : id(d.scanner_report_id,"Informe scanner");
  out.technician_confirmed = d.technician_confirmed === true || d.confirmed === true;
  if (!out.dtc_code && !out.symptom && !out.measurements && !out.test_performed && !out.conclusion) throw Error("Registra al menos un síntoma, DTC, medición, prueba o conclusión");
  if (out.technician_confirmed && !out.conclusion) throw Error("Una conclusión confirmada requiere la conclusión técnica");
  return out;
}
async function listDiagnostics(db, orderId) {
  if (!await editableOrder(db, orderId)) return error("Orden de trabajo no encontrada", 404);
  return json((await db.prepare(`SELECT ${DIAGNOSTIC_FIELDS.join(",")} FROM diagnosticfinding WHERE work_order_id=? ORDER BY created_at DESC,id DESC`).bind(orderId).all()).results);
}
async function validateDiagnosticLinks(db, order, data) {
  if (data.work_order_service_id != null && !await getService(db, order.id, data.work_order_service_id)) return "El servicio indicado no pertenece a esta orden";
  if (data.scanner_report_id != null) {
    const report = await db.prepare("SELECT id FROM scannerreport WHERE id=? AND work_order_id=? AND vehicle_id=?").bind(data.scanner_report_id,order.id,order.vehicle_id).first();
    if (!report) return "El informe scanner indicado no pertenece a esta orden y vehículo";
  }
  return null;
}
async function createDiagnostic(request, db, user, orderId) {
  const order = await editableOrder(db,orderId); if (!order) return error("Orden de trabajo no encontrada",404);
  let d; try { d=diagnosticData(await request.json()); } catch(e) { return error(e.message,422); }
  const linkError=await validateDiagnosticLinks(db,order,d); if(linkError) return error(linkError,422);
  const now=new Date().toISOString(), confirmed=d.technician_confirmed?now:null;
  try {
    const result=await db.prepare("INSERT INTO diagnosticfinding(work_order_id,work_order_service_id,scanner_report_id,vehicle_id,module,dtc_code,symptom,freeze_frame,measurements,test_performed,test_result,conclusion,technician_confirmed_at,recorded_by_email,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
      .bind(orderId,d.work_order_service_id,d.scanner_report_id,order.vehicle_id,d.module,d.dtc_code,d.symptom,d.freeze_frame,d.measurements,d.test_performed,d.test_result,d.conclusion,confirmed,user.email,now,now).run();
    return json(await db.prepare(`SELECT ${DIAGNOSTIC_FIELDS.join(",")} FROM diagnosticfinding WHERE id=?`).bind(result.meta.last_row_id).first(),201);
  } catch { return error("No se pudo guardar el diagnóstico",500); }
}
async function updateDiagnostic(request, db, user, orderId, findingId) {
  const order=await editableOrder(db,orderId); if(!order) return error("Orden de trabajo no encontrada",404);
  const current=await db.prepare("SELECT * FROM diagnosticfinding WHERE id=? AND work_order_id=?").bind(findingId,orderId).first();
  if(!current) return error("Registro de diagnóstico no encontrado",404);
  if(current.technician_confirmed_at) return error("Un diagnóstico confirmado no se edita; agrega una nueva evidencia si cambia el resultado",409);
  let d; try { d=diagnosticData(await request.json()); } catch(e) { return error(e.message,422); }
  const linkError=await validateDiagnosticLinks(db,order,d); if(linkError) return error(linkError,422);
  const now=new Date().toISOString();
  try {
    await db.prepare("UPDATE diagnosticfinding SET work_order_service_id=?,scanner_report_id=?,module=?,dtc_code=?,symptom=?,freeze_frame=?,measurements=?,test_performed=?,test_result=?,conclusion=?,technician_confirmed_at=?,updated_at=? WHERE id=? AND work_order_id=? AND technician_confirmed_at IS NULL")
      .bind(d.work_order_service_id,d.scanner_report_id,d.module,d.dtc_code,d.symptom,d.freeze_frame,d.measurements,d.test_performed,d.test_result,d.conclusion,d.technician_confirmed?now:null,now,findingId,orderId).run();
    return json(await db.prepare(`SELECT ${DIAGNOSTIC_FIELDS.join(",")} FROM diagnosticfinding WHERE id=?`).bind(findingId).first());
  } catch { return error("No se pudo actualizar el diagnóstico",500); }
}
export async function handleWorkshopOperations(request, env, user) {
  const url=new URL(request.url), path=url.pathname, method=request.method, db=env.DB;
  let match=path.match(/^\/api\/v1\/work-orders\/(\d+)\/inspections$/);
  if(match) return method==="GET"?listInspections(db,Number(match[1])):method==="POST"?createInspection(request,db,user,Number(match[1])):null;
  match=path.match(/^\/api\/v1\/work-orders\/(\d+)\/inspection-templates\/(\d+)\/apply$/);
  if(match&&method==="POST") { const raw=url.searchParams.get("work_order_service_id"); let serviceId=null; try{serviceId=raw==null?null:id(raw,"Trabajo");}catch(e){return error(e.message,422);} return applyTemplate(db,Number(match[1]),Number(match[2]),serviceId); }
  if(path==="/api/v1/inspection-templates") return method==="GET"?listTemplates(db):method==="POST"?createTemplate(request,db,user):null;
  match=path.match(/^\/api\/v1\/inspections\/(\d+)$/);
  if(match) return method==="PATCH"?updateInspection(request,db,Number(match[1])):method==="DELETE"?deleteInspection(db,Number(match[1])):null;
  match=path.match(/^\/api\/v1\/work-orders\/(\d+)\/reception$/);
  if(match) return reception(request,db,user,Number(match[1]),method);
  match=path.match(/^\/api\/v1\/work-orders\/(\d+)\/quality-check(?:\/(review))?$/);
  if(match) { const orderId=Number(match[1]); if(match[2]&&method==="POST") return reviewQuality(request,db,user,orderId); if(!match[2]&&method==="GET") return getQuality(db,orderId); if(!match[2]&&method==="PUT") return saveQuality(request,db,orderId); }
  match=path.match(/^\/api\/v1\/work-orders\/(\d+)\/diagnostics(?:\/(\d+))?$/);
  if(match) { const orderId=Number(match[1]), findingId=match[2]?Number(match[2]):null; if(!findingId&&method==="GET") return listDiagnostics(db,orderId); if(!findingId&&method==="POST") return createDiagnostic(request,db,user,orderId); if(findingId&&method==="PATCH") return updateDiagnostic(request,db,user,orderId,findingId); }
  return null;
}
