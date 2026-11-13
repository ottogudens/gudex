import { argon2id } from "hash-wasm";
const json = (value, status = 200) => new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" } });
const passwordProblem = value => typeof value !== "string" || value.length < 6 || value.length > 200 ? "La contraseña debe tener entre 6 y 200 caracteres" : null;
async function hashPassword(password) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  return argon2id({ password, salt, parallelism: 4, iterations: 3, memorySize: 65536, hashLength: 32, outputType: "encoded" });
}

export async function handleUsers(request, env, user) {
  const { pathname: path } = new URL(request.url), method = request.method;
  if (!path.startsWith("/api/v1/users")) return null;
  if (user.role !== "admin") return json({ detail: "Se requiere el rol de administrador" }, 403);
  const read = row => ({ id: row.id, email: row.email, full_name: row.full_name, role: row.role, customer_id: row.customer_id, active: Boolean(row.active), created_at: row.created_at });
  if (path === "/api/v1/users" && method === "GET") {
    const rows = await env.DB.prepare("SELECT * FROM user WHERE role IN ('admin','mechanic') ORDER BY full_name").all();
    return json(rows.results.map(read));
  }
  if (path === "/api/v1/users" && method === "POST") {
    const d = await request.json(), email = String(d?.email || "").trim().toLowerCase(), issue = passwordProblem(d?.password);
    if (!d || !email.includes("@") || !String(d.full_name || "").trim()) return json({ detail: "Datos de usuario inválidos" }, 422);
    if (issue) return json({ detail: issue }, 422);
    if (!['admin', 'mechanic'].includes(d.role || 'mechanic')) return json({ detail: "Rol inválido" }, 422);
    const existing = await env.DB.prepare("SELECT id FROM user WHERE email=?").bind(email).first();
    if (existing) return json({ detail: "Ya existe un usuario con ese correo" }, 409);
    const result = await env.DB.prepare("INSERT INTO user(email,full_name,password_hash,role,customer_id,active,token_version,created_at) VALUES(?,?,?,?,NULL,1,0,?)").bind(email, String(d.full_name).trim(), await hashPassword(d.password), d.role || "mechanic", new Date().toISOString()).run();
    return json(read(await env.DB.prepare("SELECT * FROM user WHERE id=?").bind(result.meta.last_row_id).first()), 201);
  }
  const match = path.match(/^\/api\/v1\/users\/(\d+)(?:\/password)?$/);
  if (!match) return json({ detail: "No encontrado" }, 404);
  const id = Number(match[1]), target = await env.DB.prepare("SELECT * FROM user WHERE id=? AND role IN ('admin','mechanic')").bind(id).first();
  if (!target) return json({ detail: "Usuario del sistema no encontrado" }, 404);
  if (method === "PATCH") {
    const d = await request.json(), name = String(d?.full_name ?? target.full_name).trim(), role = d?.role ?? target.role, active = d?.active ?? Boolean(target.active);
    if (!name || !['admin', 'mechanic'].includes(role)) return json({ detail: "Nombre o rol inválido" }, 422);
    if (target.email === user.email && active === false) return json({ detail: "No puedes desactivar tu propia cuenta" }, 409);
    if (d?.new_password && passwordProblem(d.new_password)) return json({ detail: passwordProblem(d.new_password) }, 422);
    const hash = d?.new_password ? await hashPassword(d.new_password) : target.password_hash;
    await env.DB.prepare("UPDATE user SET full_name=?,role=?,active=?,password_hash=?,token_version=token_version+1 WHERE id=?").bind(name, role, active ? 1 : 0, hash, id).run();
    return json(read(await env.DB.prepare("SELECT * FROM user WHERE id=?").bind(id).first()));
  }
  if (method === "DELETE") {
    if (target.email === user.email) return json({ detail: "No puedes desactivar tu propia cuenta" }, 409);
    await env.DB.prepare("UPDATE user SET active=0,token_version=token_version+1 WHERE id=?").bind(id).run();
    return json({ updated: true });
  }
  return json({ detail: "Método no permitido" }, 405);
}
