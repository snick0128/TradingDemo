import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order, Transaction;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme.dart';
import '../../widgets/app_dialog.dart';
import 'admin_ui.dart';

// ─── Trading categories ───────────────────────────────────────────────────────

class _Category {
  final String key;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  // Intraday (MIS) defaults
  final double defaultMisBuyLeverage;
  final double defaultMisBuyMargin;
  final double defaultMisSellLeverage;
  final double defaultMisSellMargin;
  // Overnight (NRML) defaults
  final double defaultNrmlBuyLeverage;
  final double defaultNrmlBuyMargin;
  final double defaultNrmlSellLeverage;
  final double defaultNrmlSellMargin;
  // Trade charge defaults
  final double defaultMisBuyTradeCharge;
  final double defaultMisSellTradeCharge;
  final double defaultNrmlBuyTradeCharge;
  final double defaultNrmlSellTradeCharge;
  final List<String> symbols;

  const _Category({
    required this.key,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.defaultMisBuyLeverage,
    required this.defaultMisBuyMargin,
    required this.defaultMisSellLeverage,
    required this.defaultMisSellMargin,
    required this.defaultNrmlBuyLeverage,
    required this.defaultNrmlBuyMargin,
    required this.defaultNrmlSellLeverage,
    required this.defaultNrmlSellMargin,
    this.defaultMisBuyTradeCharge = 0,
    this.defaultMisSellTradeCharge = 0,
    this.defaultNrmlBuyTradeCharge = 0,
    this.defaultNrmlSellTradeCharge = 0,
    required this.symbols,
  });
}

const _kCategories = [
  _Category(
    key: 'nifty50',
    name: 'Nifty 50',
    description: 'NSE large-cap index — top 50 companies',
    icon: LucideIcons.trendingUp,
    color: Color(0xFF1565C0),
    defaultMisBuyLeverage: 5,
    defaultMisBuyMargin: 20,
    defaultMisSellLeverage: 5,
    defaultMisSellMargin: 20,
    defaultNrmlBuyLeverage: 1,
    defaultNrmlBuyMargin: 100,
    defaultNrmlSellLeverage: 1,
    defaultNrmlSellMargin: 100,
    symbols: ['RELIANCE', 'TCS', 'INFY', 'HDFCBANK', 'SBIN'],
  ),
  _Category(
    key: 'banknifty',
    name: 'Bank Nifty',
    description: 'NSE banking sector index',
    icon: LucideIcons.landmark,
    color: Color(0xFF0277BD),
    defaultMisBuyLeverage: 5,
    defaultMisBuyMargin: 20,
    defaultMisSellLeverage: 5,
    defaultMisSellMargin: 20,
    defaultNrmlBuyLeverage: 1,
    defaultNrmlBuyMargin: 100,
    defaultNrmlSellLeverage: 1,
    defaultNrmlSellMargin: 100,
    symbols: ['HDFCBANK', 'ICICIBANK', 'SBIN', 'AXISBANK'],
  ),
  _Category(
    key: 'nifty_midcap',
    name: 'Nifty Midcap',
    description: 'NSE mid-cap stocks (150 index)',
    icon: LucideIcons.barChart2,
    color: Color(0xFF00695C),
    defaultMisBuyLeverage: 4,
    defaultMisBuyMargin: 25,
    defaultMisSellLeverage: 4,
    defaultMisSellMargin: 25,
    defaultNrmlBuyLeverage: 1,
    defaultNrmlBuyMargin: 100,
    defaultNrmlSellLeverage: 1,
    defaultNrmlSellMargin: 100,
    symbols: ['BAJFINANCE', 'WIPRO', 'HINDUNILVR'],
  ),
  _Category(
    key: 'nse_equity',
    name: 'NSE Equity (General)',
    description: 'All other NSE listed equities',
    icon: LucideIcons.activity,
    color: Color(0xFF1565C0),
    defaultMisBuyLeverage: 3,
    defaultMisBuyMargin: 33,
    defaultMisSellLeverage: 3,
    defaultMisSellMargin: 33,
    defaultNrmlBuyLeverage: 1,
    defaultNrmlBuyMargin: 100,
    defaultNrmlSellLeverage: 1,
    defaultNrmlSellMargin: 100,
    symbols: ['All NSE stocks not in above categories'],
  ),
  _Category(
    key: 'mcx_gold',
    name: 'MCX Gold',
    description: 'Gold futures — 1 kg lot',
    icon: LucideIcons.gem,
    color: Color(0xFFF9A825),
    defaultMisBuyLeverage: 10,
    defaultMisBuyMargin: 10,
    defaultMisSellLeverage: 10,
    defaultMisSellMargin: 10,
    defaultNrmlBuyLeverage: 2,
    defaultNrmlBuyMargin: 50,
    defaultNrmlSellLeverage: 2,
    defaultNrmlSellMargin: 50,
    symbols: ['GOLD', 'GOLDM', 'GOLDPETAL'],
  ),
  _Category(
    key: 'mcx_silver',
    name: 'MCX Silver',
    description: 'Silver futures — 30 kg lot',
    icon: LucideIcons.gem,
    color: Color(0xFF78909C),
    defaultMisBuyLeverage: 10,
    defaultMisBuyMargin: 10,
    defaultMisSellLeverage: 10,
    defaultMisSellMargin: 10,
    defaultNrmlBuyLeverage: 2,
    defaultNrmlBuyMargin: 50,
    defaultNrmlSellLeverage: 2,
    defaultNrmlSellMargin: 50,
    symbols: ['SILVER', 'SILVERM'],
  ),
  _Category(
    key: 'mcx_energy',
    name: 'MCX Energy',
    description: 'Crude Oil & Natural Gas futures',
    icon: LucideIcons.flame,
    color: Color(0xFFE65100),
    defaultMisBuyLeverage: 10,
    defaultMisBuyMargin: 10,
    defaultMisSellLeverage: 10,
    defaultMisSellMargin: 10,
    defaultNrmlBuyLeverage: 2,
    defaultNrmlBuyMargin: 50,
    defaultNrmlSellLeverage: 2,
    defaultNrmlSellMargin: 50,
    symbols: ['CRUDEOIL', 'NATURALGAS'],
  ),
  _Category(
    key: 'mcx_base_metals',
    name: 'MCX Base Metals',
    description: 'Copper, Zinc, Lead, Aluminium, Nickel',
    icon: LucideIcons.layers,
    color: Color(0xFF7B1FA2),
    defaultMisBuyLeverage: 10,
    defaultMisBuyMargin: 10,
    defaultMisSellLeverage: 10,
    defaultMisSellMargin: 10,
    defaultNrmlBuyLeverage: 2,
    defaultNrmlBuyMargin: 50,
    defaultNrmlSellLeverage: 2,
    defaultNrmlSellMargin: 50,
    symbols: ['COPPER', 'ZINC', 'LEAD', 'ALUMINIUM', 'NICKEL'],
  ),
  _Category(
    key: 'mcx_agri',
    name: 'MCX Agri',
    description: 'Agricultural commodities — Cotton etc.',
    icon: LucideIcons.leaf,
    color: Color(0xFF2E7D32),
    defaultMisBuyLeverage: 5,
    defaultMisBuyMargin: 20,
    defaultMisSellLeverage: 5,
    defaultMisSellMargin: 20,
    defaultNrmlBuyLeverage: 1,
    defaultNrmlBuyMargin: 100,
    defaultNrmlSellLeverage: 1,
    defaultNrmlSellMargin: 100,
    symbols: ['COTTON', 'KAPAS'],
  ),
];

