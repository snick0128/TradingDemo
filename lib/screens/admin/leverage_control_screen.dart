import 'package:cloud_firestore/cloud_firestore.dart' hide Order, Transaction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:box_trading_web/config/backend_config.dart';
import 'package:box_trading_web/data/services/backend_api_service.dart';
import 'package:box_trading_web/models/platform_settings.dart';
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
  /// If true, admin can toggle overnight short-sell blocking for this category
  final bool allowOvernightShortSellBlock;

  const _Category({
    required this.key,
    required this.displayName,
    this.perLotMode = false,
    required this.defaultMisValue,
    required this.defaultNrmlValue,
    this.allowOvernightShortSellBlock = false,
  });
}

const _kCategories = <_Category>[
  _Category(key: 'mcx_futures',        displayName: 'MCX FUTURES',        defaultMisValue: 500,   defaultNrmlValue: 20),
  _Category(key: 'mcx_option_buying',  displayName: 'MCX OPTION BUYING',  defaultMisValue: 10,    defaultNrmlValue: 2),
  _Category(key: 'mcx_option_selling', displayName: 'MCX OPTION SELLING', perLotMode: true,  defaultMisValue: 7500,  defaultNrmlValue: 20000),
  _Category(key: 'nse_option_buying',  displayName: 'NSE OPTION BUYING',  defaultMisValue: 10,    defaultNrmlValue: 2),
  _Category(key: 'nse_option_selling', displayName: 'NSE OPTION SELLING', perLotMode: true,  defaultMisValue: 7500,  defaultNrmlValue: 20000),
  _Category(key: 'nse_futures',        displayName: 'NSE FUTURES',        defaultMisValue: 500,   defaultNrmlValue: 50),
  _Category(key: 'nse_spot',           displayName: 'NSE SPOT',           defaultMisValue: 20,    defaultNrmlValue: 10,  allowOvernightShortSellBlock: true),
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
  double misSellValue;  // MIS leverage for intraday SELL (short)
  double nrmlBuyValue;  // NRML leverage for overnight BUY
  double nrmlSellValue; // NRML leverage for overnight SELL (short)
  bool? blockOvernightShortSell; // null = not applicable for this category

  // Brokerage charges — written to category_leverage and read by resolveCharges()
  double fixedCharge;   // Fixed ₹ per trade (applied to both MIS and NRML)
  double percentCharge; // % of turnover per trade (e.g. 0.03 = 0.03%)

  _MarginData({
    required this.misBuyValue,
    required this.misSellValue,
    required this.nrmlBuyValue,
    required this.nrmlSellValue,
    this.blockOvernightShortSell,
    this.fixedCharge   = 0.0,
    this.percentCharge = 0.0,
  });

  _MarginData copy() => _MarginData(
        misBuyValue:  misBuyValue,
        misSellValue: misSellValue,
        nrmlBuyValue: nrmlBuyValue,
        nrmlSellValue: nrmlSellValue,
        blockOvernightShortSell: blockOvernightShortSell,
        fixedCharge:   fixedCharge,
        percentCharge: percentCharge,
      );

  bool equals(_MarginData o) =>
      misBuyValue  == o.misBuyValue  &&
      misSellValue == o.misSellValue &&
      nrmlBuyValue == o.nrmlBuyValue &&
      nrmlSellValue == o.nrmlSellValue &&
      blockOvernightShortSell == o.blockOvernightShortSell &&
      fixedCharge   == o.fixedCharge   &&
      percentCharge == o.percentCharge;

  Map<String, dynamic> toFirestore(String key, String name, bool perLotMode) {
    final misBuyMar   = perLotMode || misBuyValue   <= 0 ? 0.0 : double.parse((100 / misBuyValue).toStringAsFixed(4));
    final misSellMar  = perLotMode || misSellValue  <= 0 ? 0.0 : double.parse((100 / misSellValue).toStringAsFixed(4));
    final nrmlBuyMar  = perLotMode || nrmlBuyValue  <= 0 ? 0.0 : double.parse((100 / nrmlBuyValue).toStringAsFixed(4));
    final nrmlSellMar = perLotMode || nrmlSellValue <= 0 ? 0.0 : double.parse((100 / nrmlSellValue).toStringAsFixed(4));
    return {
      'categoryKey':  key,
      'categoryName': name,
      'mis_value':    misBuyValue,  // legacy alias
      'nrml_value':   nrmlBuyValue, // legacy alias
      'per_lot_mode': perLotMode,
      if (perLotMode) ...{
        'mis_per_lot':        misBuyValue,
        'nrml_per_lot':       nrmlBuyValue,
        'mis_leverage':       0.0,
        'mis_buy_leverage':   0.0,
        'mis_sell_leverage':  0.0,
        'mis_margin':         0.0,
        'nrml_leverage':      0.0,
        'nrml_buy_leverage':  nrmlBuyValue,
        'nrml_sell_leverage': nrmlSellValue,
        'nrml_margin':        0.0,
        'mis_per_lot_sell':   misSellValue,
        'nrml_per_lot_sell':  nrmlSellValue,
      } else ...{
        // Separate buy / sell leverage — read by backend resolveLeverage()
        'mis_buy_leverage':   misBuyValue,
        'mis_buy_margin':     misBuyMar,
        'mis_sell_leverage':  misSellValue,
        'mis_sell_margin':    misSellMar,
        // Separate NRML BUY / NRML SELL leverage
        'nrml_buy_leverage':  nrmlBuyValue,
        'nrml_buy_margin':    nrmlBuyMar,
        'nrml_sell_leverage': nrmlSellValue,
        'nrml_sell_margin':   nrmlSellMar,
        // Legacy aliases
        'nrml_leverage':      nrmlBuyValue,
        'nrml_margin':        nrmlBuyMar,
        'mis_leverage':       misBuyValue,
        'mis_margin':         misBuyMar,
        'leverage':           misBuyValue,
        'margin':             misBuyMar,
        'mis_per_lot':        0.0,
        'nrml_per_lot':       0.0,
      },
      if (blockOvernightShortSell != null)
        'block_overnight_short_sell': blockOvernightShortSell,
      // Brokerage charges — read by backend resolveCharges()
      // Same fixed/percent charge applied across all sides for simplicity.
      'mis_buy_fixed_charge':    fixedCharge,
      'mis_sell_fixed_charge':   fixedCharge,
      'nrml_buy_fixed_charge':   fixedCharge,
      'nrml_sell_fixed_charge':  fixedCharge,
      'mis_buy_percent_charge':  percentCharge,
      'mis_sell_percent_charge': percentCharge,
      'nrml_buy_percent_charge': percentCharge,
      'nrml_sell_percent_charge': percentCharge,
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

  // ── Global risk defaults (backend API) ────────────────────────────────────
  final _api              = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
  final _intradayLevCtrl  = TextEditingController();
  final _shortSellLevCtrl = TextEditingController();
  final _nrmlBuyLevCtrl   = TextEditingController();
  final _nrmlSellLevCtrl  = TextEditingController();
  bool _enableShortSelling            = true;
  bool _allowEquityIntradayShortSell  = true;
  bool _blockOvernightEquityShortSell = true;
  bool _globalLoading = true;
  bool _globalSaving  = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadGlobal();
  }

  @override
  void dispose() {
    _intradayLevCtrl.dispose();
    _shortSellLevCtrl.dispose();
    _nrmlBuyLevCtrl.dispose();
    _nrmlSellLevCtrl.dispose();
    super.dispose();
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
        _Category? cat;
        for (final c in _kCategories) {
          if (c.key == doc.id) { cat = c; break; }
        }
        if (cat == null) continue;

        if (cat.perLotMode) {
          final misBuy  = (d['mis_per_lot']      as num?)?.toDouble() ??
                          (d['mis_value']         as num?)?.toDouble() ??
                          cat.defaultMisValue;
          final misSell = (d['mis_per_lot_sell']  as num?)?.toDouble() ?? misBuy;
          final nrmlBuy = (d['nrml_per_lot']      as num?)?.toDouble() ??
                          (d['nrml_value']         as num?)?.toDouble() ??
                          cat.defaultNrmlValue;
          final nrmlSell = (d['nrml_per_lot_sell'] as num?)?.toDouble() ??
                           (d['nrml_sell_leverage'] as num?)?.toDouble() ??
                           nrmlBuy;
          final fixedCharge   = (d['mis_buy_fixed_charge']   as num?)?.toDouble() ?? 0.0;
          final percentCharge = (d['mis_buy_percent_charge'] as num?)?.toDouble() ?? 0.0;
          loaded[doc.id] = _MarginData(
            misBuyValue:  misBuy,
            misSellValue: misSell,
            nrmlBuyValue: nrmlBuy,
            nrmlSellValue: nrmlSell,
            blockOvernightShortSell: cat.allowOvernightShortSellBlock
                ? (d['block_overnight_short_sell'] as bool? ?? true)
                : null,
            fixedCharge:   fixedCharge,
            percentCharge: percentCharge,
          );
        } else {
          final misBuy  = (d['mis_buy_leverage']  as num?)?.toDouble() ??
                          (d['mis_leverage']       as num?)?.toDouble() ??
                          (d['leverage']           as num?)?.toDouble() ??
                          (d['mis_value']          as num?)?.toDouble() ??
                          cat.defaultMisValue;
          final misSell = (d['mis_sell_leverage'] as num?)?.toDouble() ?? misBuy;
          final nrmlBuy = (d['nrml_buy_leverage'] as num?)?.toDouble() ??
                          (d['nrml_leverage']      as num?)?.toDouble() ??
                          (d['nrml_value']         as num?)?.toDouble() ??
                          cat.defaultNrmlValue;
          final nrmlSell = (d['nrml_sell_leverage'] as num?)?.toDouble() ?? nrmlBuy;
          final fixedCharge   = (d['mis_buy_fixed_charge']   as num?)?.toDouble() ?? 0.0;
          final percentCharge = (d['mis_buy_percent_charge'] as num?)?.toDouble() ?? 0.0;
          loaded[doc.id] = _MarginData(
            misBuyValue:  misBuy,
            misSellValue: misSell,
            nrmlBuyValue: nrmlBuy,
            nrmlSellValue: nrmlSell,
            blockOvernightShortSell: cat.allowOvernightShortSellBlock
                ? (d['block_overnight_short_sell'] as bool? ?? true)
                : null,
            fixedCharge:   fixedCharge,
            percentCharge: percentCharge,
          );
        }
      }

      // Seed defaults for any category not yet in Firestore
      for (final cat in _kCategories) {
        loaded.putIfAbsent(cat.key, () => _MarginData(
          misBuyValue:  cat.defaultMisValue,
          misSellValue: cat.defaultMisValue,
          nrmlBuyValue: cat.defaultNrmlValue,
          nrmlSellValue: cat.defaultNrmlValue,
          blockOvernightShortSell: cat.allowOvernightShortSellBlock ? true : null,
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

  Future<void> _loadGlobal() async {
    setState(() => _globalLoading = true);
    try {
      final data = await _api.getRmsSettings();
      final rms  = PlatformRmsSettings.fromMap(data);
      _intradayLevCtrl.text  = rms.intradayLeverage.toStringAsFixed(0);
      _shortSellLevCtrl.text = rms.shortSellLeverage.toStringAsFixed(0);
      _nrmlBuyLevCtrl.text   = rms.nrmlBuyLeverage.toStringAsFixed(0);
      _nrmlSellLevCtrl.text  = rms.nrmlSellLeverage.toStringAsFixed(0);
      setState(() {
        _enableShortSelling            = rms.enableShortSelling;
        _allowEquityIntradayShortSell  = rms.allowEquityIntradayShortSell;
        _blockOvernightEquityShortSell = rms.blockOvernightEquityShortSell;
      });
    } catch (e) {
      debugPrint('[LeverageScreen] Global load error: $e');
      _intradayLevCtrl.text  = '5';
      _shortSellLevCtrl.text = '5';
      _nrmlBuyLevCtrl.text   = '1';
      _nrmlSellLevCtrl.text  = '1';
    } finally {
      if (mounted) setState(() => _globalLoading = false);
    }
  }

  Future<void> _saveGlobal() async {
    if (_globalSaving) return;
    setState(() => _globalSaving = true);
    try {
      final shortSell = double.tryParse(_shortSellLevCtrl.text) ?? 5;
      await _api.updateRmsSettings({
        'intradayLeverage':              double.tryParse(_intradayLevCtrl.text) ?? 5,
        'shortSellLeverage':             shortSell,
        'intradayShortSellLeverage':     shortSell,
        'nrmlBuyLeverage':               double.tryParse(_nrmlBuyLevCtrl.text)  ?? 1,
        'nrmlSellLeverage':              double.tryParse(_nrmlSellLevCtrl.text)  ?? 1,
        'enableShortSelling':            _enableShortSelling,
        'allowEquityIntradayShortSell':  _allowEquityIntradayShortSell,
        'blockOvernightEquityShortSell': _blockOvernightEquityShortSell,
      });
      if (mounted) AppToast.success(context, 'Global risk defaults saved.');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Save failed. Please try again.');
    } finally {
      if (mounted) setState(() => _globalSaving = false);
    }
  }

  // field: 'misBuy' | 'misSell' | 'nrmlBuy' | 'nrmlSell'
  void _openEdit(BuildContext ctx, _Category cat, String field) {
    final data = _draft[cat.key]!;
    final double current;
    final String label;
    switch (field) {
      case 'misSell':
        current = data.misSellValue;
        label   = 'Short Sell Intraday (MIS)';
        break;
      case 'nrmlBuy':
        current = data.nrmlBuyValue;
        label   = 'Overnight BUY (NRML)';
        break;
      case 'nrmlSell':
        current = data.nrmlSellValue;
        label   = 'Short Sell Overnight (NRML)';
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
              case 'nrmlBuy':
                copy.nrmlBuyValue = val;
                break;
              case 'nrmlSell':
                copy.nrmlSellValue = val;
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
                  title: 'Leverage & Margin Control',
                  subtitle: 'Set Buy / Short Sell leverage per category. '
                      'SHORT SELL column applies to new short positions only — exit sells never require margin. '
                      'Tap any cell to change. Changes apply to all new orders immediately.',
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
                else ...[
                  _MarginTable(
                    categories: _kCategories,
                    draft: _draft,
                    saved: _saved,
                    onEdit: (cat, field) => _openEdit(context, cat, field),
                  ),
                  const SizedBox(height: 24),
                  _ChargesCard(
                    categories: _kCategories,
                    draft: _draft,
                    onChanged: (catKey, fixed, pct) {
                      setState(() {
                        final copy = _draft[catKey]!.copy();
                        copy.fixedCharge   = fixed;
                        copy.percentCharge = pct;
                        _draft[catKey] = copy;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  _GlobalRiskSection(
                    loading:       _globalLoading,
                    saving:        _globalSaving,
                    intradayCtrl:  _intradayLevCtrl,
                    shortSellCtrl: _shortSellLevCtrl,
                    nrmlBuyCtrl:   _nrmlBuyLevCtrl,
                    nrmlSellCtrl:  _nrmlSellLevCtrl,
                    enableShortSelling:            _enableShortSelling,
                    allowEquityIntradayShortSell:  _allowEquityIntradayShortSell,
                    blockOvernightEquityShortSell: _blockOvernightEquityShortSell,
                    onToggleShortSelling: (v) => setState(() => _enableShortSelling = v),
                    onToggleEquityMis:    (v) => setState(() => _allowEquityIntradayShortSell = v),
                    onToggleEquityNrml:   (v) => setState(() => _blockOvernightEquityShortSell = v),
                    onSave: _saveGlobal,
                  ),
                  const SizedBox(height: 24),
                  _OvernightRestrictionsCard(
                    draft: _draft,
                    onToggle: (catKey, val) {
                      setState(() {
                        final copy = _draft[catKey]!.copy();
                        copy.blockOvernightShortSell = val;
                        _draft[catKey] = copy;
                      });
                    },
                  ),
                ],

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

// ─── Overnight restrictions card ─────────────────────────────────────────────

class _OvernightRestrictionsCard extends StatelessWidget {
  final Map<String, _MarginData> draft;
  final void Function(String catKey, bool val) onToggle;

  const _OvernightRestrictionsCard({
    required this.draft,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final blockableCats = _kCategories.where((c) => c.allowOvernightShortSellBlock);
    if (blockableCats.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E4)),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B1522).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  LucideIcons.shieldOff,
                  size: 18,
                  color: Color(0xFF7B1522),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Overnight Short-Selling Restrictions',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'When blocked, NRML SELL orders are rejected. Intraday (MIS) short selling is unaffected.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          const SizedBox(height: 12),
          ...blockableCats.map((cat) {
            final data = draft[cat.key];
            final isBlocked = data?.blockOvernightShortSell ?? true;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat.displayName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isBlocked
                              ? 'NRML SELL blocked — equity short selling not allowed overnight'
                              : 'NRML SELL allowed — overnight short selling is enabled',
                          style: TextStyle(
                            fontSize: 11,
                            color: isBlocked
                                ? const Color(0xFF7B1522)
                                : const Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isBlocked,
                    onChanged: (val) => onToggle(cat.key, val),
                    activeColor: const Color(0xFF7B1522),
                    inactiveThumbColor: const Color(0xFF2E7D32),
                    inactiveTrackColor: const Color(0xFF2E7D32).withOpacity(0.3),
                  ),
                ],
              ),
            );
          }),
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
  // field: 'misBuy' | 'misSell' | 'nrmlBuy' | 'nrmlSell'
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
  static const _kNrmlBuy      = Color(0xFF1A4035);  // dark teal — overnight buy
  static const _kNrmlSell     = Color(0xFF4A2E1E);  // dark brown — overnight short
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
          // ── Column group labels ──────────────────────────────────────────
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(flex: 5, child: SizedBox()),
                Expanded(
                  flex: 6,
                  child: Container(
                    color: _kDarkNavy.withOpacity(0.85),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    alignment: Alignment.center,
                    child: const Text(
                      'INTRADAY (MIS)',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white70,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: Container(
                    color: _kNrmlBuy.withOpacity(0.85),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    alignment: Alignment.center,
                    child: const Text(
                      'OVERNIGHT (NRML)',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white70,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),

              ],
            ),
          ),
          // ── Header ──────────────────────────────────────────────────────
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    color: _kGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    alignment: Alignment.centerLeft,
                    child: const Text(
                      'EXCHANGE',
                      style: TextStyle(
                        fontSize: 12,
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
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    alignment: Alignment.center,
                    child: const Text(
                      'BUY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Container(
                    color: _kDeepRed,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    alignment: Alignment.center,
                    child: const Text(
                      'SHORT\nSELL',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.3,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Container(
                    color: _kNrmlBuy,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    alignment: Alignment.center,
                    child: const Text(
                      'BUY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Container(
                    color: _kNrmlSell,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    alignment: Alignment.center,
                    child: const Text(
                      'SHORT\nSELL',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.3,
                        height: 1.2,
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
              misBuyValue:   cat.defaultMisValue,
              misSellValue:  cat.defaultMisValue,
              nrmlBuyValue:  cat.defaultNrmlValue,
              nrmlSellValue: cat.defaultNrmlValue,
              blockOvernightShortSell: cat.allowOvernightShortSellBlock ? true : null,
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
                          horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                cat.displayName,
                                style: const TextStyle(
                                  fontSize: 12,
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
                    // NRML BUY (overnight)
                    Expanded(
                      flex: 3,
                      child: _ValueCell(
                        value: data.nrmlBuyValue,
                        perLotMode: cat.perLotMode,
                        rowBg: rowBg,
                        onTap: () => onEdit(cat, 'nrmlBuy'),
                      ),
                    ),
                    // NRML SELL (overnight short)
                    Expanded(
                      flex: 3,
                      child: data.blockOvernightShortSell == true
                          ? _BlockedCell(rowBg: rowBg)
                          : _ValueCell(
                              value: data.nrmlSellValue,
                              perLotMode: cat.perLotMode,
                              rowBg: rowBg,
                              onTap: () => onEdit(cat, 'nrmlSell'),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _fmtValue(value, perLotMode),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF222222),
                ),
              ),
            ),
            Icon(
              LucideIcons.pencil,
              size: 11,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Blocked cell (overnight short blocked) ──────────────────────────────────

class _BlockedCell extends StatelessWidget {
  final Color rowBg;
  const _BlockedCell({required this.rowBg});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF7B1522).withOpacity(0.05),
        border: const Border(left: BorderSide(color: Color(0xFFE4E4E4))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      alignment: Alignment.center,
      child: const Text(
        'BLOCKED',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF7B1522),
          letterSpacing: 0.5,
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
                    'Margin required: ${(100 / customVal).toStringAsFixed(2)}%',
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

// ─── Global risk defaults section ────────────────────────────────────────────

class _GlobalRiskSection extends StatelessWidget {
  final bool loading;
  final bool saving;
  final TextEditingController intradayCtrl;
  final TextEditingController shortSellCtrl;
  final TextEditingController nrmlBuyCtrl;
  final TextEditingController nrmlSellCtrl;
  final bool enableShortSelling;
  final bool allowEquityIntradayShortSell;
  final bool blockOvernightEquityShortSell;
  final ValueChanged<bool> onToggleShortSelling;
  final ValueChanged<bool> onToggleEquityMis;
  final ValueChanged<bool> onToggleEquityNrml;
  final VoidCallback onSave;

  const _GlobalRiskSection({
    required this.loading,
    required this.saving,
    required this.intradayCtrl,
    required this.shortSellCtrl,
    required this.nrmlBuyCtrl,
    required this.nrmlSellCtrl,
    required this.enableShortSelling,
    required this.allowEquityIntradayShortSell,
    required this.blockOvernightEquityShortSell,
    required this.onToggleShortSelling,
    required this.onToggleEquityMis,
    required this.onToggleEquityNrml,
    required this.onSave,
  });

  static const _kDivider = Color(0xFFEEEEEE);
  static const _kLabel   = TextStyle(
    fontSize: 11, fontWeight: FontWeight.w700,
    color: Color(0xFF666666), letterSpacing: 0.5,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E4)),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(LucideIcons.sliders, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Global Leverage Defaults',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Fallback when no category rule matches. Separate Buy / Short Sell leverage for Intraday and Overnight. '
                      'Also controls platform-wide short selling policy.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (loading) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 8),
          ] else ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: _kDivider),
            const SizedBox(height: 16),

            // ── Intraday BUY (MIS) ───────────────────────────────────────
            const Text('INTRADAY BUY (MIS)', style: _kLabel),
            const SizedBox(height: 8),
            TextField(
              controller: intradayCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Intraday Buy Leverage (x)',
                hintText: '5',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 16),

            // ── Short Selling Leverage ────────────────────────────────────
            const Text('SHORT SELLING LEVERAGE', style: _kLabel),
            const SizedBox(height: 4),
            const Text(
              'Applied when opening a new SHORT position. Exit sells do not require margin.',
              style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: shortSellCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Short Sell Intraday (MIS)',
                      hintText: '5',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: nrmlSellCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Short Sell Overnight (NRML)',
                      hintText: '1 = full margin',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Overnight BUY (NRML) ─────────────────────────────────────
            const Text('OVERNIGHT BUY (NRML)', style: _kLabel),
            const SizedBox(height: 8),
            TextField(
              controller: nrmlBuyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Overnight Buy Leverage (x)',
                hintText: '1 = full margin',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: _kDivider),
            const SizedBox(height: 8),

            // ── Short selling policy ─────────────────────────────────────
            const Text('SHORT SELLING POLICY', style: _kLabel),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable Short Selling (platform-wide)', style: TextStyle(fontSize: 13)),
              value: enableShortSelling,
              onChanged: onToggleShortSelling,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow Equity Intraday Short Sell (MIS)', style: TextStyle(fontSize: 13)),
              value: allowEquityIntradayShortSell,
              onChanged: onToggleEquityMis,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Block Overnight Equity Short Selling (NRML)', style: TextStyle(fontSize: 13)),
              subtitle: const Text(
                'Prevents users from holding equity short positions overnight. F&O short selling is unaffected.',
                style: TextStyle(fontSize: 11),
              ),
              value: blockOvernightEquityShortSell,
              onChanged: onToggleEquityNrml,
            ),
            const SizedBox(height: 12),

            // ── Save ─────────────────────────────────────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: saving ? null : onSave,
                icon: saving
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(LucideIcons.save, size: 14),
                label: const Text('Save Global Settings'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Charges card ─────────────────────────────────────────────────────────────

class _ChargesCard extends StatelessWidget {
  final List<_Category> categories;
  final Map<String, _MarginData> draft;
  final void Function(String catKey, double fixed, double pct) onChanged;

  const _ChargesCard({
    required this.categories,
    required this.draft,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(LucideIcons.receipt, size: 18, color: AppColors.warning),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Brokerage & Charges',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(
                    'Fixed ₹ per trade + % of turnover per leg. '
                    'Both are charged on entry and exit. Set 0 to disable.',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          // Header row
          Row(children: [
            const Expanded(flex: 3, child: Text('Category',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary))),
            const Expanded(flex: 2, child: Text('Fixed (₹/trade)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary))),
            const Expanded(flex: 2, child: Text('% of Turnover',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary))),
          ]),
          const Divider(height: 16),
          ...categories.map((cat) {
            final data = draft[cat.key];
            if (data == null) return const SizedBox.shrink();
            return _ChargeRow(
              label: cat.displayName,
              fixedCharge: data.fixedCharge,
              percentCharge: data.percentCharge,
              onChanged: (f, p) => onChanged(cat.key, f, p),
            );
          }),
        ],
      ),
    );
  }
}

class _ChargeRow extends StatefulWidget {
  final String label;
  final double fixedCharge;
  final double percentCharge;
  final void Function(double fixed, double pct) onChanged;

  const _ChargeRow({
    required this.label,
    required this.fixedCharge,
    required this.percentCharge,
    required this.onChanged,
  });

  @override
  State<_ChargeRow> createState() => _ChargeRowState();
}

class _ChargeRowState extends State<_ChargeRow> {
  late TextEditingController _fixedCtrl;
  late TextEditingController _pctCtrl;

  @override
  void initState() {
    super.initState();
    _fixedCtrl = TextEditingController(
        text: widget.fixedCharge > 0 ? widget.fixedCharge.toStringAsFixed(2) : '');
    _pctCtrl   = TextEditingController(
        text: widget.percentCharge > 0 ? widget.percentCharge.toStringAsFixed(4) : '');
  }

  @override
  void dispose() {
    _fixedCtrl.dispose();
    _pctCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final fixed = double.tryParse(_fixedCtrl.text.trim()) ?? 0.0;
    final pct   = double.tryParse(_pctCtrl.text.trim())   ?? 0.0;
    widget.onChanged(fixed, pct);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(flex: 3,
            child: Text(widget.label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
        Expanded(flex: 2, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TextField(
            controller: _fixedCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              hintText: '0',
              prefixText: '₹',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            onChanged: (_) => _emit(),
          ),
        )),
        Expanded(flex: 2, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TextField(
            controller: _pctCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              hintText: '0.03',
              suffixText: '%',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            onChanged: (_) => _emit(),
          ),
        )),
      ]),
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
