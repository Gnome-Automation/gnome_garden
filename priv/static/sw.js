// Self-unregistering service worker
// This file exists to clean up any previously registered service workers

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', () => {
  self.registration.unregister().then(() => {
    console.log('Service worker unregistered');
  });
});
