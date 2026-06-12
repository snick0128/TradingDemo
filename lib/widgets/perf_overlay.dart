import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/services/live_market_service.dart';
import '../services/device_tier.dart';
import '../services/performance_monitor.dart';
import '../services/subscription_manager.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PerfOverlay
// ─────────────────────────────────────────────────────────────────────────────

/// Floating performance badge rendered on top of [child].
/// Completely transparent (returns [child] unmodified) in release builds.
///
/// Placement — add once at the top of the widget tree (e.g., inside
/// MaterialApp.builder) and pass the [LiveMarketService] reference:
///
/// ```dart
/// builder: (context, child) {
///   return PerfOverlay(
///     marketService: _tradingStore.liveMarketService,
///     child: child ?? const SizedBox.shrink(),
///   );
/// }
/// ```
class PerfOverlay extends StatelessWidget {
  final Widget child;
  final LiveMarketService? marketService;

  const PerfOverlay({
    super.key,
    required this.child,
    this.marketService,
  });

  @override
  Widget build(BuildContext context) {
    // ── Release builds: zero overhead ────────────────────────────────────────
    if (!kDebugMode) return child;

    return Stack(
      children: [
        child,
        Positioned(
          top: 44,
          right: 8,
          child: _PerfBadge(marketService: marketService),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Badge (internal)
// ─────────────────────────────────────────────────────────────────────────────

class _PerfBadge extends StatefulWidget {
  final LiveMarketService? marketService;
  const _PerfBadge({this.marketService});

  @override
  State<_PerfBadge> createState() => _PerfBadgeState();
}

class _PerfBadgeState extends State<_PerfBadge> {
  // Polled values (snapshot — not streams)
  double _msgsPerSec = 0.0;
  int _activeSubs = 0;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Poll msg/s and active subs once per second.
    // FPS / frame metrics come from ValueListenableBuilder — no polling needed.
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final diag = widget.marketService?.tickBatchDiagnostics;
      final msgs = (diag?['messagesReceivedPerSecond'] as double?) ?? 0.0;
      final subs = SubscriptionManager.instance.activeSymbolCount;
      if (msgs != _msgsPerSec || subs != _activeSubs) {
        setState(() {
          _msgsPerSec = msgs;
          _activeSubs = subs;
        });
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Chain ValueListenableBuilders for FPS / frame metrics so they update
    // independently without rebuilding any parent widget.
    return ValueListenableBuilder<DeviceTier>(
      valueListenable: DeviceTierDetector.tier,
      builder: (_, tier, __) => ValueListenableBuilder<double>(
        valueListenable: PerformanceMonitor.instance.fps,
        builder: (_, fpsVal, __) => ValueListenableBuilder<double>(
          valueListenable: PerformanceMonitor.instance.avgFrameMs,
          builder: (_, avgMs, __) => ValueListenableBuilder<int>(
            valueListenable: PerformanceMonitor.instance.jankyCount,
            builder: (_, janky, __) => _Badge(
              tier: tier,
              fps: fpsVal,
              avgMs: avgMs,
              janky: janky,
              activeSubs: _activeSubs,
              msgsPerSec: _msgsPerSec,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Leaf badge widget — pure, no state, no timers
// ─────────────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final DeviceTier tier;
  final double fps;
  final double avgMs;
  final int janky;
  final int activeSubs;
  final double msgsPerSec;

  const _Badge({
    required this.tier,
    required this.fps,
    required this.avgMs,
    required this.janky,
    required this.activeSubs,
    required this.msgsPerSec,
  });

  Color get _fpsColor {
    if (fps >= 50) return const Color(0xFF4CAF50); // green
    if (fps >= 30) return const Color(0xFFFFC107); // amber
    return const Color(0xFFF44336);                 // red
  }

  @override
  Widget build(BuildContext context) {
    // Format: [H] 58fps 14ms 0j 42subs 180msg/s
    final text =
        '[${tier.label}] '
        '${fps.toStringAsFixed(0)}fps '
        '${avgMs.toStringAsFixed(0)}ms '
        '${janky}j '
        '${activeSubs}subs '
        '${msgsPerSec.toStringAsFixed(0)}msg/s';

    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xCC000000),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _fpsColor,
            decoration: TextDecoration.none,
            letterSpacing: 0,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
