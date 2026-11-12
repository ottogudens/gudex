const PRODUCT_COLUMNS = [
  "id", "sku", "name", "category", "unit", "stock_quantity", "minimum_quantity", "cost_clp", "price_clp",
  "manufacturer", "product_type", "oem_number", "equivalent_codes", "technical_specs", "application_notes",
  "sae_grade", "api_spec", "acea_spec", "oem_approvals", "data_source_url", "verification_status", "active",
];
const TECH_LIMITS = { manufacturer: 80, product_type: 40, oem_number: 120, equivalent_codes: 1000, technical_specs: 2000, application_notes: 2000, sae_grade: 30, api_spec: 80, acea_spec: 80, oem_approvals: 500, data_source_url: 500 };
const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" } });
const error = (detail, status) => json({ detail }, status);
const isAdmin = user => user?.role === "admin";
function object(value) { if (!value || typeof value !== "object" || Array.isArray(value)) throw Error("Cuerpo JSON inválido"); return value; }
function number(value, label, { min = 0, max = 1_000_000_000, integer = false } = {}) { const parsed = Number(value); if (!Number.isFinite(parsed) || parsed < min || parsed > max || (integer && !Number.isSafeInteger(parsed))) throw Error(`${label} inválido`); return parsed; }
function optionalText(data, key, max) { if (!(key in data) || data[key] == null || data[key] === "") return null; if (typeof data[key] !== "string" || data[key].trim().length > max) throw Error(`${key} inválido`); return data[key].trim() || null; }
async function getCount(db, id) { return db.prepare("SELECT * FROM inventorycountsession WHERE id=?").bind(id).first(); }
function revealExpected(count, user) { return !count.blind_count || user.role === "admin" || count.status !== "counting"; }
async function countPayload(db, count, user) {
  const productSelect = PRODUCT_COLUMNS.map(column => `p.${column} AS product_${column}`).join(",");
  const rows = await db.prepare(`SELECT l.*,${productSelect} FROM inventorycountline l JOIN product p ON p.id=l.product_id WHERE l.session_id=? ORDER BY l.id`).bind(count.id).all();
  const reveal = revealExpected(count, user), lines = [];
  for (const line of rows.results) {
    const product = Object.fromEntries(PRODUCT_COLUMNS.map(column => [column, line[`product_${column}`]]));
    for (const column of PRODUCT_COLUMNS) delete line[`product_${column}`];
    if (!reveal) delete product.stock_quantity;
    const payload = { ...line, product, difference_quantity: reveal ? line.counted_quantity - line.expected_quantity : null };
    if (!reveal) delete payload.expected_quantity;
    lines.push(payload);
  }
  return { session: count, lines, expected_visible: reveal };
}
async function createCount(request, env, user) {
  let data;
  try { data = object(await request.json()); }
  catch (e) { return error(e.message, 422); }
  try {
    const name = data.name;
    if (typeof name !== "string" || name.trim().length < 3 || name.trim().length > 140) return error("El nombre debe tener entre 3 y 140 caracteres", 422);
    if (data.blind_count != null && typeof data.blind_count !== "boolean") return error("El modo de conteo ciego es inválido", 422);
    const now = new Date(), iso = now.toISOString(), ymd = iso.slice(2, 10).replaceAll("-", ""), code = `INV-${ymd}-${crypto.randomUUID().replaceAll("-", "").slice(0, 5).toUpperCase()}`;
    const result = await env.DB.prepare("INSERT INTO inventorycountsession(code,name,status,blind_count,created_by_email,reviewed_by_email,created_at,submitted_at,applied_at) VALUES(?,?,'counting',?,?,NULL,?,NULL,NULL)").bind(code, name.trim(), data.blind_count === false ? 0 : 1, user.email, iso).run();
    return json(await getCount(env.DB, result.meta.last_row_id), 201);
  } catch { return error("No se pudo crear la toma de inventario", 500); }
}
async function saveLine(request, env, user, countId) {
  const count = await getCount(env.DB, countId);
  if (!count) return error("Toma de inventario no encontrada", 404);
  if (count.status !== "counting") return error("Esta toma ya fue enviada a revisión o aplicada", 409);
  let data, productId, counted, note;
  try {
    data = object(await request.json()); productId = number(data.product_id, "Producto", { min: 1, integer: true });
    counted = number(data.counted_quantity, "Cantidad contada"); note = optionalText(data, "note", 1000) ?? "";
  } catch (e) { return error(e.message, 422); }
  const product = await env.DB.prepare(`SELECT ${PRODUCT_COLUMNS.join(",")} FROM product WHERE id=?`).bind(productId).first();
  if (!product) return error("Producto no encontrado", 404);
  const existing = await env.DB.prepare("SELECT id,expected_quantity FROM inventorycountline WHERE session_id=? AND product_id=?").bind(countId, productId).first();
  const expected = existing ? existing.expected_quantity : product.stock_quantity, now = new Date().toISOString();
  try {
    await env.DB.batch([
      env.DB.prepare("INSERT INTO inventorycountline(session_id,product_id,expected_quantity,counted_quantity,note,counted_by_email,counted_at) SELECT ?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM inventorycountsession WHERE id=? AND status='counting') ON CONFLICT(session_id,product_id) DO UPDATE SET counted_quantity=excluded.counted_quantity,note=excluded.note,counted_by_email=excluded.counted_by_email,counted_at=excluded.counted_at")
        .bind(countId, productId, expected, counted, note, user.email, now, countId),
      env.DB.prepare("INSERT INTO inventorycountline(session_id,product_id,expected_quantity,counted_quantity,note,counted_by_email,counted_at) SELECT ?,NULL,0,0,'','',? WHERE changes()=0")
        .bind(countId, now),
    ]);
    const line = await env.DB.prepare("SELECT * FROM inventorycountline WHERE session_id=? AND product_id=?").bind(countId, productId).first();
    const reveal = revealExpected(count, user), payload = { ...line, product, difference_quantity: reveal ? counted - expected : null };
    if (!reveal) delete payload.expected_quantity;
    return json(payload);
  } catch {
    const latest = await getCount(env.DB, countId);
    return latest?.status !== "counting" ? error("Esta toma ya fue enviada a revisión o aplicada", 409) : error("No se pudo guardar el conteo", 500);
  }
}
async function missingProduct(request, env, user, countId) {
  const count = await getCount(env.DB, countId);
  if (!count) return error("Toma de inventario no encontrada", 404);
  if (count.status !== "counting") return error("Esta toma ya no permite crear productos", 409);
  let d, sku, product;
  try {
    d = object(await request.json()); sku = typeof d.barcode === "string" ? d.barcode.trim().toUpperCase() : "";
    if (sku.length < 3 || sku.length > 40) throw Error("El código debe tener entre 3 y 40 caracteres");
    const name = typeof d.name === "string" ? d.name.trim() : "";
    if (name.length < 2 || name.length > 120) throw Error("Ingresa un nombre de producto válido");
    product = { sku, name, category: optionalText(d, "category", 80), unit: d.unit == null || d.unit === "" ? "unidad" : optionalText(d, "unit", 24), stock_quantity: 0,
      minimum_quantity: number(d.minimum_quantity ?? 0, "Stock mínimo"), cost_clp: number(d.cost_clp ?? 0, "Costo", { integer: true, max: 2_147_483_647 }), price_clp: number(d.price_clp ?? 0, "Precio", { integer: true, max: 2_147_483_647 }), verification_status: "draft", active: 1 };
    if (!product.unit) product.unit = "unidad";
    for (const [key, max] of Object.entries(TECH_LIMITS)) product[key] = optionalText(d, key, max);
    product.counted_quantity = number(d.counted_quantity, "Cantidad contada");
  } catch (e) { return error(e.message, 422); }
  if (await env.DB.prepare("SELECT id FROM product WHERE sku=?").bind(sku).first()) return error("Ese código ya pertenece a un producto; registra su conteo", 409);
  const productColumns = PRODUCT_COLUMNS.filter(key => key !== "id"), now = new Date().toISOString();
  const values = productColumns.map(key => product[key] ?? null);
  try {
    const insertProduct = `INSERT INTO product(${productColumns.join(",")}) SELECT ${productColumns.map(() => "?").join(",")} WHERE EXISTS(SELECT 1 FROM inventorycountsession WHERE id=? AND status='counting')`;
    const result = await env.DB.batch([
      env.DB.prepare(insertProduct).bind(...values, countId),
      env.DB.prepare("INSERT INTO inventorycountline(session_id,product_id,expected_quantity,counted_quantity,note,counted_by_email,counted_at) SELECT ?,last_insert_rowid(),0,?,?,?,? WHERE changes()=1")
        .bind(countId, product.counted_quantity, "Producto creado durante la toma", user.email, now),
      // Force the transaction to roll back if the session stopped accepting products.
      env.DB.prepare("INSERT INTO inventorycountline(session_id,product_id,expected_quantity,counted_quantity,note,counted_by_email,counted_at) SELECT ?,NULL,0,0,'', '', ? WHERE changes()=0")
        .bind(countId, now),
    ]);
    const productId = result[0]?.meta?.last_row_id;
    const created = await env.DB.prepare(`SELECT ${PRODUCT_COLUMNS.join(",")} FROM product WHERE id=?`).bind(productId).first();
    const line = await env.DB.prepare("SELECT * FROM inventorycountline WHERE session_id=? AND product_id=?").bind(countId, productId).first();
    const reveal = revealExpected(count, user), payload = { ...line, product: created, difference_quantity: reveal ? product.counted_quantity : null };
    if (!reveal) delete payload.expected_quantity;
    return json(payload, 201);
  } catch (e) { return /UNIQUE constraint failed/.test(String(e)) ? error("Ese código ya pertenece a un producto; registra su conteo", 409) : error("No se pudo crear el producto en la toma", 500); }
}
async function submitCount(env, countId) {
  const count = await getCount(env.DB, countId);
  if (!count) return error("Toma de inventario no encontrada", 404);
  if (count.status !== "counting") return error("La toma ya fue enviada o aplicada", 409);
  if (!(await env.DB.prepare("SELECT id FROM inventorycountline WHERE session_id=? LIMIT 1").bind(countId).first())) return error("Registra al menos un producto antes de enviar la toma", 409);
  const now = new Date().toISOString();
  await env.DB.prepare("UPDATE inventorycountsession SET status='review',submitted_at=? WHERE id=? AND status='counting'").bind(now, countId).run();
  return json(await getCount(env.DB, countId));
}
async function applyCount(env, user, countId) {
  if (!isAdmin(user)) return error("Se requiere el rol de administrador", 403);
  const count = await getCount(env.DB, countId);
  if (!count) return error("Toma de inventario no encontrada", 404);
  if (count.status !== "review") return error("La toma debe enviarse a revisión antes de aplicarla", 409);
  const { results: lines } = await env.DB.prepare("SELECT * FROM inventorycountline WHERE session_id=? ORDER BY id").bind(countId).all();
  if (!lines.length) return error("La toma no tiene líneas", 409);
  const snapshots = await env.DB.prepare("SELECT p.id,p.name,p.stock_quantity,l.expected_quantity FROM inventorycountline l LEFT JOIN product p ON p.id=l.product_id WHERE l.session_id=? ORDER BY l.id").bind(countId).all();
  for (const product of snapshots.results) {
    if (product.id == null || Number(product.stock_quantity) !== Number(product.expected_quantity)) return error(`El stock de ${product?.name || "un producto"} cambió durante la toma. Repite su conteo antes de aplicar.`, 409);
  }
  const now = new Date().toISOString(), batch = [];
  for (const line of lines) {
    const delta = Number(line.counted_quantity) - Number(line.expected_quantity);
    batch.push(env.DB.prepare("UPDATE product SET stock_quantity=? WHERE id=? AND stock_quantity=?").bind(line.counted_quantity, line.product_id, line.expected_quantity));
    batch.push(env.DB.prepare("INSERT INTO stockmovement(product_id,quantity_change,reason,reference,created_at) SELECT ?,?,'inventory_count',?,? WHERE changes()=1 AND ?<>0").bind(line.product_id, delta, count.code, now, delta));
    batch.push(env.DB.prepare("INSERT INTO stockmovement(product_id,quantity_change,reason,reference,created_at) SELECT NULL,0,'inventory_count',?,? WHERE EXISTS(SELECT 1 FROM product WHERE id=? AND stock_quantity<>?)").bind(count.code, now, line.product_id, line.counted_quantity));
  }
  batch.push(env.DB.prepare("UPDATE inventorycountsession SET status='applied',applied_at=?,reviewed_by_email=? WHERE id=? AND status='review'").bind(now, user.email, countId));
  batch.push(env.DB.prepare("INSERT INTO stockmovement(product_id,quantity_change,reason,reference,created_at) SELECT NULL,0,'inventory_count',?,? WHERE changes()=0").bind(count.code, now));
  try {
    await env.DB.batch(batch);
    return json({ session: await getCount(env.DB, countId), applied_lines: lines.length });
  } catch {
    const current = await getCount(env.DB, countId);
    return current?.status !== "review" ? error("La toma debe enviarse a revisión antes de aplicarla", 409) : error("El stock cambió durante la toma. Repite el conteo de las diferencias antes de aplicar.", 409);
  }
}

