import 'dart:async';
import 'package:flutter/material.dart';

/// Connection/feed-health status banner.
///
/// Shows a slim, non-blocking banner at the top of any screen when the
/// WebSocket feed is degraded or reconnecting. Dismisses automatically
/// after [autoDismissDuration] once the feed recovers.
///
/// Usage — wrap a screen's body:
///   ConnectionBanner(
///     state: wsState,          // ConnectionBannerState from LiveMarketService
///     child: YourScreenBody(),
///   )
///
/// Or use the standalone [ConnectionStatusChip] inline inside an AppBar.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({
    super.key,
    required this.state,
    required this.child,
  });

  final ConnectionBannerState state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: state.showBanner
              ? _BannerBar(state: state, key: const ValueKey('banner'))
              : const SizedBox.shrink(key: ValueKey('hidden')),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _BannerBar extends StatelessWidget {
  const _BannerBar({super.key, required this.state});

  final ConnectionBannerState state;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(state.status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: colors.$1,
      child: Row(
        children: [
          SizedBox(
            width: 12, height: 12,
            child: state.status == BannerStatus.reconnecting
                ? CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(colors.$2),
                  )
                : Icon(_icon(state.status), size: 12, color: colors.$2),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.message,
              style: TextStyle(
                color: colors.$2,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _colors(BannerStatus s) => switch (s) {
    BannerStatus.reconnecting => (const Color(0xFFFFF3E0), const Color(0xFFE65100)),
    BannerStatus.degraded     => (const Color(0xFFFFF3E0), const Color(0xFFE65100)),
    BannerStatus.recovered    => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
    BannerStatus.offline      => (const Color(0xFFFFEBEE), const Color(0xFFC62828)),
  };

  IconData _icon(BannerStatus s) => switch (s) {
    BannerStatus.reconnecting => Icons.wifi_off_rounded,
    BannerStatus.degraded     => Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
    BannerStatus.recovered    => Icons.check_circle_outline_rounded,
    BannerStatus.offline      => Icons.wifi_off_rounded,
  };
}

/// Inline chip for AppBar or toolbar.
class ConnectionStatusChip extends StatelessWidget {
  const ConnectionStatusChip({super.key, required this.state});

  final ConnectionBannerState state;

  @override
  Widget build(BuildContext context) {
    if (!state.showBanner) return const SizedBox.shrink();
    final color = state.status == BannerStatus.recovered
        ? Colors.green
        : Colors.orange;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 10, height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          state.status == BannerStatus.recovered ? 'Recovered' : 'Reconnecting…',
          style: TextStyle(fontSize: 10, color: color),
        ),
      ]),
    );
  }
}

// ── State model ───────────────────────────────────────────────────────────────

enum BannerStatus { reconnecting, degraded, recovered, offline }

class ConnectionBannerState {
  const ConnectionBannerState({
    required this.status,
    required this.message,
    required this.showBanner,
  });

  final BannerStatus status;
  final String       message;
  final bool         showBanner;

  static const hidden = ConnectionBannerState(
    status:     BannerStatus.recovered,
    message:    '',
    showBanner: false,
  );

  static ConnectionBannerState reconnecting(int attempt) =>
      ConnectionBannerState(
        status:     BannerStatus.reconnecting,
        message:    attempt > 1
            ? 'Market feed disconnected — reconnecting (attempt $attempt)…'
            : 'Market feed disconnected — reconnecting…',
        showBanner: true,
      );

  static const degraded = ConnectionBannerState(
    status:     BannerStatus.degraded,
    message:    'Live prices may be delayed — feed recovering',
    showBanner: true,
  );

  static const recovered = ConnectionBannerState(
    status:     BannerStatus.recovered,
    message:    'Live prices restored',
    showBanner: true,
  );

  static const offline = ConnectionBannerState(
    status:     BannerStatus.offline,
    message:    'No internet connection',
    showBanner: true,
  );
}

// ── Controller ────────────────────────────────────────────────────────────────

/// Manages the banner lifecycle: show on disconnect, auto-hide after recovery.
///
/// Use this in a StatefulWidget alongside [LiveMarketService]:
///
///   late final _banner = ConnectionBannerController();
///
///   @override void initState() {
///     super.initState();
///     _banner.addListener(() => setState(() {}));
///     widget.liveMarket.connectionStateStream.listen(_banner.onConnectionChange);
///   }
///
///   @override Widget build(BuildContext context) =>
///     ConnectionBanner(state: _banner.value, child: ...);
class ConnectionBannerController extends ChangeNotifier {
  static const _autoDismissDelay = Duration(seconds: 3);

  ConnectionBannerState _state = ConnectionBannerState.hidden;
  Timer? _dismissTimer;

  ConnectionBannerState get value => _state;

  void onConnectionChange(WsConnectionStatus cs) {
    _dismissTimer?.cancel();
    _dismissTimer = null;

    if (cs.isConnected) {
      if (_state.showBanner) {
        _state = ConnectionBannerState.recovered;
        notifyListeners();
        _dismissTimer = Timer(_autoDismissDelay, () {
          _state = ConnectionBannerState.hidden;
          notifyListeners();
        });
      }
    } else if (cs.isReconnecting) {
      _state = ConnectionBannerState.reconnecting(cs.attempt ?? 1);
      notifyListeners();
    } else if (cs.isFeedDegraded) {
      _state = ConnectionBannerState.degraded;
      notifyListeners();
    } else if (cs.isDisconnected) {
      _state = ConnectionBannerState.offline;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }
}

// ── Connection status value object (mirrors LiveMarketService state) ─────────

class WsConnectionStatus {
  const WsConnectionStatus._(this._type, [this.attempt]);

  final _WsConnType _type;
  final int? attempt;

  static const connected    = WsConnectionStatus._(_WsConnType.connected);
  static const reconnecting = WsConnectionStatus._(_WsConnType.reconnecting);
  static const feedDegraded = WsConnectionStatus._(_WsConnType.feedDegraded);
  static const disconnected = WsConnectionStatus._(_WsConnType.disconnected);

  factory WsConnectionStatus.reconnectingAttempt(int n) =>
      WsConnectionStatus._(_WsConnType.reconnecting, n);

  bool get isConnected    => _type == _WsConnType.connected;
  bool get isReconnecting => _type == _WsConnType.reconnecting;
  bool get isFeedDegraded => _type == _WsConnType.feedDegraded;
  bool get isDisconnected => _type == _WsConnType.disconnected;
}

enum _WsConnType { connected, reconnecting, feedDegraded, disconnected }
