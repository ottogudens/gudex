import { argon2id, argon2Verify } from "hash-wasm";

const WEB_ORIGIN = "https://gudexapp-staging.pages.dev";
const encoder = new TextEncoder();
const decoder = new TextDecoder();
const commonPasswords = new Set(["123456", "12345678", "123456789", "1234567890", "qwerty", "qwerty123", "password", "password1", "password123", "abc12345", "qwertyuiop", "11111111", "00000000", "lubricentro", "mecanico", "administrador", "gudex1234"]);

function response(body, status = 200, origin = null) {
  const headers = new Headers({"Content-Type":"application/json; charset=utf-8","Cache-Control":"no-store, max-age=0","X-Content-Type-Options":"nosniff"});
  if (origin === WEB_ORIGIN) { headers.set("Access-Control-Allow-Origin", WEB_ORIGIN); headers.set("Vary", "Origin"); }
  return new Response(JSON.stringify(body), {status, headers});
}
const fail = (status, detail) => ({status, body:{detail}});
const b64u = (bytes) => btoa(String.fromCharCode(...bytes)).replace(/=/g,"").replace(/\+/g,"-").replace(/\//g,"_");
const unb64u = (value) => Uint8Array.from(atob(value.replace(/-/g,"+").replace(/_/g,"/").padEnd(Math.ceil(value.length/4)*4,"=")), c=>c.charCodeAt(0));
async function sign(payload, secret) {
  const head=b64u(encoder.encode(JSON.stringify({alg:"HS256",typ:"JWT"}))), body=b64u(encoder.encode(JSON.stringify(payload)));
  const key=await crypto.subtle.importKey("raw",encoder.encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
  const sig=new Uint8Array(await crypto.subtle.sign("HMAC",key,encoder.encode(`${head}.${body}`)));
  return `${head}.${body}.${b64u(sig)}`;
}
async function verifyToken(token, secret) {
  const parts=token.split("."); if(parts.length!==3) return null;
  let header,payload; try { header=JSON.parse(decoder.decode(unb64u(parts[0]))); payload=JSON.parse(decoder.decode(unb64u(parts[1]))); } catch { return null; }
  if(header.alg!=="HS256" || !payload.sub || !payload.exp || payload.exp<=Math.floor(Date.now()/1000)) return null;
  const key=await crypto.subtle.importKey("raw",encoder.encode(secret),{name:"HMAC",hash:"SHA-256"},false,["verify"]);
  return await crypto.subtle.verify("HMAC",key,unb64u(parts[2]),encoder.encode(`${parts[0]}.${parts[1]}`)) ? payload : null;
}
async function hashPassword(password) {
  const salt=crypto.getRandomValues(new Uint8Array(16));
  return await argon2id({password,salt,parallelism:4,iterations:3,memorySize:65536,hashLength:32,outputType:"encoded"});
}
async function readJson(request) { try { return await request.json(); } catch { return null; } }
const normalizeEmail = value => typeof value === "string" ? value.trim().toLowerCase() : "";
function normalizeRut(value) {
  if(value==null || !String(value).trim()) return null;
  const v=String(value).replace(/[^0-9kK]/g,"").toUpperCase();
  if(v.length<2 || v.length>9 || !/^\d+$/.test(v.slice(0,-1))) throw Error("RUT chileno inválido");
  let sum=0,m=2; for(const d of [...v.slice(0,-1)].reverse()){sum+=Number(d)*m;m=m===7?2:m+1;}
  const n=11-sum%11,expected=n===11?"0":n===10?"K":String(n);
  if(v.at(-1)!==expected) throw Error("Dígito verificador del RUT inválido");
  return `${Number(v.slice(0,-1))}-${expected}`;
}
function validatePassword(password) {
  if(typeof password!=="string" || password.length<6) return "La contraseña debe tener al menos 6 caracteres";
  if(commonPasswords.has(password.toLowerCase())) return "Esa contraseña es demasiado común; elige otra";
  return null;
}
async function auth(request, env, path) {
  const [,scheme,token]=/^\s*(\S+)\s+(.+?)\s*$/.exec(request.headers.get("Authorization")||"")||[];
  if(scheme?.toLowerCase()!=="bearer" || !token) return {error:fail(401,"Autenticación requerida")};
  const claims=await verifyToken(token,env.JWT_SECRET); if(!claims) return {error:fail(401,"Autenticación requerida")};
  const user=await env.DB.prepare("SELECT id,email,full_name,role,customer_id,active,token_version,created_at FROM user WHERE email=?").bind(claims.sub).first();
  if(!user || !user.active || user.role!==claims.role || user.token_version!==(claims.ver??0)) return {error:fail(401,"Autenticación requerida")};
  if(user.role==="customer" && path!=="/api/v1/account/password") return {error:fail(403,"Este recurso no está disponible para clientes")};
  if(user.role!=="admin" && path.startsWith("/api/v1/users")) return {error:fail(403,"Se requiere el rol de administrador")};
  return {user};
}
const userRead = ({id,email,full_name,role,customer_id,active,created_at})=>({id,email,full_name,role,customer_id,active,created_at});
const customerFields = "id,full_name,rut,email,phone,notes,created_at,archived_at";
function normalizeCustomer(data, partial=false) {
  if(!data || typeof data!=="object" || Array.isArray(data)) throw Error("Cuerpo JSON inválido");
  const out={};
  if(!partial || "full_name" in data){const name=String(data.full_name||"").trim().replace(/\s+/g," ");if(name.length<2||name.length>120)throw Error("Ingresa el nombre del cliente");out.full_name=name;}
  if(!partial || "rut" in data) out.rut=normalizeRut(data.rut);
  if(!partial || "email" in data) {const email=normalizeEmail(data.email);if(email.length>254)throw Error("Correo inválido");out.email=email||null;}
  for(const key of ["phone","notes"]) if(!partial||key in data) out[key]=data[key]==null||data[key]===""?null:String(data[key]);
  return out;
}
async function handle(request, env) {
  const url=new URL(request.url), path=url.pathname, method=request.method, origin=request.headers.get("Origin");
  if(method==="OPTIONS") return origin===WEB_ORIGIN ? new Response(null,{status:204,headers:{"Access-Control-Allow-Origin":WEB_ORIGIN,"Access-Control-Allow-Methods":"GET, POST, PATCH, DELETE, OPTIONS","Access-Control-Allow-Headers":"Authorization, Content-Type","Access-Control-Max-Age":"600","Vary":"Origin"}}) : new Response(null,{status:403});
  if(method==="GET"&&path==="/health") {try {await env.DB.prepare("SELECT 1").first();return response({status:"ok",database:"ok"},200,origin);}catch{return response({status:"unavailable",database:"error"},503,origin);}}
  if(method==="POST"&&path==="/auth/token") {
    const raw=await request.text(), form=new URLSearchParams(raw), email=normalizeEmail(form.get("username")), password=form.get("password")||"";
    const user=await env.DB.prepare("SELECT * FROM user WHERE email=?").bind(email).first();
    let valid=false; if(user?.active) {try {valid=await argon2Verify({password,hash:user.password_hash});}catch{valid=false;}}
    if(!valid) return response({detail:"Correo o contraseña incorrectos"},401,origin);
    const access_token=await sign({sub:user.email,role:user.role,ver:user.token_version||0,exp:Math.floor(Date.now()/1000)+28800},env.JWT_SECRET);
    return response({access_token,token_type:"bearer",role:user.role,full_name:user.full_name,expires_in:28800},200,origin);
  }
  if(!path.startsWith("/api/v1/")) return response({detail:"No encontrado"},404,origin);
  const {user, error}=await auth(request,env,path); if(error)return response(error.body,error.status,origin);
  try {
    if(path==="/api/v1/account/password"&&method==="POST") {
      const d=await readJson(request), current=await env.DB.prepare("SELECT * FROM user WHERE id=?").bind(user.id).first();
      if(!d||!await argon2Verify({password:d.current_password||"",hash:current.password_hash})) return response({detail:"La contraseña actual es incorrecta"},401,origin);
      const problem=validatePassword(d.new_password);if(problem)return response({detail:problem},422,origin);
      await env.DB.prepare("UPDATE user SET password_hash=?,token_version=token_version+1 WHERE id=?").bind(await hashPassword(d.new_password),user.id).run();return response({message:"Contraseña actualizada. Inicia sesión nuevamente."},200,origin);
    }
    if(path==="/api/v1/users"&&method==="GET") {const {results}=await env.DB.prepare("SELECT * FROM user WHERE role IN ('admin','mechanic') ORDER BY full_name").all();return response(results.map(userRead),200,origin);}
    if(path==="/api/v1/users"&&method==="POST") {
      const d=await readJson(request),email=normalizeEmail(d?.email),problem=validatePassword(d?.password);if(!d||!email||!d.full_name)return response({detail:"Datos de usuario inválidos"},422,origin);if(problem)return response({detail:problem},422,origin);if(!["admin","mechanic"].includes(d.role||"mechanic"))return response({detail:"Rol inválido"},422,origin);
      const r=await env.DB.prepare("INSERT INTO user(email,full_name,password_hash,role,customer_id,active,token_version,created_at) VALUES(?,?,?,?,NULL,1,0,?)").bind(email,String(d.full_name).trim(),await hashPassword(d.password),d.role||"mechanic",new Date().toISOString()).run();
      const created=await env.DB.prepare("SELECT * FROM user WHERE id=?").bind(r.meta.last_row_id).first();return response(userRead(created),201,origin);
    }
    const um=path.match(/^\/api\/v1\/users\/(\d+)(?:\/(password))?$/);
    if(um&&method==="PATCH") {const d=await readJson(request),id=Number(um[1]),target=await env.DB.prepare("SELECT * FROM user WHERE id=? AND role IN ('admin','mechanic')").bind(id).first();if(!target)return response({detail:"Usuario del sistema no encontrado"},404,origin);if(target.email===user.email&&d?.active===false)return response({detail:"No puedes desactivar tu propia cuenta"},409,origin);const name=d?.full_name??target.full_name,role=d?.role??target.role,active=d?.active??target.active;if(!["admin","mechanic"].includes(role))return response({detail:"Rol inválido"},422,origin);let hash=target.password_hash;if(d?.new_password){const problem=validatePassword(d.new_password);if(problem)return response({detail:problem},422,origin);hash=await hashPassword(d.new_password);}await env.DB.prepare("UPDATE user SET full_name=?,role=?,active=?,password_hash=?,token_version=token_version+1 WHERE id=?").bind(name,role,active?1:0,hash,id).run();return response(userRead(await env.DB.prepare("SELECT * FROM user WHERE id=?").bind(id).first()),200,origin);}
    if(um&&method==="POST"&&um[2]==="password"){const d=await readJson(request),id=Number(um[1]),target=await env.DB.prepare("SELECT * FROM user WHERE id=? AND role IN ('admin','mechanic')").bind(id).first();if(!target)return response({detail:"Usuario del sistema no encontrado"},404,origin);const problem=validatePassword(d?.new_password);if(problem)return response({detail:problem},422,origin);await env.DB.prepare("UPDATE user SET password_hash=?,token_version=token_version+1 WHERE id=?").bind(await hashPassword(d.new_password),id).run();return response({updated:true},200,origin);}
    if(um&&method==="DELETE"){const id=Number(um[1]),target=await env.DB.prepare("SELECT * FROM user WHERE id=? AND role IN ('admin','mechanic')").bind(id).first();if(!target)return response({detail:"Usuario del sistema no encontrado"},404,origin);if(target.email===user.email)return response({detail:"No puedes desactivar tu propia cuenta"},409,origin);await env.DB.prepare("UPDATE user SET active=0,token_version=token_version+1 WHERE id=?").bind(id).run();return response({updated:true},200,origin);}
    if(path==="/api/v1/customers"&&method==="GET") {const limit=Math.min(Math.max(Number(url.searchParams.get("limit")||100),1),500),offset=Math.max(Number(url.searchParams.get("offset")||0),0),q=url.searchParams.get("q"),include=url.searchParams.get("include_archived")==="true";let sql=`SELECT ${customerFields} FROM customer WHERE (?=1 OR archived_at IS NULL) AND (? IS NULL OR full_name LIKE '%'||?||'%') ORDER BY full_name LIMIT ? OFFSET ?`;const {results}=await env.DB.prepare(sql).bind(include?1:0,q,q,limit,offset).all();return response(results,200,origin);}
    if(path==="/api/v1/customers"&&method==="POST") {let d;try{d=normalizeCustomer(await readJson(request));}catch(e){return response({detail:e.message},422,origin);}if(d.rut&&await env.DB.prepare("SELECT id FROM customer WHERE rut=?").bind(d.rut).first())return response({detail:"Ya existe un cliente con ese RUT"},409,origin);if(d.email&&await env.DB.prepare("SELECT id FROM customer WHERE email=?").bind(d.email).first())return response({detail:"Ya existe un cliente con ese correo"},409,origin);const r=await env.DB.prepare("INSERT INTO customer(full_name,rut,email,phone,notes,created_at,archived_at) VALUES(?,?,?,?,?,?,NULL)").bind(d.full_name,d.rut,d.email,d.phone,d.notes,new Date().toISOString()).run();return response(await env.DB.prepare(`SELECT ${customerFields} FROM customer WHERE id=?`).bind(r.meta.last_row_id).first(),201,origin);}
    const cm=path.match(/^\/api\/v1\/customers\/(\d+)$/);
    if(cm&&method==="PATCH") {const id=Number(cm[1]),old=await env.DB.prepare("SELECT * FROM customer WHERE id=?").bind(id).first();if(!old)return response({detail:"Cliente no encontrado"},404,origin);if(old.archived_at)return response({detail:"El cliente está archivado y no puede modificarse"},409,origin);let d;try{d=normalizeCustomer(await readJson(request),true);}catch(e){return response({detail:e.message},422,origin);}const next={...old,...d};for(const field of ["rut","email"])if(d[field]&&await env.DB.prepare(`SELECT id FROM customer WHERE ${field}=? AND id<>?`).bind(d[field],id).first())return response({detail:`Ya existe un cliente con ese ${field}`},409,origin);await env.DB.prepare("UPDATE customer SET full_name=?,rut=?,email=?,phone=?,notes=? WHERE id=?").bind(next.full_name,next.rut,next.email,next.phone,next.notes,id).run();return response(await env.DB.prepare(`SELECT ${customerFields} FROM customer WHERE id=?`).bind(id).first(),200,origin);}
    if(cm&&method==="DELETE") {const id=Number(cm[1]),old=await env.DB.prepare("SELECT id,archived_at FROM customer WHERE id=?").bind(id).first();if(!old)return response({detail:"Cliente no encontrado"},404,origin);if(old.archived_at)return response({deleted:false,archived:true},200,origin);const now=new Date().toISOString();await env.DB.batch([env.DB.prepare("UPDATE customer SET archived_at=? WHERE id=?").bind(now,id),env.DB.prepare("UPDATE user SET active=0,token_version=token_version+1 WHERE customer_id=?").bind(id),env.DB.prepare("UPDATE customeraccesstoken SET used_at=? WHERE customer_id=? AND used_at IS NULL").bind(now,id)]);return response({deleted:false,archived:true},200,origin);}
    return response({detail:"No encontrado"},404,origin);
  } catch(e) { if(/UNIQUE constraint failed/.test(String(e))) return response({detail:"Ya existe un registro con esos datos"},409,origin); return response({detail:"Error interno"},500,origin); }
}
export default {fetch:handle};
