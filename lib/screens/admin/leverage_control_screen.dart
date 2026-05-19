import 'package:cloud_firestore/cloud_firestore.dart' hide Order, Transaction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:box_trading_web/theme.dart';
import 'package:box_trading_web/widgets/app_dialog.dart';
import 'package:box_trading_web/screens/admin/admin_ui.dart';

// ─── Category definitions ─────────────────────────────────────────────────────

class _Category {
  final String key;
  final String displayName;
  /// true = shows "₹X per Lot" (option selling), false = shows "Nx (Y%)" leverage
  final bool perLotMode;
  final double defaultMisValue;
  final double defaultNrmlValue;

  const _Category({
    required this.key,
    required this.displayName,
    this.perLotMode = false,
    required this.defaultMisValue,
    required this.defaultNrmlValue,
  });
}

const _kCategories = <_Category>[
  _Category(key: 'mcx_futures',        displayName: 'MCX FUTURES',        defaultMisValue: 500,   defaultNrmlValue: 20),
  _Category(key: 'mcx_option_buying',  displayName: 'MCX OPTION BUYING',  defaultMisValue: 10,    defaultNrmlValue: 2),
  _Category(key: 'mcx_option_selling', displayName: 'MCX OPTION SELLING', perLotMode: true,  defaultMisValue: 7500,  defaultNrmlValue: 20000),
  _Category(key: 'nse_option_buying',  displayName: 'NSE OPTION BUYING',  defaultMisValue: 10,    defaultNrmlValue: 2),
  _Category(key: 'nse_option_selling', displayName: 'NSE OPTION SELLING', perLotMode: true,  defaultMisValue: 7500,  defaultNrmlValue: 20000),
  _Category(key: 'nse_futures',        displayName: 'NSE FUTURES',        defaultMisValue: 500,   defaultNrmlValue: 50),
  _Category(key: 'nse_spot',           displayName: 'NSE SPOT',           defaultMisValue: 20,    defaultNrmlValue: 10),
];

// ─── Preset options ───────────────────────────────────────────────────────────

const _kLeveragePresets = <double>[2, 5, 10, 20, 25, 50, 100, 200, 500, 1000, 2000];
const _kPerLotPresets   = <double>[1000, 2500, 5000, 7500, 10000, 15000, 20000, 25000, 30000, 50000];

String _fmtLeverage(double v) {
  final pct = (100 / v).toStringAsFixed(2);
  return '${v.toStringAsFixed(0)}x ($pct%)';
}

String _fmtPerLot(double v) {
  final s = v.toStringAsFixed(0).replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return '₹$s per Lot';
}

String _fmtValue(double v, bool perLotMode) =>
    perLotMode ? _fmtPerLot(v) : _fmtLeverage(v);

// ─── Data model ───────────────────────────────────────────────────────────────

class _MarginData {
  double misBuyValue;   // MIS leverage for BUY orders
  double misSellValue;  // MIS leverage for SELL (short) orders
  double nrmlValue;

  _MarginData({
    required this.misBuyValue,
    required this.misSellValue,
    required this.nrmlValue,
  });

  _MarginData copy() => _MarginData(
        misBuyValue: misBuyValue,
        misSellValue: misSellValue,
        nrmlValue: nrmlValue,
      );

  bool equals(_MarginData o) =>
      misBuyValue == o.misBuyValue &&
      misSellValue == o.misSellValue &&
      nrmlValue == o.nrmlValue;

