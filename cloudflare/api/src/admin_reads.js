const json = (body, status = 200, headers = {}) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...headers } });
const one = async (db, sql, ...args) => db.prepare(sql).bind(...args).first();
const fail = (detail, status = 422) => json({ detail }, status);

async function saveQuote(db, data, existing = null) {
  if (!data || typeof data !== "object" || String(data.description || "").trim().length < 1 || String(data.description).length > 250) return { error: fail("Describe la cotización") };
  const orderId = data.work_order_id == null ? null : Number(data.work_order_id);
  const customerId = data.customer_id == null ? null : Number(data.customer_id);
  const vehicleId = data.vehicle_id == null ? null : Number(data.vehicle_id);
  const order = orderId ? await one(db, "SELECT * FROM workorder WHERE id=?", orderId) : null;
  if (orderId && !order) return { error: fail("Orden de trabajo no encontrada", 404) };
  const effectiveCustomer = order?.customer_id ?? customerId, effectiveVehicle = order?.vehicle_id ?? vehicleId;
  const customer = effectiveCustomer ? await one(db, "SELECT * FROM customer WHERE id=?", effectiveCustomer) : null;
  const vehicle = effectiveVehicle ? await one(db, "SELECT * FROM vehicle WHERE id=?", effectiveVehicle) : null;
  if (effectiveCustomer && !customer) return { error: fail("Cliente no encontrado", 404) };
  if (effectiveVehicle && !vehicle) return { error: fail("Vehículo no encontrado", 404) };
  if (vehicle && (!customer || vehicle.customer_id !== customer.id)) return { error: fail("Selecciona un vehículo perteneciente al cliente") };
  const inputLines = Array.isArray(data.lines) ? data.lines : [];
  let labor = 0, parts = 0; const lines = [];
  for (const line of inputLines) {
    const kind = line?.kind, qty = Number(line?.quantity), price = Number(line?.unit_price_clp), description = String(line?.description || "").trim();
    if (!["product", "service"].includes(kind) || !description || description.length > 200 || !Number.isFinite(qty) || qty <= 0 || !Number.isSafeInteger(price) || price < 0) return { error: fail("Hay una línea de cotización inválida") };
    const productId = line.product_id == null ? null : Number(line.product_id), serviceId = line.service_id == null ? null : Number(line.service_id);
    if ((kind === "product" && serviceId) || (kind === "service" && productId)) return { error: fail("El producto o servicio no coincide con el tipo de línea") };
    if (productId && !await one(db, "SELECT id FROM product WHERE id=?", productId)) return { error: fail("Producto de la cotización no encontrado", 404) };
    if (serviceId && !await one(db, "SELECT id FROM service WHERE id=?", serviceId)) return { error: fail("Servicio de la cotización no encontrado", 404) };
    const total = Math.round(qty * price); if (!Number.isSafeInteger(total)) return { error: fail("El total de la línea es inválido") };
    lines.push({ kind, productId, serviceId, description, qty, price, total });
    if (kind === "service") labor += total; else parts += total;
  }
  if (!lines.length) { labor = Number(data.labor_clp || 0); parts = Number(data.parts_clp || 0); }
  if (![labor, parts].every(v => Number.isSafeInteger(v) && v >= 0)) return { error: fail("Montos de cotización inválidos") };
  const fields = [order?.id ?? null, effectiveCustomer, effectiveVehicle, String(data.description).trim(), labor, parts,
    String(data.prospect_name || "").trim() || null, String(data.prospect_phone || "").trim() || null,
    String(data.prospect_email || "").trim().toLowerCase() || null, String(data.prospect_vehicle || "").trim() || null, data.notes ?? null];
  const now = new Date().toISOString(), statements = []; let quoteId = existing?.id;
  if (existing) {
    if (existing.status !== "draft") return { error: fail("Solo se pueden editar cotizaciones en borrador", 409) };
    statements.push(db.prepare("UPDATE quote SET work_order_id=?,customer_id=?,vehicle_id=?,description=?,labor_clp=?,parts_clp=?,prospect_name=?,prospect_phone=?,prospect_email=?,prospect_vehicle=?,notes=? WHERE id=? AND status='draft'").bind(...fields, existing.id));
    statements.push(db.prepare("DELETE FROM quoteitem WHERE quote_id=?").bind(existing.id));
  } else {
    const inserted = await db.prepare("INSERT INTO quote(work_order_id,customer_id,vehicle_id,prospect_name,prospect_phone,prospect_email,prospect_vehicle,description,labor_clp,parts_clp,status,customer_approved_at,notes,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,'draft',NULL,?,?)").bind(...fields.slice(0, 3), ...fields.slice(6, 10), fields[3], fields[4], fields[5], fields[10], now).run();
    quoteId = inserted.meta.last_row_id;
  }
  for (const line of lines) statements.push(db.prepare("INSERT INTO quoteitem(quote_id,kind,product_id,service_id,description,quantity,unit_price_clp,line_total_clp) VALUES(?,?,?,?,?,?,?,?)").bind(quoteId, line.kind, line.productId, line.serviceId, line.description, line.qty, line.price, line.total));
  if (order) statements.push(db.prepare("UPDATE workorder SET status='quoted',total_clp=? WHERE id=?").bind(labor + parts, order.id));
  await db.batch(statements);
  const saved = await one(db, "SELECT * FROM quote WHERE id=?", quoteId);
  return { quote: saved };
}

