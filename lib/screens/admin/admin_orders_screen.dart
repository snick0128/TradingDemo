import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/trade_ledger.dart';
import '../../models/trading_models.dart';
import '../../state/admin_scope.dart';
import '../../theme.dart';

// ── Timestamp helpers ──────────────────────────────────────────────────────────

bool _isUnknownTime(DateTime dt) => dt.year < 2000;

String _fmtTimestampFull(DateTime dt) {
  if (_isUnknownTime(dt)) return 'Timestamp unavailable';
  return DateFormat('dd MMM yyyy, hh:mm:ss a').format(dt);
}

String _fmtTimestampCompact(DateTime dt) {
  if (_isUnknownTime(dt)) return '—';
  return DateFormat('h:mm:ss a').format(dt);
}

String _fmtDateCompact(DateTime dt) {
  if (_isUnknownTime(dt)) return '—';
  return DateFormat('dd/MM h:mm a').format(dt);
}

// ── Tab enum ───────────────────────────────────────────────────────────────────

enum _Tab {
  all, open, closed, profit, loss, large, risk, rejected;

  String get label {
    switch (this) {
      case all:      return 'All';
      case open:     return 'Open';
      case closed:   return 'Closed';
      case profit:   return 'Profit';
      case loss:     return 'Loss';
      case large:    return 'Large';
      case risk:     return 'Risk';
      case rejected: return 'Rejected';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});
  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  _Tab _tab = _Tab.all;
  String _query = '';
  String? _expandedId;

