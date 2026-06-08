import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../state/admin_scope.dart';
import '../../models/trading_models.dart';
import '../../theme.dart';
import 'admin_ui.dart';

// ─── Entry display config ─────────────────────────────────────────────────────

class _EntryConfig {
  final IconData icon;
  final Color color;
  final String category; // for filter chips

  const _EntryConfig({
    required this.icon,
    required this.color,
    required this.category,
  });
}

_EntryConfig _configFor(String action) {
  switch (action) {
    case 'Enable User':
    case 'SET_TRADING_ENABLED':
      return const _EntryConfig(
        icon: LucideIcons.userCheck,
        color: AppColors.success,
        category: 'User',
      );
    case 'Disable User':
      return const _EntryConfig(
        icon: LucideIcons.userX,
        color: AppColors.danger,
        category: 'User',
      );
    case 'Force Close Position':
    case 'Force Close All Positions':
      return const _EntryConfig(
        icon: LucideIcons.xCircle,
        color: AppColors.danger,
        category: 'User',
      );
    case 'ADD_BALANCE':
    case 'Adjust User Balance':
      return const _EntryConfig(
        icon: LucideIcons.indianRupee,
        color: Color(0xFF0288D1),
        category: 'Wallet',
      );
    case 'Adjust User Margin':
      return const _EntryConfig(
        icon: LucideIcons.creditCard,
        color: Color(0xFF0288D1),
        category: 'Wallet',
      );
    case 'WITHDRAWAL_APPROVED':
    case 'WITHDRAWAL_REJECTED':
      return const _EntryConfig(
        icon: LucideIcons.arrowDownCircle,
        color: Color(0xFF0288D1),
        category: 'Wallet',
      );
    case 'Enable Stock':
      return const _EntryConfig(
        icon: LucideIcons.trendingUp,
        color: AppColors.success,
        category: 'Market',
      );
    case 'Disable Stock':
      return const _EntryConfig(
        icon: LucideIcons.trendingDown,
        color: AppColors.danger,
        category: 'Market',
      );
    case 'Global Trading Halt':
      return const _EntryConfig(
        icon: LucideIcons.pauseCircle,
        color: AppColors.danger,
        category: 'Market',
      );
    case 'Maintenance Mode':
      return const _EntryConfig(
        icon: LucideIcons.wrench,
        color: AppColors.warning,
        category: 'System',
      );
    case 'Broadcast Notification':
    case 'BROADCAST':
      return const _EntryConfig(
        icon: LucideIcons.bell,
        color: AppColors.warning,
        category: 'System',
      );
    case 'SET_LEVERAGE':
      return const _EntryConfig(
        icon: LucideIcons.sliders,
        color: Color(0xFF7B1FA2),
        category: 'Risk',
      );
    case 'SET_STOCK_LEVERAGE':
      return const _EntryConfig(
        icon: LucideIcons.barChart2,
        color: Color(0xFF7B1FA2),
        category: 'Risk',
      );
    case 'Set Risk Limit':
      return const _EntryConfig(
        icon: LucideIcons.shieldAlert,
        color: Color(0xFF7B1FA2),
        category: 'Risk',
      );
    case 'Approve Order (local only)':
      return const _EntryConfig(
        icon: LucideIcons.checkCircle,
        color: AppColors.success,
        category: 'Orders',
      );
    case 'Reject Order (local only)':
      return const _EntryConfig(
        icon: LucideIcons.xCircle,
        color: AppColors.danger,
        category: 'Orders',
      );
    default:
      return const _EntryConfig(
        icon: LucideIcons.activity,
        color: AppColors.textSecondary,
        category: 'System',
      );
  }
}

// ─── Human-readable description builder ─────────────────────────────────────

final _rupee = NumberFormat('#,##,##0.##', 'en_IN');

String _fmt(double v) => '₹${_rupee.format(v.abs())}';

String _userName(String userId, List<User> users) {
  User? u;
  for (final usr in users) {
    if (usr.id == userId) { u = usr; break; }
  }
  if (u != null) return '${u.name} (${u.email})';
  if (userId.isEmpty || userId == 'N/A') return 'Unknown User';
  // Truncate raw IDs to avoid cluttering the sentence
  return userId.length > 16 ? '${userId.substring(0, 14)}…' : userId;
}

