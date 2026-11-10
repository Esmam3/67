// Offline service worker for the Prometheus PWA.
//
// Strategy: runtime caching. Same-origin GET assets (JS, CSS, WASM, icons) are
// cached as they load, so after the first online visit the app — including the
// in-browser obfuscator (wasmoon + Lua sources) — works fully offline.
// Navigations fall back to the cached app shell when offline. /api/ is never
// cached (it needs the server).

const CACHE = "prometheus-pwa-v1"

self.addEventListener("install", (event) => {
  self.skipWaiting()
  event.waitUntil(caches.open(CACHE).then((c) => c.add("./")))
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys()
      await Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
      await self.clients.claim()
    })(),
  )
})

self.addEventListener("fetch", (event) => {
  const { request } = event
  if (request.method !== "GET") return

  const url = new URL(request.url)
  if (url.origin !== self.location.origin) return
  if (url.pathname.startsWith("/api/")) return // server endpoint: always network

  // Navigations: network-first, fall back to the cached shell when offline.
  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request)
        .then((res) => {
          caches.open(CACHE).then((c) => c.put("./", res.clone())).catch(() => {})
          return res
        })
        .catch(async () => (await caches.match("./")) || (await caches.match(request)) || Response.error()),
    )
    return
  }

  // Assets: cache-first, then network (and cache the result).
  event.respondWith(
    caches.match(request).then(
      (cached) =>
        cached ||
        fetch(request)
          .then((res) => {
            if (res.ok && res.type === "basic") {
              const copy = res.clone()
              caches.open(CACHE).then((c) => c.put(request, copy)).catch(() => {})
            }
            return res
          })
          .catch(() => cached || Response.error()),
    ),
  )
})
