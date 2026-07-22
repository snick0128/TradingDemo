import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/trade_ledger.dart';
import '../../models/trading_models.dart';
import '../../state/admin_scope.dart';
import '../../state/admin_store.dart';
import '../../theme.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _query = '';
  bool? _isActiveFilter;
  _SortBy _sortBy = _SortBy.name;

  List<User> _filtered(List<User> users) {
    var list = users.where((u) {
      final q = _query.toLowerCase();
      final match = q.isEmpty ||
          u.name.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q) ||
          u.clientId.toLowerCase().contains(q);
      final active = _isActiveFilter == null || u.isActive == _isActiveFilter;
      return match && active;
    }).toList();

    switch (_sortBy) {
      case _SortBy.name:
        list.sort((a, b) => a.name.compareTo(b.name));
        break;
      case _SortBy.balance:
        list.sort((a, b) => b.balance.compareTo(a.balance));
        break;
      case _SortBy.registered:
        list.sort((a, b) => b.registeredAt.compareTo(a.registeredAt));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    final users = _filtered(admin.users.toList());
    final pnlMap = admin.livePnlByUser;
    final width = MediaQuery.of(context).size.width;
    final columns = width >= 1200 ? 3 : width >= 800 ? 2 : 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────
          _UsersHeader(
            totalUsers: admin.totalUsers,
            activeUsers: admin.activeSessions,
            query: _query,
            isActiveFilter: _isActiveFilter,
            sortBy: _sortBy,
            onQueryChanged: (v) => setState(() => _query = v),
            onActiveFilterChanged: (v) =>
                setState(() => _isActiveFilter = v),
            onSortChanged: (s) => setState(() => _sortBy = s),
          ),
          // ── Grid ───────────────────────────────────────────────────
          Expanded(
            child: users.isEmpty
                ? _EmptyState(isFiltered: _query.isNotEmpty || _isActiveFilter != null)
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: columns == 1 ? 2.2 : 1.9,
                    ),
                    itemCount: users.length,
                    itemBuilder: (_, i) => _UserCard(
                      user: users[i],
                      pnl: pnlMap[users[i].id] ?? 0,
                      onToggle: () => admin.toggleUserStatus(users[i].id),
                      onFund: () => _showFundDialog(context, users[i], admin),
                      onViewDetail: () =>
                          _showUserDetail(context, users[i], pnlMap[users[i].id] ?? 0),
                      onViewTrades: () => _showUserTrades(context, users[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showFundDialog(BuildContext context, User user, AdminStore admin) {
    final ctrl = TextEditingController();
    bool isAdd = true;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Fund — ${user.clientId}',
              style: GoogleFonts.inter(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Current balance: ₹${user.balance.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setS(() => isAdd = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isAdd ? Colors.green : Colors.transparent,
                          border: Border.all(color: Colors.green),
                          borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(8)),
                        ),
                        alignment: Alignment.center,
                        child: Text('Add',
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isAdd ? Colors.white : Colors.green)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setS(() => isAdd = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !isAdd ? Colors.red : Colors.transparent,
                          border: Border.all(color: Colors.red),
                          borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(8)),
                        ),
                        alignment: Alignment.center,
                        child: Text('Deduct',
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: !isAdd ? Colors.white : Colors.red)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  hintText: '0.00',
                  suffixText: isAdd ? 'credit' : 'debit',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isAdd ? Colors.green : Colors.red,
              ),
              onPressed: () {
                final raw = double.tryParse(ctrl.text);
                if (raw != null && raw > 0) {
                  final amount = isAdd ? raw : -raw;
                  admin.adjustUserBalance(user.id, amount);
                  Navigator.pop(context);
                }
              },
              child: Text(isAdd ? 'Add Money' : 'Deduct Money'),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserDetail(BuildContext context, User user, double pnl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollCtrl) => _UserDetailSheet(
          user: user,
          pnl: pnl,
          scrollController: scrollCtrl,
        ),
      ),
    );
  }

  void _showUserTrades(BuildContext context, User user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => _UserTradesSheet(
          user: user,
          scrollController: scrollCtrl,
        ),
      ),
    );
  }
}

