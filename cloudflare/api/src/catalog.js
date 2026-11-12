const PRODUCT_FIELDS = [
  "id", "sku", "name", "category", "unit", "stock_quantity", "minimum_quantity", "cost_clp", "price_clp",
  "manufacturer", "product_type", "oem_number", "equivalent_codes", "technical_specs", "application_notes",
  "sae_grade", "api_spec", "acea_spec", "oem_approvals", "data_source_url", "verification_status", "active",
];
const TECH_FIELDS = {
  manufacturer: 80, product_type: 40, oem_number: 120, equivalent_codes: 1000, technical_specs: 2000,
  application_notes: 2000, sae_grade: 30, api_spec: 80, acea_spec: 80, oem_approvals: 500, data_source_url: 500,
};
const CATALOG_FIELDS = ["id", "code", "name", "category_id", "description", "price_clp"];
const json = (data, status = 200) => new Response(JSON.stringify(data), {
  status,
  headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" },
});
const error = (detail, status) => json({ detail }, status);
const isAdmin = user => user?.role === "admin";
const bodyObject = value => {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw Error("Cuerpo JSON inválido");
  return value;
};
function text(value, label, max, { required = false, uppercase = false } = {}) {
  if (value == null && !required) return null;
  if (typeof value !== "string") throw Error(`${label} inválido`);
  const normalized = value.trim();
  if (required && !normalized) throw Error(`${label} es obligatorio`);
  if (normalized.length > max) throw Error(`${label} supera el largo permitido`);
  return normalized ? (uppercase ? normalized.toUpperCase() : normalized) : null;
}
function finite(value, label, { min = 0, max = Number.MAX_SAFE_INTEGER, integer = false } = {}) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < min || parsed > max || (integer && !Number.isSafeInteger(parsed))) throw Error(`${label} inválido`);
  return parsed;
}
function normalizeProduct(data, { create = false } = {}) {
  bodyObject(data);
  const result = {};
  const fields = [
    ["sku", "SKU", 40, true], ["name", "Nombre", 120, true], ["category", "Categoría", 80, false], ["unit", "Unidad", 24, false],
    ...Object.entries(TECH_FIELDS).map(([key, max]) => [key, key, max, false]),
  ];
  for (const [key, label, max, uppercase] of fields) {
    if (create || key in data) result[key] = text(key === "unit" && data[key] == null && create ? "unidad" : data[key], label, max, { required: key === "name", uppercase: key === "sku" });
  }
  for (const [key, label, integer] of [["minimum_quantity", "Stock mínimo", false], ["cost_clp", "Costo CLP", true], ["price_clp", "Precio CLP", true]]) {
    if (create || key in data) result[key] = finite(key === "cost_clp" || key === "price_clp" ? (data[key] ?? 0) : (data[key] ?? 0), label, { integer, max: integer ? 2_147_483_647 : 1_000_000_000 });
  }
  if (create) result.stock_quantity = finite(data.stock_quantity ?? 0, "Stock", { max: 1_000_000_000 });
  if (create || "verification_status" in data) {
    const status = text(data.verification_status ?? "draft", "Estado técnico", 24).toLowerCase();
    if (!["draft", "verified"].includes(status)) throw Error("El estado técnico debe ser borrador o verificado");
    result.verification_status = status;
  }
  if (!create && "active" in data) {
    if (typeof data.active !== "boolean" && data.active !== 0 && data.active !== 1) throw Error("Estado activo inválido");
    result.active = data.active ? 1 : 0;
  }
  return result;
}
function normalizeCategory(data) {
  bodyObject(data);
  return { name: text(data.name, "Nombre de categoría", 80, { required: true }) };
}
function normalizeService(data) {
  bodyObject(data);
  return {
    code: text(data.code, "Código de servicio", 40, { required: true, uppercase: true }),
    name: text(data.name, "Nombre de servicio", 160, { required: true }),
    category_id: finite(data.category_id, "Categoría", { min: 1, integer: true }),
    description: text(data.description ?? "", "Descripción", 2000) ?? "",
    price_clp: finite(data.price_clp ?? 0, "Precio CLP", { integer: true, max: 2_147_483_647 }),
  };
}
async function createProduct(request, env, user) {
  if (!isAdmin(user)) return error("Se requiere el rol de administrador", 403);
  let product;
  try { product = normalizeProduct(await request.json(), { create: true }); }
  catch (e) { return error(e.message || "Datos de producto inválidos", 422); }
  if (product.sku && await env.DB.prepare("SELECT id FROM product WHERE sku=?").bind(product.sku).first()) return error("Ya existe un producto con ese SKU", 409);
  const now = new Date().toISOString(), stock = product.stock_quantity;
  const columns = PRODUCT_FIELDS.filter(key => key !== "id" && key !== "active");
  const values = columns.map(key => product[key] ?? null);
  const create = env.DB.prepare(`INSERT INTO product(${columns.join(",")},active) VALUES(${columns.map(() => "?").join(",")},1)`);
  const statements = [create.bind(...values)];
  if (stock > 0) statements.push(env.DB.prepare("INSERT INTO stockmovement(product_id,quantity_change,reason,reference,created_at) SELECT last_insert_rowid(),?,'initial_stock',NULL,? WHERE changes()=1").bind(stock, now));
  try {
    const result = await env.DB.batch(statements), id = result[0]?.meta?.last_row_id;
    return json(await env.DB.prepare(`SELECT ${PRODUCT_FIELDS.join(",")} FROM product WHERE id=?`).bind(id).first(), 201);
  } catch (e) { return /UNIQUE constraint failed/.test(String(e)) ? error("Ya existe un producto con ese SKU", 409) : error("No se pudo guardar el producto", 500); }
}
async function updateProduct(request, env, user, id) {
  if (!isAdmin(user)) return error("Se requiere el rol de administrador", 403);
  const current = await env.DB.prepare("SELECT id FROM product WHERE id=?").bind(id).first();
  if (!current) return error("Producto no encontrado", 404);
  let changes;
  try { changes = normalizeProduct(await request.json()); }
  catch (e) { return error(e.message || "Datos de producto inválidos", 422); }
  if (!Object.keys(changes).length) return error("No hay campos para actualizar", 422);
  if (changes.sku && await env.DB.prepare("SELECT id FROM product WHERE sku=? AND id<>?").bind(changes.sku, id).first()) return error("Ya existe un producto con ese SKU", 409);
  const keys = Object.keys(changes);
  try {
    await env.DB.prepare(`UPDATE product SET ${keys.map(key => `${key}=?`).join(",")} WHERE id=?`).bind(...keys.map(key => changes[key]), id).run();
    return json(await env.DB.prepare(`SELECT ${PRODUCT_FIELDS.join(",")} FROM product WHERE id=?`).bind(id).first());
  } catch (e) { return /UNIQUE constraint failed/.test(String(e)) ? error("Ya existe un producto con ese SKU", 409) : error("No se pudo actualizar el producto", 500); }
}
async function adjustStock(request, env, user, productId) {
  if (!isAdmin(user)) return error("Se requiere el rol de administrador", 403);
  const product = await env.DB.prepare("SELECT id,stock_quantity FROM product WHERE id=?").bind(productId).first();
  if (!product) return error("Producto no encontrado", 404);
  let data, delta, reason, reference;
  try {
    data = bodyObject(await request.json());
    delta = Number(data.quantity_change);
    if (!Number.isFinite(delta) || delta === 0 || Math.abs(delta) > 1_000_000_000) throw Error("El movimiento debe ser finito y distinto de cero");
    reason = text(data.reason, "Motivo", 40, { required: true });
    if (reason.length < 3) throw Error("Describe el motivo del movimiento");
    reference = text(data.reference, "Referencia", 80);
  } catch (e) { return error(e.message || "Datos de movimiento inválidos", 422); }
  const createdAt = new Date().toISOString();
  try {
    const results = await env.DB.batch([
      env.DB.prepare("UPDATE product SET stock_quantity=stock_quantity+? WHERE id=? AND stock_quantity+?>=0").bind(delta, productId, delta),
      env.DB.prepare("INSERT INTO stockmovement(product_id,quantity_change,reason,reference,created_at) SELECT ?,?,?,?,? WHERE changes()=1").bind(productId, delta, reason, reference, createdAt),
    ]);
    if (!results[0]?.meta?.changes) return error("El movimiento dejaría el stock bajo cero", 409);
    return json(await env.DB.prepare("SELECT * FROM stockmovement WHERE id=?").bind(results[1]?.meta?.last_row_id).first(), 201);
  } catch { return error("No se pudo registrar el movimiento de stock", 500); }
}
async function productRoutes(request, env, user, url, path, method) {
  if (path === "/api/v1/products" && method === "GET") {
    const limit = Math.min(Math.max(Number(url.searchParams.get("limit") || 100), 1), 500), offset = Math.max(Number(url.searchParams.get("offset") || 0), 0);
    const lowStock = url.searchParams.get("low_stock") === "true";
    const { results } = await env.DB.prepare(`SELECT ${PRODUCT_FIELDS.join(",")} FROM product WHERE active=1 AND (?=0 OR stock_quantity<=minimum_quantity) ORDER BY name LIMIT ? OFFSET ?`).bind(lowStock ? 1 : 0, limit, offset).all();
    return json(results);
  }
  if (path === "/api/v1/products" && method === "POST") return createProduct(request, env, user);
  const match = path.match(/^\/api\/v1\/products\/(\d+)(?:\/(stock-movements))?$/);
  if (!match) return null;
  const id = Number(match[1]);
  if (match[2] && method === "GET") {
    if (!(await env.DB.prepare("SELECT id FROM product WHERE id=?").bind(id).first())) return error("Producto no encontrado", 404);
    const { results } = await env.DB.prepare("SELECT * FROM stockmovement WHERE product_id=? ORDER BY created_at DESC,id DESC LIMIT 100").bind(id).all();
    return json(results);
  }
  if (match[2] && method === "POST") return adjustStock(request, env, user, id);
  if (!match[2] && method === "PATCH") return updateProduct(request, env, user, id);
  if (!match[2] && method === "DELETE") {
    if (!isAdmin(user)) return error("Se requiere el rol de administrador", 403);
    const result = await env.DB.prepare("UPDATE product SET active=0 WHERE id=? AND active=1").bind(id).run();
    return result.meta.changes ? json({ deleted: false, archived: true }) : (await env.DB.prepare("SELECT id FROM product WHERE id=?").bind(id).first() ? json({ deleted: false, archived: true }) : error("Producto no encontrado", 404));
  }
  return null;
}
async function catalogRoutes(request, env, user, path, method) {
  if (path === "/api/v1/service-categories" && method === "GET") {
    return json((await env.DB.prepare("SELECT id,name FROM servicecategory ORDER BY name").all()).results);
  }
  if (path === "/api/v1/service-categories" && method === "POST") {
    if (!isAdmin(user)) return error("Se requiere el rol de administrador", 403);
    let data; try { data = normalizeCategory(await request.json()); } catch (e) { return error(e.message, 422); }
    try { const r = await env.DB.prepare("INSERT INTO servicecategory(name) VALUES(?)").bind(data.name).run(); return json(await env.DB.prepare("SELECT id,name FROM servicecategory WHERE id=?").bind(r.meta.last_row_id).first(), 201); }
    catch { return error("Ya existe ese nombre de categoría", 409); }
  }
  let match = path.match(/^\/api\/v1\/service-categories\/(\d+)$/);
  if (match) {
    const id = Number(match[1]);
    if (method === "PUT") {
      if (!isAdmin(user)) return error("Se requiere el rol de administrador", 403);
      if (!(await env.DB.prepare("SELECT id FROM servicecategory WHERE id=?").bind(id).first())) return error("Registro no encontrado", 404);
      let data; try { data = normalizeCategory(await request.json()); } catch (e) { return error(e.message, 422); }
      try { await env.DB.prepare("UPDATE servicecategory SET name=? WHERE id=?").bind(data.name, id).run(); return json(await env.DB.prepare("SELECT id,name FROM servicecategory WHERE id=?").bind(id).first()); }
      catch { return error("Ya existe ese nombre de categoría", 409); }
    }
    if (method === "DELETE") {
      if (!isAdmin(user)) return error("Se requiere el rol de administrador", 403);
      if (!(await env.DB.prepare("SELECT id FROM servicecategory WHERE id=?").bind(id).first())) return error("Registro no encontrado", 404);
      if (await env.DB.prepare("SELECT id FROM service WHERE category_id=? LIMIT 1").bind(id).first()) return error("Mueve o elimina los servicios de esta categoría antes de eliminarla", 409);
      await env.DB.prepare("DELETE FROM servicecategory WHERE id=?").bind(id).run(); return json({ deleted: true });
    }
  }
  if (path === "/api/v1/services" && method === "GET") {
    return json((await env.DB.prepare("SELECT s.id,s.code,s.name,s.category_id,s.description,s.price_clp,c.name AS category FROM service s JOIN servicecategory c ON c.id=s.category_id ORDER BY c.name,s.name").all()).results);
  }
  if (path === "/api/v1/services" && method === "POST") {
    if (!isAdmin(user)) return error("Se requiere el rol de administrador", 403);
    let data; try { data = normalizeService(await request.json()); } catch (e) { return error(e.message, 422); }
    if (!(await env.DB.prepare("SELECT id FROM servicecategory WHERE id=?").bind(data.category_id).first())) return error("Categoría no encontrada", 404);
    try { const r = await env.DB.prepare("INSERT INTO service(code,name,category_id,description,price_clp) VALUES(?,?,?,?,?)").bind(data.code,data.name,data.category_id,data.description,data.price_clp).run(); return json(await env.DB.prepare(`SELECT ${CATALOG_FIELDS.join(",")} FROM service WHERE id=?`).bind(r.meta.last_row_id).first(), 201); }
    catch { return error("Ya existe ese nombre de categoría o código de servicio", 409); }
  }
  match = path.match(/^\/api\/v1\/services\/(\d+)$/);
  if (match) {
    const id = Number(match[1]);
    if (method === "PUT") {
      if (!isAdmin(user)) return error("Se requiere el rol de administrador", 403);
      if (!(await env.DB.prepare("SELECT id FROM service WHERE id=?").bind(id).first())) return error("Registro no encontrado", 404);
      let data; try { data = normalizeService(await request.json()); } catch (e) { return error(e.message, 422); }
      if (!(await env.DB.prepare("SELECT id FROM servicecategory WHERE id=?").bind(data.category_id).first())) return error("Categoría no encontrada", 404);
      try { await env.DB.prepare("UPDATE service SET code=?,name=?,category_id=?,description=?,price_clp=? WHERE id=?").bind(data.code,data.name,data.category_id,data.description,data.price_clp,id).run(); return json(await env.DB.prepare(`SELECT ${CATALOG_FIELDS.join(",")} FROM service WHERE id=?`).bind(id).first()); }
      catch { return error("Ya existe ese nombre de categoría o código de servicio", 409); }
    }
    if (method === "DELETE") {
      if (!isAdmin(user)) return error("Se requiere el rol de administrador", 403);
      if (!(await env.DB.prepare("SELECT id FROM service WHERE id=?").bind(id).first())) return error("Registro no encontrado", 404);
      for (const [table, field] of [["workorderservice", "catalog_service_id"], ["quoteitem", "service_id"]]) {
        if (await env.DB.prepare(`SELECT id FROM ${table} WHERE ${field}=? LIMIT 1`).bind(id).first()) return error("El servicio tiene historial asociado y no se puede eliminar", 409);
      }
      await env.DB.prepare("DELETE FROM service WHERE id=?").bind(id).run(); return json({ deleted: true });
    }
  }
  return null;
}

export async function handleCatalog(request, env, user) {
  const url = new URL(request.url), path = url.pathname, method = request.method;
  const product = await productRoutes(request, env, user, url, path, method);
  return product ?? catalogRoutes(request, env, user, path, method);
}
