import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Performance Monitor
// ─────────────────────────────────────────────────────────────────────────────

/// Collects per-frame timing data from `SchedulerBinding` and publishes
/// rolling metrics once per second through [ValueNotifier]s.
///
/// All four notifiers are safe to listen from any widget.
///
/// Usage:
///   // In main():
///   PerformanceMonitor.instance.start();
///
///   // In a widget:
///   ValueListenableBuilder<double>(
///     valueListenable: PerformanceMonitor.instance.fps,
///     builder: (_, v, __) => Text('${v.toStringAsFixed(0)}fps'),
///   )
class PerformanceMonitor {
  PerformanceMonitor._();
  static final PerformanceMonitor instance = PerformanceMonitor._();

  // Ring buffer — 120 slots covers 2 s at 60 fps.
  static const int _kRingSize = 120;
  final _durations = List<double>.filled(_kRingSize, 0.0); // ms per frame
  int _head = 0;
  int _count = 0;
  int _jankyThisInterval = 0; // frames > 33.3 ms (< 30 fps) since last publish

  // ── Public metrics ──────────────────────────────────────────────────────────
  final fps        = ValueNotifier<double>(60.0);
  final avgFrameMs = ValueNotifier<double>(16.7);
  final p90FrameMs = ValueNotifier<double>(16.7);
  final jankyCount = ValueNotifier<int>(0); // janky frames in the last second

  // ── Lifecycle ───────────────────────────────────────────────────────────────
  Timer? _publishTimer;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _publishTimer = Timer.periodic(const Duration(seconds: 1), (_) => _publish());
    debugPrint('[PerformanceMonitor] Started');
  }

  void stop() {
    if (!_started) return;
    _started = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _publishTimer?.cancel();
    _publishTimer = null;
    debugPrint('[PerformanceMonitor] Stopped');
  }

  // ── Frame callback ──────────────────────────────────────────────────────────
  // Called by Flutter after every vsync — must be allocation-free.
  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final ms = t.totalSpan.inMicroseconds / 1000.0;
      _durations[_head] = ms;
      _head = (_head + 1) % _kRingSize;
      if (_count < _kRingSize) _count++;
      if (ms > 33.3) _jankyThisInterval++;
    }
  }

  // ── Publish (every 1 s) ─────────────────────────────────────────────────────
  void _publish() {
    if (_count == 0) return;

    // Copy the last [_count] samples from the ring buffer in chronological order.
    final samples = List<double>.generate(
      _count,
      (i) => _durations[(_head - _count + i + _kRingSize) % _kRingSize],
    );
    samples.sort(); // O(n log n) on ≤120 items — negligible

    final sum = samples.fold(0.0, (a, b) => a + b);
    final avg = sum / samples.length;
    final p90 = samples[(samples.length * 0.9).floor().clamp(0, samples.length - 1)];

    avgFrameMs.value = avg;
    p90FrameMs.value = p90;
    fps.value = (avg > 0 ? 1000.0 / avg : 60.0).clamp(0.0, 120.0);
    jankyCount.value = _jankyThisInterval;
    _jankyThisInterval = 0;
  }
}