// ── Users header ───────────────────────────────────────────────────────────────

class _UsersHeader extends StatelessWidget {
  final int totalUsers;
  final int activeUsers;
  final String query;
  final bool? isActiveFilter;
  final _SortBy sortBy;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool?> onActiveFilterChanged;
  final ValueChanged<_SortBy> onSortChanged;

  const _UsersHeader({
    required this.totalUsers,
    required this.activeUsers,
    required this.query,
    required this.isActiveFilter,
    required this.sortBy,
    required this.onQueryChanged,
    required this.onActiveFilterChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.users,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('User Management',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  )),
              const Spacer(),
              _StatPill('$totalUsers total', AppColors.primary),
              const SizedBox(width: 8),
              _StatPill('$activeUsers active', AppColors.success),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    onChanged: onQueryChanged,
                    decoration: InputDecoration(
                      hintText: 'Search name, email, or ID…',
                      hintStyle: GoogleFonts.inter(fontSize: 12),
                      prefixIcon:
                          const Icon(LucideIcons.search, size: 14),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 36),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () => onQueryChanged(''),
                              padding: EdgeInsets.zero,
                            )
                          : null,
                    ),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _FilterToggle(
                label: 'Active',
                value: isActiveFilter == true,
                onTap: () => onActiveFilterChanged(
                    isActiveFilter == true ? null : true),
                color: AppColors.success,
              ),
              const SizedBox(width: 6),
              _FilterToggle(
                label: 'Inactive',
                value: isActiveFilter == false,
                onTap: () => onActiveFilterChanged(
                    isActiveFilter == false ? null : false),
                color: AppColors.danger,
              ),
              const SizedBox(width: 8),
              _SortDropdown(
                value: sortBy,
                onChanged: onSortChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatPill(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          )),
    );
  }
}

class _FilterToggle extends StatelessWidget {
  final String label;
  final bool value;
  final VoidCallback onTap;
  final Color color;
  const _FilterToggle({
    required this.label,
    required this.value,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: value ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: value ? color : AppColors.border),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: value ? Colors.white : AppColors.textSecondary,
            )),
      ),
    );
  }
}

class _SortDropdown extends StatelessWidget {
  final _SortBy value;
  final ValueChanged<_SortBy> onChanged;
  const _SortDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_SortBy>(
          value: value,
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary),
          items: [
            DropdownMenuItem(
                value: _SortBy.name,
                child: const Text('Sort: Name')),
            DropdownMenuItem(
                value: _SortBy.balance,
                child: const Text('Sort: Balance')),
            DropdownMenuItem(
                value: _SortBy.registered,
                child: const Text('Sort: Newest')),
          ],
          onChanged: (v) => v != null ? onChanged(v) : null,
        ),
      ),
    );
  }
}

