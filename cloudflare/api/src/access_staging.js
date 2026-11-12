const WEB_ORIGIN = "https://gudexapp-staging.pages.dev";
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

export default {
  async fetch(request, env) {
    const url = new URL(request.url), path = url.pathname, method = request.method, origin = request.headers.get("Origin");
    if (method === "OPTIONS") return new Response(null, { status: 204, headers: { "Access-Control-Allow-Origin": WEB_ORIGIN, "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS", "Access-Control-Allow-Headers": "Authorization, Content-Type", "Access-Control-Max-Age": "600", "Vary": "Origin" } });
    if (method === "GET" && path === "/health") {
      try { await env.DB.prepare("SELECT 1").first(); return json({ status: "ok", database: "ok" }, 200, origin); }
      catch { return json({ status: "unavailable", database: "error" }, 503, origin); }
    }
    const user = await authorizedUser(request, env);
    if (!user) return json({ detail: "Inicia sesión con Cloudflare Access para continuar" }, 401, origin);
    if (method === "POST" && path === "/auth/access") return json({ access_token: "cloudflare-access", token_type: "bearer", role: user.role, full_name: user.full_name, expires_in: 28800 }, 200, origin);
    try {
      const fields = "id,full_name,rut,email,phone,notes,created_at,archived_at";
      if (method === "GET" && path === "/api/v1/customers") {
        const limit = Math.min(Math.max(Number(url.searchParams.get("limit") || 100), 1), 500);
        const offset = Math.max(Number(url.searchParams.get("offset") || 0), 0);
        const q = url.searchParams.get("q"), include = url.searchParams.get("include_archived") === "true";
        const { results } = await env.DB.prepare(`SELECT ${fields} FROM customer WHERE (?=1 OR archived_at IS NULL) AND (? IS NULL OR full_name LIKE '%'||?||'%') ORDER BY full_name LIMIT ? OFFSET ?`).bind(include ? 1 : 0, q, q, limit, offset).all();
        return json(results, 200, origin);
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