  Map<String, dynamic> toFirestore(String key, String name, bool perLotMode) {
    final misBuyMar  = perLotMode || misBuyValue  <= 0 ? 0.0 : double.parse((100 / misBuyValue).toStringAsFixed(4));
    final misSellMar = perLotMode || misSellValue <= 0 ? 0.0 : double.parse((100 / misSellValue).toStringAsFixed(4));
    final nrmlMar    = perLotMode || nrmlValue    <= 0 ? 0.0 : double.parse((100 / nrmlValue).toStringAsFixed(4));
    return {
      'categoryKey':  key,
      'categoryName': name,
      'mis_value':    misBuyValue,  // legacy: treat buy as default
      'nrml_value':   nrmlValue,
      'per_lot_mode': perLotMode,
      if (perLotMode) ...{
        'mis_per_lot':  misBuyValue,
        'nrml_per_lot': nrmlValue,
        'mis_leverage':       0.0,
        'mis_buy_leverage':   0.0,
        'mis_sell_leverage':  0.0,
        'mis_margin':         0.0,
        'nrml_leverage':      0.0,
        'nrml_buy_leverage':  nrmlValue,
        'nrml_sell_leverage': nrmlValue,
        'nrml_margin':        0.0,
      } else ...{
        // Separate buy / sell leverage — read by backend resolveLeverage()
        'mis_buy_leverage':   misBuyValue,
        'mis_buy_margin':     misBuyMar,
        'mis_sell_leverage':  misSellValue,
        'mis_sell_margin':    misSellMar,
        // Shared NRML (no short-selling on overnight/delivery)
        'nrml_buy_leverage':  nrmlValue,
        'nrml_buy_margin':    nrmlMar,
        'nrml_sell_leverage': nrmlValue,
        'nrml_sell_margin':   nrmlMar,
        'nrml_leverage':      nrmlValue,
        'nrml_margin':        nrmlMar,
        // Legacy aliases for backward compatibility
        'mis_leverage':       misBuyValue,
        'mis_margin':         misBuyMar,
        'leverage':           misBuyValue,
        'margin':             misBuyMar,
        'mis_per_lot':        0.0,
        'nrml_per_lot':       0.0,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class LeverageControlScreen extends StatefulWidget {
  const LeverageControlScreen({super.key});

  @override
  State<LeverageControlScreen> createState() => _LeverageControlScreenState();
}

class _LeverageControlScreenState extends State<LeverageControlScreen> {
  final Map<String, _MarginData> _draft = {};
  final Map<String, _MarginData> _saved = {};
  bool _loading = true;
  bool _saving  = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('category_leverage')
          .get();

      final loaded = <String, _MarginData>{};
      for (final doc in snap.docs) {
        final d   = doc.data();
        final cat = _kCategories.where((c) => c.key == doc.id).firstOrNull;
        if (cat == null) continue;

        if (cat.perLotMode) {
          final mis  = (d['mis_per_lot']  as num?)?.toDouble() ??
                       (d['mis_value']    as num?)?.toDouble() ??
                       cat.defaultMisValue;
          final nrml = (d['nrml_per_lot'] as num?)?.toDouble() ??
                       (d['nrml_value']   as num?)?.toDouble() ??
                       cat.defaultNrmlValue;
          loaded[doc.id] = _MarginData(
            misBuyValue: mis,
            misSellValue: mis,
            nrmlValue: nrml,
          );
        } else {
          final misBuy  = (d['mis_buy_leverage']  as num?)?.toDouble() ??
                          (d['mis_leverage']       as num?)?.toDouble() ??
                          (d['leverage']           as num?)?.toDouble() ??
                          (d['mis_value']          as num?)?.toDouble() ??
                          cat.defaultMisValue;
          final misSell = (d['mis_sell_leverage'] as num?)?.toDouble() ??
                          misBuy;
          final nrml = (d['nrml_leverage']     as num?)?.toDouble() ??
                       (d['nrml_buy_leverage'] as num?)?.toDouble() ??
                       (d['nrml_value']        as num?)?.toDouble() ??
                       cat.defaultNrmlValue;
          loaded[doc.id] = _MarginData(
            misBuyValue: misBuy,
            misSellValue: misSell,
            nrmlValue: nrml,
          );
        }
      }

      // Seed defaults for any category not yet in Firestore
      for (final cat in _kCategories) {
        loaded.putIfAbsent(cat.key, () => _MarginData(
          misBuyValue:  cat.defaultMisValue,
          misSellValue: cat.defaultMisValue,
          nrmlValue:    cat.defaultNrmlValue,
        ));
      }

      setState(() {
        _saved.addAll(loaded);
        for (final e in loaded.entries) _draft[e.key] = e.value.copy();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[LeverageScreen] Load error: $e');
      setState(() => _loading = false);
      if (mounted) AppToast.error(context, 'Could not load leverage settings.');
    }
  }

  bool get _isDirty {
    for (final cat in _kCategories) {
      final d = _draft[cat.key];
      final s = _saved[cat.key];
      if (d != null && s != null && !d.equals(s)) return true;
    }
    return false;
  }

  Future<void> _saveAll() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final db    = FirebaseFirestore.instance;
      final batch = db.batch();
      for (final cat in _kCategories) {
        final d = _draft[cat.key];
        if (d == null) continue;
        batch.set(
          db.collection('category_leverage').doc(cat.key),
          d.toFirestore(cat.key, cat.displayName, cat.perLotMode),
        );
      }
      await batch.commit();
      for (final e in _draft.entries) _saved[e.key] = e.value.copy();
      if (mounted) AppToast.success(context, 'All margin settings saved.');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Save failed. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _discard() {
    setState(() {
      for (final e in _saved.entries) _draft[e.key] = e.value.copy();
    });
  }

  // field: 'misBuy' | 'misSell' | 'nrml'
  void _openEdit(BuildContext ctx, _Category cat, String field) {
    final data = _draft[cat.key]!;
    final double current;
    final String label;
    switch (field) {
      case 'misSell':
        current = data.misSellValue;
        label   = 'Intraday SELL (Short)';
        break;
      case 'nrml':
        current = data.nrmlValue;
        label   = 'Holding (NRML)';
        break;
      case 'misBuy':
      default:
        current = data.misBuyValue;
        label   = 'Intraday BUY (MIS)';
        break;
    }
    final presets = cat.perLotMode ? _kPerLotPresets : _kLeveragePresets;

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditSheet(
        categoryName: cat.displayName,
        label: label,
        perLotMode: cat.perLotMode,
        currentValue: current,
        presets: presets,
        onConfirm: (val) {
          setState(() {
            final copy = _draft[cat.key]!.copy();
            switch (field) {
              case 'misSell':
                copy.misSellValue = val;
                break;
              case 'nrml':
                copy.nrmlValue = val;
                break;
              default:
                copy.misBuyValue = val;
            }
            _draft[cat.key] = copy;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                AdminHeader(
                  title: 'Intraday & Holding Margin',
                  subtitle: 'Set leverage / margin per trading category. '
                      'Tap any cell to pick a preset or enter a custom value. '
                      'Changes apply to all new orders immediately.',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isDirty) ...[
                        OutlinedButton(
                          onPressed: _discard,
                          child: const Text('Discard'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ElevatedButton.icon(
                        onPressed: (_saving || _loading) ? null : _saveAll,
                        icon: _saving
                            ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(LucideIcons.save, size: 14),
                        label: Text(_isDirty ? 'Save Changes' : 'Save All'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (_loading)
                  const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  _MarginTable(
                    categories: _kCategories,
                    draft: _draft,
                    saved: _saved,
                    onEdit: (cat, field) => _openEdit(context, cat, field),
                  ),

                const SizedBox(height: 24),
              ],
            ),
          ),

          // ── Sticky bottom bar ──────────────────────────────────────────────
          if (!_loading)
            Container(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final isMobile = constraints.maxWidth < 600;
                  final statusText = Text(
                    _isDirty ? 'You have unsaved changes' : 'All changes saved',
                    style: TextStyle(
                      fontSize: 12,
                      color:      _isDirty ? AppColors.warning : AppColors.textSecondary,
                      fontWeight: _isDirty ? FontWeight.w600  : FontWeight.normal,
                    ),
                  );
                  final actions = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isDirty) ...[
                        OutlinedButton(onPressed: _discard, child: const Text('Discard')),
                        const SizedBox(width: 10),
                      ],
                      ElevatedButton.icon(
                        onPressed: (_saving || _loading) ? null : _saveAll,
                        icon: _saving
                            ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(LucideIcons.save, size: 14),
                        label: Text(_isDirty ? 'Save All Changes' : 'Save All'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                      ),
                    ],
                  );
                  if (isMobile) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: statusText),
                        const SizedBox(height: 10),
                        actions,
                      ],
                    );
                  }
                  return Row(
                    children: [statusText, const Spacer(), actions],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Table widget ─────────────────────────────────────────────────────────────

class _MarginTable extends StatelessWidget {
  final List<_Category> categories;
  final Map<String, _MarginData> draft;
  final Map<String, _MarginData> saved;
  // field: 'misBuy' | 'misSell' | 'nrml'
  final void Function(_Category, String field) onEdit;

  const _MarginTable({
    required this.categories,
    required this.draft,
    required this.saved,
    required this.onEdit,
  });

  static const _kGreen        = Color(0xFF2E7D32);
  static const _kDarkNavy     = Color(0xFF1A2035);
  static const _kDeepRed      = Color(0xFF7B1522);
  static const _kDeepOlive    = Color(0xFF3E4A1E);
  static const _kRowOdd       = Color(0xFFF7F7F7);
  static const _kRowEven      = Colors.white;
  static const _kDivider      = Color(0xFFE4E4E4);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kDivider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        color: Colors.white,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    color: _kGreen,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    alignment: Alignment.centerLeft,
                    child: const Text(
                      'EXCHANGE',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Container(
                    color: _kDarkNavy,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    alignment: Alignment.center,
                    child: const Text(
                      'INTRADAY\nBUY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.4,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Container(
                    color: _kDeepRed,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    alignment: Alignment.center,
                    child: const Text(
                      'INTRADAY\nSELL',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.4,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Container(
                    color: _kDeepOlive,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    alignment: Alignment.center,
                    child: const Text(
                      'HOLDING\n(NRML)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.4,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Data rows ────────────────────────────────────────────────────
          ...List.generate(categories.length, (i) {
            final cat  = categories[i];
            final data = draft[cat.key] ?? _MarginData(
              misBuyValue:  cat.defaultMisValue,
              misSellValue: cat.defaultMisValue,
              nrmlValue:    cat.defaultNrmlValue,
            );
            final savedData = saved[cat.key];
            final isDirty   = savedData != null && !data.equals(savedData);
            final rowBg     = i.isOdd ? _kRowOdd : _kRowEven;

            return Container(
              decoration: BoxDecoration(
                color: rowBg,
                border: const Border(bottom: BorderSide(color: _kDivider)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Exchange name
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                cat.displayName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                            ),
                            if (isDirty)
                              Container(
                                width: 7, height: 7,
                                decoration: const BoxDecoration(
                                  color: AppColors.warning,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Intraday BUY
                    Expanded(
                      flex: 3,
                      child: _ValueCell(
                        value: data.misBuyValue,
                        perLotMode: cat.perLotMode,
                        rowBg: rowBg,
                        onTap: () => onEdit(cat, 'misBuy'),
                      ),
                    ),
                    // Intraday SELL (short)
                    Expanded(
                      flex: 3,
                      child: _ValueCell(
                        value: data.misSellValue,
                        perLotMode: cat.perLotMode,
                        rowBg: rowBg,
                        onTap: () => onEdit(cat, 'misSell'),
                      ),
                    ),
                    // Holding (NRML)
                    Expanded(
                      flex: 3,
                      child: _ValueCell(
                        value: data.nrmlValue,
                        perLotMode: cat.perLotMode,
                        rowBg: rowBg,
                        onTap: () => onEdit(cat, 'nrml'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Value cell ───────────────────────────────────────────────────────────────

class _ValueCell extends StatelessWidget {
  final double value;
  final bool perLotMode;
  final Color rowBg;
  final VoidCallback onTap;

  const _ValueCell({
    required this.value,
    required this.perLotMode,
    required this.rowBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: rowBg,
          border: const Border(left: BorderSide(color: Color(0xFFE4E4E4))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _fmtValue(value, perLotMode),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF222222),
                ),
              ),
            ),
            Icon(
              LucideIcons.pencil,
              size: 12,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Edit bottom sheet ────────────────────────────────────────────────────────

class _EditSheet extends StatefulWidget {
  final String categoryName;
  final String label;
  final bool perLotMode;
  final double currentValue;
  final List<double> presets;
  final ValueChanged<double> onConfirm;

  const _EditSheet({
    required this.categoryName,
    required this.label,
    required this.perLotMode,
    required this.currentValue,
    required this.presets,
    required this.onConfirm,
  });

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late double _selected;
  bool _isCustom = false;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentValue;
    _isCustom = !widget.presets.contains(widget.currentValue);
    _ctrl = TextEditingController(
      text: _isCustom ? widget.currentValue.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _apply() {
    double val;
    if (_isCustom) {
      val = double.tryParse(_ctrl.text) ?? 0;
    } else {
      val = _selected;
    }
    if (val <= 0) return;
    widget.onConfirm(val);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isCustomInput = _isCustom;
    final customVal = double.tryParse(_ctrl.text);
    final showMarginHint = !widget.perLotMode && isCustomInput &&
        customVal != null && customVal > 0;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Title
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.categoryName,
                          style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  // Current value badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: Text(
                      _fmtValue(widget.currentValue, widget.perLotMode),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Section label
              Text(
                'Select Preset',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[600],
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 10),

              // Preset chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...widget.presets.map((p) {
                    final sel = !isCustomInput && _selected == p;
                    return _PresetChip(
                      label: _fmtValue(p, widget.perLotMode),
                      selected: sel,
                      color: AppColors.primary,
                      onTap: () => setState(() {
                        _selected  = p;
                        _isCustom  = false;
                      }),
                    );
                  }),
                  // Custom chip
                  _PresetChip(
                    label: 'Custom',
                    selected: isCustomInput,
                    color: const Color(0xFF7B1FA2),
                    icon: LucideIcons.pencil,
                    onTap: () => setState(() => _isCustom = true),
                  ),
                ],
              ),

              // Custom input field
              if (isCustomInput) ...[
                const SizedBox(height: 18),
                Text(
                  widget.perLotMode
                      ? 'Enter amount per lot (₹)'
                      : 'Enter leverage (multiplier)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    hintText: widget.perLotMode ? 'e.g. 7500' : 'e.g. 500',
                    suffixText: widget.perLotMode ? '₹/Lot' : 'x',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  onChanged: (v) => setState(() {}),
                ),
                if (showMarginHint) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Margin required: ${(100 / customVal!).toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 22),

              // Apply button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    isCustomInput && _ctrl.text.isNotEmpty
                        ? 'Apply Custom Value'
                        : 'Apply ${_fmtValue(_selected, widget.perLotMode)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Preset chip ──────────────────────────────────────────────────────────────

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final IconData? icon;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.color,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : const Color(0xFFDDDDDD),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: color.withOpacity(0.2), blurRadius: 4)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: selected ? Colors.white : color),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF333333),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