  List<TradeLedgerEntry> _applyFilters(List<TradeLedgerEntry> all) {
    var list = all;
    switch (_tab) {
      case _Tab.open:
        list = list.where((t) => t.status == TradeStatus.open).toList();
        break;
      case _Tab.closed:
        list = list.where((t) => t.status == TradeStatus.closed).toList();
        break;
      case _Tab.profit:
        list = list.where((t) => t.status == TradeStatus.closed && t.netPnl > 0).toList();
        break;
      case _Tab.loss:
        list = list.where((t) => t.status == TradeStatus.closed && t.netPnl < 0).toList();
        break;
      case _Tab.large:
        list = list.where((t) => t.entryValue > 500000).toList();
        break;
      case _Tab.risk:
        list = list.where((t) => t.health == TradeHealth.risk).toList();
        break;
      case _Tab.rejected:
        list = list.where((t) => t.status == TradeStatus.rejected).toList();
        break;
      case _Tab.all:
        break;
    }
    final q = _query.trim().toUpperCase();
    if (q.isNotEmpty) {
      list = list.where((t) =>
          t.symbol.toUpperCase().contains(q) ||
          t.userClientId.toUpperCase().contains(q) ||
          t.exchange.toUpperCase().contains(q)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final store = AdminScope.of(context);
    // buildTradeLedger already sorts most-recent-activity first (sortTime = exitTime ?? entryTime)
    final ledger = buildTradeLedger(store.masterOrderBook);
    final filtered = _applyFilters(ledger);
    final isWide = MediaQuery.of(context).size.width >= 900;

    final today = DateTime.now();
    final todayCount = ledger.where((t) =>
        t.entryTime.year == today.year &&
        t.entryTime.month == today.month &&
        t.entryTime.day == today.day).length;
    final openList    = ledger.where((t) => t.status == TradeStatus.open).toList();
    final closedList  = ledger.where((t) => t.status == TradeStatus.closed).toList();
    final winCount    = closedList.where((t) => t.netPnl > 0).length;
    final winRate     = closedList.isEmpty ? 0.0 : winCount / closedList.length;
    final userGrossPnl = closedList.fold<double>(0, (s, t) => s + t.grossPnl);
    // Admin revenue = real brokerage collected across ALL trades (0.03% per leg)
    final adminRevenue = ledger.fold<double>(0, (s, t) => s + t.brokerage);

    final tabCounts = {
      _Tab.all:      ledger.length,
      _Tab.open:     openList.length,
      _Tab.closed:   closedList.length,
      _Tab.profit:   closedList.where((t) => t.netPnl > 0).length,
      _Tab.loss:     closedList.where((t) => t.netPnl < 0).length,
      _Tab.large:    ledger.where((t) => t.entryValue > 500000).length,
      _Tab.risk:     ledger.where((t) => t.health == TradeHealth.risk).length,
      _Tab.rejected: ledger.where((t) => t.status == TradeStatus.rejected).length,
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _SummaryBar(
            todayCount:    todayCount,
            openCount:     openList.length,
            closedCount:   closedList.length,
            winRate:       winRate,
            userGrossPnl:  userGrossPnl,
            adminRevenue:  adminRevenue,
          ),
          _FilterRow(
            query:          _query,
            activeTab:      _tab,
            tabCounts:      tabCounts,
            onQueryChanged: (v) => setState(() => _query = v),
            onTabChanged:   (t) => setState(() { _tab = t; _expandedId = null; }),
          ),
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(tab: _tab, hasQuery: _query.isNotEmpty)
                : isWide
                    ? _DesktopLedger(
                        entries:      filtered,
                        expandedId:   _expandedId,
                        closedTrades: closedList,
                        onExpand: (id) => setState(() =>
                            _expandedId = _expandedId == id ? null : id),
                      )
                    : _MobileLedger(
                        entries:    filtered,
                        expandedId: _expandedId,
                        onExpand: (id) => setState(() =>
                            _expandedId = _expandedId == id ? null : id),
                      ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SUMMARY BAR
// ═══════════════════════════════════════════════════════════════════════════════

class _SummaryBar extends StatelessWidget {
  final int todayCount, openCount, closedCount;
  final double winRate, userGrossPnl, adminRevenue;
  const _SummaryBar({
    required this.todayCount,
    required this.openCount,
    required this.closedCount,
    required this.winRate,
    required this.userGrossPnl,
    required this.adminRevenue,
  });

  static String _fmtV(double v) {
    final abs = v.abs();
    if (abs >= 10000000) return '₹${(abs / 10000000).toStringAsFixed(2)}Cr';
    if (abs >= 100000)   return '₹${(abs / 100000).toStringAsFixed(1)}L';
    if (abs >= 1000)     return '₹${(abs / 1000).toStringAsFixed(1)}K';
    return '₹${abs.toStringAsFixed(0)}';
  }

  static String _fmtPnl(double v) {
    final s = _fmtV(v);
    return v >= 0 ? '+$s' : '-$s';
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    final cards = [
      _SCard(label: 'Trades Today',    value: '$todayCount',
          icon: LucideIcons.calendar,  color: AppColors.primary),
      _SCard(label: 'Open Positions',  value: '$openCount',
          icon: LucideIcons.radio,     color: AppColors.warning),
      _SCard(label: 'Closed Trades',   value: '$closedCount',
          icon: LucideIcons.checkCircle2, color: AppColors.success),
      _SCard(label: 'Win Rate',
          value: '${(winRate * 100).toStringAsFixed(1)}%',
          icon: LucideIcons.target,
          color: winRate >= 0.5 ? AppColors.success : AppColors.danger),
      _SCard(label: 'User Gross P&L',  value: _fmtPnl(userGrossPnl),
          icon: LucideIcons.trendingUp,
          color: userGrossPnl >= 0 ? AppColors.success : AppColors.danger),
      _SCard(label: 'Admin Revenue',   value: _fmtV(adminRevenue),
          icon: LucideIcons.coins,     color: const Color(0xFF7B61FF)),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: isWide
          ? Row(children: cards
              .map((c) => Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4), child: c)))
              .toList())
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: cards
                  .map((c) => SizedBox(width: 144,
                      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: c)))
                  .toList()),
            ),
    );
  }
}

class _SCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _SCard({required this.label, required this.value,
      required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: GoogleFonts.jetBrainsMono(
                  fontSize: 13, fontWeight: FontWeight.w800, color: color)),
              Text(label, style: GoogleFonts.inter(
                  fontSize: 9, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis),
            ],
          )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FILTER ROW  (search + scrollable tab chips)
// ═══════════════════════════════════════════════════════════════════════════════

class _FilterRow extends StatelessWidget {
  final String query;
  final _Tab activeTab;
  final Map<_Tab, int> tabCounts;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_Tab> onTabChanged;
  const _FilterRow({
    required this.query, required this.activeTab,
    required this.tabCounts, required this.onQueryChanged,
    required this.onTabChanged,
  });

