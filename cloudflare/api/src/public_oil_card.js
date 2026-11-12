const escapeHtml = value => String(value ?? "").replace(/[&<>\"']/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" })[char]);

function dateLabel(value) {
  if (!value) return "No definida";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "No definida" : new Intl.DateTimeFormat("es-CL", { timeZone: "UTC" }).format(date);
}

function numberLabel(value) {
  return value == null ? "No definido" : `${new Intl.NumberFormat("es-CL").format(value)} km`;
}

function htmlPage(plate, card) {
  const content = card ? `
    <article class="card" aria-label="Tarjeta digital de cambio de aceite">
      <div class="top"><span>GUDEX / SERVITECA</span><span>MANTENCIÓN DIGITAL</span></div>
      <div class="plate">${escapeHtml(plate)}</div>
      <h2>${escapeHtml(`${card.make} ${card.model}`.trim())}</h2>
      <p class="service">${escapeHtml(card.service_name)}</p>
      <div class="grid">
        <div><small>ÚLTIMO SERVICIO</small><strong>${dateLabel(card.performed_at)}</strong></div>
        <div><small>KILOMETRAJE REGISTRADO</small><strong>${numberLabel(card.mileage_km)}</strong></div>
        <div><small>PRÓXIMO CAMBIO · KM</small><strong>${numberLabel(card.next_due_km)}</strong></div>
        <div><small>PRÓXIMO CAMBIO · FECHA</small><strong>${dateLabel(card.next_due_at)}</strong></div>
      </div>
      <section class="used"><h3>Productos del último servicio</h3><div class="grid">
        <div><small>ACEITE UTILIZADO</small><p>${escapeHtml(card.oil_used || "No registrado en este servicio")}</p></div>
        <div><small>FILTROS INSTALADOS</small><p>${escapeHtml(card.filters_used || "No registrados en este servicio")}</p></div>
      </div>${card.customer_note ? `<p class="note"><b>Nota del taller:</b> ${escapeHtml(card.customer_note)}</p>` : ""}</section>
      <p class="foot">La próxima mantención vence por fecha o kilometraje, lo que ocurra primero. Confirma con el taller si cambian las condiciones de uso.</p>
    </article>` : plate ? '<p class="empty" role="status">No hay una tarjeta pública disponible para esta patente. Verifica el dato o consulta al taller.</p>' : "";
  return `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>Tarjeta digital de aceite · Gudex</title><style>
    :root{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;color:#f6f7fa;background:#111318}*{box-sizing:border-box}body{margin:0;min-height:100vh;background:radial-gradient(circle at 80% 0%,#43211d,#111318 55%);padding:24px}main{max-width:760px;margin:48px auto}a{color:#ffdb56}.brand{font-size:14px;letter-spacing:.2em;color:#ffdb56;font-weight:800}h1{font-size:clamp(32px,6vw,54px);line-height:1.05;margin:18px 0 12px}.intro{color:#bfc3cc;max-width:55ch}form{display:flex;gap:8px;margin:28px 0}input{min-width:0;flex:1;padding:15px 16px;border-radius:13px;border:1px solid #535866;background:#22262e;color:white;font:inherit;text-transform:uppercase}button{border:0;border-radius:13px;padding:15px 22px;background:#e2231a;color:white;font-weight:800;font:inherit;cursor:pointer}.card{border:1px solid #50545f;border-radius:26px;padding:clamp(24px,5vw,40px);background:linear-gradient(145deg,#272b33,#171a20);box-shadow:0 24px 70px #0008}.top{display:flex;justify-content:space-between;gap:16px;font-size:11px;font-weight:800;letter-spacing:.15em;color:#ffdc5b}.plate{font-size:clamp(40px,9vw,72px);font-weight:900;letter-spacing:.04em;margin-top:25px}h2{margin:0;font-size:23px}.service{color:#ffdc5b;margin:8px 0 25px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.grid div{background:#ffffff0c;border:1px solid #ffffff18;border-radius:15px;padding:18px}small{display:block;color:#b6bac4;font-size:11px;letter-spacing:.09em;margin-bottom:8px}strong{font-size:clamp(18px,4vw,25px)}.used{margin-top:26px;border-top:1px solid #ffffff26;padding-top:20px}.used h3{font-size:18px;margin:0 0 14px}.used p{margin:0;line-height:1.45;white-space:pre-wrap;overflow-wrap:anywhere}.note{line-height:1.5;white-space:pre-wrap;overflow-wrap:anywhere}.foot{color:#b6bac4;font-size:13px;line-height:1.5;margin:24px 0 0}.empty{padding:20px;border:1px solid #555;border-radius:15px;color:#d7d9df}@media(max-width:500px){form{flex-direction:column}.grid{grid-template-columns:1fr}.top{flex-direction:column}}
    </style></head><body><main><a href="https://gudex.cl">← Volver a Gudex</a><p class="brand">GUDEX / PUCÓN</p><h1>Tu cambio de aceite, ahora digital.</h1><p class="intro">Consulta la próxima mantención por patente. Solo se muestran tarjetas autorizadas por el taller; la ficha completa está en el portal del cliente.</p><form method="get"><label for="patente" hidden>Patente del vehículo</label><input id="patente" name="patente" required maxlength="16" autocomplete="off" placeholder="Ingresa tu patente" value="${escapeHtml(plate)}"><button type="submit">Ver tarjeta</button></form>${content}</main></body></html>`;
}

export async function publicOilCard(request, env) {
  const url = new URL(request.url);
  const rawPlate = url.searchParams.get("patente") || "";
  const plate = rawPlate.replace(/[^A-Za-z0-9]/g, "").toUpperCase().slice(0, 8);
  let card = null;
  if (plate.length >= 4) {
    const vehicle = await env.DB.prepare("SELECT id,plate,make,model FROM vehicle WHERE plate=? AND public_service_card_enabled=1").bind(plate).first();
    if (vehicle) {
      card = await env.DB.prepare("SELECT service_name,performed_at,mileage_km,next_due_km,next_due_at,oil_used,filters_used,customer_note FROM oilservicecard WHERE vehicle_id=?").bind(vehicle.id).first();
      if (!card) card = await env.DB.prepare("SELECT e.plan_name AS service_name,e.performed_at,e.mileage_km,COALESCE(e.next_due_km,CASE WHEN e.interval_km IS NOT NULL THEN e.mileage_km+e.interval_km END) AS next_due_km,COALESCE(e.next_due_at,CASE WHEN e.interval_days IS NOT NULL THEN datetime(e.performed_at,'+'||e.interval_days||' days') END) AS next_due_at,e.oil_used,e.filters_used,'' AS customer_note FROM maintenanceexecution e JOIN maintenanceplan p ON p.id=e.plan_id WHERE e.vehicle_id=? AND p.category='oil' ORDER BY e.performed_at DESC,e.id DESC LIMIT 1").bind(vehicle.id).first();
      if (card) card = { ...card, make: vehicle.make, model: vehicle.model };
    }
  }
  return new Response(htmlPage(plate, card), { headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "private, no-store, max-age=0", "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer", "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'" } });
}