// ─── Data model ───────────────────────────────────────────────────────────────

class _LevData {
  double misBuyLeverage;
  double misBuyMargin;
  double misSellLeverage;
  double misSellMargin;
  double nrmlBuyLeverage;
  double nrmlBuyMargin;
  double nrmlSellLeverage;
  double nrmlSellMargin;
  // Trade Charges
  double misBuyTradeCharge;
  double misSellTradeCharge;
  double nrmlBuyTradeCharge;
  double nrmlSellTradeCharge;
  // Legacy Trade Charges
  double misBuyFixedCharge;
  double misBuyPercentCharge;
  double misBuyOtherCharge;
  double misSellFixedCharge;
  double misSellPercentCharge;
  double misSellOtherCharge;
  double nrmlBuyFixedCharge;
  double nrmlBuyPercentCharge;
  double nrmlBuyOtherCharge;
  double nrmlSellFixedCharge;
  double nrmlSellPercentCharge;
  double nrmlSellOtherCharge;

  _LevData({
    required this.misBuyLeverage,
    required this.misBuyMargin,
    required this.misSellLeverage,
    required this.misSellMargin,
    required this.nrmlBuyLeverage,
    required this.nrmlBuyMargin,
    required this.nrmlSellLeverage,
    required this.nrmlSellMargin,
    this.misBuyTradeCharge = 0,
    this.misSellTradeCharge = 0,
    this.nrmlBuyTradeCharge = 0,
    this.nrmlSellTradeCharge = 0,
    this.misBuyFixedCharge = 0,
    this.misBuyPercentCharge = 0,
    this.misBuyOtherCharge = 0,
    this.misSellFixedCharge = 0,
    this.misSellPercentCharge = 0,
    this.misSellOtherCharge = 0,
    this.nrmlBuyFixedCharge = 0,
    this.nrmlBuyPercentCharge = 0,
    this.nrmlBuyOtherCharge = 0,
    this.nrmlSellFixedCharge = 0,
    this.nrmlSellPercentCharge = 0,
    this.nrmlSellOtherCharge = 0,
  });

  _LevData copy() => _LevData(
    misBuyLeverage: misBuyLeverage,
    misBuyMargin: misBuyMargin,
    misSellLeverage: misSellLeverage,
    misSellMargin: misSellMargin,
    nrmlBuyLeverage: nrmlBuyLeverage,
    nrmlBuyMargin: nrmlBuyMargin,
    nrmlSellLeverage: nrmlSellLeverage,
    nrmlSellMargin: nrmlSellMargin,
    misBuyTradeCharge: misBuyTradeCharge,
    misSellTradeCharge: misSellTradeCharge,
    nrmlBuyTradeCharge: nrmlBuyTradeCharge,
    nrmlSellTradeCharge: nrmlSellTradeCharge,
    misBuyFixedCharge: misBuyFixedCharge,
    misBuyPercentCharge: misBuyPercentCharge,
    misBuyOtherCharge: misBuyOtherCharge,
    misSellFixedCharge: misSellFixedCharge,
    misSellPercentCharge: misSellPercentCharge,
    misSellOtherCharge: misSellOtherCharge,
    nrmlBuyFixedCharge: nrmlBuyFixedCharge,
    nrmlBuyPercentCharge: nrmlBuyPercentCharge,
    nrmlBuyOtherCharge: nrmlBuyOtherCharge,
    nrmlSellFixedCharge: nrmlSellFixedCharge,
    nrmlSellPercentCharge: nrmlSellPercentCharge,
    nrmlSellOtherCharge: nrmlSellOtherCharge,
  );

  bool equals(_LevData other) =>
      misBuyLeverage == other.misBuyLeverage &&
      misBuyMargin == other.misBuyMargin &&
      misSellLeverage == other.misSellLeverage &&
      misSellMargin == other.misSellMargin &&
      nrmlBuyLeverage == other.nrmlBuyLeverage &&
      nrmlBuyMargin == other.nrmlBuyMargin &&
      nrmlSellLeverage == other.nrmlSellLeverage &&
      nrmlSellMargin == other.nrmlSellMargin &&
      misBuyTradeCharge == other.misBuyTradeCharge &&
      misSellTradeCharge == other.misSellTradeCharge &&
      nrmlBuyTradeCharge == other.nrmlBuyTradeCharge &&
      nrmlSellTradeCharge == other.nrmlSellTradeCharge &&
      misBuyFixedCharge == other.misBuyFixedCharge &&
      misBuyPercentCharge == other.misBuyPercentCharge &&
      misBuyOtherCharge == other.misBuyOtherCharge &&
      misSellFixedCharge == other.misSellFixedCharge &&
      misSellPercentCharge == other.misSellPercentCharge &&
      misSellOtherCharge == other.misSellOtherCharge &&
      nrmlBuyFixedCharge == other.nrmlBuyFixedCharge &&
      nrmlBuyPercentCharge == other.nrmlBuyPercentCharge &&
      nrmlBuyOtherCharge == other.nrmlBuyOtherCharge &&
      nrmlSellFixedCharge == other.nrmlSellFixedCharge &&
      nrmlSellPercentCharge == other.nrmlSellPercentCharge &&
      nrmlSellOtherCharge == other.nrmlSellOtherCharge;

