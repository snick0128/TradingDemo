import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../data/services/market_settings_service.dart';
import '../services/persistence_service.dart';
import '../models/market_settings.dart';
import '../models/trading_models.dart';
import '../state/tab_notifier.dart';
import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../theme.dart';
import '../widgets/backend_error_widget.dart';
import '../widgets/shared_widgets.dart';
import '../widgets/trading_bottom_nav_bar.dart';
import 'advanced_chart_screen.dart';
import 'fno_dashboard_screen.dart';
import 'fno_market_screen.dart';
import 'ipo_screen.dart';
import 'stock_guide_screen.dart';
import 'market_depth_screen.dart';
import 'notifications_center_screen.dart';
import 'options_chain_screen.dart';
import 'sector_heatmap_screen.dart';
import 'time_and_sales_screen.dart';
import 'top_gainers_losers_screen.dart';
import 'universal_search_screen.dart';
import 'market_watch_screen.dart';
import 'portfolio_screen.dart';
import 'stock_detail_screen.dart';
import 'wallet_screen.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
const _kProfit = Color(0xFF00C853);
const _kLoss   = Color(0xFFD50000);

// Shared with MarketWatchScreen — same SharedPreferences key
const _kWatchlistsKey = 'watchlist.lists_v2';

// ─── Lightweight helpers ──────────────────────────────────────────────────────

class _SymStat {
  final int count;
  final DateTime lastDate;
  const _SymStat(this.count, this.lastDate);
}

class _TodayPerf {
  final int totalTrades;
  final double winRate;
  final double realizedPnl;
  const _TodayPerf(this.totalTrades, this.winRate, this.realizedPnl);
}

