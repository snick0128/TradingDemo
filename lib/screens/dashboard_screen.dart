import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';
import 'advanced_chart_screen.dart';
import 'fno_dashboard_screen.dart';
import 'ipo_screen.dart';
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

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
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
    final topMovers = movers.take(5).toList();

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Net Worth Card
            _NetWorthCard(
              netWorth: netWorth,
              dayPnl: dayPnl,
              dayPnlPct: dayPnlPct,
              balance: store.balance,
            ),
            const SizedBox(height: 20),

            // 2. Quick Actions
            const _QuickActionsRow(),
            const SizedBox(height: 20),

            // 3. Today's P&L strip
            _PnlStrip(realized: realizedPnl, unrealized: dayPnl),
            const SizedBox(height: 20),

            // 4. Positions snapshot
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
              const SizedBox(height: 20),
            ],

            // 5. Top Movers
            _SectionHeader(title: 'Top Movers'),
            const SizedBox(height: 8),
            _TopMoversRow(stocks: topMovers),
            const SizedBox(height: 20),

            // 6. Quick Trade / Watchlist Preview
            _SectionHeader(
              title: 'Quick Trade',
              onViewAll: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MarketWatchScreen()),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Watchlist',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            _WatchlistPreview(stocks: store.watchlist.take(4).toList()),
            const SizedBox(height: 20),

            // 7. Indices strip
            _IndicesStrip(),
          ],
        ),
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
          colors: [Color(0xFF1A3A6B), Color(0xFF387ED1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Net Worth',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '₹${_fmt(netWorth)}',
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w700,
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
                'Available Cash  ',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '₹${balance.toStringAsFixed(2)}',
                style: GoogleFonts.jetBrainsMono(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
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
    return v.toStringAsFixed(0);
  }
}

// ─── Quick Actions ────────────────────────────────────────────────────────────

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow();
  @override
  Widget build(BuildContext context) {
    final actions = [
      (LucideIcons.barChart2, 'Markets', AppColors.primary),
      (LucideIcons.listTodo, 'Orders', AppColors.accent),
      (LucideIcons.fileText, 'IPO', AppColors.warning),
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
            } else if (a.$2 == 'Orders') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OrdersScreen()),
              );
            } else if (a.$2 == 'IPO') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const IPOScreen()),
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
              'Options Chain',
              const OptionsChainScreen(),
              icon: Icons.stacked_bar_chart,
            ),
            _sheetItem(
              ctx,
              'F&O Dashboard',
              const FnoDashboardScreen(),
              icon: LucideIcons.activity,
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
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
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
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: _PnlItem(label: "Realized P&L", value: realized),
          ),
          Container(width: 1, height: 36, color: AppColors.border),
          Expanded(
            child: _PnlItem(label: "Unrealized P&L", value: unrealized),
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
          '${isPos ? '+' : ''}₹${value.abs().toStringAsFixed(0)}',
          style: GoogleFonts.jetBrainsMono(
            color: isPos ? AppColors.success : AppColors.danger,
            fontSize: 16,
            fontWeight: FontWeight.w700,
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
        Text(title, style: Theme.of(context).textTheme.titleLarge),
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
        boxShadow: AppColors.softShadow,
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
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
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
                        color: AppColors.primary.withValues(alpha: 0.1),
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
                style: GoogleFonts.jetBrainsMono(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.textPrimary,
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

// ─── Top Movers ───────────────────────────────────────────────────────────────

class _TopMoversRow extends StatelessWidget {
  final List<Stock> stocks;

  const _TopMoversRow({required this.stocks});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: stocks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) => _MoverCard(stock: stocks[index]),
      ),
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

    return InkWell(
      borderRadius: BorderRadius.circular(AppColors.cardRadius),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: stock.symbol)),
      ),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          boxShadow: AppColors.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              stock.symbol,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '₹${stock.currentPrice.toStringAsFixed(2)}',
              style: GoogleFonts.jetBrainsMono(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isPos
                    ? AppColors.success.withValues(alpha: 0.12)
                    : AppColors.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$sign${stock.changePercentage.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: isPos ? AppColors.success : AppColors.danger,
                  fontWeight: FontWeight.w700,
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
    if (stocks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        boxShadow: AppColors.softShadow,
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
    final changeColor = isPos ? AppColors.success : AppColors.danger;

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: stock.symbol)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                stock.symbol,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            PriceFlashWidget(
              price: stock.currentPrice,
              child: Text(
                '₹${stock.currentPrice.toStringAsFixed(2)}',
                style: GoogleFonts.jetBrainsMono(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: changeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$sign${stock.changePercentage.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: changeColor,
                  fontWeight: FontWeight.w700,
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

// ─── Indices Strip ────────────────────────────────────────────────────────────

class _IndicesStrip extends StatelessWidget {
  const _IndicesStrip();

  static const _indices = [
    ('NIFTY 50', '22,814.65', '+0.84%', true),
    ('SENSEX', '75,091.11', '+0.59%', true),
    ('BANK NIFTY', '48,115.30', '-0.44%', false),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < _indices.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _indices[i].$1,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    _indices[i].$2,
                    style: GoogleFonts.jetBrainsMono(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _indices[i].$4
                          ? AppColors.success.withValues(alpha: 0.12)
                          : AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _indices[i].$3,
                      style: TextStyle(
                        color: _indices[i].$4
                            ? AppColors.success
                            : AppColors.danger,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (i < _indices.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
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
    final color = isPos ? AppColors.success : AppColors.danger;
    final sign = isPos ? '+' : '';
    final bgColor = light
        ? Colors.white.withValues(alpha: 0.2)
        : color.withValues(alpha: 0.15);
    final textColor = light ? Colors.white : color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$sign₹${value.abs().toStringAsFixed(0)}  ($sign${pct.toStringAsFixed(2)}%)',
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