String _describeEntry(AuditLogEntry log, List<User> users) {
  final raw    = log.targetId.trim();
  final meta   = log.metadata ?? {};

  switch (log.action) {
    // ── User management ─────────────────────────────────────────────────────
    case 'Enable User':
    case 'SET_TRADING_ENABLED':
      final enabled = meta['enabled'];
      if (enabled == false) return 'Disabled trading access for ${_userName(raw, users)}';
      return 'Enabled trading access for ${_userName(raw, users)}';

    case 'Disable User':
      return 'Disabled trading access for ${_userName(raw, users)}';

    // ── Wallet / balance ─────────────────────────────────────────────────────
    case 'ADD_BALANCE':
    case 'Adjust User Balance': {
      // target may be "userId: amount" (local mode) or just userId (Firebase mode)
      String userId = raw;
      double? amount;
      if (raw.contains(': ')) {
        final parts = raw.split(': ');
        userId = parts[0];
        amount = double.tryParse(parts[1]);
      }
      amount ??= (meta['amount'] as num?)?.toDouble();
      final name = _userName(userId, users);
      if (amount == null) return 'Adjusted wallet balance for $name';
      if (amount >= 0) return 'Credited ${_fmt(amount)} to $name\'s wallet';
      return 'Debited ${_fmt(-amount)} from $name\'s wallet';
    }

    case 'Adjust User Margin': {
      String userId = raw;
      double? amount;
      if (raw.contains(': ')) {
        final parts = raw.split(': ');
        userId = parts[0];
        amount = double.tryParse(parts[1]);
      }
      amount ??= (meta['amount'] as num?)?.toDouble();
      final name = _userName(userId, users);
      if (amount == null) return 'Adjusted margin limit for $name';
      if (amount >= 0) return 'Increased margin limit by ${_fmt(amount)} for $name';
      return 'Reduced margin limit by ${_fmt(-amount)} for $name';
    }

    case 'WITHDRAWAL_APPROVED':
      return 'Withdrawal of ${_fmt((meta['amount'] as num?)?.toDouble() ?? 0)} approved for ${_userName(raw, users)}';

    case 'WITHDRAWAL_REJECTED':
      return 'Withdrawal rejected for ${_userName(raw, users)}${meta['reason'] != null ? ' — ${meta['reason']}' : ''}';

    // ── Market / stock ───────────────────────────────────────────────────────
    case 'Enable Stock':
      return 'Re-enabled trading for $raw';

    case 'Disable Stock':
      return 'Blocked trading for $raw (symbol suspended)';

    case 'Global Trading Halt':
      if (raw == 'ENABLED') return 'All trading halted across the platform';
      if (raw == 'DISABLED') return 'Trading halt lifted — market resumed';
      return 'Global trading halt toggled to $raw';

    // ── System ──────────────────────────────────────────────────────────────
    case 'Maintenance Mode':
      if (raw == 'ON')  return 'Platform put into maintenance mode — users cannot log in';
      if (raw == 'OFF') return 'Maintenance mode ended — platform is live';
      return 'Maintenance mode changed to $raw';

    case 'Broadcast Notification':
    case 'BROADCAST':
      final title   = (meta['title'] as String?)   ?? raw;
      final message = (meta['message'] as String?);
      if (message != null && message.isNotEmpty) return 'Broadcast sent: "$title" — $message';
      return 'Broadcast notification sent: "$title"';

    // ── Risk & leverage ─────────────────────────────────────────────────────
    case 'Set Risk Limit': {
      // raw = "userId: limitType=value"
      if (raw.contains(': ')) {
        final outer = raw.split(': ');
        final name  = _userName(outer[0], users);
        final kv    = outer.length > 1 ? outer[1] : raw;
        return 'Risk limit updated for $name: $kv';
      }
      return 'Risk limit updated: $raw';
    }

    case 'SET_LEVERAGE': {
      // raw = "userId: mcxFutures=500x, nseFutures=200x"
      if (raw.contains(': ')) {
        final parts   = raw.split(': ');
        final name    = _userName(parts[0], users);
        final details = parts.length > 1 ? parts[1] : '';
        return 'Leverage updated for $name — $details';
      }
      return 'Leverage settings updated: $raw';
    }

    case 'SET_STOCK_LEVERAGE':
      return 'Per-symbol leverage updated: $raw';

    // ── Position force-close ────────────────────────────────────────────────
    case 'Force Close Position': {
      // raw = "userId / positionId"
      final parts  = raw.split(' / ');
      final name   = _userName(parts[0], users);
      final posId  = parts.length > 1 ? parts[1] : '';
      return 'Manually closed position "$posId" for $name';
    }

    case 'Force Close All Positions':
      return 'Force-closed ALL open positions for ${_userName(raw, users)}';

    // ── Orders (legacy, local-only) ─────────────────────────────────────────
    case 'Approve Order (local only)':
      return 'Order $raw approved (local)';

    case 'Reject Order (local only)': {
      final spaceIdx = raw.indexOf(' ');
      if (spaceIdx > 0) {
        final orderId = raw.substring(0, spaceIdx);
        final reason  = raw.substring(spaceIdx + 1);
        return 'Order $orderId rejected — $reason';
      }
      return 'Order $raw rejected';
    }

    default:
      // Fallback: make SCREAMING_SNAKE readable and append target
      final readable = log.action
          .replaceAll('_', ' ')
          .toLowerCase()
          .replaceFirstMapped(RegExp(r'^\w'), (m) => m.group(0)!.toUpperCase());
      if (raw.isNotEmpty && raw != 'N/A') return '$readable — $raw';
      return readable;
  }
}

