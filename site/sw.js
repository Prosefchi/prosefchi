// Makes the site readable offline. tool/build_site.dart fills the {{...}}.
//
// No skipWaiting: taking over before the old worker's last page has gone would
// pair that page's HTML with another version's day.js.

const PRECACHE = '{{cache}}';
const RUNTIME = 'prosefchi-runtime';

// Relative, since GitHub Pages serves a project site from a subdirectory.
const ASSETS = {{assets}};

const CALENDARS = {{calendars}};

self.addEventListener('install', (event) => {
  // Atomic: one name that 404s and the worker never installs at all.
  event.waitUntil(caches.open(PRECACHE).then((cache) => cache.addAll(ASSETS)));
});

self.addEventListener('activate', (event) => event.waitUntil(activate()));

async function activate() {
  const names = await caches.keys();
  await Promise.all(
    names
      .filter((name) => name !== PRECACHE && name !== RUNTIME)
      .map((name) => caches.delete(name)),
  );
  // Or the page that registered the worker goes uncontrolled, and only a
  // second visit is available offline.
  await self.clients.claim();
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (CALENDARS.some((name) => url.pathname.endsWith(name))) {
    event.respondWith(freshest(request));
  } else {
    event.respondWith(cached(request));
  }
});

async function cached(request) {
  // ignoreSearch: the day view carries its date in a query string, and
  // ./?date=2026-01-01 is the same document as ./.
  const hit = await caches.match(request, {
    cacheName: PRECACHE,
    ignoreSearch: true,
  });
  return hit || fetch(request);
}

// Network first, last copy second: the calendar is rebuilt every night.
async function freshest(request) {
  const cache = await caches.open(RUNTIME);
  try {
    const response = await fetch(request);
    if (response.ok) await cache.put(request, response.clone());
    return response;
  } catch (error) {
    const hit = await cache.match(request);
    if (hit) return hit;
    throw error;
  }
}
