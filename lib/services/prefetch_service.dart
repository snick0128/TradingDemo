import 'dart:async';
import '../data/services/backend_api_service.dart';
import '../services/persistence_service.dart';

/// Background prefetch service.
///
/// Proactively fetches watchlist, portfolio, positions, and orders at a
/// staggered interval so screens render instantly from cache on open.
///
/// Design principles:
///   • Staggered start — spread the first fetches across 5s to avoid a
///     burst of parallel requests at login time.
///   • Per-category TTL — market data refreshes more often than static data.
///   • Error-silent — failures are swallowed; screens fall back to cached data.
///   • Pause on disconnect — stops fetching when WS feed is degraded to
///     avoid hammering an already-struggling backend.
///
/// Usage:
///   final prefetch = PrefetchService(api: apiService, persist: persistenceService);
///   prefetch.start();   // call after login
///   prefetch.stop();    // call on logout / app background
class PrefetchService {
  PrefetchService({
    required BackendApiService api,
    required PersistenceService persist,
  })  : _api = api,
        _persist = persist;

  final BackendApiService   _api;
  final PersistenceService  _persist;

  String? _userId;

  Timer? _marketTimer;
  Timer? _portfolioTimer;
  bool   _running = false;
  bool   _paused  = false;

  // Stagger intervals to spread backend load
  static const _marketInterval    = Duration(seconds: 30);
  static const _portfolioInterval = Duration(minutes: 2);

  void setUserId(String userId) { _userId = userId; }

  void start() {
    if (_running) return;
    _running = true;

    // Stagger first fetches so they don't all fire at t=0
    Future.delayed(const Duration(seconds: 2),  _prefetchMarket);
    Future.delayed(const Duration(seconds: 7),  _prefetchPortfolio);

    _marketTimer = Timer.periodic(_marketInterval,    (_) => _prefetchMarket());
    _portfolioTimer = Timer.periodic(_portfolioInterval, (_) => _prefetchPortfolio());
  }

  void stop() {
    _running = false;
    _marketTimer?.cancel();
    _portfolioTimer?.cancel();
    _marketTimer = null;
    _portfolioTimer = null;
  }

  /// Pause prefetching (e.g. when backend is degraded or app is in background).
  void pause()  { _paused = true;  }
  void resume() { _paused = false; }

  // ── Prefetch tasks ────────────────────────────────────────────────────────────

  Future<void> _prefetchMarket() async {
    if (!_running || _paused) return;
    try {
      final data = await _api.getAllMarketData();
      // Extract price map and persist for offline-first rendering
      final prices = <String, double>{};
      for (final item in data) {
        final sym = item['symbol'] as String?;
        final ltp = (item['ltp'] as num?)?.toDouble();
        if (sym != null && ltp != null && ltp > 0) prices[sym] = ltp;
      }
      if (prices.isNotEmpty) await _persist.savePrices(prices);
    } catch (_) {
      // Silently fail — stale cache remains valid
    }
  }

  Future<void> _prefetchPortfolio() async {
    if (!_running || _paused || _userId == null) return;
    try {
      final resp = await _api.getPortfolio(_userId!);
      final items = resp['data'];
      if (items is List && items.isNotEmpty) {
        await _persist.savePortfolio(items.cast<Map<String, dynamic>>());
      }
    } catch (_) {}
  }
}
