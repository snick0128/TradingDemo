/// GlobalToast — Root-level overlay toast system.
///
/// Renders toasts directly into the root Navigator's Overlay, so they always
/// appear above drawers, bottom sheets, dialogs, and any presented route.
///
/// Usage (same API as AppToast):
///   GlobalToast.success(context, 'Order placed!');
///   GlobalToast.error(context, 'Insufficient balance.');
///   GlobalToast.warning(context, 'Market closing soon.');
///   GlobalToast.info(context, 'Price alert triggered.');

import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme.dart';

// ── Toast entry ───────────────────────────────────────────────────────────────

enum _ToastType { success, error, warning, info }

class _ToastEntry {
  final String message;
  final _ToastType type;
  final Duration duration;
  _ToastEntry(this.message, this.type, this.duration);
}

// ── Global queue manager ──────────────────────────────────────────────────────

class _ToastManager {
  _ToastManager._();
  static final _ToastManager instance = _ToastManager._();

  OverlayEntry? _currentEntry;
  final Queue<_ToastEntry> _queue = Queue();
  bool _showing = false;

  void enqueue(_ToastEntry entry, BuildContext context) {
    _queue.addLast(entry);
    if (!_showing) _showNext(context);
  }

  void _showNext(BuildContext context) {
    if (_queue.isEmpty) {
      _showing = false;
      return;
    }
    _showing = true;
    final entry = _queue.removeFirst();

    // Find the root overlay — above all routes, drawers, sheets, dialogs
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) {
      _showing = false;
      return;
    }

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (_) => _ToastWidget(
        entry: entry,
        onDismissed: () {
          overlayEntry.remove();
          _currentEntry = null;
          // Small gap between toasts
          Future.delayed(const Duration(milliseconds: 120), () {
            _showNext(context);
          });
        },
      ),
    );

    _currentEntry = overlayEntry;
    overlay.insert(overlayEntry);
  }

  /// Dismiss current toast immediately (e.g. before showing a new one)
  void dismissCurrent() {
    // The widget handles its own removal via onDismissed
  }
}

// ── Public API ────────────────────────────────────────────────────────────────

class GlobalToast {
  GlobalToast._();

  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(context, message, _ToastType.success, duration);
  }

  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(context, message, _ToastType.error, duration);
  }

  static void warning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(context, message, _ToastType.warning, duration);
  }

  static void info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(context, message, _ToastType.info, duration);
  }

  static void _show(
    BuildContext context,
    String message,
    _ToastType type,
    Duration duration,
  ) {
    _ToastManager.instance.enqueue(
      _ToastEntry(message, type, duration),
      context,
    );
  }
}

// ── Toast widget ──────────────────────────────────────────────────────────────

class _ToastWidget extends StatefulWidget {
  final _ToastEntry entry;
  final VoidCallback onDismissed;

  const _ToastWidget({required this.entry, required this.onDismissed});

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnim = Tween<double>(begin: 40, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );

    // Slide in
    _ctrl.forward();

    // Auto-dismiss after duration
    Future.delayed(widget.entry.duration, () {
      if (mounted) _dismiss();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted) return;
    _ctrl.reverse().then((_) {
      if (mounted) widget.onDismissed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomPad = mq.padding.bottom + 16;

    final (bgColor, icon) = switch (widget.entry.type) {
      _ToastType.success => (const Color(0xFF1B5E20), LucideIcons.checkCircle),
      _ToastType.error   => (const Color(0xFFB71C1C), LucideIcons.xCircle),
      _ToastType.warning => (const Color(0xFFE65100), LucideIcons.alertCircle),
      _ToastType.info    => (const Color(0xFF0D47A1), LucideIcons.info),
    };

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottomPad,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, _slideAnim.value),
          child: Opacity(opacity: _fadeAnim.value, child: child),
        ),
        child: GestureDetector(
          onTap: _dismiss,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.entry.message,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Tap to dismiss hint
                  Icon(
                    LucideIcons.x,
                    size: 14,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
