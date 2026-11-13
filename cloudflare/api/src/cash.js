const json = (value, status = 200) => new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" } });
const defaults = [["Caja principal", "cash"], ["Banco y transferencias", "bank"], ["Tarjetas", "card"], ["Mercado Pago", "gateway"]];

export async function handleCash(request, env, user) {
  const url = new URL(request.url), path = url.pathname, method = request.method;
  if (!path.startsWith("/api/v1/cash/")) return null;
  if (user.role !== "admin") return json({ detail: "Se requiere el rol de administrador" }, 403);
  const db = env.DB, now = new Date().toISOString();
  const ensureAccounts = async () => {
    for (const [name, kind] of defaults) await db.prepare("INSERT INTO cashaccount(name,kind,active,created_at) SELECT ?,?,?,? WHERE NOT EXISTS (SELECT 1 FROM cashaccount WHERE name=?)").bind(name, kind, 1, now, name).run();
  };
  if (path === "/api/v1/cash/accounts" && method === "GET") {
    await ensureAccounts();
    return json((await db.prepare("SELECT * FROM cashaccount ORDER BY kind,name").all()).results.map(a => ({ ...a, active: Boolean(a.active) })));
  }
  if (path === "/api/v1/cash/accounts" && method === "POST") {
    const d = await request.json(), name = String(d?.name || "").trim(), kind = String(d?.kind || "cash").trim().toLowerCase();
    if (name.length < 2 || name.length > 80) return json({ detail: "Nombre de cuenta inválido" }, 422);
    if (await db.prepare("SELECT id FROM cashaccount WHERE name=?").bind(name).first()) return json({ detail: "Ya existe una caja o cuenta con ese nombre" }, 409);
    const result = await db.prepare("INSERT INTO cashaccount(name,kind,active,created_at) VALUES(?,?,1,?)").bind(name, kind, now).run();
    return json(await db.prepare("SELECT * FROM cashaccount WHERE id=?").bind(result.meta.last_row_id).first(), 201);
  }
  if (path === "/api/v1/cash/summary" && method === "GET") {
    await ensureAccounts();
    const from = url.searchParams.get("from_date"), to = url.searchParams.get("to_date");
    const clauses = ["status='recorded'"], args = [];
    if (from) { clauses.push("occurred_at>=?"); args.push(from); }
    if (to) { clauses.push("occurred_at<?"); args.push(to); }
    const rows = (await db.prepare(`SELECT * FROM cashmovement WHERE ${clauses.join(" AND ")}`).bind(...args).all()).results;
    const accounts = (await db.prepare("SELECT * FROM cashaccount ORDER BY name").all()).results;
    const byAccount = accounts.map(account => {
      const entries = rows.filter(row => row.account_id === account.id);
      const incoming = entries.filter(row => ["income", "transfer_in"].includes(row.direction)).reduce((n, row) => n + row.amount_clp, 0);
      const outgoing = entries.filter(row => ["expense", "transfer_out", "reversal"].includes(row.direction)).reduce((n, row) => n + row.amount_clp, 0);
      return { account: { ...account, active: Boolean(account.active) }, incoming_clp: incoming, outgoing_clp: outgoing, balance_clp: incoming - outgoing };
    });
    const income = rows.filter(row => row.direction === "income").reduce((n, row) => n + row.amount_clp, 0), expense = rows.filter(row => ["expense", "reversal"].includes(row.direction)).reduce((n, row) => n + row.amount_clp, 0);
    const open = (await db.prepare("SELECT * FROM cashclosure WHERE status='open' ORDER BY opened_at").all()).results;
    return json({ income_clp: income, expense_clp: expense, net_clp: income - expense, accounts: byAccount, open_closures: open });
  }
  if (path === "/api/v1/cash/movements" && method === "GET") {
    const clauses = ["1=1"], args = [];
    for (const [param, column] of [["from_date", "occurred_at >= ?"], ["to_date", "occurred_at < ?"], ["account_id", "account_id = ?"], ["direction", "direction = ?"]]) {
      const value = url.searchParams.get(param); if (value != null && value !== "") { clauses.push(column); args.push(value); }
    }
    const limit = Math.min(Math.max(Number(url.searchParams.get("limit") || 100), 1), 200), offset = Math.max(Number(url.searchParams.get("offset") || 0), 0);
    const rows = (await db.prepare(`SELECT m.*,a.name account_name FROM cashmovement m LEFT JOIN cashaccount a ON a.id=m.account_id WHERE ${clauses.join(" AND ")} ORDER BY m.occurred_at DESC LIMIT ? OFFSET ?`).bind(...args, limit, offset).all()).results;
    return json(rows);
  }
  const d = method === "POST" ? await request.json() : null;
  const account = async id => db.prepare("SELECT * FROM cashaccount WHERE id=? AND active=1").bind(id).first();
  const validAmount = amount => Number.isSafeInteger(amount) && amount > 0;
  const movement = (accountId, direction, amount, source, category, note, reference = null, counterparty = null) => db.prepare("INSERT INTO cashmovement(account_id,direction,amount_clp,status,source_type,source_id,payment_id,customer_id,vehicle_id,work_order_id,category,note,reference,counterparty,reversal_of_id,created_by_email,occurred_at,created_at) VALUES(?,?,?,'recorded',?,NULL,NULL,NULL,NULL,NULL,?,?,?, ?,NULL,?,?,?)").bind(accountId, direction, amount, source, category, note, reference, counterparty, user.email, now, now);
  if (path === "/api/v1/cash/expenses" && method === "POST") {
    const accountRow = await account(d?.account_id), amount = Number(d?.amount_clp), category = String(d?.category || "").trim(), note = String(d?.note || "").trim();
    if (!accountRow) return json({ detail: "Selecciona una caja o cuenta activa" }, 422);
    if (!validAmount(amount) || category.length < 2 || note.length < 2) return json({ detail: "Revisa monto, categoría y detalle del gasto" }, 422);
    for (const [key, table, label] of [["customer_id", "customer", "Cliente"], ["vehicle_id", "vehicle", "Vehículo"], ["work_order_id", "workorder", "Orden de trabajo"]]) if (d[key] && !await db.prepare(`SELECT id FROM ${table} WHERE id=?`).bind(d[key]).first()) return json({ detail: `${label} no encontrado` }, 404);
    const result = await db.prepare("INSERT INTO cashmovement(account_id,direction,amount_clp,status,source_type,source_id,payment_id,customer_id,vehicle_id,work_order_id,category,note,reference,counterparty,reversal_of_id,created_by_email,occurred_at,created_at) VALUES(?,'expense',?,'recorded','manual_expense',NULL,NULL,?,?,?, ?,?,?,?,NULL,?,?,?)").bind(accountRow.id, amount, d.customer_id ?? null, d.vehicle_id ?? null, d.work_order_id ?? null, category, note, d.reference?.trim() || null, d.counterparty?.trim() || null, user.email, now, now).run();
    return json(await db.prepare("SELECT m.*,a.name account_name FROM cashmovement m JOIN cashaccount a ON a.id=m.account_id WHERE m.id=?").bind(result.meta.last_row_id).first(), 201);
  }
  if (path === "/api/v1/cash/transfers" && method === "POST") {
    const from = Number(d?.from_account_id), to = Number(d?.to_account_id), amount = Number(d?.amount_clp);
    if (from === to) return json({ detail: "Selecciona dos cuentas distintas para la transferencia" }, 422);
    if (!validAmount(amount) || !await account(from) || !await account(to)) return json({ detail: "Revisa cuentas activas y monto de transferencia" }, 422);
    const reference = String(d.reference || `TRF-${Date.now()}`), note = String(d.note || "Transferencia interna").trim();
    const outgoing = await movement(from, "transfer_out", amount, "internal_transfer", "transferencia", note, reference);
    const incoming = await movement(to, "transfer_in", amount, "internal_transfer", "transferencia", note, reference);
    const result = await db.batch([outgoing, incoming]);
    const ids = result.map(x => x.meta.last_row_id);
    const rows = await Promise.all(ids.map(id => db.prepare("SELECT m.*,a.name account_name FROM cashmovement m JOIN cashaccount a ON a.id=m.account_id WHERE m.id=?").bind(id).first()));
    return json({ outgoing: rows[0], incoming: rows[1] }, 201);
  }
  if (path === "/api/v1/cash/closures/open" && method === "POST") {
    if (!await account(d?.account_id)) return json({ detail: "Selecciona una caja o cuenta activa" }, 422);
    const open = await db.prepare("SELECT id FROM cashclosure WHERE account_id=? AND status='open'").bind(d.account_id).first();
    if (open) return json({ detail: "Esta caja ya tiene un turno abierto" }, 409);
    const amount = Number(d.opening_amount_clp ?? 0), notes = String(d.notes || "").trim();
    if (!Number.isSafeInteger(amount) || amount < 0 || notes.length > 1000) return json({ detail: "Monto de apertura inválido" }, 422);
    const result = await db.prepare("INSERT INTO cashclosure(account_id,status,opening_amount_clp,closing_amount_clp,expected_amount_clp,difference_clp,notes,opened_by_email,closed_by_email,opened_at,closed_at) VALUES(?,'open',?,NULL,NULL,NULL,?,?,NULL,?,NULL)").bind(d.account_id, amount, notes, user.email, now).run();
    return json(await db.prepare("SELECT * FROM cashclosure WHERE id=?").bind(result.meta.last_row_id).first(), 201);
  }
  const close = path.match(/^\/api\/v1\/cash\/closures\/(\d+)\/close$/);
  if (close && method === "POST") {
    const closure = await db.prepare("SELECT * FROM cashclosure WHERE id=? AND status='open'").bind(Number(close[1])).first();
    if (!closure) return json({ detail: "Turno de caja abierto no encontrado" }, 404);
    const amount = Number(d?.closing_amount_clp), notes = String(d?.notes || "").trim();
    if (!Number.isSafeInteger(amount) || amount < 0) return json({ detail: "Monto de cierre inválido" }, 422);
    const totals = await db.prepare("SELECT COALESCE(SUM(CASE WHEN direction IN ('income','transfer_in') THEN amount_clp ELSE -amount_clp END),0) total FROM cashmovement WHERE account_id=? AND occurred_at>=? AND status='recorded'").bind(closure.account_id, closure.opened_at).first();
    const expected = closure.opening_amount_clp + totals.total;
    await db.prepare("UPDATE cashclosure SET status='closed',closing_amount_clp=?,expected_amount_clp=?,difference_clp=?,notes=?,closed_by_email=?,closed_at=? WHERE id=? AND status='open'").bind(amount, expected, amount - expected, notes || closure.notes, user.email, now, closure.id).run();
    return json(await db.prepare("SELECT * FROM cashclosure WHERE id=?").bind(closure.id).first());
  }
  return null;
}
