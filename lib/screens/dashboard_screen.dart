import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../data/services/market_settings_service.dart';
import '../models/market_settings.dart';
import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/backend_error_widget.dart';
import '../widgets/shared_widgets.dart';
import 'advanced_chart_screen.dart';
import 'fno_dashboard_screen.dart';
import 'fno_market_screen.dart';
import 'stock_guide_screen.dart';
import 'market_depth_screen.dart';
import 'notifications_center_screen.dart';
import 'options_chain_screen.dart';
import 'sector_heatmap_screen.dart';
import 'time_and_sales_screen.dart';
import 'top_gainers_losers_screen.dart';
import 'universal_search_screen.dart';
import 'market_watch_screen.dart';
import 'orders_screen.dart';
import 'portfolio_screen.dart';
import 'stock_detail_screen.dart';
import 'stock_guide_screen.dart';

// ─── Design tokens (spec-compliant) ──────────────────────────────────────────
const _kProfit = Color(0xFF00C853);
const _kLoss = Color(0xFFD50000);
const _kCta = Color(0xFF1565C0);

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);

    // ── Error state: backend unreachable ──────────────────────────────────────
    if (store.backendError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard')),
        backgroundColor: AppColors.background,
        body: BackendErrorWidget(
          message: store.backendErrorMessage,
          onRetry: () => store.connectLiveBackend(),
        ),
      );
    }

    // ── Loading state: waiting for first data ─────────────────────────────────
    if (store.watchlist.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard')),
        backgroundColor: AppColors.background,
        body: const BackendLoadingWidget(
          message: 'Connecting to market data server...',
        ),
      );
    }

    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final firstName = store.currentUser.name.split(' ').first;

    final netWorth =
        store.holdings.fold(0.0, (s, h) => s + h.currentValue) +
        store.positions.fold(0.0, (s, p) => s + p.quantity * p.currentPrice) +
        store.balance;
    final dayPnl = store.positions.fold(0.0, (s, p) => s + p.unrealizedPnl);
    final dayPnlPct = netWorth == 0 ? 0.0 : (dayPnl / netWorth) * 100;

    // Top movers: sort by abs changePercentage
    final movers = store.watchlist.toList()
      ..sort(
        (a, b) => b.changePercentage.abs().compareTo(a.changePercentage.abs()),
      );
    final topMovers = movers.take(6).toList();

    final positions = store.positions.take(3).toList();
    final realizedPnl = store.orders
        .where(
          (o) =>
              o.status == OrderStatus.executed ||
              o.status == OrderStatus.approved,
        )
        .fold(0.0, (s, o) {
          final exec = o.executedPrice ?? o.price;
          return s +
              (o.type == OrderType.sell
                  ? (exec - o.price) * o.quantity
                  : (o.price - exec) * o.quantity);
        });

    return Scaffold(
      appBar: _DashboardAppBar(
        greeting: '$greeting, $firstName',
        unreadCount: store.unreadNotificationCount,
      ),
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // 1. Net Worth hero card (blue gradient)
          _NetWorthCard(
            netWorth: netWorth,
            dayPnl: dayPnl,
            dayPnlPct: dayPnlPct,
            balance: store.balance,
          ),
          const SizedBox(height: 16),

          // 2. Indices row (NIFTY/SENSEX pills horizontal scroll)
          _IndicesRow(stocks: store.watchlist),
          const SizedBox(height: 16),

          // 3. Quick Actions row (Markets/Orders/IPO/More, 48dp circles)
          const _QuickActionsRow(),
          const SizedBox(height: 24),

          // 4. P&L split row (Realized | Unrealized)
          _PnlStrip(realized: realizedPnl, unrealized: dayPnl),
          const SizedBox(height: 24),

          // 5. Positions preview (max 3 cards, no "N/A")
          if (positions.isNotEmpty) ...[
            _SectionHeader(
              title: 'Positions',
              onViewAll: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PortfolioScreen()),
              ),
            ),
            const SizedBox(height: 8),
            _PositionsSnapshot(positions: positions),
            const SizedBox(height: 24),
          ],

          // 7. Top Movers 2-column grid
          _SectionHeader(title: 'Top Movers'),
          const SizedBox(height: 8),
          _TopMoversGrid(stocks: topMovers),
          const SizedBox(height: 24),

          // 8. Quick Trade section
          _SectionHeader(
            title: 'Quick Trade',
            onViewAll: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MarketWatchScreen()),
            ),
          ),
          const SizedBox(height: 8),
          _WatchlistPreview(stocks: store.watchlist.take(4).toList()),
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
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UniversalSearchScreen()),
          ),
          icon: const Icon(LucideIcons.search),
          tooltip: 'Search',
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationsCenterScreen(),
                ),
              ),
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
                  decoration: const BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
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
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ─── Net Worth Card ───────────────────────────────────────────────────────────