  static Color _tabColor(_Tab t) {
    switch (t) {
      case _Tab.open:     return AppColors.warning;
      case _Tab.closed:   return AppColors.success;
      case _Tab.profit:   return AppColors.success;
      case _Tab.loss:     return AppColors.danger;
      case _Tab.large:    return const Color(0xFF7B61FF);
      case _Tab.risk:     return AppColors.danger;
      case _Tab.rejected: return AppColors.textSecondary;
      case _Tab.all:      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Divider(height: 1),
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: TextField(
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              hintText: 'Search symbol, user or exchange…',
              hintStyle: GoogleFonts.inter(fontSize: 12),
              prefixIcon: const Icon(LucideIcons.search, size: 14),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 14),
                      onPressed: () => onQueryChanged(''),
                      padding: EdgeInsets.zero)
                  : null,
            ),
            style: GoogleFonts.inter(fontSize: 13),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _Tab.values.map((t) {
              final active = activeTab == t;
              final count  = tabCounts[t] ?? 0;
              final c      = _tabColor(t);
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => onTabChanged(t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: active ? c : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: active ? c : AppColors.border),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(t.label, style: GoogleFonts.inter(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: active ? Colors.white : AppColors.textSecondary)),
                      if (count > 0) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: active ? Colors.white.withOpacity(0.2) : c.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('$count', style: GoogleFonts.inter(
                              fontSize: 9, fontWeight: FontWeight.w800,
                              color: active ? Colors.white : c)),
                        ),
                      ],
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DESKTOP LEDGER
// ═══════════════════════════════════════════════════════════════════════════════

class _DesktopLedger extends StatelessWidget {
  final List<TradeLedgerEntry> entries;
  final String? expandedId;
  final ValueChanged<String> onExpand;
  final List<TradeLedgerEntry> closedTrades;
  const _DesktopLedger({
    required this.entries, required this.expandedId,
    required this.onExpand, required this.closedTrades,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        flex: 3,
        child: Column(children: [
          _TableHeader(),
          Expanded(
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (_, i) {
                final t = entries[i];
                return Column(children: [
                  _TableRow(
                    entry: t,
                    isExpanded: expandedId == t.id,
                    onTap: () => onExpand(t.id),
                  ),
                  if (expandedId == t.id) _ExpandedDrawer(entry: t),
                ]);
              },
            ),
          ),
        ]),
      ),
      Container(
        width: 236,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(left: BorderSide(color: AppColors.border)),
        ),
        child: _WinnersLosersPanel(closedTrades: closedTrades),
      ),
    ]);
  }
}

// ── Table header ───────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      color: AppColors.surfaceAlt,
      child: const Row(children: [
        _TH('User',       2),
        _TH('Symbol',     2),
        _TH('Exch',       1),
        _TH('Qty',        1, right: true),
        _TH('Entry',      2, right: true),
        _TH('Exit',       2, right: true),
        _TH('Gross P&L',  2, right: true),
        _TH('Brok',       1, right: true),
        _TH('Net P&L',    2, right: true),
        _TH('Duration',   2),
        _TH('Health',     1),
        _TH('Status',     2),
        SizedBox(width: 28),
      ]),
    );
  }
}

class _TH extends StatelessWidget {
  final String label;
  final int flex;
  final bool right;
  const _TH(this.label, this.flex, {this.right = false});

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(label,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: AppColors.textSecondary, letterSpacing: 0.3)),
  );
}

// ── Table row ──────────────────────────────────────────────────────────────────

class _TableRow extends StatelessWidget {
  final TradeLedgerEntry entry;
  final bool isExpanded;
  final VoidCallback onTap;
  const _TableRow({required this.entry, required this.isExpanded, required this.onTap});

  static Color _healthColor(TradeHealth h) {
    switch (h) {
      case TradeHealth.profit:  return AppColors.success;
      case TradeHealth.loss:    return AppColors.danger;
      case TradeHealth.risk:    return const Color(0xFFFF6D00);
      case TradeHealth.large:   return const Color(0xFF7B61FF);
      case TradeHealth.neutral: return AppColors.border;
    }
  }

  static Color _exchColor(String e) {
    switch (e.toUpperCase()) {
      case 'BSE': return const Color(0xFF1565C0);
      case 'MCX': return const Color(0xFF6A1B9A);
      case 'NFO': return const Color(0xFF00897B);
      default:    return AppColors.primary;
    }
  }

