// web/firebase-messaging-sw.template.js
// COPY THIS FILE to firebase-messaging-sw.js and replace YOUR_* placeholders
// OR use a build script to inject env vars

importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "YOUR_WEB_API_KEY",
  authDomain: "YOUR_AUTH_DOMAIN",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_STORAGE_BUCKET",
  messagingSenderId: "YOUR_MESSAGING_SENDER_ID",
  appId: "YOUR_WEB_APP_ID"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[SW] Background message:', payload);
  self.registration.showNotification(
    payload.notification?.title || 'Medication Reminder',
    {
      body: payload.notification?.body || 'Time for your medication',
      icon: '/icons/Icon-192.png',
      requireInteraction: true,
    }
  );
});