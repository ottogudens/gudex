const API_ORIGIN = "https://gudexapp-api-staging.agenciaskalechile.workers.dev";

export async function onRequest(context) {
  const { request, next } = context;
  const { pathname } = new URL(request.url);

  // Pages Functions uses a catch-all so existing FastAPI-style routes such as
  // /auth/token and /api/v1/... can keep their paths. Static Flutter assets
  // pass through unchanged.
  if (!pathname.startsWith("/api/") && !pathname.startsWith("/auth/") && pathname !== "/health") {
    return next();
  }

  const upstream = new Request(`${API_ORIGIN}${pathname}${new URL(request.url).search}`, request);
  const forwardedHeaders = new Headers(upstream.headers);
  const assertion = request.headers.get("Cf-Access-Jwt-Assertion");
  if (assertion) forwardedHeaders.set("Cf-Access-Jwt-Assertion", assertion);

  return fetch(new Request(upstream, { headers: forwardedHeaders, redirect: "manual" }));
}
