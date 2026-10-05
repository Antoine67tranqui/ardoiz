// Service worker minimal : met en cache la COQUE de l'application (HTML, CSS, JS) pour qu'elle
// s'ouvre même sans réseau et affiche un message clair. Les appels à l'API ne sont JAMAIS
// interceptés ni mis en cache : aucune donnée de carnet ne reste dans le cache du navigateur.
const CACHE = 'carne-web-v1';
const SHELL = [
  './', './index.html', './app.css', './manifest.webmanifest', './config.js',
  './js/main.js', './js/api.js', './js/dom.js', './js/format.js', './js/model.js', './js/state.js', './js/ui.js',
  './js/views/auth.js', './js/views/parties.js', './js/views/debts.js', './js/views/cash.js', './js/views/dashboard.js', './js/views/settings.js', './js/nav.js',
];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin || url.pathname.startsWith('/api/')) return;
  // Réseau d'abord (toujours la dernière version), cache en secours hors connexion.
  event.respondWith(
    fetch(event.request).then((response) => {
      if (response.ok) {
        const copy = response.clone();
        caches.open(CACHE).then((cache) => cache.put(event.request, copy));
      }
      return response;
    }).catch(() => caches.match(event.request).then((hit) => hit ?? Response.error())),
  );
});