  static String _fmtPnl(double v) {
    final abs = v.abs();
    final s = abs >= 10000000 ? '₹${(abs/10000000).toStringAsFixed(1)}Cr'
            : abs >= 100000   ? '₹${(abs/100000).toStringAsFixed(1)}L'
            : abs >= 1000     ? '₹${(abs/1000).toStringAsFixed(1)}K'
            : '₹${abs.toStringAsFixed(0)}';
    return v >= 0 ? '+$s' : '-$s';
  }

  static String _fmtDuration(Duration d) {
    if (d.inDays > 0)    return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours > 0)   return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final pnlColor  = entry.netPnl >= 0 ? AppColors.success : AppColors.danger;
    final dirColor  = entry.direction == OrderType.buy ? AppColors.success : AppColors.danger;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isExpanded ? AppColors.primary.withOpacity(0.03) : null,
          border: Border(
            bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
            left: BorderSide(color: _healthColor(entry.health), width: 2),
          ),
        ),
        child: Row(children: [
          // User
          Expanded(flex: 2, child: Text(
            entry.userClientId.isNotEmpty
                ? entry.userClientId
                : entry.userId.substring(0, entry.userId.length.clamp(0, 8)),
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
            overflow: TextOverflow.ellipsis,
          )),
          // Symbol + L/S badge
          Expanded(flex: 2, child: Row(children: [
            Expanded(child: Text(entry.symbol, style: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                overflow: TextOverflow.ellipsis)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: dirColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(entry.direction == OrderType.buy ? 'L' : 'S',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: dirColor)),
            ),
          ])),
          // Exchange
          Expanded(flex: 1, child: Text(entry.exchange,
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                  color: _exchColor(entry.exchange)))),
          // Qty
          Expanded(flex: 1, child: Text('${entry.quantity}',
              textAlign: TextAlign.right,
              style: GoogleFonts.jetBrainsMono(fontSize: 11))),
          // Entry price + time
          Expanded(flex: 2, child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(entry.entryPrice > 0
                      ? '₹${entry.entryPrice.toStringAsFixed(2)}' : '—',
                  style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textPrimary)),
              Text(_fmtDateCompact(entry.entryTime),
                  style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondary)),
            ],
          )),
          // Exit price + time
          Expanded(flex: 2, child: entry.exitPrice != null
              ? Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('₹${entry.exitPrice!.toStringAsFixed(2)}',
                      style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textPrimary)),
                  Text(_fmtDateCompact(entry.exitTime!),
                      style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondary)),
                ])
              : Text('—', textAlign: TextAlign.right,
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary))),
          // Gross P&L
          Expanded(flex: 2, child: entry.status == TradeStatus.closed
              ? Text(_fmtPnl(entry.grossPnl), textAlign: TextAlign.right,
                  style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w600,
                      color: entry.grossPnl >= 0 ? AppColors.success : AppColors.danger))
              : Text('—', textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
          // Brokerage (real: 0.03% of turnover)
          Expanded(flex: 1, child: Text(
            entry.brokerage > 0 ? '₹${entry.brokerage.toStringAsFixed(0)}' : '—',
            textAlign: TextAlign.right,
            style: GoogleFonts.jetBrainsMono(fontSize: 9, color: AppColors.textSecondary),
          )),
          // Net P&L
          Expanded(flex: 2, child: entry.status == TradeStatus.closed
              ? Text(_fmtPnl(entry.netPnl), textAlign: TextAlign.right,
                  style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w800,
                      color: pnlColor))
              : Text('—', textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
          // Duration
          Expanded(flex: 2, child: Text(
              _isUnknownTime(entry.entryTime) ? '—' : _fmtDuration(entry.holdingDuration),
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textSecondary))),
          // Health
          Expanded(flex: 1, child: _HealthBadge(health: entry.health, mini: true)),
          // Status
          Expanded(flex: 2, child: _StatusBadge(status: entry.status)),
          // Chevron
          SizedBox(width: 28, child: Icon(
            isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
            size: 14, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }
}

// ── Expanded drawer ────────────────────────────────────────────────────────────

class _ExpandedDrawer extends StatelessWidget {
  final TradeLedgerEntry entry;
  const _ExpandedDrawer({required this.entry});

  static String _fmtV(double v) {
    final abs = v.abs();
    if (abs >= 100000) return '₹${(abs / 100000).toStringAsFixed(2)}L';
    if (abs >= 1000)   return '₹${(abs / 1000).toStringAsFixed(1)}K';
    return '₹${abs.toStringAsFixed(2)}';
  }

  static String _fmtDur(Duration d) {
    if (d.inDays > 0)    return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours > 0)   return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  }

  static String _healthLabel(TradeHealth h) {
    switch (h) {
      case TradeHealth.profit:  return 'Profit';
      case TradeHealth.loss:    return 'Loss';
      case TradeHealth.risk:    return 'High Risk Loss';
      case TradeHealth.large:   return 'Large Trade';
      case TradeHealth.neutral: return 'Neutral';
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry0 = entry.sourceOrders.isNotEmpty ? entry.sourceOrders.first : null;
    final exit0  = entry.sourceOrders.length > 1  ? entry.sourceOrders.last  : null;
    final dirColor = entry.direction == OrderType.buy ? AppColors.success : AppColors.danger;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.clipboardList, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text('Trade Breakdown', style: GoogleFonts.inter(
              fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(width: 10),
          Text('${_isUnknownTime(entry.entryTime) ? 'Date unavailable' : DateFormat('dd MMM yyyy').format(entry.entryTime)} · ${entry.product} · ${entry0?.variety ?? 'MARKET'}',
              style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Entry leg
          Expanded(child: _LegCard(
            title: 'ENTRY LEG',
            color: dirColor,
            rows: [
              ('Order ID',  _short(entry.entryOrderId)),
              ('Side',      entry.direction == OrderType.buy ? 'BUY — Long' : 'SELL — Short'),
              ('Fill Price','₹${entry.entryPrice.toStringAsFixed(2)}'),
              ('Quantity',  '${entry.quantity}'),
              ('Notional',  _fmtV(entry.entryValue)),
              ('Time',      _fmtTimestampFull(entry.entryTime)),
              ('Exchange',  entry.exchange),
              ('Product',   entry.product),
            ],
          )),
          const SizedBox(width: 10),
          // Exit leg
          Expanded(child: entry.exitPrice != null
              ? _LegCard(
                  title: 'EXIT LEG',
                  color: entry.direction == OrderType.buy ? AppColors.danger : AppColors.success,
                  rows: [
                    ('Order ID',  _short(entry.exitOrderId ?? '')),
                    ('Side',      entry.direction == OrderType.buy ? 'SELL — Close' : 'BUY — Close'),
                    ('Fill Price','₹${entry.exitPrice!.toStringAsFixed(2)}'),
                    ('Quantity',  '${entry.quantity}'),
                    ('Notional',  _fmtV(entry.exitValue)),
                    ('Time',      _fmtTimestampFull(entry.exitTime!)),
                    ('Duration',  _isUnknownTime(entry.entryTime) ? 'Timestamp unavailable' : _fmtDur(entry.holdingDuration)),
                    ('Variety',   exit0?.variety ?? '—'),
                  ],
                )
              : _LegCard(
                  title: 'EXIT LEG',
                  color: AppColors.textSecondary,
                  rows: const [('Status', 'Position still open — awaiting close')],
                )),
          const SizedBox(width: 10),
          // P&L breakdown
          Expanded(child: _LegCard(
            title: 'P&L BREAKDOWN',
            color: entry.netPnl >= 0 ? AppColors.success : AppColors.danger,
            rows: [
              ('Entry Value', _fmtV(entry.entryValue)),
              ('Exit Value',  entry.exitPrice != null ? _fmtV(entry.exitValue) : '—'),
              ('Gross P&L',   entry.status == TradeStatus.closed ? _fmtV(entry.grossPnl) : '—'),
              ('Brokerage',   entry.brokerage > 0 ? '-₹${entry.brokerage.toStringAsFixed(2)}' : '—'),
              ('Net P&L',     entry.status == TradeStatus.closed ? _fmtV(entry.netPnl) : '—'),
              ('Health',      _healthLabel(entry.health)),
              ('User',        entry.userClientId.isNotEmpty ? entry.userClientId : entry.userId.substring(0, entry.userId.length.clamp(0, 10))),
              if (entry0?.rejectionReason != null)
                ('Reason', entry0!.rejectionReason!),
            ],
          )),
        ]),
      ]),
    );
  }

  static String _short(String s) => s.length > 14 ? '${s.substring(0, 14)}…' : s;
}