class _NetWorthCard extends StatelessWidget {
  final double netWorth;
  final double dayPnl;
  final double dayPnlPct;
  final double balance;

  const _NetWorthCard({
    required this.netWorth,
    required this.dayPnl,
    required this.dayPnlPct,
    required this.balance,
  });

  @override
  Widget build(BuildContext context) {
    final isPos = dayPnl >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D2B6B), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppColors.heroRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available Balance',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '₹${balance.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                "Today's P&L  ",
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              _PnlChip(
                value: dayPnl,
                pct: dayPnlPct,
                isPos: isPos,
                light: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'Net Worth  ',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '₹${_fmt(netWorth)}',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(2)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(2)}L';
    return v.toStringAsFixed(2);
  }
}

// ─── Quick Actions ────────────────────────────────────────────────────────────

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow();
  @override
  Widget build(BuildContext context) {
    final actions = [
      (LucideIcons.barChart2, 'Markets', AppColors.primary),
      (LucideIcons.activity, 'F&O', const Color(0xFF00897B)),
      (LucideIcons.bookOpen, 'Courses', const Color(0xFF6A1B9A)),
      (LucideIcons.moreHorizontal, 'More', AppColors.textSecondary),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: actions.map((a) {
        return _QuickActionButton(
          icon: a.$1,
          label: a.$2,
          color: a.$3,
          onTap: () {
            if (a.$2 == 'Markets') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MarketWatchScreen()),
              );
            } else if (a.$2 == 'F&O') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FnoMarketScreen()),
              );
            } else if (a.$2 == 'Courses') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StockGuideScreen()),
              );
            } else if (a.$2 == 'More') {
              _showMoreActions(context);
            }
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
    Widget destination, {
    required IconData icon,
  }) {
    return ListTile(
      leading: Icon(icon, size: 18, color: AppColors.textPrimary),
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (_) => destination));
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
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.25), width: 1),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── P&L Strip ────────────────────────────────────────────────────────────────

class _PnlStrip extends StatelessWidget {
  final double realized;
  final double unrealized;

  const _PnlStrip({required this.realized, required this.unrealized});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PnlItem(label: 'Realized P&L', value: realized),
          ),
          Container(width: 1, height: 36, color: AppColors.border),
          Expanded(
            child: _PnlItem(label: 'Unrealized P&L', value: unrealized),
          ),
        ],
      ),
    );
  }
}

class _PnlItem extends StatelessWidget {
  final String label;
  final double value;

