/// Admin — Market Settings Screen
///
/// Allows admin to:
///   - Enable/disable stocks and MCX segments
///   - Enable/disable buy and sell independently
///   - Change market open/close times (IST) — with explicit Save button
///   - Set maximum leverage and margin % per category (Fix 1 & Fix 3)
///
/// Changes write to Firestore marketSettings/config and apply live
/// to all connected clients without a server restart.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../data/services/market_settings_service.dart';
import '../../models/market_settings.dart';
import '../../theme.dart';
import '../../widgets/app_dialog.dart';
import 'admin_ui.dart';

class MarketSettingsScreen extends StatefulWidget {
  const MarketSettingsScreen({super.key});

  @override
  State<MarketSettingsScreen> createState() => _MarketSettingsScreenState();
}

class _MarketSettingsScreenState extends State<MarketSettingsScreen> {
  final _service = MarketSettingsService();
  StreamSubscription<MarketSettings>? _sub;

  MarketSettings _settings = MarketSettings.defaults;
  bool _saving = false;

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

  Future<void> _save(MarketSettings updated) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _service.update(updated);
      if (mounted) AppToast.success(context, 'Market settings saved.');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not save settings. Please check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Market Settings',
            subtitle:
                'Control trading hours, buy/sell permissions, and leverage & margin per category. Changes apply live.',
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                _SegmentCard(
                  title: 'NSE / BSE — Stocks',
                  icon: LucideIcons.barChart2,
                  color: AppColors.primary,
                  settings: _settings.stocks,
                  saving: _saving,
                  onChanged: (updated) => _save(
                    MarketSettings(stocks: updated, mcx: _settings.mcx),
                  ),
                ),
                const SizedBox(height: 16),
                _SegmentCard(
                  title: 'MCX — Commodities',
                  icon: LucideIcons.flame,
                  color: const Color(0xFF7B1FA2),
                  settings: _settings.mcx,
                  saving: _saving,
                  onChanged: (updated) => _save(
                    MarketSettings(stocks: _settings.stocks, mcx: updated),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Segment card ──────────────────────────────────────────────────────────────

class _SegmentCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final SegmentSettings settings;
  final bool saving;
  final ValueChanged<SegmentSettings> onChanged;

  const _SegmentCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.settings,
    required this.saving,
    required this.onChanged,
  });

  @override
  State<_SegmentCard> createState() => _SegmentCardState();
}

class _SegmentCardState extends State<_SegmentCard> {
  late TextEditingController _openCtrl;
  late TextEditingController _closeCtrl;

  // Track whether the time fields have unsaved changes
  bool _timeDirty = false;

  @override
  void initState() {
    super.initState();
    _openCtrl  = TextEditingController(text: widget.settings.marketOpen);
    _closeCtrl = TextEditingController(text: widget.settings.marketClose);
  }

  @override
  void didUpdateWidget(_SegmentCard old) {
    super.didUpdateWidget(old);
    if (!_timeDirty) {
      if (old.settings.marketOpen  != widget.settings.marketOpen)
        _openCtrl.text  = widget.settings.marketOpen;
      if (old.settings.marketClose != widget.settings.marketClose)
        _closeCtrl.text = widget.settings.marketClose;
    }
  }

  @override
  void dispose() {
    _openCtrl.dispose();
    _closeCtrl.dispose();
    super.dispose();
  }

  void _emitToggles({
    bool? enabled,
    bool? buyEnabled,
    bool? sellEnabled,
  }) {
    widget.onChanged(widget.settings.copyWith(
      enabled:     enabled,
      buyEnabled:  buyEnabled,
      sellEnabled: sellEnabled,
    ));
  }

