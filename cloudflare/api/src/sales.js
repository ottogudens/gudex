const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" } });
const fail = (detail, status = 422) => json({ detail }, status);
const one = (db, sql, ...args) => db.prepare(sql).bind(...args).first();

export async function handleSales(request, env, user) {
  const url = new URL(request.url), path = url.pathname, method = request.method, db = env.DB;
  if (!path.startsWith("/api/v1/sales")) return null;
  if (user.role !== "admin") return fail("Se requiere el rol de administrador", 403);
  if (method === "POST" && path === "/api/v1/sales") {
    const d = await request.json();
    if (!Array.isArray(d?.lines) || !d.lines.length) return fail("La venta requiere al menos un ítem");
    const discount = Number(d.discount_clp || 0); if (!Number.isSafeInteger(discount) || discount < 0) return fail("El descuento no puede ser negativo");
    if (d.customer_id && !await one(db, "SELECT id FROM customer WHERE id=? AND archived_at IS NULL", d.customer_id)) return fail("Cliente no encontrado", 404);
    if (d.vehicle_id) { const vehicle = await one(db, "SELECT customer_id FROM vehicle WHERE id=?", d.vehicle_id); if (!vehicle || (d.customer_id && vehicle.customer_id !== d.customer_id)) return fail("Vehículo no válido para el cliente indicado", 409); }
    if (d.work_order_id) {
      const order = await one(db, "SELECT * FROM workorder WHERE id=?", d.work_order_id);
      if (!order || (d.customer_id && order.customer_id !== d.customer_id) || (d.vehicle_id && order.vehicle_id !== d.vehicle_id)) return fail("Orden de trabajo no válida para la venta", 409);
      const existing = await one(db, "SELECT * FROM sale WHERE work_order_id=? ORDER BY created_at DESC LIMIT 1", d.work_order_id);
      if (existing) return fail(`La orden ${order.code} ya tiene un cobro. Recupera la venta ${existing.receipt_code} en el POS.`, 409);
    }
    let subtotal = 0; const lines = [], stock = new Map();
    for (const line of d.lines) {
      const quantity = Number(line?.quantity), unit = Number(line?.unit_price_clp), description = String(line?.description || "").trim(), productId = line?.product_id == null ? null : Number(line.product_id);
      if (!Number.isFinite(quantity) || quantity <= 0 || !Number.isSafeInteger(unit) || unit < 0 || !description || description.length > 200) return fail("Cantidad, descripción o precio inválido");
      const total = Math.round(quantity * unit); if (!Number.isSafeInteger(total)) return fail("Total de línea inválido");
      if (productId) stock.set(productId, (stock.get(productId) || 0) + quantity);
      lines.push({ productId, description, quantity, unit, total }); subtotal += total;
    }
    const total = subtotal - discount; if (total < 0) return fail("El descuento supera el subtotal");
    if (!Number.isSafeInteger(subtotal) || !Number.isSafeInteger(total)) return fail("El total de la venta es inválido");
    for (const [id, quantity] of stock) if (!await one(db, "SELECT id FROM product WHERE id=? AND active=1", id)) return fail(`Producto ${id} no encontrado`, 404);
    const invalidStock = [...stock].map(([id, quantity]) => `SELECT id FROM product WHERE id=${id} AND (active=0 OR stock_quantity<${quantity})`).join(" UNION ALL ");
    const receipt = `V-${new Date().toISOString().slice(2,10).replaceAll("-","")}-${crypto.randomUUID().slice(0,6).toUpperCase()}`, now = new Date().toISOString();
    const insert = db.prepare(`INSERT INTO sale(receipt_code,customer_id,vehicle_id,work_order_id,subtotal_clp,discount_clp,total_clp,status,created_at) SELECT ?,?,?,?,?,?,?,?,? WHERE NOT EXISTS (${invalidStock || "SELECT 1 WHERE 0"})`).bind(receipt,d.customer_id ?? null,d.vehicle_id ?? null,d.work_order_id ?? null,subtotal,discount,total,total ? "open" : "paid",now);
    const statements = [insert];
    for (const line of lines) statements.push(db.prepare("INSERT INTO saleitem(sale_id,product_id,description,quantity,unit_price_clp,line_total_clp) SELECT id,?,?,?,?,? FROM sale WHERE receipt_code=?").bind(line.productId,line.description,line.quantity,line.unit,line.total,receipt));
    for (const [id, quantity] of stock) {
      statements.push(db.prepare("UPDATE product SET stock_quantity=stock_quantity-? WHERE id=? AND active=1 AND stock_quantity>=? AND EXISTS(SELECT 1 FROM sale WHERE receipt_code=?)").bind(quantity,id,quantity,receipt));
      statements.push(db.prepare("INSERT INTO stockmovement(product_id,quantity_change,reason,reference,created_at) SELECT ?,?,'pos_sale',?,? WHERE EXISTS(SELECT 1 FROM sale WHERE receipt_code=?)").bind(id,-quantity,receipt,now,receipt));
    }
    const results = await db.batch(statements);
    if (!results[0]?.meta?.changes) return fail("Stock insuficiente para uno o más productos", 409);
    const sale = await one(db, "SELECT * FROM sale WHERE receipt_code=?", receipt);
    return json({ ...sale, items: (await db.prepare("SELECT * FROM saleitem WHERE sale_id=? ORDER BY id").bind(sale.id).all()).results }, 201);
  }
  const paymentMatch = path.match(/^\/api\/v1\/sales\/(\d+)\/payments$/);
  if (paymentMatch && method === "POST") {
    const id = Number(paymentMatch[1]), d = await request.json(), sale = await one(db, "SELECT * FROM sale WHERE id=?", id);
    if (!sale) return fail("Venta no encontrada", 404);
    const amount = Number(d?.amount_clp), methodName = String(d?.method || "");
    if (!Number.isSafeInteger(amount) || amount <= 0) return fail("El monto debe ser mayor que cero");
    if (["mercado_pago", "mercado_pago_checkout"].includes(methodName)) return fail("Checkout Mercado Pago aún no está configurado en Cloudflare", 503);
    if (!["cash","card","transfer"].includes(methodName)) return fail("Medio de pago no admitido");
    if (sale.status === "paid") return fail("La venta ya está pagada", 409);
    const reference = `CF-${crypto.randomUUID()}`, now = new Date().toISOString();
    const accountName = { cash: "Caja principal", transfer: "Banco y transferencias", card: "Tarjetas" }[methodName];
    await db.prepare("INSERT INTO cashaccount(name,kind,active,created_at) SELECT ?,?,?,? WHERE NOT EXISTS(SELECT 1 FROM cashaccount WHERE name=?)").bind(accountName, { cash: "cash", transfer: "bank", card: "card" }[methodName], 1, now, accountName).run();
    const account = await one(db, "SELECT id FROM cashaccount WHERE name=? AND active=1", accountName);
    if (!account) return fail("La cuenta de caja asociada al pago no está habilitada", 503);
    const paymentInsert = db.prepare("INSERT INTO payment(sale_id,method,amount_clp,status,provider_reference,created_at) SELECT ?,?,?,'recorded',?,? WHERE EXISTS(SELECT 1 FROM sale WHERE id=? AND status!='paid' AND total_clp>=?+COALESCE((SELECT SUM(amount_clp) FROM payment WHERE sale_id=? AND status='recorded'),0)) AND NOT EXISTS(SELECT 1 FROM payment WHERE sale_id=? AND status='pending_external')").bind(id,methodName,amount,reference,now,id,amount,id,id);
    const statements = [paymentInsert, db.prepare("INSERT INTO cashmovement(account_id,direction,amount_clp,status,source_type,source_id,payment_id,customer_id,vehicle_id,work_order_id,category,note,reference,counterparty,reversal_of_id,created_by_email,occurred_at,created_at) SELECT ?, 'income', ?, 'recorded','sale_payment',s.id,p.id,s.customer_id,s.vehicle_id,s.work_order_id,'venta',?,p.provider_reference,NULL,NULL,?,p.created_at,? FROM sale s JOIN payment p ON p.sale_id=s.id WHERE s.id=? AND p.provider_reference=? AND NOT EXISTS(SELECT 1 FROM cashmovement WHERE payment_id=p.id)").bind(account.id,amount,`Cobro venta ${sale.receipt_code}`,user.email,now,id,reference)];
    statements.push(db.prepare("UPDATE sale SET status='paid' WHERE id=? AND total_clp<=COALESCE((SELECT SUM(amount_clp) FROM payment WHERE sale_id=? AND status='recorded'),0)").bind(id,id));
    if (sale.work_order_id) statements.push(db.prepare("UPDATE workorder SET status='delivered' WHERE id=? AND status='ready' AND EXISTS(SELECT 1 FROM sale WHERE id=? AND status='paid')").bind(sale.work_order_id,id));
    if (sale.customer_id) statements.push(db.prepare("INSERT INTO loyaltytransaction(customer_id,sale_id,points,kind,note,created_at) SELECT ?,?,CAST(?/1000 AS INTEGER),'earned',?,? FROM sale WHERE id=? AND status='paid' AND ? > 0 AND NOT EXISTS(SELECT 1 FROM loyaltytransaction WHERE sale_id=?)").bind(sale.customer_id,id,sale.total_clp,`Compra ${sale.receipt_code}`,now,id,sale.total_clp,id));
    const results = await db.batch(statements);
    if (!results[0]?.meta?.changes) return fail("El pago supera el saldo de la venta o existe un cobro externo pendiente", 409);
    const payment = await one(db, "SELECT * FROM payment WHERE provider_reference=?", reference);
    return json(await one(db, "SELECT * FROM payment WHERE id=?", payment.id), 201);
  }
  const mpCancel = path.match(/^\/api\/v1\/sales\/(\d+)\/mercado-pago\/cancel$/);
  if (mpCancel && method === "POST") return fail("Checkout Mercado Pago aún no está configurado en Cloudflare", 503);
  const receipt = path.match(/^\/api\/v1\/sales\/(\d+)\/receipt\.pdf$/);
  if (receipt && method === "GET") return fail("Generación de comprobantes PDF requiere migrar la plantilla a Cloudflare", 501);
  if (/^\/api\/v1\/sales\/\d+\/mercado-pago\/checkout$/.test(path) && method === "POST") return fail("Checkout Mercado Pago requiere migrar y configurar sus secretos en Cloudflare", 503);
  return null;
}