// ─── DashboardScreen ─────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Snapshotted store values — updated via addListener, never via TradingScope.of
  bool _backendError = false;
  String _backendErrorMessage = '';
  String _userName = '';
  int _unreadNotificationCount = 0;
  double _usedMargin = 0;
  double _balance = 0;
  double _safeLevel = 0;
  List<Stock> _topMovers = const [];
  List<Stock> _watchlist = const [];
  List<Position> _positions = const [];
  List<Holding> _holdings = const [];
  List<Order> _orders = const [];
  List<Stock> _quickTradeStocks = const [];

  bool _isActiveTab = false;
  TradingStore? _store;

  @override
  void initState() {
    super.initState();
    _isActiveTab = activeTabNotifier.value == 0;
    activeTabNotifier.addListener(_onTabVisibilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = TradingScope.read(context);
    if (_store != store) {
      _store?.removeListener(_onStoreChanged);
      _store = store;
      store.addListener(_onStoreChanged);
      _syncFromStore(store);
    }
  }

  void _syncFromStore(TradingStore store) {
    _backendError = store.backendError;
    _backendErrorMessage = store.backendErrorMessage;
    _userName = store.currentUser.name;
    _unreadNotificationCount = store.unreadNotificationCount;
    _usedMargin = store.usedMargin;
    _balance = store.balance;
    _safeLevel = store.rmsSettings.safeLevelRupees;
    _topMovers = store.topMovers.toList();
    _watchlist = _loadPersistedWatchlist(store);
    _positions = store.positions.toList();
    _holdings = store.holdings.toList();
    _orders = store.orders.toList();
    _quickTradeStocks = _buildQuickTrade(store);
  }

  // Read watchlist symbols from SharedPreferences (same store as MarketWatchScreen)
  // and resolve them against the live price universe.
  static List<Stock> _loadPersistedWatchlist(TradingStore store) {
    final saved = PersistenceService.instance.getJson<List<dynamic>>(_kWatchlistsKey);
    if (saved == null || saved.isEmpty) return const [];
    // Collect symbols from all watchlist tabs, preserve order, deduplicate
    final seen = <String>{};
    final symbols = <String>[];
    for (final item in saved) {
      if (item is! Map) continue;
      for (final sym in (item['symbols'] as List<dynamic>? ?? [])) {
        final s = sym as String;
        if (seen.add(s)) symbols.add(s);
      }
    }
    return symbols
        .map(store.stockBySymbolOrNull)
        .whereType<Stock>()
        .toList();
  }

  // Derive most-traded symbols from order history: count DESC, then most recent.
  static List<Stock> _buildQuickTrade(TradingStore store) {
    final Map<String, _SymStat> stats = {};
    for (final o in store.orders) {
      if (o.status != OrderStatus.executed) continue;
      final prev = stats[o.symbol];
      if (prev == null) {
        stats[o.symbol] = _SymStat(1, o.dateTime);
      } else {
        stats[o.symbol] = _SymStat(
          prev.count + 1,
          o.dateTime.isAfter(prev.lastDate) ? o.dateTime : prev.lastDate,
        );
      }
    }
    if (stats.isEmpty) return const [];
    final sorted = stats.entries.toList()
      ..sort((a, b) {
        final c = b.value.count.compareTo(a.value.count);
        if (c != 0) return c;
        return b.value.lastDate.compareTo(a.value.lastDate);
      });
    final result = <Stock>[];
    for (final e in sorted) {
      final s = store.stockBySymbolOrNull(e.key);
      if (s != null) result.add(s);
      if (result.length >= 5) break;
    }
    return result;
  }

  _TodayPerf get _todayPerf {
    final today = DateTime.now();
    final todayOrders = _orders.where((o) {
      if (o.status != OrderStatus.executed) return false;
      final d = o.executedAt ?? o.dateTime;
      return d.year == today.year && d.month == today.month && d.day == today.day;
    }).toList();
    if (todayOrders.isEmpty) return const _TodayPerf(0, 0.0, 0.0);
    final closing = todayOrders.where((o) => o.type == OrderType.sell && o.pnl != null).toList();
    final wins = closing.where((o) => (o.pnl ?? 0) > 0).length;
    final winRate = closing.isEmpty ? 0.0 : (wins / closing.length) * 100;
    final realized = closing.fold<double>(0, (s, o) => s + (o.pnl ?? 0));
    return _TodayPerf(todayOrders.length, winRate, realized);
  }

  void _onStoreChanged() {
    if (_store == null) return;
    final store = _store!;
    final wasError        = _backendError;
    final wasName         = _userName;
    final wasUnread       = _unreadNotificationCount;
    final wasWatchlistLen = _watchlist.length;
    final wasPosLen       = _positions.length;
    final wasMoversEmpty  = _topMovers.isEmpty;
    final wasOrdersLen    = _orders.length;
    final wasQtLen        = _quickTradeStocks.length;
    _syncFromStore(store);
    // Only rebuild on structural changes — tick data goes to individual VLBs.
    final structural =
        _backendError != wasError ||
        _userName != wasName ||
        _unreadNotificationCount != wasUnread ||
        _watchlist.length != wasWatchlistLen ||
        _positions.length != wasPosLen ||
        _topMovers.isEmpty != wasMoversEmpty ||
        _orders.length != wasOrdersLen ||
        _quickTradeStocks.length != wasQtLen;
    if (structural && _isActiveTab) setState(() {});
  }

  void _onTabVisibilityChanged() {
    final active = activeTabNotifier.value == 0;
    if (active == _isActiveTab) return;
    _isActiveTab = active;
    if (active) {
      // Re-read SharedPreferences watchlist in case user modified it on another tab
      if (_store != null) _syncFromStore(_store!);
      setState(() {});
    }
  }

  @override
  void dispose() {
    activeTabNotifier.removeListener(_onTabVisibilityChanged);
    _store?.removeListener(_onStoreChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_backendError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard')),
        backgroundColor: AppColors.background,
        body: BackendErrorWidget(
          message: _backendErrorMessage,
          onRetry: () => TradingScope.read(context).connectLiveBackend(),
        ),
      );
    }

    final hour          = DateTime.now().hour;
    final greeting      = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    final firstName     = _userName.split(' ').first;
    final walletBalance = _balance + _usedMargin;
    final store         = _store!;

    final perf          = _todayPerf;
    final hasWatchlist  = _watchlist.isNotEmpty;
    final hasPositions  = _positions.isNotEmpty;
    final hasHoldings   = _holdings.isNotEmpty;
    final hasQuickTrade = _quickTradeStocks.isNotEmpty;
    final hasToday      = perf.totalTrades > 0;

    final indicesStocks = _topMovers.isNotEmpty
        ? _topMovers
        : ['NIFTY', 'BANKNIFTY', 'SENSEX', 'NIFTYNXT50']
              .map(store.stockBySymbolOrNull)
              .whereType<Stock>()
              .toList();

    return Scaffold(
      appBar: _DashboardAppBar(
        greeting: '$greeting, $firstName',
        unreadCount: _unreadNotificationCount,
      ),
      backgroundColor: AppColors.background,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, TradingBottomNavBar.bottomInset(context)),
        children: [

          // ── 1. Portfolio card ──────────────────────────────────────────
          _BalanceCard(store: store, safeLevel: _safeLevel, walletBalance: walletBalance),
          const SizedBox(height: 8),
          _MarginStrip(store: store, safeLevel: _safeLevel, usedMargin: _usedMargin),
          const SizedBox(height: 16),

          // ── 2. Explore shortcuts — directly after portfolio card ───────
          const _QuickActionsRow(),
          const SizedBox(height: 20),

          // ── 3. Open Positions ──────────────────────────────────────────
          if (hasPositions) ...[
            _SectionHeader(
              title: 'Open Positions',
              onViewAll: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PortfolioScreen())),
            ),
            const SizedBox(height: 8),
            _PositionsSnapshot(positions: _positions.take(3).toList(), store: store),
            const SizedBox(height: 20),
          ],

          // ── 3b. Holdings (CNC/overnight) ───────────────────────────────
          if (hasHoldings) ...[
            _SectionHeader(
              title: 'Holdings',
              onViewAll: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PortfolioScreen())),
            ),
            const SizedBox(height: 8),
            _HoldingsSnapshot(holdings: _holdings.take(3).toList(), store: store),
            const SizedBox(height: 20),
          ],

          // ── 4. Quick Trade (when no watchlist — moved up per spec) ─────
          if (!hasWatchlist && hasQuickTrade) ...[
            const _SectionHeader(title: 'Quick Trade'),
            const SizedBox(height: 8),
            _WatchlistPreview(stocks: _quickTradeStocks.take(4).toList(), store: store),
            const SizedBox(height: 20),
          ],

          // ── 5. Today's Performance ────────────────────────────────────
          if (hasToday) ...[
            _TodayPerformanceCard(
              totalTrades: perf.totalTrades,
              winRate: perf.winRate,
              realizedPnl: perf.realizedPnl,
            ),
            const SizedBox(height: 16),
          ],

          // ── 6. Indices row ─────────────────────────────────────────────
          _IndicesRow(stocks: indicesStocks, store: store),
          const SizedBox(height: 20),

          // ── 7. My Watchlist ────────────────────────────────────────────
          if (hasWatchlist) ...[
            _SectionHeader(
              title: 'My Watchlist',
              actionLabel: 'See All',
              onViewAll: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MarketWatchScreen())),
            ),
            const SizedBox(height: 8),
            _WatchlistPreview(stocks: _watchlist.take(4).toList(), store: store),
            const SizedBox(height: 20),
          ],

          // ── 8. Quick Trade below watchlist (when watchlist exists) ─────
          if (hasWatchlist && hasQuickTrade) ...[
            const _SectionHeader(title: 'Quick Trade'),
            const SizedBox(height: 8),
            _WatchlistPreview(stocks: _quickTradeStocks.take(4).toList(), store: store),
            const SizedBox(height: 20),
          ],

          // ── 9. Top Movers (3 only, View More) ─────────────────────────
          _SectionHeader(
            title: 'Top Movers',
            actionLabel: 'View More',
            onViewAll: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TopGainersLosersScreen())),
          ),
          const SizedBox(height: 8),
          _TopMoversList(store: store),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ─── AppBar ───────────────────────────────────────────────────────────────────