  /// Validate and save market hours from the text controllers.
  void _saveMarketHours() {
    final openVal  = _openCtrl.text.trim();
    final closeVal = _closeCtrl.text.trim();
    final re = RegExp(r'^\d{2}:\d{2}$');

    if (!re.hasMatch(openVal)) {
      AppToast.error(
          context, 'Open time is not valid. Please use HH:MM format (e.g. 09:15).');
      return;
    }
    if (!re.hasMatch(closeVal)) {
      AppToast.error(
          context, 'Close time is not valid. Please use HH:MM format (e.g. 15:30).');
      return;
    }

    // Validate open < close
    int _toMin(String t) {
      final p = t.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    if (_toMin(openVal) >= _toMin(closeVal)) {
      AppToast.error(context, 'Open time must be earlier than close time.');
      return;
    }

    setState(() => _timeDirty = false);
    widget.onChanged(widget.settings.copyWith(
      marketOpen:  openVal,
      marketClose: closeVal,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final c = widget.color;

    return AdminPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(widget.icon, size: 18, color: c),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              // Master enable/disable
              Row(
                children: [
                  Text(
                    s.enabled ? 'Enabled' : 'Disabled',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: s.enabled
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: s.enabled,
                    onChanged: widget.saving
                        ? null
                        : (v) => _emitToggles(enabled: v),
                    activeColor: AppColors.success,
                  ),
                ],
              ),
            ],
          ),

          if (!s.enabled) ...[
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertCircle,
                      size: 14, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Text(
                    'This segment is fully disabled. No orders can be placed.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.danger),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),

          // ── Buy / Sell toggles ───────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _ToggleRow(
                  label: 'Buy Orders',
                  icon: LucideIcons.trendingUp,
                  iconColor: AppColors.success,
                  value: s.buyEnabled,
                  disabled: !s.enabled || widget.saving,
                  onChanged: (v) => _emitToggles(buyEnabled: v),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ToggleRow(
                  label: 'Sell Orders',
                  icon: LucideIcons.trendingDown,
                  iconColor: AppColors.danger,
                  value: s.sellEnabled,
                  disabled: !s.enabled || widget.saving,
                  onChanged: (v) => _emitToggles(sellEnabled: v),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),

          // ── Market hours ─────────────────────────────────────────────────
          Row(
            children: [
              Text(
                'MARKET HOURS (IST)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (_timeDirty)
                _UnsavedBadge(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TimeField(
                  label: 'Open',
                  controller: _openCtrl,
                  disabled: !s.enabled || widget.saving,
                  onChanged: (_) => setState(() => _timeDirty = true),
                ),
              ),
              const SizedBox(width: 12),
              const Text('–',
                  style: TextStyle(
                      fontSize: 18, color: AppColors.textSecondary)),
              const SizedBox(width: 12),
              Expanded(
                child: _TimeField(
                  label: 'Close',
                  controller: _closeCtrl,
                  disabled: !s.enabled || widget.saving,
                  onChanged: (_) => setState(() => _timeDirty = true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Format: HH:MM (24-hour IST).',
            style: TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: (!s.enabled || widget.saving)
                  ? null
                  : _saveMarketHours,
              icon: widget.saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(LucideIcons.save, size: 14),
              label: const Text('Save Hours'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Unsaved badge ─────────────────────────────────────────────────────────────

class _UnsavedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.warning.withOpacity(0.4)),
      ),
      child: const Text(
        'Unsaved changes',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.warning,
        ),
      ),
    );
  }
}

// ── Leverage summary row ──────────────────────────────────────────────────────

class _LeverageSummaryRow extends StatelessWidget {
  final SegmentSettings settings;
  final Color color;

  const _LeverageSummaryRow({required this.settings, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 13, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Currently live: Max leverage ${settings.maxLeverage.toStringAsFixed(0)}x  •  '
              'Margin required ${settings.marginPercent.toStringAsFixed(2)}%',
              style: TextStyle(
                fontSize: 11,
                color: color.withOpacity(0.85),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Toggle row ────────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final bool value;
  final bool disabled;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.disabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: disabled
            ? const Color(0xFFF5F5F5)
            : value
                ? iconColor.withValues(alpha: 0.06)
                : AppColors.danger.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: disabled
              ? const Color(0xFFE0E0E0)
              : value
                  ? iconColor.withValues(alpha: 0.3)
                  : AppColors.danger.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: disabled ? AppColors.textSecondary : iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: disabled
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: disabled ? null : onChanged,
            activeColor: iconColor,
          ),
        ],
      ),
    );
  }
}

// ── Time field ────────────────────────────────────────────────────────────────

class _TimeField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool disabled;
  final ValueChanged<String>? onChanged;

  const _TimeField({
    required this.label,
    required this.controller,
    required this.disabled,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: !disabled,
          keyboardType: TextInputType.datetime,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: 'HH:MM',
            filled: true,
            fillColor:
                disabled ? const Color(0xFFF5F5F5) : Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ── Labeled numeric field ─────────────────────────────────────────────────────

class _LabeledField extends StatelessWidget {
  final String label;
  final String hint;
  final String suffix;
  final TextEditingController controller;
  final bool disabled;
  final ValueChanged<String>? onChanged;
  final String? helperText;

  const _LabeledField({
    required this.label,
    required this.hint,
    required this.suffix,
    required this.controller,
    required this.disabled,
    this.onChanged,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: !disabled,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: hint,
            suffixText: suffix,
            filled: true,
            fillColor:
                disabled ? const Color(0xFFF5F5F5) : Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
          ),
          onChanged: onChanged,
        ),
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            helperText!,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}