class _LegCard extends StatelessWidget {
  final String title;
  final Color color;
  final List<(String, String)> rows;
  const _LegCard({required this.title, required this.color, required this.rows});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: GoogleFonts.inter(
          fontSize: 9, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.8)),
      const SizedBox(height: 8),
      ...rows.map((r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(width: 72, child: Text(r.$1, style: GoogleFonts.inter(
              fontSize: 10, color: AppColors.textSecondary))),
          Expanded(child: Text(r.$2, style: GoogleFonts.inter(
              fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis)),
        ]),
      )),
    ]),
  );
}

// ── Winners / Losers side panel ────────────────────────────────────────────────

class _WinnersLosersPanel extends StatefulWidget {
  final List<TradeLedgerEntry> closedTrades;
  const _WinnersLosersPanel({required this.closedTrades});
  @override
  State<_WinnersLosersPanel> createState() => _WinnersLosersPanelState();
}

class _WinnersLosersPanelState extends State<_WinnersLosersPanel> {
  bool _showWinners = true;

  static String _fmtPnl(double v) {
    final abs = v.abs();
    final s = abs >= 100000 ? '₹${(abs/100000).toStringAsFixed(1)}L'
            : abs >= 1000   ? '₹${(abs/1000).toStringAsFixed(1)}K'
            : '₹${abs.toStringAsFixed(0)}';
    return v >= 0 ? '+$s' : '-$s';
  }