export async function handleAdminReads(request, env, user) {
  const url = new URL(request.url), path = url.pathname, method = request.method, db = env.DB;
  if (["/api/v1/sales", "/api/v1/quotes", "/api/v1/quote-requests"].some(p => path === p || path.startsWith(`${p}/`)) && user.role !== "admin") return json({ detail: "Se requiere el rol de administrador" }, 403);
  if (path.startsWith("/api/v1/social/") && user.role !== "admin") return json({ detail: "Se requiere el rol de administrador" }, 403);
  if (method === "GET" && path === "/api/v1/sales") {
    const limit = Math.min(Math.max(Number(url.searchParams.get("limit") || 100), 1), 200), offset = Math.max(Number(url.searchParams.get("offset") || 0), 0);
    const rows = (await db.prepare("SELECT * FROM sale ORDER BY created_at DESC LIMIT ? OFFSET ?").bind(limit, offset).all()).results;
    return json(await Promise.all(rows.map(async sale => ({ ...sale,
      items: (await db.prepare("SELECT * FROM saleitem WHERE sale_id=? ORDER BY id").bind(sale.id).all()).results,
      payments: (await db.prepare("SELECT * FROM payment WHERE sale_id=? ORDER BY created_at").bind(sale.id).all()).results,
    }))));
  }
  if (method === "GET" && path === "/api/v1/quotes") {
    const limit = Math.min(Math.max(Number(url.searchParams.get("limit") || 100), 1), 200), offset = Math.max(Number(url.searchParams.get("offset") || 0), 0);
    const rows = (await db.prepare("SELECT q.*,c.full_name customer_name,v.plate vehicle_plate,w.code order_code FROM quote q LEFT JOIN customer c ON c.id=q.customer_id LEFT JOIN vehicle v ON v.id=q.vehicle_id LEFT JOIN workorder w ON w.id=q.work_order_id ORDER BY q.created_at DESC,q.id DESC LIMIT ? OFFSET ?").bind(limit, offset).all()).results;
    return json(await Promise.all(rows.map(async q => ({ ...q, customer_name: q.customer_name || q.prospect_name, vehicle_plate: q.vehicle_plate || q.prospect_vehicle, lines: (await db.prepare("SELECT * FROM quoteitem WHERE quote_id=? ORDER BY id").bind(q.id).all()).results }))));
  }
  if (method === "GET" && path === "/api/v1/quote-requests") {
    const rows = (await db.prepare("SELECT r.*,c.full_name customer_name,v.plate vehicle_plate FROM quoterequest r JOIN customer c ON c.id=r.customer_id JOIN vehicle v ON v.id=r.vehicle_id ORDER BY r.created_at DESC").all()).results;
    return json(rows);
  }
  if (path === "/api/v1/quotes" && method === "POST") {
    const result = await saveQuote(db, await request.json()); if (result.error) return result.error;
    return json(result.quote, 201);
  }
  const quote = path.match(/^\/api\/v1\/quotes\/(\d+)(?:\/(publish|pdf|email|customer-approval))?$/);
  if (quote) {
    const id = Number(quote[1]), action = quote[2], existing = await one(db, "SELECT * FROM quote WHERE id=?", id);
    if (method === "PUT" && !action) { if (!existing) return fail("Cotización no encontrada", 404); const result = await saveQuote(db, await request.json(), existing); return result.error || json(result.quote); }
    if (!existing) return fail("Cotización no encontrada", 404);
    if (method === "DELETE" && !action) {
      if (existing.status !== "draft") return fail("Solo se pueden eliminar cotizaciones en borrador", 409);
      await db.batch([db.prepare("DELETE FROM quoteitem WHERE quote_id=?").bind(id), db.prepare("DELETE FROM quote WHERE id=? AND status='draft'").bind(id)]);
      return json({ deleted: true });
    }
    if (method === "POST" && action === "publish") {
      if (existing.status !== "draft") return fail("La cotización ya fue publicada o respondida", 409);
      if (!existing.customer_id || !existing.vehicle_id) return fail("Vincula primero un cliente y un vehículo registrados para enviarla al portal");
      const updates = [db.prepare("UPDATE quote SET status='sent' WHERE id=? AND status='draft'").bind(id)];
      if (existing.work_order_id) updates.push(db.prepare("UPDATE workorder SET status='awaiting_approval',total_clp=? WHERE id=?").bind(existing.labor_clp + existing.parts_clp, existing.work_order_id));
      await db.batch(updates); return json(await one(db, "SELECT * FROM quote WHERE id=?", id));
    }
    if (method === "POST" && action === "customer-approval") {
      if (existing.status !== "sent") return fail("Solo se pueden aprobar cotizaciones publicadas al cliente", 409);
      const approved = new URL(request.url).searchParams.get("approved") === "true", status = approved ? "approved" : "rejected";
      const statements = [db.prepare("UPDATE quote SET status=?,customer_approved_at=? WHERE id=?").bind(status, new Date().toISOString(), id)];
      if (existing.work_order_id) statements.push(db.prepare("UPDATE workorder SET status=? WHERE id=?").bind(approved ? "approved" : "quote_rejected", existing.work_order_id));
      await db.batch(statements); return json(await one(db, "SELECT * FROM quote WHERE id=?", id));
    }
    if (method === "GET" && action === "pdf") return fail("Generación PDF aún no está disponible en Cloudflare", 501);
    if (method === "POST" && action === "email") return fail("Envío de cotizaciones por correo requiere migrar la integración Gmail", 501);
  }
  const quoteRequest = path.match(/^\/api\/v1\/quote-requests\/(\d+)\/draft$/);
  if (quoteRequest && method === "POST") {
    const row = await one(db, "SELECT * FROM quoterequest WHERE id=?", Number(quoteRequest[1]));
    if (!row) return fail("Solicitud no encontrada", 404);
    if (row.quote_id) return json(await one(db, "SELECT * FROM quote WHERE id=?", row.quote_id));
    const idResult = await db.prepare("INSERT INTO quote(customer_id,vehicle_id,description,labor_clp,parts_clp,status,created_at) VALUES(?,?,?,0,0,'draft',?)").bind(row.customer_id, row.vehicle_id, row.description.slice(0, 250), new Date().toISOString()).run();
    await db.prepare("UPDATE quoterequest SET status='draft_created',quote_id=? WHERE id=? AND quote_id IS NULL").bind(idResult.meta.last_row_id, row.id).run();
    return json(await one(db, "SELECT * FROM quote WHERE id=?", idResult.meta.last_row_id));
  }
  if (path === "/api/v1/social/brand" && method === "PUT") {
    const d = await request.json(), defaults = { name: "Gudex", tone: "Cercano, claro y profesional", audience: "Conductores y propietarios de vehículos", primary_color: "#ED0606", accent_color: "#FFE600", call_to_action: "Agenda tu atención con nosotros", contact: "", logo_base64: "" };
    const b = { ...defaults, ...(await one(db, "SELECT * FROM socialbrand WHERE id=1") || {}), ...d };
    if (String(b.name).length < 1 || String(b.name).length > 80 || !/^#[0-9a-fA-F]{6}$/.test(b.primary_color) || !/^#[0-9a-fA-F]{6}$/.test(b.accent_color) || String(b.logo_base64).length > 7000000) return fail("Revisa nombre, colores e imagen de marca");
    await db.prepare("INSERT INTO socialbrand(id,name,tone,audience,primary_color,accent_color,call_to_action,contact,logo_base64) VALUES(1,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,tone=excluded.tone,audience=excluded.audience,primary_color=excluded.primary_color,accent_color=excluded.accent_color,call_to_action=excluded.call_to_action,contact=excluded.contact,logo_base64=excluded.logo_base64").bind(b.name,b.tone,b.audience,b.primary_color,b.accent_color,b.call_to_action,b.contact,b.logo_base64).run();
    return json(await one(db, "SELECT * FROM socialbrand WHERE id=1"));
  }
  if (path === "/api/v1/social/brand" && method === "GET") return json(await one(db, "SELECT * FROM socialbrand WHERE id=1") || { id: 1, name: "Gudex", tone: "Cercano, claro y profesional", audience: "Conductores y propietarios de vehículos", primary_color: "#ED0606", accent_color: "#FFE600", call_to_action: "Agenda tu atención con nosotros", contact: "", logo_base64: "" });
  if (path === "/api/v1/social/accounts" && method === "GET") return json(["instagram", "facebook", "linkedin"].map(network => ({ network, connected: false, publishing_available: false, message: "Exportación manual disponible. Publica manualmente en tu cuenta." })));
  if (path === "/api/v1/social/posts" && method === "GET") {
    const rows = (await db.prepare("SELECT id,title,network,format,objective,product_id,source_name,brief,caption,headline,status,planned_at,published_at,created_by,approved_by,generation_method,created_at,updated_at FROM socialpost ORDER BY created_at DESC").all()).results;
    return json(rows);
  }
  const post = path.match(/^\/api\/v1\/social\/posts\/(\d+)$/);
  if (path === "/api/v1/social/posts" && method === "POST") {
    const d = await request.json();
    if (!String(d?.title || "").trim() || !["instagram","facebook","linkedin"].includes(d.network) || !["square","portrait","story"].includes(d.format) || !["sell","inform","engage"].includes(d.objective) || String(d.image_base64 || "").length > 7000000) return fail("Revisa título, red, formato, objetivo e imagen");
    let source = String(d.source_name || "");
    if (d.product_id != null) { const product = await one(db, "SELECT name,active FROM product WHERE id=?", d.product_id); if (!product || !product.active) return fail("El producto no existe o está archivado"); source = product.name; }
    const brand = await one(db, "SELECT * FROM socialbrand WHERE id=1") || { id: 1, name: "Gudex", tone: "Cercano, claro y profesional", audience: "Conductores y propietarios de vehículos", primary_color: "#ED0606", accent_color: "#FFE600", call_to_action: "Agenda tu atención con nosotros", contact: "", logo_base64: "" };
    const now = new Date().toISOString();
    const result = await db.prepare("INSERT INTO socialpost(title,network,format,objective,product_id,source_name,brief,caption,headline,image_base64,brand_snapshot,status,planned_at,published_at,created_by,approved_by,generation_method,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,'draft',NULL,NULL,?,NULL,'manual',?,?)").bind(String(d.title).trim(), d.network, d.format, d.objective, d.product_id ?? null, source, d.brief || "", d.caption || "", d.headline || "", d.image_base64 || "", JSON.stringify(Object.fromEntries(Object.entries(brand).filter(([k]) => k !== "id"))), user.email, now, now).run();
    return json(await one(db, "SELECT * FROM socialpost WHERE id=?", result.meta.last_row_id), 201);
  }
  if (post && method === "GET") { const row = await one(db, "SELECT * FROM socialpost WHERE id=?", Number(post[1])); return row ? json(row) : fail("Publicación no encontrada", 404); }
  if (post && method === "PUT") {
    const id = Number(post[1]), old = await one(db, "SELECT * FROM socialpost WHERE id=?", id), d = await request.json();
    if (!old) return fail("Publicación no encontrada", 404);
    if (!["draft","review"].includes(old.status)) return fail("Vuelve a borrador antes de editar una publicación aprobada", 409);
    if (!String(d?.title || "").trim() || !["instagram","facebook","linkedin"].includes(d.network) || !["square","portrait","story"].includes(d.format) || !["sell","inform","engage"].includes(d.objective) || String(d.image_base64 || "").length > 7000000) return fail("Revisa título, red, formato, objetivo e imagen");
    let source = String(d.source_name || "");
    if (d.product_id != null) { const product = await one(db, "SELECT name,active FROM product WHERE id=?", d.product_id); if (!product || !product.active) return fail("El producto no existe o está archivado"); source = product.name; }
    await db.prepare("UPDATE socialpost SET title=?,network=?,format=?,objective=?,product_id=?,source_name=?,brief=?,caption=?,headline=?,image_base64=?,status='draft',generation_method='manual',updated_at=? WHERE id=?").bind(String(d.title).trim(),d.network,d.format,d.objective,d.product_id ?? null,source,d.brief || "",d.caption || "",d.headline || "",d.image_base64 || "",new Date().toISOString(),id).run();
    return json(await one(db, "SELECT * FROM socialpost WHERE id=?", id));
  }
  const socialAction = path.match(/^\/api\/v1\/social\/posts\/(\d+)\/(generate|status|preview\.png|export)$/);
  const socialPostId = path.match(/^\/api\/v1\/social\/posts\/(\d+)$/);
  if (socialPostId && method === "DELETE") {
    const id = Number(socialPostId[1]), row = await one(db, "SELECT status FROM socialpost WHERE id=?", id);
    if (!row) return fail("Publicación no encontrada", 404);
    if (row.status !== "draft") return fail("Solo se pueden eliminar borradores", 409);
    await db.prepare("DELETE FROM socialpost WHERE id=? AND status='draft'").bind(id).run(); return json({ deleted: true });
  }
  if (socialAction) {
    const id = Number(socialAction[1]), action = socialAction[2], row = await one(db, "SELECT * FROM socialpost WHERE id=?", id);
    if (!row) return fail("Publicación no encontrada", 404);
    if (action === "status" && method === "POST") {
      const d = await request.json(), allowed = { draft: ["review"], review: ["draft","approved"], approved: ["draft","planned","published"], planned: ["draft","approved","published"], published: [] };
      if (!allowed[row.status]?.includes(d.status)) return fail("Transición de estado no permitida", 409);
      if (["review","approved"].includes(d.status) && (!row.caption.trim() || !row.headline.trim())) return fail("Completa el texto y el titular antes de solicitar revisión");
      let planned = null;
      if (d.status === "planned") { if (!d.planned_at || !Number.isFinite(Date.parse(d.planned_at)) || Date.parse(d.planned_at) <= Date.now()) return fail("Selecciona una fecha futura con zona horaria"); planned = new Date(d.planned_at).toISOString(); }
      const published = d.status === "published" ? new Date().toISOString() : row.published_at;
      await db.prepare("UPDATE socialpost SET status=?,planned_at=?,published_at=?,approved_by=?,updated_at=? WHERE id=?").bind(d.status, planned, published, d.status === "approved" ? user.email : d.status === "draft" ? null : row.approved_by, new Date().toISOString(), id).run();
      return json(await one(db, "SELECT * FROM socialpost WHERE id=?", id));
    }
    if (action === "generate" && method === "POST") {
      if (!["draft","review"].includes(row.status)) return fail("Vuelve a borrador antes de generar contenido", 409);
      const d = await request.json(); if (d?.use_ai) return fail("Generación con IA requiere migrar la integración de modelos a Cloudflare", 501);
      const brand = JSON.parse(row.brand_snapshot), product = row.product_id ? await one(db, "SELECT price_clp FROM product WHERE id=?", row.product_id) : null;
      const intro = row.objective === "sell" ? `Conoce ${row.source_name || row.title} en ${brand.name}.` : row.objective === "engage" ? `¿Qué te gustaría saber sobre ${row.source_name || row.title}?` : `En ${brand.name}: ${row.source_name || row.title}.`;
      const price = product ? `Precio: $${Number(product.price_clp).toLocaleString("es-CL")} CLP.` : "";
      const ending = row.network === "instagram" ? (brand.name === "Gudex" ? "#Gudex #CuidadoAutomotriz" : "#CuidadoAutomotriz") : row.network === "facebook" ? "Comparte esta información con quien la necesite." : "Conversemos sobre el cuidado y mantenimiento de vehículos.";
      const caption = [intro,row.brief,price,brand.call_to_action,brand.contact,ending].filter(Boolean).join("\n\n").slice(0,2200), headline = (row.source_name || row.title).slice(0,140);
      await db.prepare("UPDATE socialpost SET caption=?,headline=?,generation_method='template',status='draft',updated_at=? WHERE id=?").bind(caption,headline,new Date().toISOString(),id).run(); return json(await one(db,"SELECT * FROM socialpost WHERE id=?",id));
    }
    if (action === "preview.png" && method === "GET") return fail("La vista previa gráfica requiere migrar el generador de imágenes a Cloudflare",501);
    if (action === "export" && method === "GET") return fail("La exportación PNG requiere migrar el generador gráfico a Cloudflare",501);
  }
  return null;
}
