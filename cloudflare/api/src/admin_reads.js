const json = (body, status = 200, headers = {}) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...headers } });
const one = async (db, sql, ...args) => db.prepare(sql).bind(...args).first();

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
  if (path === "/api/v1/social/brand" && method === "GET") return json(await one(db, "SELECT * FROM socialbrand WHERE id=1") || { id: 1, name: "Gudex", tone: "Cercano, claro y profesional", audience: "Conductores y propietarios de vehículos", primary_color: "#ED0606", accent_color: "#FFE600", call_to_action: "Agenda tu atención con nosotros", contact: "", logo_base64: "" });
  if (path === "/api/v1/social/accounts" && method === "GET") return json(["instagram", "facebook", "linkedin"].map(network => ({ network, connected: false, publishing_available: false, message: "Exportación manual disponible. Publica manualmente en tu cuenta." })));
  if (path === "/api/v1/social/posts" && method === "GET") {
    const rows = (await db.prepare("SELECT id,title,network,format,objective,product_id,source_name,brief,caption,headline,status,planned_at,published_at,created_by,approved_by,generation_method,created_at,updated_at FROM socialpost ORDER BY created_at DESC").all()).results;
    return json(rows);
  }
  const post = path.match(/^\/api\/v1\/social\/posts\/(\d+)$/);
  if (post && method === "GET") return json(await one(db, "SELECT * FROM socialpost WHERE id=?", Number(post[1])) || { detail: "Publicación no encontrada" }, (await one(db, "SELECT id FROM socialpost WHERE id=?", Number(post[1]))) ? 200 : 404);
  return null;
}