export async function handleInventoryCounts(request, env, user) {
  const path = new URL(request.url).pathname, method = request.method;
  if (path === "/api/v1/inventory-counts" && method === "GET") return json((await env.DB.prepare("SELECT * FROM inventorycountsession ORDER BY created_at DESC LIMIT 100").all()).results);
  if (path === "/api/v1/inventory-counts" && method === "POST") return createCount(request, env, user);
  const match = path.match(/^\/api\/v1\/inventory-counts\/(\d+)(?:\/(lookup|lines|missing-product|submit|apply))?$/);
  if (!match) return null;
  const id = Number(match[1]), action = match[2] || "detail";
  if (action === "detail" && method === "GET") {
    const count = await getCount(env.DB, id);
    return count ? json(await countPayload(env.DB, count, user)) : error("Toma de inventario no encontrada", 404);
  }
  if (action === "lookup" && method === "GET") {
    const count = await getCount(env.DB, id);
    if (!count) return error("Toma de inventario no encontrada", 404);
    const raw = new URL(request.url).searchParams.get("barcode") || "", barcode = raw.trim().toUpperCase();
    if (!barcode) return error("Ingresa o escanea un código", 422);
    const product = await env.DB.prepare(`SELECT ${PRODUCT_COLUMNS.join(",")} FROM product WHERE sku=?`).bind(barcode).first();
    if (product && count.blind_count && count.status === "counting" && !isAdmin(user)) delete product.stock_quantity;
    return json({ barcode, product });
  }
  if (action === "lines" && method === "PUT") return saveLine(request, env, user, id);
  if (action === "missing-product" && method === "POST") return missingProduct(request, env, user, id);
  if (action === "submit" && method === "POST") return submitCount(env, id);
  if (action === "apply" && method === "POST") return applyCount(env, user, id);
  return null;
}