// ─── Metadata detail builder ─────────────────────────────────────────────────

List<_MetaChip> _metaChips(AuditLogEntry log) {
  final meta   = log.metadata ?? {};
  final chips  = <_MetaChip>[];

  final before = (meta['balanceBefore'] as num?)?.toDouble();
  final after  = (meta['balanceAfter']  as num?)?.toDouble();
  if (before != null) chips.add(_MetaChip('Before', _fmt(before)));
  if (after  != null) chips.add(_MetaChip('After',  _fmt(after)));

  final amount = (meta['amount'] as num?)?.toDouble();
  if (amount != null && before == null) chips.add(_MetaChip('Amount', _fmt(amount)));

  final ref = meta['referenceId'] as String?;
  if (ref != null && ref.isNotEmpty) chips.add(_MetaChip('Ref', ref));

  final remarks = meta['remarks'] as String?;
  if (remarks != null && remarks.isNotEmpty) chips.add(_MetaChip('Note', remarks));

  final enabled = meta['enabled'];
  if (enabled != null) chips.add(_MetaChip('Status', enabled == true ? 'Enabled' : 'Disabled'));

  final message = meta['message'] as String?;
  if (message != null && message.isNotEmpty) chips.add(_MetaChip('Message', message));

  return chips;
}

class _MetaChip {
  final String label;
  final String value;
  const _MetaChip(this.label, this.value);
}

// ─── Relative time ────────────────────────────────────────────────────────────

