import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

// Must be top-level — Flutter's isolate background handler requirement.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialized before this fires.
  // Log only — system tray notification is shown automatically by FCM SDK.
  debugPrint('[FCM] Background: ${message.notification?.title} — ${message.notification?.body}');
}

/// FCM push notification service.
///
/// Call [NotificationService.instance.initialize()] once in main() after
/// Firebase.initializeApp(), then call [saveTokenForUser()] after login.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  bool _initialized = false;

  /// Initialize FCM: register handlers, request permission, subscribe to
  /// the broadcast topic, and wire all three delivery states.
  ///
  /// [onMessage]  — foreground: show an in-app banner (snackbar, dialog…)
  /// [onTap]      — background/terminated tap: navigate to the right screen
  Future<void> initialize({
    void Function(RemoteMessage message)? onMessage,
    void Function(RemoteMessage? message)? onTap,
  }) async {
    if (_initialized) return;
    _initialized = true;

    // Register background handler FIRST (before any await).
    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

    // Request OS permission (required on Android 13+ and iOS).
    // On web, this triggers the browser's native push-permission dialog.
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    // Subscribe every install to the broadcast topic.
    // Admin can push to "all_users" to reach everyone at once.
    await FirebaseMessaging.instance.subscribeToTopic('all_users');

    // ── Delivery state 1: Foreground ──────────────────────────────────────────
    // Message arrives while app is open. FCM does NOT auto-show a system tray
    // notification on Android/iOS — the app must handle it in-app.
    if (onMessage != null) {
      FirebaseMessaging.onMessage.listen(onMessage);
    }

    // ── Delivery state 2: Background tap ─────────────────────────────────────
    // App was in background (or partially visible). User tapped the system
    // notification. Use this to navigate to a relevant screen.
    FirebaseMessaging.onMessageOpenedApp.listen(
      (msg) => onTap?.call(msg),
    );

    // ── Delivery state 3: Terminated state tap ────────────────────────────────
    // App was fully closed. User tapped the notification to launch the app.
    // getInitialMessage() returns the message that caused the launch.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      // Delay to let the app finish building before any navigation.
      Future.delayed(const Duration(milliseconds: 500), () => onTap?.call(initial));
    }

    // Token refresh — fire-and-forget.
    FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      debugPrint('[FCM] Token refreshed — re-save on next login if needed.');
    });
  }

  /// Returns the current FCM registration token for this device/browser.
  /// On Flutter Web, pass [vapidKey] from Firebase Console → Cloud Messaging → Web Push.
  /// If VAPID key is not set, token will be null on web.
  Future<String?> getToken({String? vapidKey}) async {
    try {
      return await FirebaseMessaging.instance.getToken(vapidKey: vapidKey);
    } catch (e) {
      debugPrint('[FCM] getToken failed: $e');
      return null;
    }
  }
}
