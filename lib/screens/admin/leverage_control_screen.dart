import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../state/admin_scope.dart';
import '../../models/trading_models.dart';
import '../../theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/shared_widgets.dart';
import 'admin_ui.dart';

// ── Segment definitions (matches the image) ───────────────────────────────────

class _Seg {
  final String key;
  final String label;
  final List<double> options; // descending — first = platform max
  final bool isPerLot;        // true → show ₹ per Lot, false → show Nx

  const _Seg({
    required this.key,
    required this.label,
    required this.options,
    this.isPerLot = false,
  });
}

const _kSegs = [
  _Seg(
    key: 'mcxFutures',
    label: 'MCX Futures',
    options: [500, 200, 100, 50, 20, 10, 5],
  ),
  _Seg(
    key: 'mcxOptionBuying',
    label: 'MCX Option Buying',
    options: [10, 5, 4, 3, 2],
  ),
  _Seg(
    key: 'mcxOptionSelling',
    label: 'MCX Option Selling',
    options: [20000, 15000, 10000, 7500, 5000],
    isPerLot: true,
  ),
  _Seg(
    key: 'nseFutures',
    label: 'NSE Futures',
    options: [500, 200, 100, 50, 20, 10, 5],
  ),
  _Seg(
    key: 'nseOptionBuying',
    label: 'NSE Option Buying',
    options: [10, 5, 4, 3, 2],
  ),
  _Seg(
    key: 'nseOptionSelling',
    label: 'NSE Option Selling',
    options: [20000, 15000, 10000, 7500, 5000],
    isPerLot: true,
  ),
  _Seg(
    key: 'nseSpot',
    label: 'NSE Spot',
    options: [20, 15, 10, 5, 2],
  ),
  _Seg(
    key: 'crypto',
    label: 'Crypto',
    options: [200, 100, 50, 20, 10],
  ),
  _Seg(
    key: 'comex',
    label: 'COMEX',
    options: [100, 50, 20, 10, 5],
  ),
  _Seg(
    key: 'forex',
    label: 'Forex',
    options: [100, 50, 20, 10, 5],
  ),
  _Seg(
    key: 'usStocks',
    label: 'US Stocks',
    options: [100, 50, 20, 10, 5],
  ),
];

// ── Helpers ───────────────────────────────────────────────────────────────────

String _fmtOption(_Seg seg, double val) {
  if (seg.isPerLot) {
    return '₹${NumberFormat('#,##,##0').format(val)} / Lot';
  }
  final pct = (100 / val).toStringAsFixed(2);
  return '${val.toInt()}x ($pct%)';
}

String _fmtCurrent(_Seg seg, double? val) {
  if (val == null) return 'Default';
  return _fmtOption(seg, val);
}

// ── Screen ────────────────────────────────────────────────────────────────────

class LeverageControlScreen extends StatefulWidget {
  const LeverageControlScreen({super.key});

  @override
  State<LeverageControlScreen> createState() => _LeverageControlScreenState();
}

