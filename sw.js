/* EAGLES service worker — web push only (no offline caching, so app updates are never stale). */
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) { data = { title: 'EAGLES', body: event.data ? event.data.text() : '' }; }
  const title = data.title || 'EAGLES';
  const options = {
    body: data.body || '',
    icon: 'icon-192.png',
    badge: 'icon-192.png',
    tag: data.tag || undefined,
    renotify: !!data.tag,
    data: { url: data.url || '' },
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const raw = (event.notification.data && event.notification.data.url) || '';
  const q = raw.indexOf('?') >= 0 ? raw.slice(raw.indexOf('?')) : '';
  const target = self.registration.scope + q; // stays inside the app's own folder on GitHub Pages
  event.waitUntil((async () => {
    const list = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of list) {
      if (c.url.startsWith(self.registration.scope)) {
        await c.focus();
        c.postMessage({ type: 'nav', url: q });
        return;
      }
    }
    await self.clients.openWindow(target);
  })());
});
