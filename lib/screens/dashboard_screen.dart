import 'dart:async';

import 'package:flutter/material.dart';
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
import '../widgets/instrument_logo.dart';
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

// Shared with MarketWatchScreen — same SharedPreferences key
const _kWatchlistsKey = 'watchlist.lists_v2';

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
  double _safeLevel = 0;
  List<Stock> _watchlist = const [];

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
    _safeLevel = store.rmsSettings.safeLevelRupees;
    _watchlist = _loadPersistedWatchlist(store);
  }

  // Read watchlist symbols from SharedPreferences (same store as MarketWatchScreen)
  // and resolve them against the live price universe.
  static List<Stock> _loadPersistedWatchlist(TradingStore store) {
    final saved = PersistenceService.instance.getJson<List<dynamic>>(
      _kWatchlistsKey,
    );
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
    return symbols.map(store.stockBySymbolOrNull).whereType<Stock>().toList();
  }

  void _onStoreChanged() {
    if (_store == null) return;
    final store = _store!;
    final wasError = _backendError;
    final wasName = _userName;
    final wasUnread = _unreadNotificationCount;
    final wasWatchlistLen = _watchlist.length;
    _syncFromStore(store);
    // Only rebuild on structural changes — tick data goes to individual VLBs.
    final structural =
        _backendError != wasError ||
        _userName != wasName ||
        _unreadNotificationCount != wasUnread ||
        _watchlist.length != wasWatchlistLen;
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

    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final firstName = _userName.split(' ').first;
    final store = _store!;

    final hasWatchlist = _watchlist.isNotEmpty;

    // New users with no watchlist yet see a curated set of well-known
    // large-cap stocks instead of an empty section.
    final popularStocks = hasWatchlist
        ? const <Stock>[]
        : [
            'RELIANCE',
            'TCS',
            'INFY',
            'HDFCBANK',
          ].map(store.stockBySymbolOrNull).whereType<Stock>().toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            TradingBottomNavBar.bottomInset(context),
          ),
          children: [
            // ── 0. Header ────────────────────────────────────────────────
            _DashboardHeader(
              greeting: greeting,
              name: firstName,
              unreadCount: _unreadNotificationCount,
            ),
            const SizedBox(height: AppSpacing.md),

            // ── 1. Portfolio card ──────────────────────────────────────────
            _BalanceCard(store: store, safeLevel: _safeLevel),
            const SizedBox(height: 16),

            // ── 2. Explore shortcuts — directly after portfolio card ───────
            const _QuickActionsRow(),
            const SizedBox(height: 20),

            // ── 2b. Market Pulse (indices) ───────────────────────────────────
            _SectionHeader(
              title: 'Market Pulse',
              actionLabel: 'See all',
              onViewAll: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MarketWatchScreen()),
              ),
            ),
            const SizedBox(height: 8),
            _IndicesRow(store: store),
            const SizedBox(height: 20),

            // ── 3. My Watchlist (or a starter list for brand-new users) ─────
            if (hasWatchlist) ...[
              _SectionHeader(
                title: 'My Watchlist',
                actionLabel: 'See All',
                onViewAll: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MarketWatchScreen()),
                ),
              ),
              const SizedBox(height: 8),
              _WatchlistPreview(
                stocks: _watchlist.take(4).toList(),
                store: store,
              ),
              const SizedBox(height: 20),
            ] else if (popularStocks.isNotEmpty) ...[
              _SectionHeader(
                title: 'Popular Stocks',
                actionLabel: 'Explore Markets',
                onViewAll: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MarketWatchScreen()),
                ),
              ),
              const SizedBox(height: 8),
              _WatchlistPreview(stocks: popularStocks, store: store),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _DashboardHeader extends StatelessWidget {
  final String greeting;
  final String name;
  final int unreadCount;
  const _DashboardHeader({
    required this.greeting,
    required this.name,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                greeting,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        AppHeaderAction(
          icon: LucideIcons.search,
          tooltip: 'Search',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UniversalSearchScreen()),
          ),
        ),
        const SizedBox(width: 8),
        _NotifBell(unreadCount: unreadCount),
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
        AppHeaderAction(
          icon: LucideIcons.bell,
          tooltip: 'Notifications',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const NotificationsCenterScreen(),
            ),
          ),
        ),
        if (unreadCount > 0)
          Positioned(
            right: 1,
            top: 1,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.background, width: 1.5),
              ),
              child: Center(
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Balance Card ─────────────────────────────────────────────────────────────
// Primary hero: Total Portfolio Value (holdings) · Today's P&L · Overall P&L
// breakdown. Tapping the whole card opens the full Portfolio screen.

// _BalanceCard: outer gradient structure is const/static — never rebuilds.
// Inner numbers use granular VLBs so only the specific Text that changed repaints.
class _BalanceCard extends StatelessWidget {
  final TradingStore store;
  final double safeLevel;

  const _BalanceCard({required this.store, required this.safeLevel});

  @override
  Widget build(BuildContext context) {
    final invested = store.portfolioInvested;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppColors.heroRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppColors.heroRadius),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PortfolioScreen()),
        ),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: AppColors.heroGradient,
            borderRadius: BorderRadius.circular(AppColors.heroRadius),
            boxShadow: [
              BoxShadow(
                color: AppColors.heroGradientEnd.withOpacity(0.28),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Wallet Balance',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const Text(
                          "Today's P&L",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Wallet balance — rebuilds on deposit/withdraw and
                        // on order execution (margin blocked/released), not
                        // on price ticks (see _pushWalletBalance).
                        Expanded(
                          child: ValueListenableBuilder<double>(
                            valueListenable: store.walletBalanceNotifier,
                            builder: (_, balance, __) => PriceFlashWidget(
                              price: balance,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _fmtBalance(balance),
                                  style: AppTheme.mono(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    height: 1.05,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 56,
                          height: 34,
                          child: Sparkline(
                            valueListenable: store.walletBalanceNotifier,
                            color: Colors.white,
                            filled: true,
                            seedValue: store.walletBalanceNotifier.value,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Today's P&L — same colored-text treatment as the
                        // old running-P&L line, now scoped to holdings only.
                        ValueListenableBuilder<double>(
                          valueListenable: store.portfolioTodaysPnlNotifier,
                          builder: (_, todaysPnl, __) {
                            final isPos = todaysPnl >= 0;
                            return PriceFlashWidget(
                              price: todaysPnl,
                              child: Text(
                                '${isPos ? '+' : '-'}₹${todaysPnl.abs().toStringAsFixed(2)}',
                                style: AppTheme.mono(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: isPos
                                      ? _PnlBadge._lightGreen
                                      : _PnlBadge._lightRed,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Overall P&L (since purchase) — the prominent colored
                    // pill under the portfolio value. Uses the side-aware
                    // overall-P&L notifier, not current−invested, since that
                    // subtraction gives the wrong sign for short positions.
                    ValueListenableBuilder<double>(
                      valueListenable: store.portfolioOverallPnlNotifier,
                      builder: (_, pnl, __) {
                        final pct = invested > 0 ? (pnl / invested) * 100 : 0.0;
                        return _PnlBadge(value: pnl, pct: pct, isPos: pnl >= 0);
                      },
                    ),
                  ],
                ),
              ),

              // Bottom stat row: Invested · Current · Overall P&L · Overall P&L%
              Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.white24)),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: 12,
                ),
                child: ValueListenableBuilder<double>(
                  valueListenable: store.portfolioCurrentNotifier,
                  builder: (_, current, __) => ValueListenableBuilder<double>(
                    valueListenable: store.portfolioOverallPnlNotifier,
                    builder: (_, pnl, __) {
                      final pct = invested > 0 ? (pnl / invested) * 100 : 0.0;
                      final pnlColor = pnl >= 0
                          ? _PnlBadge._lightGreen
                          : _PnlBadge._lightRed;
                      return Row(
                        children: [
                          Expanded(
                            child: _HeroStat(
                              label: 'Invested',
                              value: _fmtBalance(invested),
                            ),
                          ),
                          Expanded(
                            child: _HeroStat(
                              label: 'Current',
                              value: _fmtBalance(current),
                            ),
                          ),
                          Expanded(
                            child: _HeroStat(
                              label: 'Overall P&L',
                              value:
                                  '${pnl >= 0 ? '+' : '-'}${_fmtBalance(pnl.abs())}',
                              color: pnlColor,
                            ),
                          ),
                          Expanded(
                            child: _HeroStat(
                              label: 'Overall P&L %',
                              value:
                                  '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
                              color: pnlColor,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              // Critical alert banner — rebuilds only when equity crosses safeLevel.
              // Kept independent of the portfolio-value headline above: this is a
              // trading-account margin/auto-square-off risk warning, driven by
              // cash + margin + open-position P&L, not holdings value.
              ValueListenableBuilder<double>(
                valueListenable: store.equityNotifier,
                builder: (_, equity, __) {
                  if (equity <= 0 || equity > safeLevel)
                    return const SizedBox(height: 0);
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.18),
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(AppColors.heroRadius),
                      ),
                      border: const Border(
                        top: BorderSide(color: Colors.white24),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Auto square-off imminent — equity ≤ ₹${safeLevel.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtBalance(double v) => _fmtRupee(v, decimals: 2);
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _HeroStat({
    required this.label,
    required this.value,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: AppTheme.mono(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ─── Shared rupee formatter (single source of truth for all financial values) ─
// Every number on the dashboard and detail sheet uses this function.
// Consistency: all values at the same magnitude always show the same precision.
String _fmtRupee(double v, {int decimals = 2}) {
  final abs = v.abs();
  final sign = v < 0 ? '-' : '';
  if (abs >= 10000000)
    return '$sign₹${(abs / 10000000).toStringAsFixed(decimals)}Cr';
  if (abs >= 100000)
    return '$sign₹${(abs / 100000).toStringAsFixed(decimals)}L';
  return '₹${v.toStringAsFixed(decimals)}';
}

// ─── P&L Badge ────────────────────────────────────────────────────────────────

// Used only on the blue gradient hero card — lightened success/danger
// tints for AA contrast against the gradient, no background pill (the
// gradient card is the one place flat colored text over color is correct).
class _PnlBadge extends StatelessWidget {
  final double value;
  final double pct;
  final bool isPos;

  const _PnlBadge({
    required this.value,
    required this.pct,
    required this.isPos,
  });

  static const _lightGreen = Color(0xFF7FE3B4);
  static const _lightRed = Color(0xFFFFB4B4);

  @override
  Widget build(BuildContext context) {
    final arrow = isPos ? '▲' : '▼';
    final sign = isPos ? '+' : '';
    final color = isPos ? _lightGreen : _lightRed;

    return PriceFlashWidget(
      price: value,
      child: Text(
        '$arrow $sign₹${value.abs().toStringAsFixed(2)}  ($sign${pct.toStringAsFixed(2)}%)',
        style: AppTheme.mono(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
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
      (LucideIcons.barChart2, 'Markets', AppColors.primary),
      (LucideIcons.activity, 'F&O', AppColors.primary),
      (LucideIcons.wallet, 'Wallet', AppColors.primary),
      (LucideIcons.moreHorizontal, 'More', AppColors.textSecondary),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0)
                const VerticalDivider(
                  width: 1,
                  indent: 8,
                  endIndent: 8,
                  color: AppColors.divider,
                ),
              Expanded(
                child: _QuickActionButton(
                  icon: actions[i].$1,
                  label: actions[i].$2,
                  color: actions[i].$3,
                  onTap: () {
                    final label = actions[i].$2;
                    if (label == 'Markets')
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MarketWatchScreen(),
                        ),
                      );
                    else if (label == 'F&O')
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FnoMarketScreen(),
                        ),
                      );
                    else if (label == 'Wallet')
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WalletScreen()),
                      );
                    else
                      _showMoreActions(context);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
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
            _sheetItem(
              ctx,
              'Market Watch',
              const MarketWatchScreen(),
              icon: Icons.view_list,
            ),
            _sheetItem(
              ctx,
              'Advanced Chart',
              const AdvancedChartScreen(symbol: 'REL'),
              icon: Icons.show_chart,
            ),
            _sheetItem(
              ctx,
              'Top Gainers / Losers',
              const TopGainersLosersScreen(),
              icon: Icons.trending_up,
            ),
            _sheetItem(
              ctx,
              'Sector Heatmap',
              const SectorHeatmapScreen(),
              icon: Icons.grid_view,
            ),
            _sheetItem(
              ctx,
              'F&O Markets',
              const FnoMarketScreen(),
              icon: LucideIcons.activity,
            ),
            _sheetItem(
              ctx,
              'Options Chain',
              const OptionsChainScreen(),
              icon: Icons.stacked_bar_chart,
            ),
            _sheetItem(
              ctx,
              'F&O Dashboard',
              const FnoDashboardScreen(),
              icon: LucideIcons.barChart2,
            ),
            _sheetItem(
              ctx,
              'Market Depth',
              const MarketDepthScreen(),
              icon: Icons.layers,
            ),
            _sheetItem(
              ctx,
              'Time & Sales',
              const TimeAndSalesScreen(),
              icon: LucideIcons.clock3,
            ),
            _sheetItem(
              ctx,
              'IPO',
              const IPOScreen(),
              icon: LucideIcons.briefcase,
            ),
            _sheetItem(
              ctx,
              'Universal Search',
              const UniversalSearchScreen(),
              icon: LucideIcons.search,
            ),
            _sheetItem(
              ctx,
              'Stock Guide',
              const StockGuideScreen(),
              icon: LucideIcons.bookOpen,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetItem(
    BuildContext context,
    String title,
    Widget dest, {
    required IconData icon,
  }) {
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

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color.withOpacity(0.10),
          shape: CircleBorder(side: BorderSide(color: color.withOpacity(0.20))),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, color: color, size: 19),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ],
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
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        if (onViewAll != null)
          GestureDetector(
            onTap: onViewAll,
            child: Text(
              actionLabel,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Indices Row ──────────────────────────────────────────────────────────────

class _IndicesRow extends StatelessWidget {
  final TradingStore store;
  const _IndicesRow({required this.store});

  // Market Pulse always shows these three plain indices, resolved directly
  // by their canonical symbol — never derived from a top-movers/watchlist
  // list, which can be empty, stock-only, or (worse) include F&O contracts
  // that happen to contain a matching substring like "NIFTY".
  static const _want = ['NIFTY', 'SENSEX', 'BANKNIFTY'];

  @override
  Widget build(BuildContext context) {
    final indices = <_IndexData>[];
    for (final sym in _want) {
      final m = store.stockBySymbolOrNull(sym);
      if (m != null)
        indices.add(
          _IndexData(
            m.symbol,
            m.currentPrice,
            m.changePercentage,
            m.expiry,
            m.exchange,
            m.token,
          ),
        );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < indices.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _IndexPill(data: indices[i], store: store),
          ),
        ],
      ],
    );
  }
}

class _IndexData {
  final String symbol;
  final double price;
  final double change;
  final DateTime? expiry;
  final String exchange;
  final String token;
  const _IndexData(
    this.symbol,
    this.price,
    this.change, [
    this.expiry,
    this.exchange = '',
    this.token = '',
  ]);
}

// _IndexPill: "Market Pulse" card — symbol, live price, change badge, sparkline.
class _IndexPill extends StatelessWidget {
  final _IndexData data;
  final TradingStore store;
  const _IndexPill({required this.data, required this.store});

  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  String? _expiryLabel(DateTime? dt) {
    if (dt == null) return null;
    return '${dt.day} ${_months[dt.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final expiry = _expiryLabel(data.expiry);
    final changeNotifier = store.changeNotifier(data.symbol);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data.symbol,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (expiry != null)
                Text(
                  expiry,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Live price
          ValueListenableBuilder<double>(
            valueListenable: store.ltpNotifier(data.symbol),
            builder: (_, price, __) {
              final p = price > 0 ? price : data.price;
              return PriceFlashWidget(
                price: p,
                child: Text(
                  '₹${p.toStringAsFixed(2)}',
                  style: AppTheme.mono(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 3),
          // Live change%
          ValueListenableBuilder<double>(
            valueListenable: changeNotifier,
            builder: (_, change, __) {
              final c = change != 0 ? change : data.change;
              final isPos = c >= 0;
              final color = isPos ? AppColors.success : AppColors.danger;
              final arrow = isPos ? '▲' : '▼';
              return Text(
                '$arrow ${c.abs().toStringAsFixed(2)}%',
                style: AppTheme.mono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<double>(
            valueListenable: changeNotifier,
            builder: (_, change, __) {
              final c = change != 0 ? change : data.change;
              final color = c >= 0 ? AppColors.success : AppColors.danger;
              return SizedBox(
                height: 28,
                width: double.infinity,
                child: Sparkline(
                  valueListenable: store.ltpNotifier(data.symbol),
                  color: color,
                  filled: true,
                  seedValue: data.price,
                  symbol: data.symbol,
                  exchange: data.exchange,
                  token: data.token,
                ),
              );
            },
          ),
        ],
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
            if (i < stocks.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

// _WatchlistPreviewRow: symbol/name/tags are static; price, change%, and the
// sparkline all update from live notifiers without a parent setState.
class _WatchlistPreviewRow extends StatelessWidget {
  final Stock stock;
  final TradingStore store;
  const _WatchlistPreviewRow({required this.stock, required this.store});

  static String _instrumentTag(InstrumentType t) {
    switch (t) {
      case InstrumentType.equity:
        return 'EQ';
      case InstrumentType.marketIndex:
        return 'IDX';
      case InstrumentType.etf:
        return 'ETF';
      case InstrumentType.futuresStkIdx:
      case InstrumentType.futuresCom:
        return 'FUT';
      case InstrumentType.optionCE:
        return 'CE';
      case InstrumentType.optionPE:
        return 'PE';
      case InstrumentType.currency:
        return 'CCY';
      case InstrumentType.unknown:
        return 'EQ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final changeNotifier = store.changeNotifier(stock.symbol);
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StockDetailScreen(symbol: stock.symbol),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            InstrumentLogo.forStock(stock, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          stock.symbol,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      AppTagChip.neutral(stock.exchange),
                      const SizedBox(width: 4),
                      AppTagChip(_instrumentTag(stock.instrumentType)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stock.name,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 44,
              height: 28,
              child: ValueListenableBuilder<double>(
                valueListenable: changeNotifier,
                builder: (_, change, __) {
                  final c = change != 0.0 ? change : stock.changePercentage;
                  return Sparkline(
                    valueListenable: store.ltpNotifier(stock.symbol),
                    color: c >= 0 ? AppColors.success : AppColors.danger,
                    filled: false,
                    seedValue: stock.currentPrice,
                    symbol: stock.symbol,
                    exchange: stock.exchange,
                    token: stock.token,
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                LivePriceText(
                  symbol: stock.symbol,
                  store: store,
                  style: AppTheme.mono(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                // Live change% — rebuilds only when this symbol's change% updates
                ValueListenableBuilder<double>(
                  valueListenable: changeNotifier,
                  builder: (_, change, __) {
                    final c = change != 0.0 ? change : stock.changePercentage;
                    final isPos = c >= 0;
                    final sign = isPos ? '+' : '';
                    final changeColor = isPos
                        ? AppColors.success
                        : AppColors.danger;
                    final arrow = isPos ? '▲' : '▼';
                    return Text(
                      '$arrow $sign${c.abs().toStringAsFixed(2)}%',
                      style: AppTheme.mono(
                        color: changeColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
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
    _sub = _service.stream.listen((s) {
      if (mounted) setState(() => _settings = s);
    });
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
                const Icon(
                  LucideIcons.shieldCheck,
                  size: 15,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Margin & Leverage Limits',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Admin-set',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'These limits are set by the platform admin and cannot be changed.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
          const Divider(height: 1),
          _CategoryLimitRow(
            label: 'NSE / BSE — Stocks',
            icon: LucideIcons.barChart2,
            color: AppColors.primary,
            settings: _settings.stocks,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _CategoryLimitRow(
            label: 'MCX — Commodities',
            icon: LucideIcons.flame,
            color: const Color(0xFF7B1FA2),
            settings: _settings.mcx,
          ),
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

  const _CategoryLimitRow({
    required this.label,
    required this.icon,
    required this.color,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = settings.enabled;
    final statusColor = isEnabled ? AppColors.success : AppColors.danger;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isEnabled ? 'Open' : 'Closed',
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${settings.marketOpen}–${settings.marketClose} IST',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _LimitTile(
            label: 'Max Lev.',
            value: '${settings.maxLeverage.toStringAsFixed(0)}x',
            color: color,
          ),
          const SizedBox(width: 8),
          _LimitTile(
            label: 'Margin',
            value: '${settings.marginPercent.toStringAsFixed(1)}%',
            color: color,
          ),
        ],
      ),
    );
  }
}

class _LimitTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _LimitTile({
    required this.label,
    required this.value,
    required this.color,
  });

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
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: color.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTheme.mono(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
