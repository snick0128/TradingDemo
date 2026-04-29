// File generated from Firebase project config.
// Project: trade-kosh (trade-kosh.firebaseapp.com)

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAlpSt1cS_J-zNm0gaIXn1R2zuNbYnlplk',
    authDomain: 'trade-kosh.firebaseapp.com',
    projectId: 'trade-kosh',
    storageBucket: 'trade-kosh.firebasestorage.app',
    messagingSenderId: '421918726497',
    appId: '1:421918726497:web:2e1208377f635c08d48d20',
    measurementId: 'G-J3T7977GTP',
  );

  // Reuse web config for other platforms until native configs are added.
  static const FirebaseOptions android = web;
  static const FirebaseOptions ios = web;
  static const FirebaseOptions macos = web;
}
