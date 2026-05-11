import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/trading_models.dart';
import '../../state/admin_scope.dart';
import '../../theme.dart';
import '../../widgets/app_dialog.dart';
import 'admin_ui.dart';

// ── Leverage config from the image ────────────────────────────────────────────
//
// Each segment has a list of allowed leverage values (max → min).
// The admin picks one from a dropdown; the selected value is saved.

class _SegmentConfig {
  final String key;        // Firestore / store key
  final String label;      // Display label
  final List<double> options; // Allowed leverage values (descending)
  final String unit;       // 'x' or 'per_lot'

  const _SegmentConfig({
    required this.key,
    required this.label,
    required this.options,
    this.unit = 'x',
  });
}

const _kSegments = [
  _SegmentConfig(
    key: 'mcxFutures',
    label: 'MCX Futures',
    options: [500, 200, 100, 50, 20, 10, 5],
  ),
  _SegmentConfig(
    key: 'mcxOptionBuying',
    label: 'MCX Option Buying',
    options: [10, 5, 4, 3, 2],
  ),
  _SegmentConfig(
    key: 'mcxOptionSelling',
    label: 'MCX Option Selling',
    options: [20000, 15000, 10000, 7500, 5000],
    unit: 'per_lot',
  ),
  _SegmentConfig(
    key: 'nseFutures',
    label: 'NSE Futures',
    options: [500, 200, 100, 50, 20, 10, 5],
  ),
  _SegmentConfig(
    key: 'nseOptionBuying',
    label: 'NSE Option Buying',
    options: [10, 5, 4, 3, 2],
  ),
  _SegmentConfig(
    key: 'nseOptionSelling',
    label: 'NSE Option Selling',
    options: [20000, 15000, 10000, 7500, 5000],
    unit: 'per_lot',
  ),
  _SegmentConfig(
    key: 'nseSpot',
    label: 'NSE Spot',
    options: [20, 15, 10, 5, 2],
  ),
  _SegmentConfig(
    key: 'crypto',
    label: 'Crypto',
    options: [200, 100, 50, 20, 10],
  ),
  _SegmentConfig(
    key: 'comex',
    label: 'COMEX',
    options: [100, 50, 20, 10, 5],
  ),
  _SegmentConfig(
    key: 'forex',
    label: 'Forex',
    options: [100, 50, 20, 10, 5],
  ),
  _SegmentConfig(
    key: 'usStocks',
    label: 'US Stocks',
    options: [100, 50, 20, 10, 5],
  ),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _query = '';
  bool? _isActiveFilter;

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    final users = admin.users.where((user) {
      final q = _query.toLowerCase();
      final matchQuery =
          q.isEmpty ||
          user.name.toLowerCase().contains(q) ||
          user.email.toLowerCase().contains(q) ||
          user.clientId.toLowerCase().contains(q);
      final matchStatus =
          _isActiveFilter == null || user.isActive == _isActiveFilter;
      return matchQuery && matchStatus;
    }).toList();

    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'User Management',
            subtitle: '${users.length} user(s) across the platform.',
          ),
          const SizedBox(height: 12),
          AdminPanel(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Search by name, email, client ID',
                    prefixIcon: Icon(LucideIcons.search, size: 18),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    _filterChip('All', null),
                    _filterChip('Active', true),
                    _filterChip('Disabled', false),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: users.isEmpty
                ? const Center(child: Text('No users found.'))
                : AdminPanel(
                    child: ListView.separated(
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _userRow(context, users[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool? value) {
    final selected = _isActiveFilter == value;
    return AdminFilterChip(
      label: label,
      selected: selected,
      onTap: () => setState(() => _isActiveFilter = value),
    );
  }

  Widget _userRow(BuildContext context, User user) {
    final admin = AdminScope.of(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withOpacity(0.1),
        child: Text(
          user.name.isEmpty ? 'U' : user.name[0].toUpperCase(),
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        user.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${user.email}\n${user.clientId} • Bal ₹${NumberFormat('#,##,##0').format(user.balance)} • Margin ₹${NumberFormat('#,##,##0').format(user.marginLimit)}',
        style: const TextStyle(fontSize: 12),
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: user.isActive,
            onChanged: (enabled) async {
              try {
                if (enabled) {
                  await admin.enableUser(user.id);
                } else {
                  await admin.disableUser(user.id);
                }
                if (context.mounted) {
                  AppToast.success(context, 'User ${enabled ? "enabled" : "disabled"} successfully.');
                }
              } catch (e) {
                if (context.mounted) {
                  AppToast.error(context, 'Failed to update user status: $e');
                }
              }
            },
            activeColor: AppColors.success,
          ),
          IconButton(
            onPressed: () => _openUserActions(context, user),
            icon: const Icon(LucideIcons.moreVertical, size: 18),
          ),
        ],
      ),
    );
  }

  void _openUserActions(BuildContext context, User user) {
    AppBottomSheet.show(
      context,
      title: 'User Actions — ${user.clientId}',
      child: Column(
        children: [
          ListTile(
            leading: const Icon(LucideIcons.wallet),
            title: const Text('Adjust Balance'),
            contentPadding: EdgeInsets.zero,
            onTap: () {
              Navigator.pop(context);
              _showAmountDialog(
                context,
                user,
                title: 'Adjust Balance',
                onSubmit: (amount) =>
                    AdminScope.of(context).adjustUserBalance(user.id, amount),
              );
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.gauge),
            title: const Text('Adjust Margin Limit'),
            contentPadding: EdgeInsets.zero,
            onTap: () {
              Navigator.pop(context);
              _showAmountDialog(
                context,
                user,
                title: 'Adjust Margin Limit',
                onSubmit: (amount) =>
                    AdminScope.of(context).adjustUserMargin(user.id, amount),
              );
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.zap, color: AppColors.warning),
            title: const Text('Set Leverage'),
            subtitle: const Text(
              'Configure per-segment leverage limits',
              style: TextStyle(fontSize: 11),
            ),
            contentPadding: EdgeInsets.zero,
            onTap: () {
              Navigator.pop(context);
              _showLeverageDialog(context, user);
            },
          ),
        ],
      ),
    );
  }

  // ── Leverage dialog ─────────────────────────────────────────────────────────

  void _showLeverageDialog(BuildContext context, User user) {
    showDialog(
      context: context,
      builder: (_) => _LeverageDialog(user: user),
    );
  }

  // ── Amount dialog ───────────────────────────────────────────────────────────

  void _showAmountDialog(
    BuildContext context,
    User user, {
    required String title,
    required Future<void> Function(double amount) onSubmit,
  }) {
    AppDialog.input(
      context,
      title: title,
      message: 'User: ${user.clientId}  •  Use + to add, - to deduct',
      hint: 'e.g. 5000 or -2000',
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: true),
      confirmLabel: 'Apply',
      onSubmit: (value) async {
        final amount = double.tryParse(value) ?? 0;
        if (amount == 0) return;
        try {
          await onSubmit(amount);
          if (context.mounted) {
            AppToast.success(
                context, 'Adjustment of ₹$amount applied successfully.');
          }
        } catch (e) {
          if (context.mounted) {
            AppToast.error(context, 'Failed to apply adjustment: $e');
          }
        }
      },
    );
  }
}