class _DashboardAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String greeting;
  final int unreadCount;
  const _DashboardAppBar({required this.greeting, required this.unreadCount});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 16,
      title: Text(greeting, style: Theme.of(context).textTheme.titleLarge),
      actions: [
        IconButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UniversalSearchScreen())),
          icon: const Icon(LucideIcons.search),
          tooltip: 'Search',
        ),
        _NotifBell(unreadCount: unreadCount),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _NotifBell extends StatelessWidget {
  final int unreadCount;
  const _NotifBell({required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsCenterScreen())),
          icon: const Icon(LucideIcons.bell),
          tooltip: 'Notifications',
        ),
        if (unreadCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
              child: Center(
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Balance Card ─────────────────────────────────────────────────────────────
// Primary hero: Live Equity · Running P&L · Free Margin
// Never shows more than 3 financial metrics.

// _BalanceCard: outer gradient structure is const/static — never rebuilds.
// Inner numbers use granular VLBs so only the specific Text that changed repaints.
class _BalanceCard extends StatelessWidget {
  final TradingStore store;
  final double safeLevel;
  final double walletBalance; // balance + usedMargin; static between position changes

  const _BalanceCard({
    required this.store,
    required this.safeLevel,
    required this.walletBalance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D2B6B), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withOpacity(0.30),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Live Equity',
                  style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.3),
                ),
                const SizedBox(height: 6),

                // Equity number — rebuilds only when equity changes
                ValueListenableBuilder<double>(
                  valueListenable: store.equityNotifier,
                  builder: (_, equity, __) => Text(
                    _fmtBalance(equity),
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Running P&L badge — rebuilds only when runningPnL changes
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Running P&L', style: TextStyle(color: Colors.white54, fontSize: 11)),
                        const SizedBox(height: 3),
                        ValueListenableBuilder<double>(
                          valueListenable: store.runningPnlNotifier,
                          builder: (_, pnl, __) {
                            final pct = walletBalance > 0 ? (pnl / walletBalance) * 100 : 0.0;
                            return _PnlBadge(value: pnl, pct: pct, isPos: pnl >= 0);
                          },
                        ),
                      ],
                    ),

                    const Spacer(),
                    Container(width: 1, height: 32, color: Colors.white.withOpacity(0.15)),
                    const SizedBox(width: 16),

                    // Available margin — rebuilds only when margin/shortfall changes
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Available Margin', style: TextStyle(color: Colors.white54, fontSize: 11)),
                        const SizedBox(height: 3),
                        ListenableBuilder(
                          listenable: Listenable.merge([store.availableMarginNotifier, store.marginShortfallNotifier]),
                          builder: (_, __) {
                            final margin   = store.availableMarginNotifier.value;
                            final shortfall = store.marginShortfallNotifier.value;
                            return Text(
                              _fmtCompact(margin),
                              style: GoogleFonts.inter(
                                color: shortfall > 0 ? const Color(0xFFFF5252) : Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Critical alert banner — rebuilds only when equity crosses safeLevel
          ValueListenableBuilder<double>(
            valueListenable: store.equityNotifier,
            builder: (_, equity, __) {
              if (equity <= 0 || equity > safeLevel) return const SizedBox(height: 0);
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFD50000).withOpacity(0.22),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                  border: const Border(top: BorderSide(color: Color(0xFFD50000), width: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Auto square-off imminent — equity ≤ ₹${safeLevel.toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static String _fmtBalance(double v) => _fmtRupee(v, decimals: 2);
  static String _fmtCompact(double v)  => _fmtRupee(v, decimals: 2);
}

// ─── Shared rupee formatter (single source of truth for all financial values) ─
// Every number on the dashboard and detail sheet uses this function.
// Consistency: all values at the same magnitude always show the same precision.
String _fmtRupee(double v, {int decimals = 2}) {
  final abs = v.abs();
  final sign = v < 0 ? '-' : '';
  if (abs >= 10000000) return '$sign₹${(abs / 10000000).toStringAsFixed(decimals)}Cr';
  if (abs >= 100000)   return '$sign₹${(abs / 100000).toStringAsFixed(decimals)}L';
  return '₹${v.toStringAsFixed(decimals)}';
}

// ─── P&L Badge ────────────────────────────────────────────────────────────────

class _PnlBadge extends StatelessWidget {
  final double value;
  final double pct;
  final bool isPos;

  const _PnlBadge({required this.value, required this.pct, required this.isPos});

  @override
  Widget build(BuildContext context) {
    final arrow = isPos ? '▲' : '▼';
    final sign  = isPos ? '+' : '';
    final bg    = isPos
        ? const Color(0xFF00C853).withOpacity(0.22)
        : const Color(0xFFD50000).withOpacity(0.22);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        '$arrow $sign₹${value.abs().toStringAsFixed(2)}  ($sign${pct.toStringAsFixed(2)}%)',
        style: GoogleFonts.inter(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ─── Margin Strip ─────────────────────────────────────────────────────────────
// Compact 2-metric row: Free Margin | Used Margin + "View Details"

// _MarginStrip: wraps its entire content in a single ListenableBuilder so
// the strip only rebuilds when equity, availableMargin, or marginShortfall changes.
class _MarginStrip extends StatelessWidget {
  final TradingStore store;
  final double usedMargin; // static between position opens/closes
  final double safeLevel;

  const _MarginStrip({
    required this.store,
    required this.usedMargin,
    required this.safeLevel,
  });

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MarginDetailSheet(safeLevel: safeLevel),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        store.equityNotifier,
        store.availableMarginNotifier,
        store.marginShortfallNotifier,
      ]),
      builder: (ctx, __) {
        final equity          = store.equityNotifier.value;
        final availableMargin = store.availableMarginNotifier.value;
        final marginShortfall = store.marginShortfallNotifier.value;
        final hasPositions    = usedMargin > 0;
        final hasShortfall    = marginShortfall > 0;
        final isCritical      = equity > 0 && equity <= safeLevel;

        final borderColor = isCritical   ? _kLoss.withOpacity(0.5)
            : hasShortfall ? AppColors.warning.withOpacity(0.5)
            : AppColors.border;

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: (isCritical || hasShortfall) ? 1.5 : 1),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _showDetails(ctx),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _StripMetric(
                        label: 'Available Margin',
                        value: _fmt(availableMargin),
                        valueColor: isCritical || hasShortfall ? _kLoss : null,
                      ),
                    ),
                    Container(width: 1, height: 28, color: AppColors.border),
                    Expanded(
                      child: hasShortfall
                          ? _StripMetric(label: 'Shortfall', value: _fmt(marginShortfall), valueColor: _kLoss, align: CrossAxisAlignment.center)
                          : _StripMetric(label: 'Margin Used', value: hasPositions ? _fmt(usedMargin) : '—', align: CrossAxisAlignment.center),
                    ),
                    Container(width: 1, height: 28, color: AppColors.border),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Details', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        SizedBox(height: 2),
                        Icon(LucideIcons.chevronRight, size: 16, color: AppColors.primary),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _fmt(double v) => _fmtRupee(v);
}

class _StripMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final CrossAxisAlignment align;

  const _StripMetric({
    required this.label,
    required this.value,
    this.valueColor,
    this.align = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 3),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ─── Margin Detail Bottom Sheet ───────────────────────────────────────────────
// Full live breakdown. ALL values read from the store on every rebuild —
// no constructor params for financial data, so numbers stay consistent as
// prices move while the sheet is open.

class _MarginDetailSheet extends StatelessWidget {
  final double safeLevel;
  const _MarginDetailSheet({required this.safeLevel});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);

    // Derive every number from the same live sources — never from stale Firestore.
    final usedMargin      = store.usedMargin;
    final runningPnL      = store.runningPnL;
    final walletBalance   = store.balance + usedMargin;
    final equity          = store.equity;
    final availableMargin = store.availableMargin;   // max(0, equity - usedMargin)
    final marginShortfall = store.marginShortfall;   // max(0, usedMargin - equity)
    final marginLevel     = store.marginLevel;
    final isCritical      = equity > 0 && equity <= safeLevel;   // Auto Square-Off Risk
    final hasShortfall    = marginShortfall > 0;                  // Margin Shortfall

    // Status: Auto Square-Off Risk takes precedence over Margin Shortfall
    final statusLabel = isCritical   ? 'Auto Square-Off Risk'
        : hasShortfall ? 'Margin Shortfall'
        : 'Healthy';
    final statusColor = isCritical   ? _kLoss
        : hasShortfall ? AppColors.warning
        : _kProfit;

    return DraggableScrollableSheet(
      initialChildSize: 0.52,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(LucideIcons.shieldCheck, size: 16, color: AppColors.primary),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Margin & Equity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      Text('Live account risk metrics', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                  const Spacer(),
                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withOpacity(0.3)),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),

            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(20),
                children: [

                  // Equity formula card
                  _FormulaCard(
                    walletBalance: walletBalance,
                    runningPnL: runningPnL,
                    equity: equity,
                    isCritical: isCritical,
                  ),
                  const SizedBox(height: 12),

                  // 3-metric row: Used Margin | Available Margin | Margin Level
                  Row(
                    children: [
                      Expanded(child: _DetailMetric(label: 'Used Margin', value: _fmt(usedMargin), hint: 'Blocked')),
                      const SizedBox(width: 8),
                      Expanded(child: _DetailMetric(
                        label: 'Available Margin',
                        value: _fmt(availableMargin),
                        hint: 'max(0, E − UM)',
                        valueColor: (isCritical || hasShortfall) ? _kLoss : null,
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: _DetailMetric(
                        label: 'Margin Level',
                        value: marginLevel != null ? '${marginLevel.toStringAsFixed(1)}%' : '—',
                        hint: '(E ÷ UM) × 100',
                        valueColor: marginLevel != null && marginLevel < 200 ? _kLoss
                            : marginLevel != null && marginLevel < 500 ? AppColors.warning
                            : null,
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Running P&L
                  _RunningPnLTile(value: runningPnL),
                  const SizedBox(height: 12),

                  // Margin Shortfall card (when in shortfall) — replaces green Safe Level row
                  if (hasShortfall) ...[
                    _MarginShortfallCard(
                      requiredMargin: usedMargin,
                      equity: equity,
                      shortfall: marginShortfall,
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    // Safe level indicator (only when healthy — no shortfall)
                    _SafeLevelRow(equity: equity, safeLevel: safeLevel),
                    const SizedBox(height: 12),
                  ],

                  // Margin level bar (only with open positions)
                  if (marginLevel != null) ...[
                    _MarginLevelBar(marginLevel: marginLevel),
                    const SizedBox(height: 8),
                  ],

                  // Formula explanation
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('How these are calculated', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                        SizedBox(height: 6),
                        _FormulaLine('Equity', '= Wallet Balance + Running P&L'),
                        _FormulaLine('Available Margin', '= max(0, Equity − Used Margin)'),
                        _FormulaLine('Margin Shortfall', '= max(0, Used Margin − Equity)'),
                        _FormulaLine('Margin Level', '= (Equity ÷ Used Margin) × 100'),
                        _FormulaLine('Auto Square-Off', '= when Equity ≤ Safe Level'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(double v) => _fmtRupee(v);
}

class _FormulaLine extends StatelessWidget {
  final String term;
  final String formula;
  const _FormulaLine(this.term, this.formula);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(term, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
          Expanded(
            child: Text(formula, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}

class _FormulaCard extends StatelessWidget {
  final double walletBalance;
  final double runningPnL;
  final double equity;
  final bool isCritical;
  const _FormulaCard({required this.walletBalance, required this.runningPnL, required this.equity, required this.isCritical});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isCritical
              ? [const Color(0xFF4A0000), const Color(0xFF8B0000)]
              : [const Color(0xFF0D2B6B), const Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(child: _EqItem(label: 'Wallet Balance', value: walletBalance, white: true)),
          const _EqOp('+'),
          Expanded(child: _EqItem(label: 'Running P&L', value: runningPnL, white: true, colored: true)),
          const _EqOp('='),
          Expanded(child: _EqItem(label: 'Equity', value: equity, white: true, bold: true)),
        ],
      ),
    );
  }
}

class _EqItem extends StatelessWidget {
  final String label;
  final double value;
  final bool white;
  final bool colored;
  final bool bold;
  const _EqItem({required this.label, required this.value, this.white = false, this.colored = false, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final textColor = white ? Colors.white : AppColors.textPrimary;
    Color valueColor = white ? Colors.white : AppColors.textPrimary;
    if (colored) valueColor = value >= 0 ? _kProfit : _kLoss;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 9, color: textColor.withOpacity(0.6), fontWeight: FontWeight.w500)),
        const SizedBox(height: 3),
        Text(
          _fmt(value),
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  static String _fmt(double v) => _fmtRupee(v);
}

class _EqOp extends StatelessWidget {
  final String op;
  const _EqOp(this.op);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(op, style: const TextStyle(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.w300)),
    );
  }
}

class _DetailMetric extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final Color? valueColor;
  const _DetailMetric({required this.label, required this.value, this.hint, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _RunningPnLTile extends StatelessWidget {
  final double value;
  const _RunningPnLTile({required this.value});

  @override
  Widget build(BuildContext context) {
    final isPos  = value >= 0;
    final color  = isPos ? _kProfit : _kLoss;
    final sign   = isPos ? '+' : '';
    final arrow  = isPos ? '▲' : '▼';
    final bg     = color.withOpacity(0.06);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.2))),
      child: Row(
        children: [
          Icon(isPos ? LucideIcons.trendingUp : LucideIcons.trendingDown, size: 16, color: color),
          const SizedBox(width: 8),
          const Text('Running P&L', style: TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(
            '$arrow $sign₹${value.abs().toStringAsFixed(2)}',
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: color, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

// ─── Margin Shortfall Card ────────────────────────────────────────────────────

class _MarginShortfallCard extends StatelessWidget {
  final double requiredMargin;
  final double equity;
  final double shortfall;

  const _MarginShortfallCard({
    required this.requiredMargin,
    required this.equity,
    required this.shortfall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kLoss.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kLoss.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 14, color: _kLoss),
              const SizedBox(width: 6),
              const Text(
                'Margin Shortfall',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kLoss),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ShortfallMetricRow('Required Margin', requiredMargin),
          const SizedBox(height: 6),
          _ShortfallMetricRow('Current Equity',  equity),
          const Divider(height: 16),
          _ShortfallMetricRow('Shortfall', shortfall, bold: true, color: _kLoss),
        ],
      ),
    );
  }
}

class _ShortfallMetricRow extends StatelessWidget {
  final String label;
  final double value;
  final bool bold;
  final Color? color;

  const _ShortfallMetricRow(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        Text(
          _fmtRupee(value),
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: color ?? AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ─── Safe Level Row ───────────────────────────────────────────────────────────

class _SafeLevelRow extends StatelessWidget {
  final double equity;
  final double safeLevel;
  const _SafeLevelRow({required this.equity, required this.safeLevel});

  @override
  Widget build(BuildContext context) {
    final ratio   = safeLevel > 0 ? (equity / safeLevel).clamp(0.0, 5.0) : 5.0;
    final pct     = ratio / 5.0;
    final color   = ratio < 1.0 ? _kLoss : ratio < 2.0 ? AppColors.warning : _kProfit;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Safe Level', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const Spacer(),
              Text('₹${safeLevel.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Equity is ${ratio < 1.0 ? 'below' : '${ratio.toStringAsFixed(1)}×'} the safe level',
            style: TextStyle(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }
}

class _MarginLevelBar extends StatelessWidget {
  final double marginLevel;
  const _MarginLevelBar({required this.marginLevel});

  @override
  Widget build(BuildContext context) {
    final capped = marginLevel.clamp(0.0, 1000.0);
    final pct    = (capped / 1000.0).clamp(0.0, 1.0);
    final color  = capped < 150 ? _kLoss : capped < 300 ? AppColors.warning : _kProfit;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Margin Level', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const Spacer(),
              Text('${marginLevel.toStringAsFixed(1)}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('150% — Warning',  style: TextStyle(fontSize: 9, color: AppColors.warning)),
              Text('300% — Safe',     style: TextStyle(fontSize: 9, color: _kProfit)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Quick Actions ────────────────────────────────────────────────────────────

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context) {
    final actions = [
      (LucideIcons.barChart2,      'Markets',   AppColors.primary),
      (LucideIcons.activity,       'F&O',       const Color(0xFF00897B)),
      (LucideIcons.wallet,         'Wallet',    const Color(0xFF2E7D32)),
      (LucideIcons.moreHorizontal, 'More',      AppColors.textSecondary),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: actions.map((a) {
        return _QuickActionButton(
          icon: a.$1, label: a.$2, color: a.$3,
          onTap: () {
            if (a.$2 == 'Markets')     Navigator.push(context, MaterialPageRoute(builder: (_) => const MarketWatchScreen()));
            else if (a.$2 == 'F&O')    Navigator.push(context, MaterialPageRoute(builder: (_) => const FnoMarketScreen()));
            else if (a.$2 == 'Wallet') Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
            else _showMoreActions(context);
          },
        );
      }).toList(),
    );
  }

  void _showMoreActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            _sheetItem(ctx, 'Market Watch',        const MarketWatchScreen(),                     icon: Icons.view_list),
            _sheetItem(ctx, 'Advanced Chart',      const AdvancedChartScreen(symbol: 'REL'),      icon: Icons.show_chart),
            _sheetItem(ctx, 'Top Gainers / Losers',const TopGainersLosersScreen(),                icon: Icons.trending_up),
            _sheetItem(ctx, 'Sector Heatmap',      const SectorHeatmapScreen(),                   icon: Icons.grid_view),
            _sheetItem(ctx, 'F&O Markets',         const FnoMarketScreen(),                       icon: LucideIcons.activity),
            _sheetItem(ctx, 'Options Chain',       const OptionsChainScreen(),                    icon: Icons.stacked_bar_chart),
            _sheetItem(ctx, 'F&O Dashboard',       const FnoDashboardScreen(),                    icon: LucideIcons.barChart2),
            _sheetItem(ctx, 'Market Depth',        const MarketDepthScreen(),                     icon: Icons.layers),
            _sheetItem(ctx, 'Time & Sales',        const TimeAndSalesScreen(),                    icon: LucideIcons.clock3),
            _sheetItem(ctx, 'IPO',                 const IPOScreen(),                              icon: LucideIcons.briefcase),
            _sheetItem(ctx, 'Universal Search',    const UniversalSearchScreen(),                 icon: LucideIcons.search),
            _sheetItem(ctx, 'Stock Guide',         const StockGuideScreen(),                      icon: LucideIcons.bookOpen),
          ],
        ),
      ),
    );
  }

  Widget _sheetItem(BuildContext context, String title, Widget dest, {required IconData icon}) {
    return ListTile(
      leading: Icon(icon, size: 18, color: AppColors.textPrimary),
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (_) => dest));
      },
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.20)),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback? onViewAll;

  const _SectionHeader({
    required this.title,
    this.actionLabel = 'See all',
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        if (onViewAll != null)
          GestureDetector(
            onTap: onViewAll,
            child: Text(actionLabel, style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}

// ─── Positions Snapshot ───────────────────────────────────────────────────────

class _PositionsSnapshot extends StatelessWidget {
  final List<Position> positions;
  final TradingStore store;
  const _PositionsSnapshot({required this.positions, required this.store});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < positions.length; i++) ...[
            _PositionRow(position: positions[i], store: store),
            if (i < positions.length - 1) const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

// _PositionRow: symbol/meta are static; price + P&L use ltpNotifier VLB so
// only the right-column rebuilds when the position's symbol ticks.
class _PositionRow extends StatelessWidget {
  final Position position;
  final TradingStore store;
  const _PositionRow({required this.position, required this.store});

  @override
  Widget build(BuildContext context) {
    final p = position;
    final productLabel = switch (p.product) {
      ProductType.mis       => 'MIS',
      ProductType.nrml      => 'NRML',
      ProductType.overnight => 'CNC',
      ProductType.mtf       => 'MTF',
    };

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PortfolioScreen())),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            // Symbol + meta — never rebuilds from ticks
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.symbol, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _Tag(productLabel, AppColors.primary),
                      const SizedBox(width: 6),
                      Text('${p.quantity} qty', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
            // Price + P&L — rebuilds only when this symbol ticks
            ValueListenableBuilder<double>(
              valueListenable: store.ltpNotifier(p.symbol),
              builder: (_, ltp, __) {
                final price = ltp > 0 ? ltp : p.currentPrice;
                final pnl = p.calculatePnL(price);
                final pnlPct = p.avgPrice > 0 ? (pnl / (p.avgPrice * p.quantity.abs())) * 100 : 0.0;
                final isPos  = pnl >= 0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${price.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    const SizedBox(height: 3),
                    _PnlChip(value: pnl, pct: pnlPct, isPos: isPos),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Holdings Snapshot ────────────────────────────────────────────────────────

class _HoldingsSnapshot extends StatelessWidget {
  final List<Holding> holdings;
  final TradingStore store;
  const _HoldingsSnapshot({required this.holdings, required this.store});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < holdings.length; i++) ...[
            _HoldingRow(holding: holdings[i], store: store),
            if (i < holdings.length - 1) const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _HoldingRow extends StatelessWidget {
  final Holding holding;
  final TradingStore store;
  const _HoldingRow({required this.holding, required this.store});

  @override
  Widget build(BuildContext context) {
    final h = holding;
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PortfolioScreen())),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.symbol, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _Tag('CNC', AppColors.primary),
                      const SizedBox(width: 6),
                      Text('${h.quantity} qty', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
            ValueListenableBuilder<double>(
              valueListenable: store.ltpNotifier(h.symbol),
              builder: (_, ltp, __) {
                final price = ltp > 0 ? ltp : h.currentPrice;
                final pnl = h.calculatePnL(price);
                final pnlPct  = h.avgPrice > 0 ? (pnl / (h.avgPrice * h.quantity)) * 100 : 0.0;
                final isPos   = pnl >= 0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${price.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    const SizedBox(height: 3),
                    _PnlChip(value: pnl, pct: pnlPct, isPos: isPos),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
    );
  }
}

// ─── Indices Row ──────────────────────────────────────────────────────────────

class _IndicesRow extends StatelessWidget {
  final List<Stock> stocks;
  final TradingStore store;
  const _IndicesRow({required this.stocks, required this.store});

  @override
  Widget build(BuildContext context) {
    final indices = <_IndexData>[];
    const want = ['NIFTY', 'SENSEX', 'BANKNIFTY', 'NIFTYNXT50'];
    for (final sym in want) {
      Stock? m;
      for (final s in stocks) {
        if (s.symbol.toUpperCase().contains(sym)) { m = s; break; }
      }
      if (m != null) indices.add(_IndexData(m.symbol, m.currentPrice, m.changePercentage, m.expiry));
    }
    if (indices.isEmpty) {
      for (final s in stocks.take(4)) {
        indices.add(_IndexData(s.symbol, s.currentPrice, s.changePercentage, s.expiry));
      }
    }

    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: indices.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _IndexPill(data: indices[i], store: store),
      ),
    );
  }
}

class _IndexData {
  final String symbol;
  final double price;
  final double change;
  final DateTime? expiry;
  const _IndexData(this.symbol, this.price, this.change, [this.expiry]);
}

// _IndexPill: static container + symbol label; only price and change% use VLBs.
class _IndexPill extends StatelessWidget {
  final _IndexData data;
  final TradingStore store;
  const _IndexPill({required this.data, required this.store});

  static const _months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];

  String? _expiryLabel(DateTime? dt) {
    if (dt == null) return null;
    return '${dt.day} ${_months[dt.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final expiry = _expiryLabel(data.expiry);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(data.symbol, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              if (expiry != null)
                Text(expiry, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(width: 8),
          // Live price
          ValueListenableBuilder<double>(
            valueListenable: store.ltpNotifier(data.symbol),
            builder: (_, price, __) {
              final p = price > 0 ? price : data.price;
              return Text('₹${p.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFeatures: const [FontFeature.tabularFigures()]));
            },
          ),
          const SizedBox(width: 6),
          // Live change%
          ValueListenableBuilder<double>(
            valueListenable: store.changeNotifier(data.symbol),
            builder: (_, change, __) {
              final c    = change != 0 ? change : data.change;
              final isPos = c >= 0;
              final color = isPos ? _kProfit : _kLoss;
              final arrow = isPos ? '▲' : '▼';
              return Text('$arrow ${c.abs().toStringAsFixed(2)}%',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color));
            },
          ),
        ],
      ),
    );
  }
}

// ─── Top Movers ───────────────────────────────────────────────────────────────
// Shows 3 movers as a clean list (reduced density vs the old 2-col grid).
// Rebuilds only when topMoversNotifier fires (~every 5 s), not on every tick.

class _TopMoversList extends StatelessWidget {
  final TradingStore store;
  const _TopMoversList({required this.store});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Stock>>(
      valueListenable: store.topMoversNotifier,
      builder: (_, movers, __) {
        final stocks = movers.take(3).toList();
        if (stocks.isEmpty) return const SizedBox.shrink();
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < stocks.length; i++) ...[
                _MoverRow(stock: stocks[i]),
                if (i < stocks.length - 1) const Divider(height: 1, indent: 16, endIndent: 16),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MoverRow extends StatelessWidget {
  final Stock stock;
  const _MoverRow({required this.stock});

  @override
  Widget build(BuildContext context) {
    final isPos = stock.changePercentage >= 0;
    final color = isPos ? _kProfit : _kLoss;
    final sign  = isPos ? '+' : '';
    final arrow = isPos ? '▲' : '▼';

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: stock.symbol))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stock.symbol,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('₹${stock.currentPrice.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 12, color: AppColors.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
              child: Text('$arrow $sign${stock.changePercentage.toStringAsFixed(2)}%',
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Watchlist Preview ────────────────────────────────────────────────────────

class _WatchlistPreview extends StatelessWidget {
  final List<Stock> stocks;
  final TradingStore store;
  const _WatchlistPreview({required this.stocks, required this.store});

  @override
  Widget build(BuildContext context) {
    if (stocks.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < stocks.length; i++) ...[
            _WatchlistPreviewRow(stock: stocks[i], store: store),
            if (i < stocks.length - 1) const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

// _WatchlistPreviewRow: symbol is static; price uses LivePriceText (VLB);
// change% badge uses changeNotifier VLB so it updates without a parent setState.
class _WatchlistPreviewRow extends StatelessWidget {
  final Stock stock;
  final TradingStore store;
  const _WatchlistPreviewRow({required this.stock, required this.store});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: stock.symbol))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(stock.symbol, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15, color: AppColors.textPrimary)),
            ),
            LivePriceText(
              symbol: stock.symbol,
              store: store,
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            const SizedBox(width: 10),
            // Live change% — rebuilds only when this symbol's change% updates
            ValueListenableBuilder<double>(
              valueListenable: store.changeNotifier(stock.symbol),
              builder: (_, change, __) {
                final c         = change != 0.0 ? change : stock.changePercentage;
                final isPos     = c >= 0;
                final sign      = isPos ? '+' : '';
                final changeColor = isPos ? _kProfit : _kLoss;
                final arrow     = isPos ? '▲' : '▼';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: changeColor.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                  child: Text('$arrow $sign${c.abs().toStringAsFixed(2)}%',
                      style: TextStyle(color: changeColor, fontWeight: FontWeight.w600, fontSize: 12)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── P&L Chip (used in positions snapshot) ───────────────────────────────────

class _PnlChip extends StatelessWidget {
  final double value;
  final double pct;
  final bool isPos;

  const _PnlChip({required this.value, required this.pct, required this.isPos});

  @override
  Widget build(BuildContext context) {
    final color = isPos ? _kProfit : _kLoss;
    final arrow = isPos ? '▲' : '▼';
    final sign  = isPos ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(6)),
      child: Text(
        '$arrow $sign₹${value.abs().toStringAsFixed(2)} ($sign${pct.toStringAsFixed(2)}%)',
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11),
      ),
    );
  }
}

// ─── Today's Performance Card ────────────────────────────────────────────────

class _TodayPerformanceCard extends StatelessWidget {
  final int totalTrades;
  final double winRate;
  final double realizedPnl;

  const _TodayPerformanceCard({
    required this.totalTrades,
    required this.winRate,
    required this.realizedPnl,
  });

  @override
  Widget build(BuildContext context) {
    final pnlIsPos = realizedPnl >= 0;
    final pnlColor = pnlIsPos ? _kProfit : _kLoss;
    final pnlSign  = pnlIsPos ? '+' : '';
    final pnlArrow = pnlIsPos ? '▲' : '▼';

    Color rateColor = AppColors.textPrimary;
    if (winRate >= 60) rateColor = _kProfit;
    else if (winRate >= 40) rateColor = AppColors.warning;
    else if (winRate > 0) rateColor = _kLoss;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: [
                const Icon(LucideIcons.activity, size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                const Text("Today's Performance",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.2)),
              ],
            ),
          ),
          const Divider(height: 1),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(child: _PerfMetric(label: 'Trades', value: '$totalTrades')),
                const VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
                Expanded(child: _PerfMetric(
                  label: 'Win Rate',
                  value: winRate > 0 ? '${winRate.toStringAsFixed(0)}%' : '—',
                  valueColor: winRate > 0 ? rateColor : null,
                )),
                const VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
                Expanded(child: _PerfMetric(
                  label: 'Realized P&L',
                  value: realizedPnl != 0.0
                      ? '$pnlArrow $pnlSign₹${realizedPnl.abs().toStringAsFixed(2)}'
                      : '—',
                  valueColor: realizedPnl != 0.0 ? pnlColor : null,
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PerfMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _PerfMetric({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 5),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Category Leverage Card (kept for future use, not on main screen) ─────────

class _CategoryLimitsCard extends StatefulWidget {
  const _CategoryLimitsCard();

  @override
  State<_CategoryLimitsCard> createState() => _CategoryLimitsCardState();
}

class _CategoryLimitsCardState extends State<_CategoryLimitsCard> {
  final _service = MarketSettingsService();
  StreamSubscription<MarketSettings>? _sub;
  MarketSettings _settings = MarketSettings.defaults;

  @override
  void initState() {
    super.initState();
    _sub = _service.stream.listen((s) { if (mounted) setState(() => _settings = s); });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                const Icon(LucideIcons.shieldCheck, size: 15, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text('Margin & Leverage Limits', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                  child: const Text('Admin-set', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('These limits are set by the platform admin and cannot be changed.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ),
          const Divider(height: 1),
          _CategoryLimitRow(label: 'NSE / BSE — Stocks', icon: LucideIcons.barChart2, color: AppColors.primary, settings: _settings.stocks),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _CategoryLimitRow(label: 'MCX — Commodities', icon: LucideIcons.flame, color: const Color(0xFF7B1FA2), settings: _settings.mcx),
        ],
      ),
    );
  }
}

class _CategoryLimitRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final SegmentSettings settings;

  const _CategoryLimitRow({required this.label, required this.icon, required this.color, required this.settings});

  @override
  Widget build(BuildContext context) {
    final isEnabled   = settings.enabled;
    final statusColor = isEnabled ? _kProfit : _kLoss;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(isEnabled ? 'Open' : 'Closed', style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Text('${settings.marketOpen}–${settings.marketClose} IST', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          _LimitTile(label: 'Max Lev.', value: '${settings.maxLeverage.toStringAsFixed(0)}x', color: color),
          const SizedBox(width: 8),
          _LimitTile(label: 'Margin', value: '${settings.marginPercent.toStringAsFixed(1)}%', color: color),
        ],
      ),
    );
  }
}

class _LimitTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _LimitTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color.withOpacity(0.7))),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}
