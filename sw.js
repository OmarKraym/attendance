// Offline cache for the attendance app.
// To publish a new version: change VERSION below, then upload the files.
// Open apps will show "نسخة جديدة ... تحديث الآن" and switch when the user taps it.
const VERSION = 'v3';
const CACHE = 'attendance-' + VERSION;
const ASSETS = [
  './',
  './index.html',
  './manifest.webmanifest',
  './vendor/xlsx.full.min.js',
  './vendor/supabase.js',
  './config.js',
  './fonts/fonts.css',
  './fonts/cairo-arabic-wght-normal.woff2',
  './fonts/cairo-latin-wght-normal.woff2',
  './fonts/cairo-latin-ext-wght-normal.woff2',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/maskable-512.png',
  './icons/apple-touch-icon.png',
  './icons/favicon-64.png'
];

self.addEventListener('install', event => {
  // cache: 'reload' skips the browser's HTTP cache so a new version gets fresh files.
  event.waitUntil(
    caches.open(CACHE).then(cache => cache.addAll(ASSETS.map(url => new Request(url, { cache: 'reload' }))))
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k.startsWith('attendance-') && k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// The page asks for this when the user taps "تحديث الآن".
self.addEventListener('message', event => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});

// Cache first: the app opens instantly and works with no connection.
// Attendance data is never here — it lives in the browser's storage, not in requests.
self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // Supabase calls go straight to the network

  // config.js: network first, so changing the Supabase settings takes effect without a new VERSION.
  if (url.pathname.endsWith('/config.js')) {
    event.respondWith(
      fetch(req).then(res => {
        if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); }
        return res;
      }).catch(() => caches.match(req, { ignoreSearch: true }))
    );
    return;
  }

  event.respondWith(
    caches.match(req, { ignoreSearch: true }).then(hit => {
      if (hit) return hit;
      return fetch(req).then(res => {
        if (res.ok && res.type === 'basic') {
          const copy = res.clone();
          caches.open(CACHE).then(cache => cache.put(req, copy));
        }
        return res;
      }).catch(() => req.mode === 'navigate' ? caches.match('./index.html') : Response.error());
    })
  );
});
