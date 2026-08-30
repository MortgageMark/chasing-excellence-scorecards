/* Chasing Excellence Scorecards — service worker
 *
 * Deliberately minimal. It caches the icons and the manifest so an installed
 * PWA has its chrome offline, and NOTHING else.
 *
 * index.html is never cached. The whole app is that one file and it ships
 * often; a cached shell means a deploy silently lands as a no-op and you spend
 * an hour proving the code you just wrote is actually running. The time
 * tracker ships with no service worker at all for exactly this reason. If this
 * ever grows into a real offline cache, the app shell needs a version stamp
 * tied to APP_RELEASE and a skipWaiting/claim dance — do not bolt it on here
 * without that.
 */
const CACHE = 'ces-static-v1';
const ASSETS = [
  '/manifest.json',
  '/icon-192.png',
  '/icon-512.png',
  '/icon-maskable-512.png',
  '/apple-touch-icon.png',
  '/favicon-32.png'
];

self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)).catch(() => {}));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  if (url.origin !== location.origin) return;          // never touch Supabase
  if (req.mode === 'navigate') return;                 // HTML always from network
  if (!ASSETS.includes(url.pathname)) return;          // everything else: network

  e.respondWith(
    caches.match(req).then(hit => hit || fetch(req).then(res => {
      if (res && res.ok) {
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(req, copy)).catch(() => {});
      }
      return res;
    }))
  );
});