// ── User card ──────────────────────────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  final User user;
  final double pnl;
  final VoidCallback onToggle;
  final VoidCallback onFund;
  final VoidCallback onViewDetail;
  final VoidCallback onViewTrades;

  const _UserCard({
    required this.user,
    required this.pnl,
    required this.onToggle,
    required this.onFund,
    required this.onViewDetail,
    required this.onViewTrades,
  });

  static String _fmtV(double v) {
    if (v.abs() >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v.abs() >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final initials = user.name.isNotEmpty
        ? user.name
            .split(' ')
            .take(2)
            .map((w) => w.isNotEmpty ? w[0] : '')
            .join()
            .toUpperCase()
        : '?';
    final avatarColor = _hashColor(user.id);
    final pnlColor =
        pnl >= 0 ? AppColors.success : AppColors.danger;

    return GestureDetector(
      onTap: onViewDetail,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: user.isActive
                ? AppColors.border
                : AppColors.danger.withOpacity(0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row ──────────────────────────────────────────
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: avatarColor.withOpacity(0.15),
                    child: Text(
                      initials,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: avatarColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          user.clientId,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(isActive: user.isActive),
                ],
              ),
              const SizedBox(height: 12),

              // ── Financials ───────────────────────────────────────
              Row(
                children: [
                  _MetricCol(
                    label: 'Balance',
                    value: _fmtV(user.balance),
                    color: AppColors.textPrimary,
                  ),
                  const SizedBox(width: 16),
                  _MetricCol(
                    label: 'Margin Limit',
                    value: _fmtV(user.marginLimit),
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 16),
                  _MetricCol(
                    label: 'Net P&L (Lifetime)',
                    value: '${pnl >= 0 ? '+' : ''}${_fmtV(pnl)}',
                    color: pnlColor,
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── Email + plan ─────────────────────────────────────
              Text(
                user.email,
                style: GoogleFonts.inter(
                    fontSize: 10, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),

              // ── Action buttons ───────────────────────────────────
              Row(
                children: [
                  _CardBtn(
                    icon: LucideIcons.eye,
                    label: 'Details',
                    onTap: onViewDetail,
                  ),
                  const SizedBox(width: 5),
                  _CardBtn(
                    icon: LucideIcons.clipboardList,
                    label: 'Trades',
                    onTap: onViewTrades,
                    color: const Color(0xFF7C3AED),
                  ),
                  const SizedBox(width: 5),
                  _CardBtn(
                    icon: LucideIcons.wallet,
                    label: 'Fund',
                    onTap: onFund,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 5),
                  _CardBtn(
                    icon: user.isActive
                        ? LucideIcons.userX
                        : LucideIcons.userCheck,
                    label: user.isActive ? 'Disable' : 'Enable',
                    onTap: onToggle,
                    color: user.isActive ? AppColors.danger : AppColors.success,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _hashColor(String id) {
    const colors = [
      Color(0xFF2962FF),
      Color(0xFF00897B),
      Color(0xFF6A1B9A),
      Color(0xFFE65100),
      Color(0xFF1565C0),
      Color(0xFF558B2F),
      Color(0xFF6D4C41),
    ];
    return colors[id.hashCode.abs() % colors.length];
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;
  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        isActive ? 'ACTIVE' : 'DISABLED',
        style: GoogleFonts.inter(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _MetricCol extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MetricCol(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 9, color: AppColors.textSecondary)),
        const SizedBox(height: 1),
        Text(value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            )),
      ],
    );
  }
}

class _CardBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _CardBtn(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: c.withOpacity(0.07),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: c.withOpacity(0.15)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: c),
              const SizedBox(width: 4),
              Text(label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: c,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ── User detail sheet ──────────────────────────────────────────────────────────

class _UserDetailSheet extends StatelessWidget {
  final User user;
  final double pnl;
  final ScrollController scrollController;
  const _UserDetailSheet({
    required this.user,
    required this.pnl,
    required this.scrollController,
  });

  static String _fmtV(double v) {
    if (v.abs() >= 100000) return '₹${(v / 100000).toStringAsFixed(2)}L';
    if (v.abs() >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final initials = user.name.isNotEmpty
        ? user.name
            .split(' ')
            .take(2)
            .map((w) => w.isNotEmpty ? w[0] : '')
            .join()
            .toUpperCase()
        : '?';
    final pnlColor = pnl >= 0 ? AppColors.success : AppColors.danger;
    final registeredFmt =
        DateFormat('d MMM yyyy').format(user.registeredAt);
    final lastLoginFmt = user.lastLoginAt != null
        ? DateFormat('d MMM yyyy · HH:mm').format(user.lastLoginAt!)
        : 'Never';

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        // Drag handle
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // Avatar + name
        Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.primary.withOpacity(0.15),
              child: Text(
                initials,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      )),
                  Text(user.clientId,
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                  Text(user.email,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppColors.textSecondary)),
                ],
              ),
            ),
            _StatusBadge(isActive: user.isActive),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 16),

        // Financial grid
        Text('Wallet & Margin',
            style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5)),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: [
            _DetailTile(
                label: 'Balance',
                value: _fmtV(user.balance),
                icon: LucideIcons.wallet,
                color: AppColors.primary),
            _DetailTile(
                label: 'Margin Limit',
                value: _fmtV(user.marginLimit),
                icon: LucideIcons.layers,
                color: AppColors.warning),
            _DetailTile(
                label: 'Overall P&L',
                value: '${pnl >= 0 ? '+' : ''}${_fmtV(pnl)}',
                icon: LucideIcons.trendingUp,
                color: pnlColor),
          ],
        ),
        const SizedBox(height: 20),

        Text('Account Info',
            style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5)),
        const SizedBox(height: 10),
        _InfoRow('Plan', user.brokeragePlan),
        _InfoRow('Registered', registeredFmt),
        _InfoRow('Last Login', lastLoginFmt),
        _InfoRow('User ID', user.id),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _DetailTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _DetailTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              )),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 9, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                )),
          ),
        ],
      ),
    );
  }
}