// ── Leverage Dialog ───────────────────────────────────────────────────────────

class _LeverageDialog extends StatefulWidget {
  final User user;
  const _LeverageDialog({required this.user});

  @override
  State<_LeverageDialog> createState() => _LeverageDialogState();
}

class _LeverageDialogState extends State<_LeverageDialog> {
  // Selected leverage per segment key — null means "use default (max)"
  late final Map<String, double?> _selected;

  @override
  void initState() {
    super.initState();
    final admin = AdminScope.of(context);
    _selected = {
      for (final seg in _kSegments)
        seg.key: admin.getSegmentLeverage(widget.user.id, seg.key),
    };
  }

  String _formatOption(_SegmentConfig seg, double val) {
    if (seg.unit == 'per_lot') {
      return '₹${NumberFormat('#,##,##0').format(val)} per Lot';
    }
    // Show margin % alongside leverage
    final pct = (100 / val).toStringAsFixed(2);
    return '${val.toInt()}x ($pct%)';
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 40,
        vertical: isMobile ? 16 : 40,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
              decoration: const BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(LucideIcons.zap,
                        size: 18, color: AppColors.warning),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Set Leverage',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        Text(
                          '${widget.user.name}  •  ${widget.user.clientId}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── Segment rows ─────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Column(
                  children: [
                    // Info banner
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.info,
                              size: 14, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Select the maximum leverage allowed for each segment. '
                              '"Default" uses the platform maximum.',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.primary.withOpacity(0.85)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Segment rows
                    ...List.generate(_kSegments.length, (i) {
                      final seg = _kSegments[i];
                      final current = _selected[seg.key];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SegmentRow(
                          seg: seg,
                          selected: current,
                          formatOption: _formatOption,
                          onChanged: (val) =>
                              setState(() => _selected[seg.key] = val),
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),

            // ── Footer buttons ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  // Reset all to default
                  TextButton.icon(
                    onPressed: () => setState(() {
                      for (final seg in _kSegments) {
                        _selected[seg.key] = null;
                      }
                    }),
                    icon: const Icon(LucideIcons.rotateCcw, size: 14),
                    label: const Text('Reset All'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _save,
                    icon: const Icon(LucideIcons.save, size: 14),
                    label: const Text('Save Leverage'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final admin = AdminScope.of(context);
    // Only save segments that have an explicit selection (non-null)
    final toSave = <String, double>{
      for (final entry in _selected.entries)
        if (entry.value != null) entry.key: entry.value!,
    };
    admin.setUserSegmentLeverages(widget.user.id, toSave);
    Navigator.pop(context);
    AppToast.success(context, 'Leverage updated for ${widget.user.clientId}.');
  }
}

// ── Single segment row ────────────────────────────────────────────────────────

class _SegmentRow extends StatelessWidget {
  final _SegmentConfig seg;
  final double? selected;
  final String Function(_SegmentConfig, double) formatOption;
  final ValueChanged<double?> onChanged;

  const _SegmentRow({
    required this.seg,
    required this.selected,
    required this.formatOption,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Build dropdown items: "Default (max)" + each option
    final items = <DropdownMenuItem<double?>>[
      DropdownMenuItem<double?>(
        value: null,
        child: Text(
          'Default (${formatOption(seg, seg.options.first)})',
          style: const TextStyle(
              fontSize: 13, color: AppColors.textSecondary),
        ),
      ),
      ...seg.options.map(
        (val) => DropdownMenuItem<double?>(
          value: val,
          child: Text(
            formatOption(seg, val),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    ];

    return Row(
      children: [
        // Segment label
        Expanded(
          flex: 5,
          child: Text(
            seg.label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        // Dropdown
        Expanded(
          flex: 6,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected != null
                    ? AppColors.warning.withOpacity(0.6)
                    : AppColors.border,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<double?>(
                value: selected,
                isExpanded: true,
                icon: const Icon(LucideIcons.chevronDown, size: 14),
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
