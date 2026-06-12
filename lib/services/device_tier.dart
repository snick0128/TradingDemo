// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;

import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Device Tier
// ─────────────────────────────────────────────────────────────────────────────

enum DeviceTier { high, mid, low }

extension DeviceTierConfig on DeviceTier {
  /// Recommended tick-batch flush interval for this tier.
  Duration get batchInterval => switch (this) {
    DeviceTier.high => const Duration(milliseconds: 16),
    DeviceTier.mid  => const Duration(milliseconds: 24),
    DeviceTier.low  => const Duration(milliseconds: 33),
  };

  /// Number of strikes to subscribe and display on each side of ATM.
  int get strikeRadius => switch (this) {
    DeviceTier.high => 8,
    DeviceTier.mid  => 6,
    DeviceTier.low  => 4,
  };

  String get label => switch (this) {
    DeviceTier.high => 'H',
    DeviceTier.mid  => 'M',
    DeviceTier.low  => 'L',
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Detector
// ─────────────────────────────────────────────────────────────────────────────

/// Detects device performance capability once at startup and exposes it as a
/// [ValueNotifier<DeviceTier>].
///
/// Detection is synchronous (JS interop) and never mutates after [detect] returns.
/// Non-web platforms and any JS errors fall back to [DeviceTier.mid].
///
/// Usage:
///   // In main(), after WidgetsFlutterBinding.ensureInitialized():
///   DeviceTierDetector.detect();
///
///   // Anywhere:
///   final radius = DeviceTierDetector.tier.value.strikeRadius;
class DeviceTierDetector {
  DeviceTierDetector._();

  static final ValueNotifier<DeviceTier> tier =
      ValueNotifier<DeviceTier>(DeviceTier.mid);

  /// Detect the device tier and write [tier].
  /// Safe to call multiple times — detection only runs once.
  static bool _detected = false;
  static void detect() {
    if (_detected) return;
    _detected = true;

    if (!kIsWeb) {
      // Native platforms: default MID. Could use Platform.numberOfProcessors
      // but it's unnecessary for the current web-only app.
      debugPrint('[DeviceTier] Non-web — defaulting to MID');
      return;
    }

    try {
      // ── CPU cores ────────────────────────────────────────────────────────────
      // navigator.hardwareConcurrency: number of logical processor cores.
      // Spec: https://html.spec.whatwg.org/#dom-workerglobalscope-hardwareconcurrency
      // Availability: Chrome, Firefox, Safari 15+, Edge — very broad.
      final cores =
          (js.context['navigator']['hardwareConcurrency'] as num?)?.toInt() ?? 4;

      // ── Heap limit (Chrome only) ─────────────────────────────────────────────
      // window.performance.memory is a Chrome extension not in the spec.
      // Firefox and Safari will throw — caught below.
      int? heapLimitBytes;
      try {
        final perf = js.context['performance'];
        if (perf != null) {
          final mem = perf['memory'];
          if (mem != null) {
            heapLimitBytes =
                (mem['jsHeapSizeLimit'] as num?)?.toInt();
          }
        }
      } catch (_) {
        // Firefox / Safari: performance.memory absent — leave null.
      }

      // ── Classification ───────────────────────────────────────────────────────
      // HIGH: ≥6 cores AND (heap unknown OR >512 MB)
      // LOW:  ≤2 cores OR heap <256 MB
      // MID:  everything else
      final DeviceTier detected;
      if (cores >= 6 &&
          (heapLimitBytes == null || heapLimitBytes > 512 * 1024 * 1024)) {
        detected = DeviceTier.high;
      } else if (cores <= 2 ||
          (heapLimitBytes != null && heapLimitBytes < 256 * 1024 * 1024)) {
        detected = DeviceTier.low;
      } else {
        detected = DeviceTier.mid;
      }

      tier.value = detected;

      final heapMb = heapLimitBytes != null
          ? '${(heapLimitBytes / (1024 * 1024)).round()} MB'
          : 'unknown';
      debugPrint(
        '[DeviceTier] Detected: $detected  '
        '(cores=$cores, heapLimit=$heapMb)',
      );
    } catch (e) {
      // Any unexpected JS interop error → safe default.
      tier.value = DeviceTier.mid;
      debugPrint('[DeviceTier] Detection error ($e) — defaulting to MID');
    }
  }
}