// ── User Trades Sheet ──────────────────────────────────────────────────────────

class _UserTradesSheet extends StatefulWidget {
  final User user;
  final ScrollController scrollController;
  const _UserTradesSheet({required this.user, required this.scrollController});
  @override
  State<_UserTradesSheet> createState() => _UserTradesSheetState();
}

class _UserTradesSheetState extends State<_UserTradesSheet> {
  TradeStatus? _filter;

  static String _fmtV(double v) {
    if (v.abs() >= 100000) return '₹${(v / 100000).toStringAsFixed(2)}L';
    if (v.abs() >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(2)}';
  }

  static String _fmtDate(DateTime dt) {
    if (dt.year < 2000) return '—';
    return DateFormat('dd MMM · h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    final liveUser = admin.users.firstWhere(
      (u) => u.id == widget.user.id,
      orElse: () => widget.user,
    );
    final userOrders = admin.masterOrderBook
        .where((o) => o.userId == widget.user.id)
        .toList();
    final allTrades = buildTradeLedger(userOrders)
      ..sort((a, b) => b.sortTime.compareTo(a.sortTime));

    final closedTrades =
        allTrades.where((t) => t.status == TradeStatus.closed).toList();
    final openCount =
        allTrades.where((t) => t.status == TradeStatus.open).length;
    final totalRealized =
        closedTrades.fold<double>(0, (s, t) => s + t.netPnl);
    final unrealizedPnl = liveUser.runningPnL;
    final wins = closedTrades.where((t) => t.netPnl > 0).length;
    final losses = closedTrades.where((t) => t.netPnl < 0).length;

    final trades = _filter == null
        ? allTrades
        : allTrades.where((t) => t.status == _filter).toList();

    final pnlColor =
        totalRealized >= 0 ? AppColors.success : AppColors.danger;
    final unrealizedColor =
        unrealizedPnl >= 0 ? AppColors.success : AppColors.danger;

    return Column(
      children: [
        // Drag handle
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // ── Header ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.name,
                      style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary),
                    ),
                    Text(
                      '${widget.user.clientId} · Trade History',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _TradeStat(
                  label: 'Realized P&L',
                  value: '${totalRealized >= 0 ? '+' : ''}${_fmtV(totalRealized)}',
                  color: pnlColor),
              const SizedBox(width: 8),
              _TradeStat(
                  label: 'Unrealized',
                  value: '${unrealizedPnl >= 0 ? '+' : ''}${_fmtV(unrealizedPnl)}',
                  color: unrealizedColor),
              const SizedBox(width: 8),
              _TradeStat(
                  label: 'Win / Loss',
                  value: '$wins / $losses',
                  color: AppColors.primary),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Filter tabs ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              _TradeFilterTab(
                label: 'All (${allTrades.length})',
                selected: _filter == null,
                onTap: () => setState(() => _filter = null),
              ),
              const SizedBox(width: 6),
              _TradeFilterTab(
                label: 'Open ($openCount)',
                selected: _filter == TradeStatus.open,
                onTap: () => setState(() => _filter = TradeStatus.open),
              ),
              const SizedBox(width: 6),
              _TradeFilterTab(
                label: 'Closed (${closedTrades.length})',
                selected: _filter == TradeStatus.closed,
                onTap: () => setState(() => _filter = TradeStatus.closed),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),

        // ── Trade list ────────────────────────────────────────────────
        Expanded(
          child: trades.isEmpty
              ? Center(
                  child: Text(
                    'No trades found.',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                )
              : ListView.separated(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  itemCount: trades.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) =>
                      _TradeTile(trade: trades[i], fmtV: _fmtV, fmtDate: _fmtDate),
                ),
        ),
      ],
    );
  }
}

