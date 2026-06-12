// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Polls /build-manifest.json and listens for SW update events.
/// When a new version is detected it sets [updateAvailable] to true.
///
/// The "acknowledged version" pattern prevents the dialog from reappearing
/// for the same server build after the user taps "Update Now":
///   - On update tap:  localStorage[_kAcked] = serverBuildId  (saved before reload)
///   - On next check:  if serverBuildId == localStorage[_kAcked]  →  skip dialog
///
/// Usage:
///   AppUpdateService.instance.start();      // call once in main()
///   AppUpdateService.instance.updateAvailable  // ValueNotifier<bool>
///   AppUpdateService.reload();              // call from "Update Now" button
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  // Injected at build time via --dart-define=APP_BUILD_ID=<git-hash>.
  // Defaults to 'dev' when not injected; 'dev' disables the manifest comparison.
  static const String _buildId =
      String.fromEnvironment('APP_BUILD_ID', defaultValue: 'dev');

  // localStorage key: version the user last explicitly updated to.
  static const String _kAcked    = '_acked_build_id';
  // localStorage key: version detected as new but not yet acked (for reload()).
  static const String _kDetected = '_detected_build_id';
  // sessionStorage key: set before reload() so in-flight SW events are ignored.
  static const String _kReloading = '_sw_reloading';

  final ValueNotifier<bool> updateAvailable = ValueNotifier<bool>(false);

  Timer? _initialCheckTimer;
  Timer? _periodicTimer;
  bool _checking = false;
  bool _disposed = false;

  // ── Public API ──────────────────────────────────────────────────────────────

  void start() {
    if (!kIsWeb) return;
    _setupSwListener();
    // Defer the first manifest check so it does not compete with app startup
    // (Firebase init, auth resolution, Firestore streams, WebSocket connect).
    // The periodic timer and visibility/online listeners ensure coverage after
    // the initial delay.
    _initialCheckTimer = Timer(const Duration(seconds: 8), _checkForUpdate);
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _checkForUpdate(),
    );
    _setupVisibilityListener();
    _setupOnlineListener();
  }

  Future<void> checkNow() => _checkForUpdate();

  /// Clear all SW caches and reload.
  ///
  /// Stores the detected build ID as "acknowledged" so the dialog does not
  /// reappear for the same version after the page reloads.
  static void reload() {
    if (!kIsWeb) return;

    // Acknowledge the version the user is updating to so it is not re-detected.
    final detected = html.window.localStorage[_kDetected] ?? '';
    if (detected.isNotEmpty) {
      html.window.localStorage[_kAcked] = detected;
      html.window.localStorage.remove(_kDetected);
    }

    // Guard: tells the SW controllerchange handler in index.html to do a second
    // silent reload rather than signalling another update.
    html.window.sessionStorage.remove('_sw_update_ready');
    html.window.sessionStorage[_kReloading] = '1';

    // Clear all SW caches so the next load fetches fresh files, then reload.
    js.context.callMethod('_clearAllCachesAndReload');
  }

  void dispose() {
    _disposed = true;
    _initialCheckTimer?.cancel();
    _initialCheckTimer = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  void _setupSwListener() {
    // Suppress everything during an in-progress update reload.
    if (html.window.sessionStorage[_kReloading] == '1') {
      // Fallback: clear the flag after 15 s in case no controllerchange fires.
      Timer(const Duration(seconds: 15), () {
        html.window.sessionStorage.remove(_kReloading);
      });
      return;
    }

    // SW signalled before Flutter mounted — re-verify via manifest check rather
    // than showing immediately (the manifest check gates on the acked version).
    // Small delay so startup (auth + Firebase) completes before the HTTP fetch.
    if (html.window.sessionStorage['_sw_update_ready'] == '1') {
      Timer(const Duration(seconds: 3), _checkForUpdate);
      return;
    }

    // React in real-time when index.html's controllerchange handler fires.
    html.window.on['swupdateready'].listen((_) async {
      if (updateAvailable.value) return;
      if (html.window.sessionStorage[_kReloading] == '1') return;
      // Re-verify via manifest so we don't show the dialog for a version that
      // was already acknowledged (e.g. stale SW event after update-reload).
      await _checkForUpdate();
    });
  }

  void _setupVisibilityListener() {
    html.document.addEventListener('visibilitychange', (_) {
      if (html.document.visibilityState == 'visible') _checkForUpdate();
    });
  }

  void _setupOnlineListener() {
    html.window.addEventListener('online', (_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    if (_checking || _disposed || updateAvailable.value) return;
    if (html.window.sessionStorage[_kReloading] == '1') return;
    _checking = true;
    try {
      final uri = Uri.parse(
        '/build-manifest.json?_=${DateTime.now().millisecondsSinceEpoch}',
      );
      final response = await http
          .get(uri, headers: {
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Pragma': 'no-cache',
          })
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final serverBuildId = (data['buildId'] as String? ?? '').trim();

      if (serverBuildId.isEmpty || serverBuildId == 'dev') return;

      final ackedId = html.window.localStorage[_kAcked] ?? '';

      // User already updated to this exact version → skip.
      if (ackedId.isNotEmpty && serverBuildId == ackedId) return;

      // Compiled version matches server → up to date.
      if (_buildId != 'dev' && serverBuildId == _buildId) {
        // Persist so future checks (after the compiled ID becomes stale) still
        // recognise this as the last-acked version.
        html.window.localStorage[_kAcked] = serverBuildId;
        return;
      }

      // Dev build with no prior ack: initialise baseline silently so the very
      // first load does not trigger a spurious update dialog.
      if (ackedId.isEmpty && _buildId == 'dev') {
        html.window.localStorage[_kAcked] = serverBuildId;
        return;
      }

      // Genuine new version — store it so reload() can acknowledge it.
      html.window.localStorage[_kDetected] = serverBuildId;
      updateAvailable.value = true;
    } catch (_) {
      // Network error / offline — silently skip; next interval will retry.
    } finally {
      _checking = false;
    }
  }
}