String _relativeTime(DateTime ts) {
  final diff = DateTime.now().difference(ts);
  if (diff.inSeconds < 60)  return 'just now';
  if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
  if (diff.inHours < 24)    return '${diff.inHours}h ago';
  if (diff.inDays < 7)      return '${diff.inDays}d ago';
  return DateFormat('dd MMM').format(ts);
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});
  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  String _categoryFilter = 'All';
  DateTimeRange? _dateRange;
  String? _expandedId;

  static const _categories = ['All', 'User', 'Wallet', 'Market', 'Risk', 'System', 'Orders'];

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    final users = admin.users.toList();

    final logs = admin.auditLogs.where((l) {
      if (_categoryFilter != 'All' && _configFor(l.action).category != _categoryFilter) return false;
      if (_dateRange != null) {
        if (l.timestamp.isBefore(_dateRange!.start) ||
            l.timestamp.isAfter(_dateRange!.end.add(const Duration(days: 1)))) { return false; }
      }
      return true;
    }).toList();

    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Audit Log',
            subtitle: '${logs.length} ${_categoryFilter == 'All' ? 'total' : _categoryFilter.toLowerCase()} entries',
            trailing: OutlinedButton.icon(
              onPressed: () => _exportCsv(logs, users),
              icon: const Icon(LucideIcons.download, size: 16),
              label: const Text('Export CSV'),
            ),
          ),
          const SizedBox(height: 12),

          // ── Filters ─────────────────────────────────────────────────────────
          AdminPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Category chips
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _categories.map((cat) {
                        final selected = _categoryFilter == cat;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(cat),
                            selected: selected,
                            onSelected: (_) => setState(() => _categoryFilter = cat),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                              color: selected ? AppColors.primary : AppColors.textSecondary,
                            ),
                            selectedColor: AppColors.primary.withOpacity(0.12),
                            checkmarkColor: AppColors.primary,
                            side: BorderSide(
                              color: selected ? AppColors.primary : AppColors.border,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                      initialDateRange: _dateRange,
                    );
                    if (range != null) setState(() => _dateRange = range);
                  },
                  icon: const Icon(LucideIcons.calendar, size: 14),
                  label: Text(
                    _dateRange == null
                        ? 'Date Range'
                        : '${DateFormat('dd MMM').format(_dateRange!.start)} – ${DateFormat('dd MMM').format(_dateRange!.end)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (_dateRange != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 14),
                    tooltip: 'Clear date filter',
                    onPressed: () => setState(() => _dateRange = null),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Log list ─────────────────────────────────────────────────────────
          Expanded(
            child: logs.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.fileSearch, size: 48, color: AppColors.border),
                        SizedBox(height: 12),
                        Text('No audit entries found.', style: TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  )
                : AdminPanel(
                    child: ListView.separated(
                      itemCount: logs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) => _logRow(logs[i], users),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _logRow(AuditLogEntry log, List<User> users) {
    final cfg         = _configFor(log.action);
    final description = _describeEntry(log, users);
    final chips       = _metaChips(log);
    final expanded    = _expandedId == log.id;
    final hasDetails  = chips.isNotEmpty;
    final fmtTime     = DateFormat('dd MMM, HH:mm').format(log.timestamp);

    return InkWell(
      onTap: hasDetails ? () => setState(() => _expandedId = expanded ? null : log.id) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cfg.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(cfg.icon, size: 15, color: cfg.color),
                ),
                const SizedBox(width: 12),

                // Description + meta
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category chip + time on same row
                      Row(
                        children: [
                          _CategoryBadge(label: cfg.category, color: cfg.color),
                          const Spacer(),
                          Text(
                            fmtTime,
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '· ${_relativeTime(log.timestamp)}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Main description
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),

                      // Admin who did it
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(LucideIcons.user, size: 11, color: AppColors.textSecondary),
                          const SizedBox(width: 3),
                          Text(
                            log.adminId == 'SYSTEM' ? 'System' : log.adminId,
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                          if (hasDetails) ...[
                            const SizedBox(width: 8),
                            Icon(
                              expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                              size: 12,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              expanded ? 'Hide details' : 'Show details',
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Expanded metadata chips
            if (expanded && chips.isNotEmpty) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 46),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: chips.map((c) => _DetailChip(label: c.label, value: c.value)).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _exportCsv(List<AuditLogEntry> logs, List<User> users) {
    final csv = StringBuffer('Time,Category,Description,Admin,Raw Action,Target ID\n');
    for (final l in logs) {
      final desc = _describeEntry(l, users).replaceAll(',', ';');
      final cat  = _configFor(l.action).category;
      final time = DateFormat('yyyy-MM-dd HH:mm:ss').format(l.timestamp);
      csv.writeln('"$time","$cat","$desc","${l.adminId}","${l.action}","${l.targetId}"');
    }
    Clipboard.setData(ClipboardData(text: csv.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CSV copied to clipboard.'),
        backgroundColor: AppColors.success,
      ),
    );
  }
}

// ─── Small widgets ────────────────────────────────────────────────────────────

class _CategoryBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _CategoryBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final String label;
  final String value;
  const _DetailChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
