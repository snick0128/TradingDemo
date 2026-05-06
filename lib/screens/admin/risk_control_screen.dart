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

  @override
  void dispose() {
    for (final c in _maxPositionControllers.values) c.dispose();
    for (final c in _maxDailyLossControllers.values) c.dispose();
    for (final c in _maxLeverageControllers.values) c.dispose();
    super.dispose();
  }

  TextEditingController _posCtrl(String userId) =>
      _maxPositionControllers.putIfAbsent(userId, () => TextEditingController());

  TextEditingController _lossCtrl(String userId) =>
      _maxDailyLossControllers.putIfAbsent(userId, () => TextEditingController());

  TextEditingController _levCtrl(String userId) =>
      _maxLeverageControllers.putIfAbsent(userId, () => TextEditingController());

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
            // ── Global Trading Halt ──────────────────────────────────────
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.alertTriangle,
                          color: AppColors.danger, size: 20),
                      const SizedBox(width: 8),
                      Text('Global Trading Halt',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Immediately prevents all users from placing new orders.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
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
            Text('Per-User Risk Limits',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ...users.map((user) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CustomCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.user,
                                size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 6),
                            Text(user.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(width: 6),
                            Text(user.clientId,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _limitField(
                                controller: _posCtrl(user.id),
                                label: 'Max Position (₹)',
                                hint: admin.getRiskLimit(
                                            user.id, 'maxPosition') !=
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
                                hint: admin.getRiskLimit(
                                            user.id, 'maxDailyLoss') !=
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
                                hint: admin.getRiskLimit(
                                            user.id, 'maxLeverage') !=
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
                                    horizontal: 16, vertical: 8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )),

            const SizedBox(height: 16),

            // ── Real-Time Risk Exposure ──────────────────────────────────
            Text('Real-Time Risk Exposure',
                style: Theme.of(context).textTheme.titleMedium),
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
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(12))),
                    children: [
                      _headerCell('User'),
                      _headerCell('Open Position Value'),
                      _headerCell('Daily P&L'),
                      _headerCell('Status'),
                    ],
                  ),
                  ...users.map((user) {
                    // Mock exposure data
                    final posValue = user.balance * 0.4;
                    final dailyPnl = user.balance * 0.02 * (user.isActive ? 1 : -1);
                    final isAtRisk = posValue > user.marginLimit * 0.8;
                    return TableRow(
                      children: [
                        _cell(user.name),
                        _cell('₹${posValue.toStringAsFixed(0)}'),
                        _cell(
                          '${dailyPnl >= 0 ? '+' : ''}₹${dailyPnl.toStringAsFixed(0)}',
                          color: dailyPnl >= 0
                              ? AppColors.success
                              : AppColors.danger,
                        ),
                        _cell(
                          isAtRisk ? '⚠ At Risk' : '✓ Normal',
                          color: isAtRisk
                              ? AppColors.warning
                              : AppColors.success,
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }

  Widget _headerCell(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary)),
      );

  Widget _cell(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: color ?? AppColors.textPrimary,
                fontWeight:
                    color != null ? FontWeight.w700 : FontWeight.normal)),
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
          backgroundColor: AppColors.success),
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