  @override
  Widget build(BuildContext context) {
    // Build real per-user net P&L from matched closed trades only
    final pnlByUser   = <String, double>{};
    final labelByUser = <String, String>{};
    for (final t in widget.closedTrades) {
      pnlByUser[t.userId] = (pnlByUser[t.userId] ?? 0) + t.netPnl;
      if (t.userClientId.isNotEmpty) labelByUser[t.userId] = t.userClientId;
    }
    final sorted  = pnlByUser.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    final winners = sorted.where((e) => e.value > 0).take(5).toList();
    final losers  = sorted.reversed.where((e) => e.value < 0).take(5).toList();
    final list    = _showWinners ? winners : losers;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _WLToggle(
              label: 'Winners', active: _showWinners,
              color: AppColors.success,
              onTap: () => setState(() => _showWinners = true))),
          const SizedBox(width: 6),
          Expanded(child: _WLToggle(
              label: 'Losers', active: !_showWinners,
              color: AppColors.danger,
              onTap: () => setState(() => _showWinners = false))),
        ]),
        const SizedBox(height: 12),
        if (list.isEmpty)
          Center(child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text('No closed trades yet.',
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
          ))
        else
          ...list.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            final label   = labelByUser[e.key] ?? e.key.substring(0, e.key.length.clamp(0, 8));
            final initials= label.substring(0, label.length.clamp(0, 2)).toUpperCase();
            final c       = e.value >= 0 ? AppColors.success : AppColors.danger;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                CircleAvatar(radius: 15,
                    backgroundColor: c.withOpacity(0.12),
                    child: Text(initials, style: GoogleFonts.inter(
                        fontSize: 9, fontWeight: FontWeight.w800, color: c))),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis),
                  Text('#${i + 1}', style: GoogleFonts.inter(
                      fontSize: 9, color: AppColors.textSecondary)),
                ])),
                Text(_fmtPnl(e.value), style: GoogleFonts.jetBrainsMono(
                    fontSize: 11, fontWeight: FontWeight.w800, color: c)),
              ]),
            );
          }),
      ]),
    );
  }
}

class _WLToggle extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _WLToggle({required this.label, required this.active,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: active ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: active ? color : AppColors.border),
      ),
      child: Text(label, textAlign: TextAlign.center, style: GoogleFonts.inter(
          fontSize: 10, fontWeight: FontWeight.w700,
          color: active ? Colors.white : AppColors.textSecondary)),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// MOBILE LEDGER
// ═══════════════════════════════════════════════════════════════════════════════

class _MobileLedger extends StatelessWidget {
  final List<TradeLedgerEntry> entries;
  final String? expandedId;
  final ValueChanged<String> onExpand;
  const _MobileLedger({
    required this.entries, required this.expandedId, required this.onExpand});

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.all(10),
    itemCount: entries.length,
    itemBuilder: (_, i) {
      final t = entries[i];
      return Column(children: [
        _MobileCard(
            entry: t, isExpanded: expandedId == t.id,
            onTap: () => onExpand(t.id)),
        if (expandedId == t.id) _MobileDetail(entry: t),
      ]);
    },
  );
}