class _LeverageControlScreenState extends State<LeverageControlScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    final users = admin.users.where((u) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return u.name.toLowerCase().contains(q) ||
          u.clientId.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q);
    }).toList();

    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminHeader(
            title: 'Leverage Control',
            subtitle: 'Set per-segment leverage limits for each user.',
          ),
          const SizedBox(height: 12),

          // Search bar
          AdminPanel(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search user by name, email or client ID...',
                prefixIcon: Icon(LucideIcons.search, size: 18),
              ),
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
                      itemBuilder: (_, i) => _UserLeverageTile(user: users[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── User tile with expand ─────────────────────────────────────────────────────

class _UserLeverageTile extends StatefulWidget {
  final User user;
  const _UserLeverageTile({required this.user});

  @override
  State<_UserLeverageTile> createState() => _UserLeverageTileState();
}

class _UserLeverageTileState extends State<_UserLeverageTile> {
  bool _expanded = false;

  // Working copy of selections — null = use platform default
  late Map<String, double?> _draft;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadDraft();
  }

  void _loadDraft() {
    final admin = AdminScope.of(context);
    _draft = {
      for (final seg in _kSegs)
        seg.key: admin.getSegmentLeverage(widget.user.id, seg.key),
    };
  }

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    // Count how many segments have custom (non-default) leverage
    final customCount =
        _kSegs.where((s) => admin.getSegmentLeverage(widget.user.id, s.key) != null).length;

    return Column(
      children: [
        // ── Header row ──────────────────────────────────────────────────────
        InkWell(
          onTap: () {
            if (!_expanded) _loadDraft(); // refresh draft when opening
            setState(() => _expanded = !_expanded);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Text(
                    widget.user.name.isEmpty
                        ? 'U'
                        : widget.user.name[0].toUpperCase(),
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                // Name + info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.user.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      Text(
                        '${widget.user.clientId}  •  ${widget.user.email}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Badge showing custom count
                if (customCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.warning.withOpacity(0.4)),
                    ),
                    child: Text(
                      '$customCount custom',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Default',
                      style: TextStyle(
                          fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ),
                const SizedBox(width: 8),
                Icon(
                  _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),

        // ── Expanded panel ──────────────────────────────────────────────────
        if (_expanded)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                // Segment grid
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: isMobile
                      ? _buildMobileGrid()
                      : _buildDesktopGrid(),
                ),
                // Action row
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() {
                          for (final seg in _kSegs) {
                            _draft[seg.key] = null;
                          }
                        }),
                        icon: const Icon(LucideIcons.rotateCcw, size: 13),
                        label: const Text('Reset to Default'),
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            textStyle: const TextStyle(fontSize: 12)),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _save,
                        icon: const Icon(LucideIcons.save, size: 13),
                        label: const Text('Save'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Desktop: 2-column grid
  Widget _buildDesktopGrid() {
    final half = (_kSegs.length / 2).ceil();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: _kSegs
                .take(half)
                .map((seg) => _segRow(seg))
                .toList(),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: _kSegs
                .skip(half)
                .map((seg) => _segRow(seg))
                .toList(),
          ),
        ),
      ],
    );
  }

  // Mobile: single column
  Widget _buildMobileGrid() {
    return Column(
      children: _kSegs.map((seg) => _segRow(seg)).toList(),
    );
  }

  Widget _segRow(_Seg seg) {
    final current = _draft[seg.key];
    final isCustom = current != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Label
          Expanded(
            flex: 5,
            child: Row(
              children: [
                if (isCustom)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: const BoxDecoration(
                      color: AppColors.warning,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    seg.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isCustom
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isCustom
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Dropdown
          Expanded(
            flex: 6,
            child: _LevDropdown(
              seg: seg,
              value: current,
              onChanged: (v) => setState(() => _draft[seg.key] = v),
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    final admin = AdminScope.of(context);
    final toSave = <String, double>{
      for (final e in _draft.entries)
        if (e.value != null) e.key: e.value!,
    };
    admin.setUserSegmentLeverages(widget.user.id, toSave);
    setState(() => _expanded = false);
    AppToast.success(
        context, 'Leverage saved for ${widget.user.clientId}.');
  }
}

// ── Dropdown widget ───────────────────────────────────────────────────────────

class _LevDropdown extends StatelessWidget {
  final _Seg seg;
  final double? value;
  final ValueChanged<double?> onChanged;

  const _LevDropdown({
    required this.seg,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isCustom = value != null;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isCustom
            ? AppColors.warning.withOpacity(0.06)
            : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCustom
              ? AppColors.warning.withOpacity(0.5)
              : AppColors.border,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<double?>(
          value: value,
          isExpanded: true,
          icon: const Icon(LucideIcons.chevronDown, size: 13),
          style: TextStyle(
            fontSize: 12,
            fontWeight: isCustom ? FontWeight.w700 : FontWeight.normal,
            color: isCustom ? AppColors.warning : AppColors.textSecondary,
          ),
          items: [
            // Default option
            DropdownMenuItem<double?>(
              value: null,
              child: Text(
                'Default (${_fmtOption(seg, seg.options.first)})',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            // All allowed values
            ...seg.options.map(
              (v) => DropdownMenuItem<double?>(
                value: v,
                child: Text(
                  _fmtOption(seg, v),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
