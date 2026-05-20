// FCM Web Service Worker — handles background push notifications on Flutter Web.
// Must stay at web/firebase-messaging-sw.js (served from root of app origin).

importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey:            'AIzaSyAlpSt1cS_J-zNm0gaIXn1R2zuNbYnlplk',
  authDomain:        'trade-kosh.firebaseapp.com',
  projectId:         'trade-kosh',
  storageBucket:     'trade-kosh.firebasestorage.app',
  messagingSenderId: '421918726497',
  appId:             '1:421918726497:web:2e1208377f635c08d48d20',
});

const messaging = firebase.messaging();

// Background message handler — fires when app is NOT in foreground.
messaging.onBackgroundMessage((payload) => {
  const { title, body } = payload.notification ?? {};
  if (!title) return;
  self.registration.showNotification(title, {
    body:  body  ?? '',
    icon:  '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data:  payload.data ?? {},
  });
});