class _MobileCard extends StatelessWidget {
  final TradeLedgerEntry entry;
  final bool isExpanded;
  final VoidCallback onTap;
  const _MobileCard({required this.entry, required this.isExpanded, required this.onTap});

  static Color _hColor(TradeHealth h) {
    switch (h) {
      case TradeHealth.profit:  return AppColors.success;
      case TradeHealth.loss:    return AppColors.danger;
      case TradeHealth.risk:    return const Color(0xFFFF6D00);
      case TradeHealth.large:   return const Color(0xFF7B61FF);
      case TradeHealth.neutral: return AppColors.border;
    }
  }

  static String _fmtPnl(double v) {
    final abs = v.abs();
    final s = abs >= 100000 ? '₹${(abs/100000).toStringAsFixed(1)}L'
            : abs >= 1000   ? '₹${(abs/1000).toStringAsFixed(1)}K'
            : '₹${abs.toStringAsFixed(0)}';
    return v >= 0 ? '+$s' : '-$s';
  }

  static String _fmtDur(Duration d) {
    if (d.inDays > 0)    return '${d.inDays}d';
    if (d.inHours > 0)   return '${d.inHours}h';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final dirColor  = entry.direction == OrderType.buy ? AppColors.success : AppColors.danger;
    final pnlColor  = entry.netPnl >= 0 ? AppColors.success : AppColors.danger;
    final borderC   = _hColor(entry.health);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderC.withOpacity(0.4)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            // Row 1
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: dirColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(entry.direction == OrderType.buy ? 'LONG' : 'SHORT',
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: dirColor)),
              ),
              const SizedBox(width: 6),
              Text(entry.symbol, style: GoogleFonts.inter(
                  fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(width: 6),
              Text(entry.exchange, style: GoogleFonts.inter(
                  fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const Spacer(),
              _HealthBadge(health: entry.health),
              const SizedBox(width: 5),
              _StatusBadge(status: entry.status),
            ]),
            const SizedBox(height: 10),
            // Row 2: entry | exit | net P&L
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Entry', style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondary)),
                Text(entry.entryPrice > 0 ? '₹${entry.entryPrice.toStringAsFixed(2)}' : '—',
                    style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w700, color: dirColor)),
                Text(_fmtTimestampCompact(entry.entryTime),
                    style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondary)),
              ])),
              Container(width: 1, height: 36, color: AppColors.border,
                  margin: const EdgeInsets.symmetric(horizontal: 10)),
              Expanded(child: entry.exitPrice != null
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Exit', style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondary)),
                      Text('₹${entry.exitPrice!.toStringAsFixed(2)}',
                          style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.w700,
                              color: entry.direction == OrderType.buy ? AppColors.danger : AppColors.success)),
                      Text(_fmtTimestampCompact(entry.exitTime!),
                          style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondary)),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Exit', style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondary)),
                      Text('OPEN', style: GoogleFonts.inter(fontSize: 13,
                          fontWeight: FontWeight.w700, color: AppColors.warning)),
                    ])),
              Container(width: 1, height: 36, color: AppColors.border,
                  margin: const EdgeInsets.symmetric(horizontal: 10)),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Net P&L', style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondary)),
                entry.status == TradeStatus.closed
                    ? Text(_fmtPnl(entry.netPnl), style: GoogleFonts.jetBrainsMono(
                        fontSize: 15, fontWeight: FontWeight.w900, color: pnlColor))
                    : Text('—', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
              ]),
            ]),
            const SizedBox(height: 8),
            // Row 3: user, qty, duration
            Row(children: [
              const Icon(LucideIcons.user, size: 11, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(child: Text(
                entry.userClientId.isNotEmpty
                    ? entry.userClientId
                    : entry.userId.substring(0, entry.userId.length.clamp(0, 8)),
                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
              )),
              Text('${entry.quantity} qty',
                  style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              Text(_isUnknownTime(entry.entryTime) ? '—' : _fmtDur(entry.holdingDuration),
                  style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              Icon(isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 14, color: AppColors.textSecondary),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _MobileDetail extends StatelessWidget {
  final TradeLedgerEntry entry;
  const _MobileDetail({required this.entry});

  static String _fmtV(double v) {
    final abs = v.abs();
    if (abs >= 100000) return '₹${(abs/100000).toStringAsFixed(2)}L';
    if (abs >= 1000)   return '₹${(abs/1000).toStringAsFixed(1)}K';
    return '₹${abs.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surfaceAlt,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('TRADE DETAILS', style: GoogleFonts.inter(fontSize: 9,
          fontWeight: FontWeight.w800, color: AppColors.textSecondary, letterSpacing: 0.8)),
      const SizedBox(height: 8),
      _DRow('Entry Order',  entry.entryOrderId.length > 14 ? '${entry.entryOrderId.substring(0, 14)}…' : entry.entryOrderId),
      if (entry.exitOrderId != null)
        _DRow('Exit Order', entry.exitOrderId!.length > 14 ? '${entry.exitOrderId!.substring(0, 14)}…' : entry.exitOrderId!),
      _DRow('Product',   entry.product),
      _DRow('Variety',   entry.sourceOrders.isNotEmpty ? entry.sourceOrders.first.variety : '—'),
      _DRow('Entry Value', _fmtV(entry.entryValue)),
      if (entry.exitPrice != null) _DRow('Exit Value', _fmtV(entry.exitValue)),
      _DRow('Gross P&L', entry.status == TradeStatus.closed ? _fmtV(entry.grossPnl) : '—'),
      _DRow('Brokerage', entry.brokerage > 0 ? '-₹${entry.brokerage.toStringAsFixed(2)}' : '—'),
      _DRow('Net P&L',   entry.status == TradeStatus.closed ? _fmtV(entry.netPnl) : '—'),
      if (entry.sourceOrders.isNotEmpty && entry.sourceOrders.first.rejectionReason != null)
        _DRow('Reason', entry.sourceOrders.first.rejectionReason!),
    ]),
  );
}

class _DRow extends StatelessWidget {
  final String label, value;
  const _DRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      SizedBox(width: 88, child: Text(label,
          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary))),
      Expanded(child: Text(value, style: GoogleFonts.inter(
          fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED BADGES
// ═══════════════════════════════════════════════════════════════════════════════

class _HealthBadge extends StatelessWidget {
  final TradeHealth health;
  final bool mini;
  const _HealthBadge({required this.health, this.mini = false});

  static Color _c(TradeHealth h) {
    switch (h) {
      case TradeHealth.profit:  return AppColors.success;
      case TradeHealth.loss:    return AppColors.danger;
      case TradeHealth.risk:    return const Color(0xFFFF6D00);
      case TradeHealth.large:   return const Color(0xFF7B61FF);
      case TradeHealth.neutral: return AppColors.textSecondary;
    }
  }

  static String _l(TradeHealth h) {
    switch (h) {
      case TradeHealth.profit:  return 'PROFIT';
      case TradeHealth.loss:    return 'LOSS';
      case TradeHealth.risk:    return 'RISK';
      case TradeHealth.large:   return 'LARGE';
      case TradeHealth.neutral: return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (health == TradeHealth.neutral) return const SizedBox.shrink();
    final c = _c(health);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: mini ? 4 : 7, vertical: mini ? 1 : 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(_l(health), style: TextStyle(
          fontSize: mini ? 7 : 9, fontWeight: FontWeight.w800, color: c)),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final TradeStatus status;
  const _StatusBadge({required this.status});

  static Color _c(TradeStatus s) {
    switch (s) {
      case TradeStatus.open:     return AppColors.warning;
      case TradeStatus.closed:   return AppColors.success;
      case TradeStatus.rejected: return AppColors.danger;
      case TradeStatus.pending:  return AppColors.primary;
    }
  }

  static String _l(TradeStatus s) {
    switch (s) {
      case TradeStatus.open:     return 'OPEN';
      case TradeStatus.closed:   return 'CLOSED';
      case TradeStatus.rejected: return 'REJECTED';
      case TradeStatus.pending:  return 'PENDING';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(_l(status), style: TextStyle(
          fontSize: 8, fontWeight: FontWeight.w800, color: c)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final _Tab tab;
  final bool hasQuery;
  const _EmptyState({required this.tab, required this.hasQuery});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(hasQuery ? LucideIcons.searchX : LucideIcons.clipboardList,
          size: 48, color: AppColors.border),
      const SizedBox(height: 16),
      Text(hasQuery
              ? 'No trades match your search.'
              : 'No trades in "${tab.label}".',
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary)),
      const SizedBox(height: 8),
      Text('Trades appear here as users execute orders.',
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
    ]),
  );
}
