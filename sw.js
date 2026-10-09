'use strict';
const CACHE='daleel-shell-v2';
const FILES=['./','./index.html','./manifest.webmanifest','./icon.svg','./logo.png','./icon-192.png','./icon-512.png','./icon-maskable.png'];
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(FILES)).then(()=>self.skipWaiting()))});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('daleel-shell-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',event=>{const u=new URL(event.request.url);if(event.request.method!=='GET'||u.origin!==self.location.origin)return;
 if(event.request.mode==='navigate'){event.respondWith(fetch(event.request).then(r=>{if(r.ok){const c=r.clone();caches.open(CACHE).then(cache=>cache.put('./index.html',c))}return r}).catch(()=>caches.match('./index.html')));return}
 if(FILES.some(p=>new URL(p,self.registration.scope).pathname===u.pathname))event.respondWith(caches.match(event.request).then(cached=>cached||fetch(event.request)));
});