class _TradeStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _TradeStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(value,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color)),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 9, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _TradeFilterTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TradeFilterTab(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary.withOpacity(0.4)
                : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _TradeTile extends StatelessWidget {
  final TradeLedgerEntry trade;
  final String Function(double) fmtV;
  final String Function(DateTime) fmtDate;
  const _TradeTile(
      {required this.trade, required this.fmtV, required this.fmtDate});

  @override
  Widget build(BuildContext context) {
    final isBuy = trade.direction == OrderType.buy;
    final dirColor = isBuy ? AppColors.success : AppColors.danger;

    // Subtitle: shows entry→exit price and date per status
    final bool hasValidEntry = trade.entryPrice > 0;
    final bool hasValidExit  = trade.status == TradeStatus.closed &&
        trade.exitPrice != null && trade.exitPrice! > 0;
    final String entryStr = hasValidEntry ? fmtV(trade.entryPrice) : '—';
    final String subtitle;
    switch (trade.status) {
      case TradeStatus.closed:
        subtitle = hasValidExit
            ? '$entryStr → ${fmtV(trade.exitPrice!)}  ·  ${trade.quantity} qty  ·  ${fmtDate(trade.sortTime)}'
            : '$entryStr → Exit pending  ·  ${trade.quantity} qty  ·  ${fmtDate(trade.sortTime)}';
        break;
      case TradeStatus.pending:
        subtitle =
            '$entryStr → Pending  ·  ${trade.quantity} qty  ·  ${fmtDate(trade.entryTime)}';
        break;
      case TradeStatus.rejected:
        subtitle =
            '$entryStr → Rejected  ·  ${trade.quantity} qty  ·  ${fmtDate(trade.entryTime)}';
        break;
      case TradeStatus.open:
        subtitle =
            '$entryStr → Open  ·  ${trade.quantity} qty  ·  ${fmtDate(trade.entryTime)}';
        break;
    }

    // P&L column: only show realized P&L for closed trades with valid prices
    Widget pnlWidget;
    switch (trade.status) {
      case TradeStatus.closed:
        final pnlColor =
            trade.netPnl >= 0 ? AppColors.success : AppColors.danger;
        pnlWidget = hasValidExit && hasValidEntry
            ? Text(
                '${trade.netPnl >= 0 ? '+' : ''}${fmtV(trade.netPnl)}',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 13, fontWeight: FontWeight.w700, color: pnlColor),
              )
            : Text('—',
                style: GoogleFonts.inter(
                    fontSize: 11, color: AppColors.textSecondary));
        break;
      case TradeStatus.pending:
        pnlWidget = Text(
          'PENDING',
          style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.warning),
        );
        break;
      case TradeStatus.rejected:
        pnlWidget = Text(
          'REJECTED',
          style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.danger),
        );
        break;
      case TradeStatus.open:
        pnlWidget = Text(
          'OPEN',
          style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary),
        );
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Direction stripe
          Container(
            width: 3,
            height: 42,
            decoration: BoxDecoration(
              color: dirColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),

          // Symbol + meta
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      trade.symbol,
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(width: 6),
                    _Badge(trade.product, AppColors.textSecondary),
                    const SizedBox(width: 4),
                    _Badge(
                        isBuy ? 'BUY' : 'SELL',
                        isBuy ? AppColors.success : AppColors.danger),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                      fontSize: 10, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),

          // P&L / status
          pnlWidget,
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: color),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isFiltered;
  const _EmptyState({required this.isFiltered});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFiltered ? LucideIcons.searchX : LucideIcons.users,
            size: 48,
            color: AppColors.border,
          ),
          const SizedBox(height: 16),
          Text(
            isFiltered ? 'No users match.' : 'No users yet.',
            style: GoogleFonts.inter(
                fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

enum _SortBy { name, balance, registered }
