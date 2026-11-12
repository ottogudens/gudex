const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" } });
const error = (detail, status) => json({ detail }, status);
function utcDayBounds() {
  const now = new Date();
  return { day: now.toISOString().slice(0, 10), now: now.toISOString() };
}
export async function handleDashboard(request, env, user) {
  const url = new URL(request.url);
  if (url.pathname !== "/api/v1/dashboard") return null;
  if (request.method !== "GET") return null;
  if (user?.role !== "admin") return error("Se requiere el rol de administrador", 403);
  const { day, now } = utcDayBounds(), db = env.DB;
  try {
    const [orderRows, appointmentRows, appointmentCount, lowStockRows, lowStockCount, quotes, sales] = await Promise.all([
      db.prepare("SELECT id,code,status,promised_at,technician_name,vehicle_id,opened_at FROM workorder WHERE status NOT IN ('delivered','cancelled') ORDER BY opened_at DESC").all(),
      db.prepare("SELECT id,starts_at,service_type,status,customer_id,vehicle_id FROM appointment WHERE date(starts_at)=? AND status<>'cancelled' ORDER BY starts_at LIMIT 10").bind(day).all(),
      db.prepare("SELECT COUNT(*) AS count FROM appointment WHERE date(starts_at)=? AND status<>'cancelled'").bind(day).first(),
      db.prepare("SELECT id,name,stock_quantity,minimum_quantity,unit FROM product WHERE active=1 AND stock_quantity<=minimum_quantity ORDER BY name LIMIT 10").all(),
      db.prepare("SELECT COUNT(*) AS count FROM product WHERE active=1 AND stock_quantity<=minimum_quantity").first(),
      db.prepare("SELECT COUNT(*) AS count FROM quote WHERE status='sent'").first(),
      db.prepare("SELECT COALESCE(SUM(total_clp),0) AS total FROM sale WHERE status='paid' AND date(created_at)=?").bind(day).first(),
    ]);
    const activeOrders = orderRows.results || [];
    const overdue = activeOrders.filter(order => order.promised_at && Date.parse(order.promised_at) < Date.parse(now));
    const requests = await db.prepare("SELECT COUNT(*) AS count FROM appointment WHERE status='requested'").first();
    const todayAppointments = Number(appointmentCount?.count || 0);
    return json({
      generated_at: now,
      metrics: {
        active_orders: activeOrders.length,
        overdue_orders: overdue.length,
        today_appointments: todayAppointments,
        requested_appointments: Number(requests?.count || 0),
        low_stock: Number(lowStockCount?.count || 0),
        quotes_pending: Number(quotes?.count || 0),
        sales_today_clp: Number(sales?.total || 0),
      },
      urgent_orders: overdue.slice(0, 8).map(({ id, code, status, promised_at, technician_name, vehicle_id }) => ({ id, code, status, promised_at, technician_name, vehicle_id })),
      today_schedule: appointmentRows.results || [],
      low_stock_items: lowStockRows.results || [],
    });
  } catch { return error("No se pudo cargar el panel principal", 500); }
}
