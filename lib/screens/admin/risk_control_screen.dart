import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../state/admin_scope.dart';
import '../../theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/shared_widgets.dart';

class RiskControlScreen extends StatefulWidget {
  const RiskControlScreen({super.key});

  @override
  State<RiskControlScreen> createState() => _RiskControlScreenState();
}

class _RiskControlScreenState extends State<RiskControlScreen> {
  // Per-user limit controllers keyed by userId
  final Map<String, TextEditingController> _maxPositionControllers = {};
  final Map<String, TextEditingController> _maxDailyLossControllers = {};
  final Map<String, TextEditingController> _maxLeverageControllers = {};

  // Safe level (equity-based auto square-off threshold)
  final TextEditingController _safeLevelController = TextEditingController();
  double _currentSafeLevel = 500;
  bool _safeLevelLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSafeLevel();
  }

  Future<void> _loadSafeLevel() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('admin_config')
          .doc('rms_settings')
          .get();
      final level = (snap.data()?['safeLevel'] as num?)?.toDouble() ?? 500;
      if (mounted) {
        setState(() {
          _currentSafeLevel = level;
          _safeLevelController.text = level.toStringAsFixed(0);
          _safeLevelLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _safeLevelLoading = false);
    }
  }

  Future<void> _saveSafeLevel() async {
    final val = double.tryParse(_safeLevelController.text);
    if (val == null || val < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid amount (≥ 0).'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('admin_config')
          .doc('rms_settings')
          .set({'safeLevel': val, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
              SetOptions(merge: true));
      setState(() => _currentSafeLevel = val);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Safe level updated to ₹${val.toStringAsFixed(0)}.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in _maxPositionControllers.values) c.dispose();
    for (final c in _maxDailyLossControllers.values) c.dispose();
    for (final c in _maxLeverageControllers.values) c.dispose();
    _safeLevelController.dispose();
    super.dispose();
  }

  TextEditingController _posCtrl(String userId) => _maxPositionControllers
      .putIfAbsent(userId, () => TextEditingController());

  TextEditingController _lossCtrl(String userId) => _maxDailyLossControllers
      .putIfAbsent(userId, () => TextEditingController());

  TextEditingController _levCtrl(String userId) => _maxLeverageControllers
      .putIfAbsent(userId, () => TextEditingController());

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    final users = admin.users;

    return Scaffold(
      appBar: AppBar(title: const Text('Risk Control')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Safe Level (Equity-Based Auto Square-Off) ────────────────
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.shieldAlert, color: AppColors.warning, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Safe Level — Auto Square-Off',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'When a user\'s equity (Wallet Balance + Running P&L) drops to or below '
                    'this amount, ALL open positions are automatically closed immediately.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Equity = Wallet Balance + Running P&L\n'
                    'Free Margin = Equity − Used Margin\n'
                    'Margin Level % = (Equity ÷ Used Margin) × 100',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary.withOpacity(0.75),
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_safeLevelLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _safeLevelController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Safe Level (₹)',
                              hintText: '500',
                              helperText: 'Current: ₹${_currentSafeLevel.toStringAsFixed(0)}',
                              prefixText: '₹ ',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _saveSafeLevel,
                          icon: const Icon(LucideIcons.save, size: 14),
                          label: const Text('Save'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.warning,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.info, size: 14, color: AppColors.warning),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Changes apply immediately to all accounts on the next price tick.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.warning.withOpacity(0.9),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Global Trading Halt ──────────────────────────────────────
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.alertTriangle,
                        color: AppColors.danger,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Global Trading Halt',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Immediately prevents all users from placing new orders.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          admin.globalTradingHalt
                              ? '🔴  Trading is HALTED'
                              : '🟢  Trading is ACTIVE',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: admin.globalTradingHalt
                                ? AppColors.danger
                                : AppColors.success,
                          ),
                        ),
                      ),
                      Switch(
                        value: admin.globalTradingHalt,
                        activeColor: AppColors.danger,
                        onChanged: (value) => _confirmHaltToggle(value),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Per-User Risk Limits ─────────────────────────────────────
            Text(
              'Per-User Risk Limits',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            ...users.map(
              (user) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: CustomCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            LucideIcons.user,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            user.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            user.clientId,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _limitField(
                              controller: _posCtrl(user.id),
                              label: 'Max Position (₹)',
                              hint:
                                  admin.getRiskLimit(user.id, 'maxPosition') !=
                                      null
                                  ? admin
                                        .getRiskLimit(user.id, 'maxPosition')!
                                        .toStringAsFixed(0)
                                  : 'Unlimited',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _limitField(
                              controller: _lossCtrl(user.id),
                              label: 'Max Daily Loss (₹)',
                              hint:
                                  admin.getRiskLimit(user.id, 'maxDailyLoss') !=
                                      null
                                  ? admin
                                        .getRiskLimit(user.id, 'maxDailyLoss')!
                                        .toStringAsFixed(0)
                                  : 'Unlimited',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _limitField(
                              controller: _levCtrl(user.id),
                              label: 'Max Leverage',
                              hint:
                                  admin.getRiskLimit(user.id, 'maxLeverage') !=
                                      null
                                  ? admin
                                        .getRiskLimit(user.id, 'maxLeverage')!
                                        .toStringAsFixed(1)
                                  : 'Default',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: () => _saveLimits(user.id),
                          icon: const Icon(LucideIcons.save, size: 14),
                          label: const Text('Save'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Real-Time Risk Exposure ──────────────────────────────────
            Text(
              'Real-Time Risk Exposure',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            CustomCard(
              padding: EdgeInsets.zero,
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(1.5),
                  3: FlexColumnWidth(1.5),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                    children: [
                      _headerCell('User'),
                      _headerCell('Open Position Value'),
                      _headerCell('Daily P&L'),
                      _headerCell('Status'),
                    ],
                  ),
                  ...users.map((user) {
                    final pnl = admin.livePnlByUser[user.id] ?? 0.0;
                    // Used margin estimate: margin = balance - (balance - usedMargin).
                    // Use marginLimit as the ceiling; exposure = runningPnL magnitude as proxy.
                    final usedMargin = user.marginLimit > 0
                        ? (user.marginLimit - user.balance).clamp(0.0, user.marginLimit)
                        : 0.0;
                    final isAtRisk = user.marginLimit > 0 &&
                        usedMargin > user.marginLimit * 0.8;
                    return TableRow(
                      children: [
                        _cell(user.name),
                        _cell('₹${usedMargin.toStringAsFixed(0)}'),
                        _cell(
                          '${pnl >= 0 ? '+' : ''}₹${pnl.toStringAsFixed(0)}',
                          color: pnl >= 0 ? AppColors.success : AppColors.danger,
                        ),
                        _cell(
                          isAtRisk ? '⚠ At Risk' : '✓ Normal',
                          color: isAtRisk ? AppColors.warning : AppColors.success,
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _limitField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
      ),
    );
  }

  Widget _headerCell(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
      ),
    ),
  );

  Widget _cell(String text, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: color ?? AppColors.textPrimary,
        fontWeight: color != null ? FontWeight.w700 : FontWeight.normal,
      ),
    ),
  );

  void _saveLimits(String userId) {
    final admin = AdminScope.of(context);
    final pos = double.tryParse(_posCtrl(userId).text);
    final loss = double.tryParse(_lossCtrl(userId).text);
    final lev = double.tryParse(_levCtrl(userId).text);

    if (pos != null) admin.setRiskLimit(userId, 'maxPosition', pos);
    if (loss != null) admin.setRiskLimit(userId, 'maxDailyLoss', loss);
    if (lev != null) admin.setRiskLimit(userId, 'maxLeverage', lev);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Risk limits saved.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _confirmHaltToggle(bool newValue) {
    AppDialog.warning(
      context,
      title: newValue ? 'Halt All Trading?' : 'Resume Trading?',
      message: newValue
          ? 'This will immediately prevent all users from placing new orders. Are you sure?'
          : 'This will allow users to place orders again.',
      confirmLabel: newValue ? 'Halt Trading' : 'Resume',
      onConfirm: () {
        AdminScope.of(context).toggleGlobalTradingHalt(newValue);
        if (newValue) {
          AppToast.warning(context, 'Trading halted for all users.');
        } else {
          AppToast.success(context, 'Trading resumed.');
        }
      },
    );
  }
}
