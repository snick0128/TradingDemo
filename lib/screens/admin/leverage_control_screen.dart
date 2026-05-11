import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart'
    hide Order, Transaction;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme.dart';
import '../../widgets/app_dialog.dart';
import 'admin_ui.dart';

// ─── Trading categories ───────────────────────────────────────────────────────
// These are real Indian market categories as used by brokers (Zerodha, Upstox).
// Each category maps to a Firestore doc: category_leverage/{categoryKey}

class _Category {
  final String key;         // Firestore doc ID
  final String name;        // Display name
  final String description; // Short description
  final IconData icon;
  final Color color;
  final double defaultLeverage; // Platform default
  final double defaultMargin;   // = 100 / leverage
  final List<String> symbols;   // Example symbols in this category

  const _Category({
    required this.key,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.defaultLeverage,
    required this.defaultMargin,
    required this.symbols,
  });
}

const _kCategories = [
  // ── NSE Equity Indices ──────────────────────────────────────────────────────
  _Category(
    key:             'nifty50',
    name:            'Nifty 50',
    description:     'NSE large-cap index — top 50 companies',
    icon:            LucideIcons.trendingUp,
    color:           Color(0xFF1565C0),
    defaultLeverage: 5,
    defaultMargin:   20,
    symbols:         ['RELIANCE', 'TCS', 'INFY', 'HDFCBANK', 'ICICIBANK', 'SBIN'],
  ),
  _Category(
    key:             'banknifty',
    name:            'Bank Nifty',
    description:     'NSE banking sector index',
    icon:            LucideIcons.landmark,
    color:           Color(0xFF0277BD),
    defaultLeverage: 5,
    defaultMargin:   20,
    symbols:         ['HDFCBANK', 'ICICIBANK', 'SBIN', 'AXISBANK'],
  ),
  _Category(
    key:             'nifty_midcap',
    name:            'Nifty Midcap',
    description:     'NSE mid-cap stocks (150 index)',
    icon:            LucideIcons.barChart2,
    color:           Color(0xFF00695C),
    defaultLeverage: 4,
    defaultMargin:   25,
    symbols:         ['BAJFINANCE', 'WIPRO', 'HINDUNILVR'],
  ),
  _Category(
    key:             'nse_equity',
    name:            'NSE Equity (General)',
    description:     'All other NSE listed equities',
    icon:            LucideIcons.activity,
    color:           Color(0xFF1565C0),
    defaultLeverage: 3,
    defaultMargin:   33,
    symbols:         ['All NSE stocks not in above categories'],
  ),

  // ── MCX Commodities ─────────────────────────────────────────────────────────
  _Category(
    key:             'mcx_gold',
    name:            'MCX Gold',
    description:     'Gold futures — 1 kg lot',
    icon:            LucideIcons.gem,
    color:           Color(0xFFF9A825),
    defaultLeverage: 10,
    defaultMargin:   10,
    symbols:         ['GOLD', 'GOLDM', 'GOLDPETAL'],
  ),
  _Category(
    key:             'mcx_silver',
    name:            'MCX Silver',
    description:     'Silver futures — 30 kg lot',
    icon:            LucideIcons.gem,
    color:           Color(0xFF78909C),
    defaultLeverage: 10,
    defaultMargin:   10,
    symbols:         ['SILVER', 'SILVERM'],
  ),
  _Category(
    key:             'mcx_energy',
    name:            'MCX Energy',
    description:     'Crude Oil & Natural Gas futures',
    icon:            LucideIcons.flame,
    color:           Color(0xFFE65100),
    defaultLeverage: 10,
    defaultMargin:   10,
    symbols:         ['CRUDEOIL', 'NATURALGAS', 'CRUDEOILM'],
  ),
  _Category(
    key:             'mcx_base_metals',
    name:            'MCX Base Metals',
    description:     'Copper, Zinc, Lead, Aluminium, Nickel',
    icon:            LucideIcons.layers,
    color:           Color(0xFF7B1FA2),
    defaultLeverage: 10,
    defaultMargin:   10,
    symbols:         ['COPPER', 'ZINC', 'LEAD', 'ALUMINIUM', 'NICKEL'],
  ),
  _Category(
    key:             'mcx_agri',
    name:            'MCX Agri',
    description:     'Agricultural commodities — Cotton etc.',
    icon:            LucideIcons.leaf,
    color:           Color(0xFF2E7D32),
    defaultLeverage: 5,
    defaultMargin:   20,
    symbols:         ['COTTON', 'KAPAS'],
  ),
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class LeverageControlScreen extends StatefulWidget {
  const LeverageControlScreen({super.key});

  @override
  State<LeverageControlScreen> createState() => _LeverageControlScreenState();
}

class _LeverageControlScreenState extends State<LeverageControlScreen> {
  // category key → { leverage, margin }
  final Map<String, Map<String, double>> _draft = {};
  final Map<String, Map<String, double>> _saved = {};
  bool _loading = true;
  bool _saving  = false;

  @override
  void initState() {
    super.initState();
    _loadFromFirestore();
  }

  Future<void> _loadFromFirestore() async {
    setState(() => _loading = true);
    try {
      final db   = FirebaseFirestore.instance;
      final snap = await db.collection('category_leverage').get();

      final loaded = <String, Map<String, double>>{};
      for (final doc in snap.docs) {
        final d   = doc.data();
        final lev = (d['leverage'] as num?)?.toDouble();
        final mar = (d['margin']   as num?)?.toDouble();
        if (lev != null && mar != null) {
          loaded[doc.id] = {'leverage': lev, 'margin': mar};
        }
      }

      // Seed defaults for any category not yet in Firestore
      for (final cat in _kCategories) {
        loaded.putIfAbsent(cat.key, () => {
          'leverage': cat.defaultLeverage,
          'margin':   cat.defaultMargin,
        });
      }

      setState(() {
        _saved.addAll(loaded);
        // Deep copy into draft
        for (final e in loaded.entries) {
          _draft[e.key] = Map.from(e.value);
        }
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) AppToast.error(context, 'Could not load leverage settings.');
    }
  }

  bool get _isDirty {
    for (final cat in _kCategories) {
      final d = _draft[cat.key];
      final s = _saved[cat.key];
      if (d == null || s == null) continue;
      if (d['leverage'] != s['leverage'] || d['margin'] != s['margin']) {
        return true;
      }
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
          {
            'categoryKey': cat.key,
            'categoryName': cat.name,
            'leverage':  d['leverage'],
            'margin':    d['margin'],
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
      }

      await batch.commit();

      // Sync saved state
      for (final e in _draft.entries) {
        _saved[e.key] = Map.from(e.value);
      }

      if (mounted) AppToast.success(context, 'Leverage & margin settings saved.');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not save settings. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSingle(String categoryKey) async {
    if (_saving) return;
    final d = _draft[categoryKey];
    if (d == null) return;
    setState(() => _saving = true);
    try {
      final db  = FirebaseFirestore.instance;
      final cat = _kCategories.firstWhere((c) => c.key == categoryKey);
      await db.collection('category_leverage').doc(categoryKey).set({
        'categoryKey':  categoryKey,
        'categoryName': cat.name,
        'leverage':     d['leverage'],
        'margin':       d['margin'],
        'updatedAt':    FieldValue.serverTimestamp(),
      });
      _saved[categoryKey] = Map.from(d);
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
        _draft[e.key] = Map.from(e.value);
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
            subtitle: 'Set maximum leverage and margin % per trading category. '
                'Changes apply to all new orders immediately.',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isDirty)
                  OutlinedButton(
                    onPressed: _discard,
                    child: const Text('Discard'),
                  ),
                if (_isDirty) const SizedBox(width: 8),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
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
                const Icon(LucideIcons.info, size: 14, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Leverage and margin are set per trading category. '
                    'Margin % = 100 ÷ Leverage. '
                    'Lower leverage = higher margin required = less risk.',
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
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _kCategories.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final cat = _kCategories[i];
                  final data = _draft[cat.key] ?? {
                    'leverage': cat.defaultLeverage,
                    'margin':   cat.defaultMargin,
                  };
                  final savedData = _saved[cat.key];
                  final isDirty = savedData != null &&
                      (data['leverage'] != savedData['leverage'] ||
                       data['margin']   != savedData['margin']);

                  return _CategoryCard(
                    category:  cat,
                    leverage:  data['leverage']!,
                    margin:    data['margin']!,
                    isDirty:   isDirty,
                    saving:    _saving,
                    onChanged: (lev, mar) {
                      setState(() {
                        _draft[cat.key] = {'leverage': lev, 'margin': mar};
                      });
                    },
                    onSave: () => _saveSingle(cat.key),
                  );
                },
              ),
            ),

          // Sticky save bar — always visible at bottom
          if (!_loading)
            Container(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Text(
                    _isDirty
                        ? 'You have unsaved changes'
                        : 'All changes saved',
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
  final double leverage;
  final double margin;
  final bool isDirty;
  final bool saving;
  final void Function(double leverage, double margin) onChanged;
  final VoidCallback onSave;

  const _CategoryCard({
    required this.category,
    required this.leverage,
    required this.margin,
    required this.isDirty,
    required this.saving,
    required this.onChanged,
    required this.onSave,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  late TextEditingController _levCtrl;
  late TextEditingController _marCtrl;

  @override
  void initState() {
    super.initState();
    _levCtrl = TextEditingController(
        text: widget.leverage.toStringAsFixed(0));
    _marCtrl = TextEditingController(
        text: widget.margin.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(_CategoryCard old) {
    super.didUpdateWidget(old);
    // Only sync if not currently focused (user isn't typing)
    if (!_levCtrl.selection.isValid || _levCtrl.text.isEmpty) {
      _levCtrl.text = widget.leverage.toStringAsFixed(0);
    }
    if (!_marCtrl.selection.isValid || _marCtrl.text.isEmpty) {
      _marCtrl.text = widget.margin.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _levCtrl.dispose();
    _marCtrl.dispose();
    super.dispose();
  }

  void _onLeverageChanged(String v) {
    final lev = double.tryParse(v);
    if (lev != null && lev > 0) {
      final mar = double.parse((100 / lev).toStringAsFixed(2));
      // Update margin field without triggering another callback
      _marCtrl.text = mar.toStringAsFixed(2);
      widget.onChanged(lev, mar);
    }
  }

  void _onMarginChanged(String v) {
    final mar = double.tryParse(v);
    if (mar != null && mar > 0 && mar <= 100) {
      final lev = double.parse((100 / mar).toStringAsFixed(2));
      _levCtrl.text = lev.toStringAsFixed(0);
      widget.onChanged(lev, mar);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat   = widget.category;
    final c     = cat.color;
    final isDefault = widget.leverage == cat.defaultLeverage &&
                      widget.margin   == cat.defaultMargin;

    return AdminPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 38, height: 38,
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
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        if (widget.isDirty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: AppColors.warning.withOpacity(0.4)),
                            ),
                            child: const Text('Unsaved',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.warning)),
                          ),
                        ],
                        if (!isDefault && !widget.isDirty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: c.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: c.withOpacity(0.3)),
                            ),
                            child: Text('Custom',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: c)),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      cat.description,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              // Live summary chips
              Row(
                children: [
                  _SummaryChip(
                    label: '${widget.leverage.toStringAsFixed(0)}x',
                    sublabel: 'Leverage',
                    color: c,
                  ),
                  const SizedBox(width: 8),
                  _SummaryChip(
                    label: '${widget.margin.toStringAsFixed(1)}%',
                    sublabel: 'Margin',
                    color: c,
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Input fields
          Row(
            children: [
              Expanded(
                child: _InputField(
                  label: 'Max Leverage',
                  suffix: 'x',
                  controller: _levCtrl,
                  helperText: 'e.g. 5 for 5x',
                  onChanged: _onLeverageChanged,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _InputField(
                  label: 'Margin Required',
                  suffix: '%',
                  controller: _marCtrl,
                  helperText: 'e.g. 20 for 20%',
                  onChanged: _onMarginChanged,
                ),
              ),
              const SizedBox(width: 12),
              // Reset to default
              Tooltip(
                message: 'Reset to default\n'
                    '(${cat.defaultLeverage.toStringAsFixed(0)}x / '
                    '${cat.defaultMargin.toStringAsFixed(0)}%)',
                child: IconButton(
                  onPressed: () {
                    setState(() {
                      _levCtrl.text = cat.defaultLeverage.toStringAsFixed(0);
                      _marCtrl.text = cat.defaultMargin.toStringAsFixed(2);
                    });
                    widget.onChanged(cat.defaultLeverage, cat.defaultMargin);
                  },
                  icon: const Icon(LucideIcons.rotateCcw, size: 16),
                  color: AppColors.textSecondary,
                ),
              ),
              // Per-card Save button — always visible
              const SizedBox(width: 4),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: widget.saving ? null : widget.onSave,
                  icon: widget.saving && widget.isDirty
                      ? const SizedBox(
                          width: 12, height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.save, size: 13),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isDirty
                        ? AppColors.primary
                        : AppColors.primary.withOpacity(0.6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 0),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),

          // Example symbols
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: cat.symbols.take(4).map((s) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: c.withOpacity(0.06),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.withOpacity(0.2)),
              ),
              child: Text(s,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: c.withOpacity(0.8))),
            )).toList(),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color)),
          Text(sublabel,
              style: TextStyle(
                  fontSize: 9,
                  color: color.withOpacity(0.7),
                  fontWeight: FontWeight.w500)),
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
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            suffixText: suffix,
            hintText: helperText,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
