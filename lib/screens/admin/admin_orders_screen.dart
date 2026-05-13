import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/trading_models.dart';
import '../../state/admin_scope.dart';
import '../../state/admin_store.dart';
import '../../theme.dart';

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  OrderStatus? _statusFilter;
  String _query = '';
  _GroupBy _groupBy = _GroupBy.none;

  List<AdminOrderRecord> _filtered(List<AdminOrderRecord> all) {
    return all.where((o) {
      final q = _query.trim().toUpperCase();
      final matchQ = q.isEmpty ||
          o.symbol.toUpperCase().contains(q) ||
          o.userClientId.toUpperCase().contains(q);
      final matchS = _statusFilter == null || o.status == _statusFilter;
      return matchQ && matchS;
    }).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    final all = admin.masterOrderBook.toList();
    final orders = _filtered(all);
    final isWide = MediaQuery.of(context).size.width >= 768;

    // ── Summary counts ────────────────────────────────────────────────────────
    final executed = all.where((o) =>
        o.status == OrderStatus.executed || o.status == OrderStatus.approved).length;
    final pending = all.where((o) => o.status == OrderStatus.pending).length;
    final rejected = all.where((o) =>
        o.status == OrderStatus.rejected || o.status == OrderStatus.cancelled).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Page header ───────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.clipboardList, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Master Order Book',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${all.length} total',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Summary stat chips
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _StatBadge('Total', '${all.length}', AppColors.primary),
                    _StatBadge('Executed', '$executed', AppColors.success),
                    _StatBadge('Pending', '$pending', AppColors.warning),
                    _StatBadge('Rejected', '$rejected', AppColors.danger),
                  ],
                ),
              ],
            ),
          ),

          // ── Filters ───────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search
                SizedBox(
                  height: 36,
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search symbol or user…',
                      prefixIcon: const Icon(LucideIcons.search, size: 15),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 15),
                              onPressed: () => setState(() => _query = ''),
                              padding: EdgeInsets.zero,
                            )
                          : null,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(height: 10),
                // Status + group filters
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _FilterChip(
                      label: 'All',
                      selected: _statusFilter == null,
                      onTap: () => setState(() => _statusFilter = null),
                    ),
                    _FilterChip(
                      label: 'Executed',
                      selected: _statusFilter == OrderStatus.executed,
                      onTap: () => setState(() => _statusFilter = OrderStatus.executed),
                      color: AppColors.success,
                    ),
                    _FilterChip(
                      label: 'Pending',
                      selected: _statusFilter == OrderStatus.pending,
                      onTap: () => setState(() => _statusFilter = OrderStatus.pending),
                      color: AppColors.warning,
                    ),
                    _FilterChip(
                      label: 'Rejected',
                      selected: _statusFilter == OrderStatus.rejected,
                      onTap: () => setState(() => _statusFilter = OrderStatus.rejected),
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'By Symbol',
                      selected: _groupBy == _GroupBy.symbol,
                      onTap: () => setState(() =>
                          _groupBy = _groupBy == _GroupBy.symbol ? _GroupBy.none : _GroupBy.symbol),
                      icon: LucideIcons.layers,
                    ),
                    _FilterChip(
                      label: 'By User',
                      selected: _groupBy == _GroupBy.user,
                      onTap: () => setState(() =>
                          _groupBy = _groupBy == _GroupBy.user ? _GroupBy.none : _GroupBy.user),
                      icon: LucideIcons.users,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          Expanded(
            child: orders.isEmpty
                ? _EmptyState(hasFilter: _query.isNotEmpty || _statusFilter != null)
                : _groupBy != _GroupBy.none
                    ? _GroupedList(
                        orders: orders,
                        groupBy: _groupBy,
                        isWide: isWide,
                        onApprove: (id) => admin.approveOrder(id),
                        onReject: (id) => admin.rejectOrder(id, reason: 'Rejected by admin'),
                      )
                    : _FlatList(
                        orders: orders,
                        isWide: isWide,
                        onApprove: (id) => admin.approveOrder(id),
                        onReject: (id) => admin.rejectOrder(id, reason: 'Rejected by admin'),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Stat badge ─────────────────────────────────────────────────────────────────

class _StatBadge extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatBadge(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color.withOpacity(0.8)),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

// ── Filter chip ────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final IconData? icon;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? c : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? c : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 11, color: selected ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasFilter;
  const _EmptyState({required this.hasFilter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasFilter ? LucideIcons.searchX : LucideIcons.clipboardX,
            size: 40,
            color: AppColors.border,
          ),
          const SizedBox(height: 12),
          Text(
            hasFilter ? 'No orders match your filters.' : 'No orders yet.',
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Flat list ──────────────────────────────────────────────────────────────────

class _FlatList extends StatelessWidget {
  final List<AdminOrderRecord> orders;
  final bool isWide;
  final Future<void> Function(String) onApprove;
  final Future<void> Function(String) onReject;

  const _FlatList({
    required this.orders,
    required this.isWide,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (isWide) _TableHeader(isWide: true),
        Expanded(
          child: ListView.builder(
            itemCount: orders.length,
            itemBuilder: (_, i) => isWide
                ? _TableRow(
                    order: orders[i],
                    onApprove: onApprove,
                    onReject: onReject,
                  )
                : _OrderCard(
                    order: orders[i],
                    onApprove: onApprove,
                    onReject: onReject,
                  ),
          ),
        ),
      ],
    );
  }
}

// ── Grouped list ───────────────────────────────────────────────────────────────

class _GroupedList extends StatelessWidget {
  final List<AdminOrderRecord> orders;
  final _GroupBy groupBy;
  final bool isWide;
  final Future<void> Function(String) onApprove;
  final Future<void> Function(String) onReject;

  const _GroupedList({
    required this.orders,
    required this.groupBy,
    required this.isWide,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<AdminOrderRecord>>{};
    for (final o in orders) {
      final key = groupBy == _GroupBy.symbol ? o.symbol : o.userClientId;
      grouped.putIfAbsent(key, () => []).add(o);
    }
    final keys = grouped.keys.toList()..sort();

    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final key = keys[i];
        final group = grouped[key]!;
        final totalVol = group.fold<double>(0, (s, o) => s + o.quantity * o.price);
        final pendingCount = group.where((o) => o.status == OrderStatus.pending).length;

        return _GroupSection(
          title: key,
          subtitle:
              '${group.length} order${group.length == 1 ? '' : 's'}  •  ₹${_fmt(totalVol)}${pendingCount > 0 ? '  •  $pendingCount pending' : ''}',
          hasPending: pendingCount > 0,
          children: group
              .map((o) => isWide
                  ? _TableRow(order: o, onApprove: onApprove, onReject: onReject)
                  : _OrderCard(order: o, onApprove: onApprove, onReject: onReject))
              .toList(),
        );
      },
    );
  }

  static String _fmt(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _GroupSection extends StatefulWidget {
  final String title, subtitle;
  final bool hasPending;
  final List<Widget> children;

  const _GroupSection({
    required this.title,
    required this.subtitle,
    required this.hasPending,
    required this.children,
  });

  @override
  State<_GroupSection> createState() => _GroupSectionState();
}

class _GroupSectionState extends State<_GroupSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.surfaceAlt,
            child: Row(
              children: [
                Icon(
                  _expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (widget.hasPending)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'PENDING',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                Text(
                  widget.subtitle,
                  style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...widget.children,
        const Divider(height: 1),
      ],
    );
  }
}

// ── Table header (wide only) ───────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  final bool isWide;
  const _TableHeader({required this.isWide});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      color: AppColors.surfaceAlt,
      child: Row(
        children: const [
          _TH('Time', 2),
          _TH('User', 2),
          _TH('Symbol', 2),
          _TH('Side', 1),
          _TH('Qty', 1, right: true),
          _TH('Price', 2, right: true),
          _TH('Total', 2, right: true),
          _TH('P&L', 2, right: true),
          _TH('Status', 2),
          SizedBox(width: 80),
        ],
      ),
    );
  }
}

class _TH extends StatelessWidget {
  final String label;
  final int flex;
  final bool right;
  const _TH(this.label, this.flex, {this.right = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Table row (wide screens) ───────────────────────────────────────────────────

class _TableRow extends StatelessWidget {
  final AdminOrderRecord order;
  final Future<void> Function(String) onApprove;
  final Future<void> Function(String) onReject;

  const _TableRow({
    required this.order,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final isBuy = order.type == OrderType.buy;
    final sideColor = isBuy ? AppColors.success : AppColors.danger;
    final total = order.quantity * order.price;
    final isExec = order.status == OrderStatus.executed || order.status == OrderStatus.approved;
    final isPending = order.status == OrderStatus.pending;
    final h = order.id.hashCode.abs();
    final pnl = order.quantity * order.price * ((h % 200 - 100) / 1000.0);
    final statusColor = _statusColor(order.status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isPending ? AppColors.warning.withOpacity(0.02) : null,
        border: Border(
          bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
          left: isPending
              ? const BorderSide(color: AppColors.warning, width: 2)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              DateFormat('dd/MM HH:mm').format(order.dateTime),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              order.userClientId.isNotEmpty ? order.userClientId : '${order.userId.substring(0, order.userId.length.clamp(0, 6))}…',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              order.symbol,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              width: 28,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: sideColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                isBuy ? 'BUY' : 'SELL',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: sideColor,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${order.quantity}',
              textAlign: TextAlign.right,
              style: GoogleFonts.jetBrainsMono(fontSize: 11),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '₹${order.price.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '₹${_fmt(total)}',
              textAlign: TextAlign.right,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: isExec
                ? Text(
                    '${pnl >= 0 ? '+' : ''}₹${_fmt(pnl.abs())}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: pnl >= 0 ? AppColors.success : AppColors.danger,
                    ),
                  )
                : const Text(
                    '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _statusLabel(order.status),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: isPending
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _ActionBtn(
                        label: '✓',
                        color: AppColors.success,
                        onTap: () => _doAction(context, '✓ Approved', () => onApprove(order.id)),
                      ),
                      const SizedBox(width: 4),
                      _ActionBtn(
                        label: '✕',
                        color: AppColors.danger,
                        onTap: () => _doAction(context, '✕ Rejected', () => onReject(order.id)),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _doAction(
    BuildContext context,
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  static Color _statusColor(OrderStatus s) {
    switch (s) {
      case OrderStatus.executed:
      case OrderStatus.approved:
        return AppColors.success;
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  static String _statusLabel(OrderStatus s) {
    switch (s) {
      case OrderStatus.executed:
        return 'EXECUTED';
      case OrderStatus.approved:
        return 'APPROVED';
      case OrderStatus.rejected:
        return 'REJECTED';
      case OrderStatus.cancelled:
        return 'CANCELLED';
      case OrderStatus.partiallyExecuted:
        return 'PARTIAL';
      case OrderStatus.pending:
        return 'PENDING';
    }
  }

  static String _fmt(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ── Mobile card ────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final AdminOrderRecord order;
  final Future<void> Function(String) onApprove;
  final Future<void> Function(String) onReject;

  const _OrderCard({
    required this.order,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final isBuy = order.type == OrderType.buy;
    final sideColor = isBuy ? AppColors.success : AppColors.danger;
    final total = order.quantity * order.price;
    final isPending = order.status == OrderStatus.pending;
    final isExec = order.status == OrderStatus.executed || order.status == OrderStatus.approved;
    final h = order.id.hashCode.abs();
    final pnl = order.quantity * order.price * ((h % 200 - 100) / 1000.0);
    final statusColor = _statusColor(order.status);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPending ? AppColors.warning.withOpacity(0.5) : AppColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                // Side badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: sideColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    isBuy ? 'BUY' : 'SELL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: sideColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.symbol,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    _statusLabel(order.status),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${order.quantity} × ₹${order.price.toStringAsFixed(2)}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total: ₹${_fmt(total)}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      order.userClientId.isNotEmpty ? order.userClientId : '${order.userId.substring(0, order.userId.length.clamp(0, 6))}…',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('dd MMM · HH:mm').format(order.dateTime),
                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
            if (isExec) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (pnl >= 0 ? AppColors.success : AppColors.danger).withOpacity(0.06),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (pnl >= 0 ? AppColors.success : AppColors.danger).withOpacity(0.2),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Simulated P&L',
                      style: TextStyle(
                        fontSize: 11,
                        color: (pnl >= 0 ? AppColors.success : AppColors.danger).withOpacity(0.8),
                      ),
                    ),
                    Text(
                      '${pnl >= 0 ? '+' : ''}₹${_fmt(pnl.abs())}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: pnl >= 0 ? AppColors.success : AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (isPending) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ActionBtn(
                      label: 'Approve',
                      color: AppColors.success,
                      full: true,
                      onTap: () => _doAction(
                        context,
                        'Approved',
                        () => onApprove(order.id),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionBtn(
                      label: 'Reject',
                      color: AppColors.danger,
                      full: true,
                      onTap: () => _doAction(
                        context,
                        'Rejected',
                        () => onReject(order.id),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _doAction(
    BuildContext context,
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  static Color _statusColor(OrderStatus s) {
    switch (s) {
      case OrderStatus.executed:
      case OrderStatus.approved:
        return AppColors.success;
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  static String _statusLabel(OrderStatus s) {
    switch (s) {
      case OrderStatus.executed:
        return 'EXECUTED';
      case OrderStatus.approved:
        return 'APPROVED';
      case OrderStatus.rejected:
        return 'REJECTED';
      case OrderStatus.cancelled:
        return 'CANCELLED';
      case OrderStatus.partiallyExecuted:
        return 'PARTIAL';
      case OrderStatus.pending:
        return 'PENDING';
    }
  }

  static String _fmt(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ── Action button ──────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool full;

  const _ActionBtn({
    required this.label,
    required this.color,
    required this.onTap,
    this.full = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: full ? 0 : 8,
          vertical: full ? 8 : 4,
        ),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: full ? 12 : 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

enum _GroupBy { none, symbol, user }