  Map<String, dynamic> toFirestore(String key, String name) => {
    'categoryKey': key,
    'categoryName': name,
    'mis_buy_leverage': misBuyLeverage,
    'mis_buy_margin': misBuyMargin,
    'mis_sell_leverage': misSellLeverage,
    'mis_sell_margin': misSellMargin,
    'nrml_buy_leverage': nrmlBuyLeverage,
    'nrml_buy_margin': nrmlBuyMargin,
    'nrml_sell_leverage': nrmlSellLeverage,
    'nrml_sell_margin': nrmlSellMargin,
    'mis_buy_trade_charge': misBuyTradeCharge,
    'mis_sell_trade_charge': misSellTradeCharge,
    'nrml_buy_trade_charge': nrmlBuyTradeCharge,
    'nrml_sell_trade_charge': nrmlSellTradeCharge,
    'mis_buy_fixed_charge': misBuyFixedCharge,
    'mis_buy_percent_charge': misBuyPercentCharge,
    'mis_buy_other_charge': misBuyOtherCharge,
    'mis_sell_fixed_charge': misSellFixedCharge,
    'mis_sell_percent_charge': misSellPercentCharge,
    'mis_sell_other_charge': misSellOtherCharge,
    'nrml_buy_fixed_charge': nrmlBuyFixedCharge,
    'nrml_buy_percent_charge': nrmlBuyPercentCharge,
    'nrml_buy_other_charge': nrmlBuyOtherCharge,
    'nrml_sell_fixed_charge': nrmlSellFixedCharge,
    'nrml_sell_percent_charge': nrmlSellPercentCharge,
    'nrml_sell_other_charge': nrmlSellOtherCharge,
    // Legacy fields kept for backward compat
    'mis_leverage': misBuyLeverage,
    'mis_margin': misBuyMargin,
    'nrml_leverage': nrmlBuyLeverage,
    'nrml_margin': nrmlBuyMargin,
    'leverage': misBuyLeverage,
    'margin': misBuyMargin,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class LeverageControlScreen extends StatefulWidget {
  const LeverageControlScreen({super.key});

  @override
  State<LeverageControlScreen> createState() => _LeverageControlScreenState();
}

class _LeverageControlScreenState extends State<LeverageControlScreen> {
  final Map<String, _LevData> _draft = {};
  final Map<String, _LevData> _saved = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadFromFirestore();
  }

  Future<void> _loadFromFirestore() async {
    setState(() => _loading = true);
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db.collection('category_leverage').get();

      final loaded = <String, _LevData>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final cat = _kCategories.where((c) => c.key == doc.id).firstOrNull;

        // Read new split buy/sell fields, fall back to legacy single-value fields
        final legacyMisLev =
            (d['mis_leverage'] as num?)?.toDouble() ??
            (d['leverage'] as num?)?.toDouble();
        final legacyMisMar =
            (d['mis_margin'] as num?)?.toDouble() ??
            (d['margin'] as num?)?.toDouble();
        final legacyNrmlLev = (d['nrml_leverage'] as num?)?.toDouble();
        final legacyNrmlMar = (d['nrml_margin'] as num?)?.toDouble();

        final misBuyLev =
            (d['mis_buy_leverage'] as num?)?.toDouble() ??
            legacyMisLev ??
            cat?.defaultMisBuyLeverage;
        final misBuyMar =
            (d['mis_buy_margin'] as num?)?.toDouble() ??
            legacyMisMar ??
            cat?.defaultMisBuyMargin;
        final misSellLev =
            (d['mis_sell_leverage'] as num?)?.toDouble() ??
            legacyMisLev ??
            cat?.defaultMisSellLeverage;
        final misSellMar =
            (d['mis_sell_margin'] as num?)?.toDouble() ??
            legacyMisMar ??
            cat?.defaultMisSellMargin;
        final nrmlBuyLev =
            (d['nrml_buy_leverage'] as num?)?.toDouble() ??
            legacyNrmlLev ??
            cat?.defaultNrmlBuyLeverage;
        final nrmlBuyMar =
            (d['nrml_buy_margin'] as num?)?.toDouble() ??
            legacyNrmlMar ??
            cat?.defaultNrmlBuyMargin;
        final nrmlSellLev =
            (d['nrml_sell_leverage'] as num?)?.toDouble() ??
            legacyNrmlLev ??
            cat?.defaultNrmlSellLeverage;
        final nrmlSellMar =
            (d['nrml_sell_margin'] as num?)?.toDouble() ??
            legacyNrmlMar ??
            cat?.defaultNrmlSellMargin;

        if (misBuyLev != null && misBuyMar != null) {
          loaded[doc.id] = _LevData(
            misBuyLeverage: misBuyLev,
            misBuyMargin: misBuyMar,
            misSellLeverage: misSellLev ?? misBuyLev,
            misSellMargin: misSellMar ?? misBuyMar,
            nrmlBuyLeverage: nrmlBuyLev ?? (cat?.defaultNrmlBuyLeverage ?? 1),
            nrmlBuyMargin: nrmlBuyMar ?? (cat?.defaultNrmlBuyMargin ?? 100),
            nrmlSellLeverage:
                nrmlSellLev ?? (cat?.defaultNrmlSellLeverage ?? 1),
            nrmlSellMargin: nrmlSellMar ?? (cat?.defaultNrmlSellMargin ?? 100),
            misBuyTradeCharge:
                (d['mis_buy_trade_charge'] as num?)?.toDouble() ??
                (cat?.defaultMisBuyTradeCharge ?? 0),
            misSellTradeCharge:
                (d['mis_sell_trade_charge'] as num?)?.toDouble() ??
                (cat?.defaultMisSellTradeCharge ?? 0),
            nrmlBuyTradeCharge:
                (d['nrml_buy_trade_charge'] as num?)?.toDouble() ??
                (cat?.defaultNrmlBuyTradeCharge ?? 0),
            nrmlSellTradeCharge:
                (d['nrml_sell_trade_charge'] as num?)?.toDouble() ??
                (cat?.defaultNrmlSellTradeCharge ?? 0),
          );
        }
      }

      // Seed defaults for categories not yet in Firestore
      for (final cat in _kCategories) {
        loaded.putIfAbsent(
          cat.key,
          () => _LevData(
            misBuyLeverage: cat.defaultMisBuyLeverage,
            misBuyMargin: cat.defaultMisBuyMargin,
            misSellLeverage: cat.defaultMisSellLeverage,
            misSellMargin: cat.defaultMisSellMargin,
            nrmlBuyLeverage: cat.defaultNrmlBuyLeverage,
            nrmlBuyMargin: cat.defaultNrmlBuyMargin,
            nrmlSellLeverage: cat.defaultNrmlSellLeverage,
            nrmlSellMargin: cat.defaultNrmlSellMargin,
            misBuyTradeCharge: cat.defaultMisBuyTradeCharge,
            misSellTradeCharge: cat.defaultMisSellTradeCharge,
            nrmlBuyTradeCharge: cat.defaultNrmlBuyTradeCharge,
            nrmlSellTradeCharge: cat.defaultNrmlSellTradeCharge,
          ),
        );
      }

      setState(() {
        _saved.addAll(loaded);
        for (final e in loaded.entries) {
          _draft[e.key] = e.value.copy();
        }
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
      if (d == null || s == null) continue;
      if (!d.equals(s)) return true;
    }
    return false;
  }

  Future<void> _saveAll() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      for (final cat in _kCategories) {
        final d = _draft[cat.key];
        if (d == null) continue;
        batch.set(
          db.collection('category_leverage').doc(cat.key),
          d.toFirestore(cat.key, cat.name),
        );
      }
      await batch.commit();
      for (final e in _draft.entries) {
        _saved[e.key] = e.value.copy();
      }
      if (mounted) AppToast.success(context, 'All leverage settings saved.');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSingle(String key) async {
    if (_saving) return;
    final d = _draft[key];
    if (d == null) return;
    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      final cat = _kCategories.firstWhere((c) => c.key == key);
      await db
          .collection('category_leverage')
          .doc(key)
          .set(d.toFirestore(key, cat.name));
      _saved[key] = d.copy();
      if (mounted) AppToast.success(context, '${cat.name} saved.');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _discard() {
    setState(() {
      for (final e in _saved.entries) {
        _draft[e.key] = e.value.copy();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Leverage & Margin',
            subtitle:
                'Configure Buy and Sell leverage separately for Intraday (MIS) '
                'and Overnight (NRML) per category. Changes apply to all new orders immediately.',
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
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.save, size: 14),
                  label: Text(_isDirty ? 'Save Changes' : 'Save All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Info banner
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.info,
                  size: 14,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Each category supports separate leverage for Buy and Sell orders, '
                    'across Intraday (MIS) and Overnight (NRML). '
                    'Margin % = 100 ÷ Leverage.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.primary.withOpacity(0.85),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView.separated(
                itemCount: _kCategories.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final cat = _kCategories[i];
                  final data =
                      _draft[cat.key] ??
                      _LevData(
                        misBuyLeverage: cat.defaultMisBuyLeverage,
                        misBuyMargin: cat.defaultMisBuyMargin,
                        misSellLeverage: cat.defaultMisSellLeverage,
                        misSellMargin: cat.defaultMisSellMargin,
                        nrmlBuyLeverage: cat.defaultNrmlBuyLeverage,
                        nrmlBuyMargin: cat.defaultNrmlBuyMargin,
                        nrmlSellLeverage: cat.defaultNrmlSellLeverage,
                        nrmlSellMargin: cat.defaultNrmlSellMargin,
                        misBuyTradeCharge: cat.defaultMisBuyTradeCharge,
                        misSellTradeCharge: cat.defaultMisSellTradeCharge,
                        nrmlBuyTradeCharge: cat.defaultNrmlBuyTradeCharge,
                        nrmlSellTradeCharge: cat.defaultNrmlSellTradeCharge,
                      );
                  final savedData = _saved[cat.key];
                  final isDirty = savedData != null && !data.equals(savedData);

                  return _CategoryCard(
                    category: cat,
                    data: data,
                    isDirty: isDirty,
                    saving: _saving,
                    onChanged: (updated) {
                      setState(() => _draft[cat.key] = updated);
                    },
                    onSave: () => _saveSingle(cat.key),
                  );
                },
              ),
            ),

          // Sticky bottom bar
          if (!_loading)
            Container(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Text(
                    _isDirty ? 'You have unsaved changes' : 'All changes saved',
                    style: TextStyle(
                      fontSize: 12,
                      color: _isDirty
                          ? AppColors.warning
                          : AppColors.textSecondary,
                      fontWeight: _isDirty
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  const Spacer(),
                  if (_isDirty) ...[
                    OutlinedButton(
                      onPressed: _discard,
                      child: const Text('Discard'),
                    ),
                    const SizedBox(width: 10),
                  ],
                  ElevatedButton.icon(
                    onPressed: (_saving || _loading) ? null : _saveAll,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.save, size: 14),
                    label: Text(_isDirty ? 'Save All Changes' : 'Save All'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Category card ────────────────────────────────────────────────────────────

class _CategoryCard extends StatefulWidget {
  final _Category category;
  final _LevData data;
  final bool isDirty;
  final bool saving;
  final void Function(_LevData) onChanged;
  final VoidCallback onSave;

  const _CategoryCard({
    required this.category,
    required this.data,
    required this.isDirty,
    required this.saving,
    required this.onChanged,
    required this.onSave,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  // MIS Buy controllers
  late TextEditingController _misBuyLevCtrl;
  late TextEditingController _misBuyMarCtrl;
  // MIS Sell controllers
  late TextEditingController _misSellLevCtrl;
  late TextEditingController _misSellMarCtrl;
  late TextEditingController _nrmlSellLevCtrl;
  late TextEditingController _nrmlSellMarCtrl;

  // Trade Charge controllers
  late TextEditingController _misBuyFixedCtrl;
  late TextEditingController _misBuyPercentCtrl;
  late TextEditingController _misBuyOtherCtrl;
  late TextEditingController _misSellFixedCtrl;
  late TextEditingController _misSellPercentCtrl;
  late TextEditingController _misSellOtherCtrl;
  late TextEditingController _nrmlBuyLevCtrl;
  late TextEditingController _nrmlBuyMarCtrl;
  late TextEditingController _nrmlBuyFixedCtrl;
  late TextEditingController _nrmlBuyPercentCtrl;
  late TextEditingController _nrmlBuyOtherCtrl;
  late TextEditingController _nrmlSellFixedCtrl;
  late TextEditingController _nrmlSellPercentCtrl;
  late TextEditingController _nrmlSellOtherCtrl;

  late TextEditingController _misBuyTradeCtrl;
  late TextEditingController _misSellTradeCtrl;
  late TextEditingController _nrmlBuyTradeCtrl;
  late TextEditingController _nrmlSellTradeCtrl;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _misBuyLevCtrl = TextEditingController(
      text: d.misBuyLeverage.toStringAsFixed(0),
    );
    _misBuyMarCtrl = TextEditingController(
      text: d.misBuyMargin.toStringAsFixed(2),
    );
    _nrmlSellMarCtrl = TextEditingController(
      text: d.nrmlSellMargin.toStringAsFixed(2),
    );
    _nrmlBuyLevCtrl = TextEditingController(
      text: d.nrmlBuyLeverage.toStringAsFixed(0),
    );
    _nrmlBuyMarCtrl = TextEditingController(
      text: d.nrmlBuyMargin.toStringAsFixed(2),
    );
    _misSellLevCtrl = TextEditingController(
      text: d.misSellLeverage.toStringAsFixed(0),
    );
    _misSellMarCtrl = TextEditingController(
      text: d.misSellMargin.toStringAsFixed(2),
    );

    _misBuyTradeCtrl = TextEditingController(text: d.misBuyTradeCharge.toString());
    _misSellTradeCtrl = TextEditingController(text: d.misSellTradeCharge.toString());
    _nrmlBuyTradeCtrl = TextEditingController(text: d.nrmlBuyTradeCharge.toString());
    _nrmlSellTradeCtrl = TextEditingController(text: d.nrmlSellTradeCharge.toString());

    _misBuyFixedCtrl = TextEditingController(text: d.misBuyFixedCharge.toString());
    _misBuyPercentCtrl = TextEditingController(text: d.misBuyPercentCharge.toString());
    _misBuyOtherCtrl = TextEditingController(text: d.misBuyOtherCharge.toString());
    _misSellFixedCtrl = TextEditingController(text: d.misSellFixedCharge.toString());
    _misSellPercentCtrl = TextEditingController(text: d.misSellPercentCharge.toString());
    _misSellOtherCtrl = TextEditingController(text: d.misSellOtherCharge.toString());
    _nrmlBuyFixedCtrl = TextEditingController(text: d.nrmlBuyFixedCharge.toString());
    _nrmlBuyPercentCtrl = TextEditingController(text: d.nrmlBuyPercentCharge.toString());
    _nrmlBuyOtherCtrl = TextEditingController(text: d.nrmlBuyOtherCharge.toString());
    _nrmlSellFixedCtrl = TextEditingController(text: d.nrmlSellFixedCharge.toString());
    _nrmlSellPercentCtrl = TextEditingController(text: d.nrmlSellPercentCharge.toString());
    _nrmlSellOtherCtrl = TextEditingController(text: d.nrmlSellOtherCharge.toString());
  }

  @override
  void dispose() {
    _misBuyLevCtrl.dispose();
    _misBuyMarCtrl.dispose();
    _misSellLevCtrl.dispose();
    _misSellMarCtrl.dispose();
    _nrmlBuyLevCtrl.dispose();
    _nrmlBuyMarCtrl.dispose();
    _nrmlSellLevCtrl.dispose();
    _nrmlSellMarCtrl.dispose();
    _misBuyTradeCtrl.dispose();
    _misSellTradeCtrl.dispose();
    _nrmlBuyTradeCtrl.dispose();
    _nrmlSellTradeCtrl.dispose();
    _misBuyFixedCtrl.dispose();
    _misBuyPercentCtrl.dispose();
    _misBuyOtherCtrl.dispose();
    _misSellFixedCtrl.dispose();
    _misSellPercentCtrl.dispose();
    _misSellOtherCtrl.dispose();
    _nrmlBuyFixedCtrl.dispose();
    _nrmlBuyPercentCtrl.dispose();
    _nrmlBuyOtherCtrl.dispose();
    _nrmlSellFixedCtrl.dispose();
    _nrmlSellPercentCtrl.dispose();
    _nrmlSellOtherCtrl.dispose();
    super.dispose();
  }

  void _update(void Function(_LevData d) mutate) {
    final copy = widget.data.copy();
    mutate(copy);
    widget.onChanged(copy);
  }

  void _onLevChanged(
    String v,
    TextEditingController marCtrl,
    void Function(_LevData, double, double) apply,
  ) {
    final lev = double.tryParse(v);
    if (lev != null && lev > 0) {
      final mar = double.parse((100 / lev).toStringAsFixed(2));
      marCtrl.text = mar.toStringAsFixed(2);
      _update((d) => apply(d, lev, mar));
    }
  }

  void _onMarChanged(
    String v,
    TextEditingController levCtrl,
    void Function(_LevData, double, double) apply,
  ) {
    final mar = double.tryParse(v);
    if (mar != null && mar > 0) {
      final lev = double.parse((100 / mar).toStringAsFixed(0));
      levCtrl.text = lev.toStringAsFixed(0);
      _update((d) => apply(d, lev, mar));
    }
  }

  void _onChargeChanged(String v, void Function(_LevData, double) apply) {
    final val = double.tryParse(v) ?? 0;
    _update((d) => apply(d, val));
  }

  void _resetToDefault() {
    final cat = widget.category;
    _misBuyLevCtrl.text = cat.defaultMisBuyLeverage.toStringAsFixed(0);
    _misBuyMarCtrl.text = cat.defaultMisBuyMargin.toStringAsFixed(2);
    _misSellLevCtrl.text = cat.defaultMisSellLeverage.toStringAsFixed(0);
    _misSellMarCtrl.text = cat.defaultMisSellMargin.toStringAsFixed(2);
    _nrmlBuyLevCtrl.text = cat.defaultNrmlBuyLeverage.toStringAsFixed(0);
    _nrmlBuyMarCtrl.text = cat.defaultNrmlBuyMargin.toStringAsFixed(2);
    _nrmlSellLevCtrl.text = cat.defaultNrmlSellLeverage.toStringAsFixed(0);
    _nrmlSellMarCtrl.text = cat.defaultNrmlSellMargin.toStringAsFixed(2);
    _misBuyTradeCtrl.text = cat.defaultMisBuyTradeCharge.toString();
    _misSellTradeCtrl.text = cat.defaultMisSellTradeCharge.toString();
    _nrmlBuyTradeCtrl.text = cat.defaultNrmlBuyTradeCharge.toString();
    _nrmlSellTradeCtrl.text = cat.defaultNrmlSellTradeCharge.toString();
    widget.onChanged(
      _LevData(
        misBuyLeverage: cat.defaultMisBuyLeverage,
        misBuyMargin: cat.defaultMisBuyMargin,
        misSellLeverage: cat.defaultMisSellLeverage,
        misSellMargin: cat.defaultMisSellMargin,
        nrmlBuyLeverage: cat.defaultNrmlBuyLeverage,
        nrmlBuyMargin: cat.defaultNrmlBuyMargin,
        nrmlSellLeverage: cat.defaultNrmlSellLeverage,
        nrmlSellMargin: cat.defaultNrmlSellMargin,
        misBuyTradeCharge: cat.defaultMisBuyTradeCharge,
        misSellTradeCharge: cat.defaultMisSellTradeCharge,
        nrmlBuyTradeCharge: cat.defaultNrmlBuyTradeCharge,
        nrmlSellTradeCharge: cat.defaultNrmlSellTradeCharge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    final c = cat.color;
    final d = widget.data;

    return AdminPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(cat.icon, size: 18, color: c),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          cat.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (widget.isDirty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppColors.warning.withOpacity(0.4),
                              ),
                            ),
                            child: const Text(
                              'Unsaved',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      cat.description,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Reset to defaults',
                child: IconButton(
                  onPressed: _resetToDefault,
                  icon: const Icon(LucideIcons.rotateCcw, size: 15),
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: widget.saving ? null : widget.onSave,
                  icon: widget.saving && widget.isDirty
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.save, size: 13),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isDirty
                        ? AppColors.primary
                        : AppColors.primary.withOpacity(0.6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 0,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // ── Intraday (MIS) ───────────────────────────────────────────────
          _ProductSection(
            label: 'Intraday (MIS)',
            labelColor: const Color(0xFFF57F17),
            labelBg: const Color(0xFFFFF8E1),
            accentColor: c,
            buyLevCtrl: _misBuyLevCtrl,
            buyMarCtrl: _misBuyMarCtrl,
            sellLevCtrl: _misSellLevCtrl,
            sellMarCtrl: _misSellMarCtrl,
            currentBuyLev: d.misBuyLeverage,
            currentBuyMar: d.misBuyMargin,
            currentSellLev: d.misSellLeverage,
            currentSellMar: d.misSellMargin,
            onBuyLevChanged: (v) => _onLevChanged(
              v,
              _misBuyMarCtrl,
              (d, lev, mar) {
                d.misBuyLeverage = lev;
                d.misBuyMargin = mar;
              },
            ),
            onBuyMarChanged: (v) => _onMarChanged(
              v,
              _misBuyLevCtrl,
              (d, lev, mar) {
                d.misBuyLeverage = lev;
                d.misBuyMargin = mar;
              },
            ),
            onSellLevChanged: (v) => _onLevChanged(
              v,
              _misSellMarCtrl,
              (d, lev, mar) {
                d.misSellLeverage = lev;
                d.misSellMargin = mar;
              },
            ),
            onSellMarChanged: (v) => _onMarChanged(
              v,
              _misSellLevCtrl,
              (d, lev, mar) {
                d.misSellLeverage = lev;
                d.misSellMargin = mar;
              },
            ),
            buyFixedCtrl: _misBuyFixedCtrl,
            buyPercentCtrl: _misBuyPercentCtrl,
            buyOtherCtrl: _misBuyOtherCtrl,
            sellFixedCtrl: _misSellFixedCtrl,
            sellPercentCtrl: _misSellPercentCtrl,
            sellOtherCtrl: _misSellOtherCtrl,
            onBuyFixedChanged: (v) => _onChargeChanged(v, (d, val) => d.misBuyFixedCharge = val),
            onBuyPercentChanged: (v) => _onChargeChanged(v, (d, val) => d.misBuyPercentCharge = val),
            onBuyOtherChanged: (v) => _onChargeChanged(v, (d, val) => d.misBuyOtherCharge = val),
            onSellFixedChanged: (v) => _onChargeChanged(v, (d, val) => d.misSellFixedCharge = val),
            onSellPercentChanged: (v) => _onChargeChanged(v, (d, val) => d.misSellPercentCharge = val),
            onSellOtherChanged: (v) => _onChargeChanged(v, (d, val) => d.misSellOtherCharge = val),
            buyTradeCtrl: _misBuyTradeCtrl,
            sellTradeCtrl: _misSellTradeCtrl,
            onBuyTradeChanged: (v) => _onChargeChanged(v, (d, val) => d.misBuyTradeCharge = val),
            onSellTradeChanged: (v) => _onChargeChanged(v, (d, val) => d.misSellTradeCharge = val),
          ),

          const SizedBox(height: 12),

          // ── Overnight (NRML) ─────────────────────────────────────────────
          _ProductSection(
            label: 'Overnight (NRML)',
            labelColor: const Color(0xFF1565C0),
            labelBg: const Color(0xFFE3F2FD),
            accentColor: c,
            buyLevCtrl: _nrmlBuyLevCtrl,
            buyMarCtrl: _nrmlBuyMarCtrl,
            sellLevCtrl: _nrmlSellLevCtrl,
            sellMarCtrl: _nrmlSellMarCtrl,
            currentBuyLev: d.nrmlBuyLeverage,
            currentBuyMar: d.nrmlBuyMargin,
            currentSellLev: d.nrmlSellLeverage,
            currentSellMar: d.nrmlSellMargin,
            onBuyLevChanged: (v) => _onLevChanged(
              v,
              _nrmlBuyMarCtrl,
              (d, lev, mar) {
                d.nrmlBuyLeverage = lev;
                d.nrmlBuyMargin = mar;
              },
            ),
            onBuyMarChanged: (v) => _onMarChanged(
              v,
              _nrmlBuyLevCtrl,
              (d, lev, mar) {
                d.nrmlBuyLeverage = lev;
                d.nrmlBuyMargin = mar;
              },
            ),
            onSellLevChanged: (v) => _onLevChanged(
              v,
              _nrmlSellMarCtrl,
              (d, lev, mar) {
                d.nrmlSellLeverage = lev;
                d.nrmlSellMargin = mar;
              },
            ),
            onSellMarChanged: (v) => _onMarChanged(
              v,
              _nrmlSellLevCtrl,
              (d, lev, mar) {
                d.nrmlSellLeverage = lev;
                d.nrmlSellMargin = mar;
              },
            ),
            buyFixedCtrl: _nrmlBuyFixedCtrl,
            buyPercentCtrl: _nrmlBuyPercentCtrl,
            buyOtherCtrl: _nrmlBuyOtherCtrl,
            sellFixedCtrl: _nrmlSellFixedCtrl,
            sellPercentCtrl: _nrmlSellPercentCtrl,
            sellOtherCtrl: _nrmlSellOtherCtrl,
            onBuyFixedChanged: (v) => _onChargeChanged(v, (d, val) => d.nrmlBuyFixedCharge = val),
            onBuyPercentChanged: (v) => _onChargeChanged(v, (d, val) => d.nrmlBuyPercentCharge = val),
            onBuyOtherChanged: (v) => _onChargeChanged(v, (d, val) => d.nrmlBuyOtherCharge = val),
            onSellFixedChanged: (v) => _onChargeChanged(v, (d, val) => d.nrmlSellFixedCharge = val),
            onSellPercentChanged: (v) => _onChargeChanged(v, (d, val) => d.nrmlSellPercentCharge = val),
            onSellOtherChanged: (v) => _onChargeChanged(v, (d, val) => d.nrmlSellOtherCharge = val),
            buyTradeCtrl: _nrmlBuyTradeCtrl,
            sellTradeCtrl: _nrmlSellTradeCtrl,
            onBuyTradeChanged: (v) => _onChargeChanged(v, (d, val) => d.nrmlBuyTradeCharge = val),
            onSellTradeChanged: (v) => _onChargeChanged(v, (d, val) => d.nrmlSellTradeCharge = val),
          ),

          // ── Example symbols ──────────────────────────────────────────────
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: cat.symbols
                .take(4)
                .map(
                  (s) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: c.withOpacity(0.2)),
                    ),
                    child: Text(
                      s,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: c.withOpacity(0.8),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Product section (MIS or NRML) with Buy / Sell columns ───────────────────

class _ProductSection extends StatelessWidget {
  final String label;
  final Color labelColor;
  final Color labelBg;
  final Color accentColor;

  final TextEditingController buyLevCtrl;
  final TextEditingController buyMarCtrl;
  final TextEditingController buyTradeCtrl;
  final TextEditingController buyFixedCtrl;
  final TextEditingController buyPercentCtrl;
  final TextEditingController buyOtherCtrl;

  final TextEditingController sellLevCtrl;
  final TextEditingController sellMarCtrl;
  final TextEditingController sellTradeCtrl;
  final TextEditingController sellFixedCtrl;
  final TextEditingController sellPercentCtrl;
  final TextEditingController sellOtherCtrl;

  final ValueChanged<String> onBuyLevChanged;
  final ValueChanged<String> onBuyMarChanged;
  final ValueChanged<String> onBuyTradeChanged;
  final ValueChanged<String> onBuyFixedChanged;
  final ValueChanged<String> onBuyPercentChanged;
  final ValueChanged<String> onBuyOtherChanged;

  final ValueChanged<String> onSellLevChanged;
  final ValueChanged<String> onSellMarChanged;
  final ValueChanged<String> onSellTradeChanged;
  final ValueChanged<String> onSellFixedChanged;
  final ValueChanged<String> onSellPercentChanged;
  final ValueChanged<String> onSellOtherChanged;

  final double currentBuyLev;
  final double currentBuyMar;
  final double currentSellLev;
  final double currentSellMar;

  const _ProductSection({
    required this.label,
    required this.labelColor,
    required this.labelBg,
    required this.accentColor,
    required this.buyLevCtrl,
    required this.buyMarCtrl,
    required this.buyTradeCtrl,
    required this.buyFixedCtrl,
    required this.buyPercentCtrl,
    required this.buyOtherCtrl,
    required this.sellLevCtrl,
    required this.sellMarCtrl,
    required this.sellTradeCtrl,
    required this.sellFixedCtrl,
    required this.sellPercentCtrl,
    required this.sellOtherCtrl,
    required this.onBuyLevChanged,
    required this.onBuyMarChanged,
    required this.onBuyTradeChanged,
    required this.onBuyFixedChanged,
    required this.onBuyPercentChanged,
    required this.onBuyOtherChanged,
    required this.onSellLevChanged,
    required this.onSellMarChanged,
    required this.onSellTradeChanged,
    required this.onSellFixedChanged,
    required this.onSellPercentChanged,
    required this.onSellOtherChanged,
    required this.currentBuyLev,
    required this.currentBuyMar,
    required this.currentSellLev,
    required this.currentSellMar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: labelBg.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: labelColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product type label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: labelBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: labelColor.withOpacity(0.3)),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: labelColor,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Buy / Sell columns side by side
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── BUY column ──────────────────────────────────────────────
              Expanded(
                child: _SideBlock(
                  side: 'BUY',
                  sideColor: const Color(0xFF2E7D32),
                  sideBg: const Color(0xFFE8F5E9),
                  accentColor: accentColor,
                  levCtrl: buyLevCtrl,
                  marCtrl: buyMarCtrl,
                  tradeCtrl: buyTradeCtrl,
                  fixedCtrl: buyFixedCtrl,
                  percentCtrl: buyPercentCtrl,
                  otherCtrl: buyOtherCtrl,
                  onLevChanged: onBuyLevChanged,
                  onMarChanged: onBuyMarChanged,
                  onTradeChanged: onBuyTradeChanged,
                  onFixedChanged: onBuyFixedChanged,
                  onPercentChanged: onBuyPercentChanged,
                  onOtherChanged: onBuyOtherChanged,
                  currentLev: currentBuyLev,
                  currentMar: currentBuyMar,
                ),
              ),
              const SizedBox(width: 10),
              // ── SELL column ─────────────────────────────────────────────
              Expanded(
                child: _SideBlock(
                  side: 'SELL',
                  sideColor: const Color(0xFFC62828),
                  sideBg: const Color(0xFFFFEBEE),
                  accentColor: accentColor,
                  levCtrl: sellLevCtrl,
                  marCtrl: sellMarCtrl,
                  tradeCtrl: sellTradeCtrl,
                  fixedCtrl: sellFixedCtrl,
                  percentCtrl: sellPercentCtrl,
                  otherCtrl: sellOtherCtrl,
                  onLevChanged: onSellLevChanged,
                  onMarChanged: onSellMarChanged,
                  onTradeChanged: onSellTradeChanged,
                  onFixedChanged: onSellFixedChanged,
                  onPercentChanged: onSellPercentChanged,
                  onOtherChanged: onSellOtherChanged,
                  currentLev: currentSellLev,
                  currentMar: currentSellMar,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Buy / Sell block ─────────────────────────────────────────────────────────

class _SideBlock extends StatelessWidget {
  final String side;
  final Color sideColor;
  final Color sideBg;
  final Color accentColor;
  final TextEditingController levCtrl;
  final TextEditingController marCtrl;
  final TextEditingController tradeCtrl;
  final TextEditingController fixedCtrl;
  final TextEditingController percentCtrl;
  final TextEditingController otherCtrl;
  final ValueChanged<String> onLevChanged;
  final ValueChanged<String> onMarChanged;
  final ValueChanged<String> onTradeChanged;
  final ValueChanged<String> onFixedChanged;
  final ValueChanged<String> onPercentChanged;
  final ValueChanged<String> onOtherChanged;
  final double currentLev;
  final double currentMar;

  const _SideBlock({
    required this.side,
    required this.sideColor,
    required this.sideBg,
    required this.accentColor,
    required this.levCtrl,
    required this.marCtrl,
    required this.tradeCtrl,
    required this.fixedCtrl,
    required this.percentCtrl,
    required this.otherCtrl,
    required this.onLevChanged,
    required this.onMarChanged,
    required this.onTradeChanged,
    required this.onFixedChanged,
    required this.onPercentChanged,
    required this.onOtherChanged,
    required this.currentLev,
    required this.currentMar,
  });


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: sideBg.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: sideColor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Side label + summary chips
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: sideColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: sideColor.withOpacity(0.3)),
                ),
                child: Text(
                  side,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: sideColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              _SummaryChip(
                label: '${currentLev.toStringAsFixed(0)}x',
                sublabel: 'Lev',
                color: accentColor,
              ),
              const SizedBox(width: 4),
              _SummaryChip(
                label: '${currentMar.toStringAsFixed(1)}%',
                sublabel: 'Margin',
                color: accentColor,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Input fields
          _InputField(
            label: 'Leverage',
            suffix: 'x',
            controller: levCtrl,
            helperText: 'e.g. 5',
            onChanged: onLevChanged,
          ),
          const SizedBox(height: 6),
          _InputField(
            label: 'Margin Required',
            suffix: '%',
            controller: marCtrl,
            helperText: 'e.g. 20',
            onChanged: onMarChanged,
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          _InputField(
            label: 'Trade charges',
            suffix: '₹',
            controller: tradeCtrl,
            helperText: '0',
            onChanged: onTradeChanged,
          ),
          const SizedBox(height: 10),
          Text(
            'OTHER TAXES & CHARGES',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: sideColor.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _InputField(
                  label: 'Fixed ₹',
                  suffix: '',
                  controller: fixedCtrl,
                  helperText: '0',
                  onChanged: onFixedChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InputField(
                  label: 'Broker %',
                  suffix: '%',
                  controller: percentCtrl,
                  helperText: '0',
                  onChanged: onPercentChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InputField(
                  label: 'Other %',
                  suffix: '%',
                  controller: otherCtrl,
                  helperText: '0',
                  onChanged: onOtherChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Summary chip ─────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final String label;
  final String sublabel;
  final Color color;

  const _SummaryChip({
    required this.label,
    required this.sublabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            sublabel,
            style: TextStyle(
              fontSize: 9,
              color: color.withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Input field ──────────────────────────────────────────────────────────────

class _InputField extends StatelessWidget {
  final String label;
  final String suffix;
  final TextEditingController controller;
  final String helperText;
  final ValueChanged<String> onChanged;

  const _InputField({
    required this.label,
    required this.suffix,
    required this.controller,
    required this.helperText,
    required this.onChanged,
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
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            suffixText: suffix,
            hintText: helperText,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7,
            ),
            isDense: true,
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