  const _PnlItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isPos = value >= 0;
    final arrow = isPos ? '▲' : '▼';
    final color = isPos ? _kProfit : _kLoss;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$arrow ₹${value.abs().toStringAsFixed(2)}',
          style: GoogleFonts.inter(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onViewAll;

  const _SectionHeader({required this.title, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        if (onViewAll != null)
          GestureDetector(
            onTap: onViewAll,
            child: const Text(
              'View all',
              style: TextStyle(
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

// ─── Positions Snapshot ───────────────────────────────────────────────────────

class _PositionsSnapshot extends StatelessWidget {
  final List<Position> positions;

  const _PositionsSnapshot({required this.positions});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        children: [
          for (var i = 0; i < positions.length; i++) ...[
            _PositionRow(position: positions[i]),
            if (i < positions.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _PositionRow extends StatelessWidget {
  final Position position;

  const _PositionRow({required this.position});

  @override
  Widget build(BuildContext context) {
    final p = position;
    final isPos = p.unrealizedPnl >= 0;
    final productLabel = p.product == ProductType.mis ? 'MIS' : 'CNC';
    // Never show N/A — use symbol as fallback for name
    final displayName =
        (p.name.isNotEmpty && p.name != 'N/A' && p.name != p.symbol)
        ? p.name
        : p.symbol;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.symbol,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        productLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${p.quantity} qty',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${p.currentPrice.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 3),
              _PnlChip(
                value: p.unrealizedPnl,
                pct: p.pnlPercentage,
                isPos: isPos,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Indices Row ──────────────────────────────────────────────────────────────

class _IndicesRow extends StatelessWidget {
  final List<Stock> stocks;
  const _IndicesRow({required this.stocks});

  @override
  Widget build(BuildContext context) {
    // Try to find index-like symbols; fall back to first 3 stocks
    final indices = <_IndexData>[];
    const indexSymbols = ['NIFTY', 'SENSEX', 'BANKNIFTY', 'NIFTYBANK'];
    for (final sym in indexSymbols) {
      final match = stocks
          .where((s) => s.symbol.toUpperCase().contains(sym))
          .firstOrNull;
      if (match != null) {
        indices.add(
          _IndexData(match.symbol, match.currentPrice, match.changePercentage),
        );
      }
    }
    // If no index symbols found, use first 3 stocks as proxy
    if (indices.isEmpty) {
      for (final s in stocks.take(3)) {
        indices.add(_IndexData(s.symbol, s.currentPrice, s.changePercentage));
      }
    }

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: indices.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _IndexPill(data: indices[i]),
      ),
    );
  }
}

class _IndexData {
  final String symbol;
  final double price;
  final double change;
  const _IndexData(this.symbol, this.price, this.change);
}

class _IndexPill extends StatelessWidget {
  final _IndexData data;
  const _IndexPill({required this.data});

  @override
  Widget build(BuildContext context) {
    final isPos = data.change >= 0;
    final color = isPos ? _kProfit : _kLoss;
    final arrow = isPos ? '▲' : '▼';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            data.symbol,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '₹${data.price.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$arrow ${data.change.abs().toStringAsFixed(2)}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Top Movers 2-column grid ─────────────────────────────────────────────────

class _TopMoversGrid extends StatelessWidget {
  final List<Stock> stocks;
  const _TopMoversGrid({required this.stocks});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 2.4,
      ),
      itemCount: stocks.length,
      itemBuilder: (context, index) => _MoverCard(stock: stocks[index]),
    );
  }
}

class _MoverCard extends StatelessWidget {
  final Stock stock;

  const _MoverCard({required this.stock});

  @override
  Widget build(BuildContext context) {
    final isPos = stock.changePercentage >= 0;
    final sign = isPos ? '+' : '';
    final color = isPos ? _kProfit : _kLoss;

    return InkWell(
      borderRadius: BorderRadius.circular(AppColors.cardRadius),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StockDetailScreen(symbol: stock.symbol),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    stock.symbol,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₹${stock.currentPrice.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$sign${stock.changePercentage.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
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

  const _WatchlistPreview({required this.stocks});

  @override
  Widget build(BuildContext context) {
    if (stocks.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        children: [
          for (var i = 0; i < stocks.length; i++) ...[
            _WatchlistPreviewRow(stock: stocks[i]),
            if (i < stocks.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _WatchlistPreviewRow extends StatelessWidget {
  final Stock stock;

  const _WatchlistPreviewRow({required this.stock});

  @override
  Widget build(BuildContext context) {
    final isPos = stock.changePercentage >= 0;
    final sign = isPos ? '+' : '';
    final changeColor = isPos ? _kProfit : _kLoss;
    final arrow = isPos ? '▲' : '▼';

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
            Expanded(
              child: Text(
                stock.symbol,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            PriceFlashWidget(
              price: stock.currentPrice,
              child: Text(
                '₹${stock.currentPrice.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: changeColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$arrow $sign${stock.changePercentage.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: changeColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── P&L Chip ─────────────────────────────────────────────────────────────────

class _PnlChip extends StatelessWidget {
  final double value;
  final double pct;
  final bool isPos;
  final bool light;

  const _PnlChip({
    required this.value,
    required this.pct,
    required this.isPos,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isPos ? _kProfit : _kLoss;
    final arrow = isPos ? '▲' : '▼';
    final sign = isPos ? '+' : '';
    final bgColor = light
        ? Colors.white.withOpacity(0.2)
        : color.withOpacity(0.12);
    final textColor = light ? Colors.white : color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$arrow $sign₹${value.abs().toStringAsFixed(2)}  ($sign${pct.toStringAsFixed(2)}%)',
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ─── Category Leverage & Margin Card (Fix 2) ──────────────────────────────────
//
// Streams admin-configured leverage and margin settings from Firestore
// (marketSettings/config) and displays them as read-only info tiles.
// Users can see their allowed limits per category but cannot edit them.

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
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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
          // NSE / Stocks row
          _CategoryLimitRow(
            label: 'NSE / BSE — Stocks',
            icon: LucideIcons.barChart2,
            color: AppColors.primary,
            settings: _settings.stocks,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          // MCX row
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
    final statusColor = isEnabled
        ? const Color(0xFF00C853)
        : const Color(0xFFD50000);
    final statusLabel = isEnabled ? 'Open' : 'Closed';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Category icon
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

          // Label + status
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
                      statusLabel,
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

          // Leverage tile
          _LimitTile(
            label: 'Max Leverage',
            value: '${settings.maxLeverage.toStringAsFixed(0)}x',
            color: color,
          ),
          const SizedBox(width: 8),

          // Margin tile
          _LimitTile(
            label: 'Margin Req.',
            value: '${settings.marginPercent.toStringAsFixed(2)}%',
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
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
