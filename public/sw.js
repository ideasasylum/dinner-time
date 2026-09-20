const VERSION = "dinner-time-v21";
// Fonts and icons never change under the same name, so they are cache-first. Everything else, the pages and
// the code, is network-first: the cache is a safety net for the kitchen wifi dropping, never a speed layer.
// Cache-first on app.css or app.js would leave a cook one deploy behind, looking at the previous design.
const IMMUTABLE = ["/favicon.svg"];
const PRECACHE = ["/app.css", "/app.js", "/manifest.json", "/favicon.svg", "/icons/icon-192.png", "/icons/icon-512.png",
                  "/fonts/barlow-sc-500.woff2", "/fonts/barlow-sc-700.woff2"];

const immutable = path => IMMUTABLE.includes(path) || path.startsWith("/icons/") || path.startsWith("/fonts/");

self.addEventListener("install", e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(PRECACHE)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return;

  if (immutable(url.pathname)) {
    e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(res => {
      if (res.ok) caches.open(VERSION).then(c => c.put(req, res.clone()));
      return res;
    })));
    return;
  }

  e.respondWith(fetch(req).then(res => {
    if (res.ok) caches.open(VERSION).then(c => c.put(req, res.clone()));
    return res;
  }).catch(() => caches.match(req).then(hit => hit || new Response(
    "<h1>Offline</h1><p>Dinner Time can't reach the server. The plans you've opened before still work.</p>",
    { headers: { "Content-Type": "text/html; charset=utf-8" }, status: 503 }))));
});

self.addEventListener("push", e => {
  let data = { title: "Dinner Time", body: "", url: "/", tag: "dinner" };
  try { data = Object.assign(data, e.data.json()); } catch (_) { if (e.data) data.body = e.data.text(); }
  e.waitUntil(self.registration.showNotification(data.title, {
    body: data.body, tag: data.tag, renotify: true, icon: "/icons/icon-192.png", badge: "/icons/badge.png",
    vibrate: [200, 100, 200], data: { url: data.url }
  }));
});

self.addEventListener("notificationclick", e => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || "/";
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(list => {
    const open = list.find(c => "focus" in c);
    if (open) { open.navigate(url); return open.focus(); }
    return self.clients.openWindow(url);
  }));
});
