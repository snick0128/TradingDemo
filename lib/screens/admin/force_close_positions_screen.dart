import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/trade_ledger.dart';
import '../../models/trading_models.dart';
import '../../state/admin_scope.dart';
import '../../theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/shared_widgets.dart';

class ForceClosePositionsScreen extends StatelessWidget {
  const ForceClosePositionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    final ledger = LedgerSummary(admin.masterOrderBook);
    final openPositions = ledger.open;

    // Group by userId
    final byUser = <String, List<TradeLedgerEntry>>{};
    for (final pos in openPositions) {
      byUser.putIfAbsent(pos.userId, () => []).add(pos);
    }

    final userNames = {for (final u in admin.users) u.id: u.name};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Force Close Positions'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              label: Text('${openPositions.length} open'),
              backgroundColor: AppColors.danger.withOpacity(0.12),
              labelStyle: const TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: openPositions.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.checkCircle2, size: 48, color: AppColors.success),
                  SizedBox(height: 12),
                  Text('No open positions across all users.'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: byUser.entries.map((entry) {
                final userId = entry.key;
                final positions = entry.value;
                final displayName = userNames[userId] ??
                    (positions.first.userClientId.isNotEmpty
                        ? positions.first.userClientId
                        : userId.substring(0, userId.length.clamp(0, 8)));

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: CustomCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── User header ──────────────────────────────
                        Row(
                          children: [
                            const Icon(
                              LucideIcons.user,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              displayName,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            OutlinedButton.icon(
                              onPressed: () => _confirmForceCloseAll(
                                context, admin, userId, displayName),
                              icon: const Icon(LucideIcons.xCircle, size: 14),
                              label: const Text('Close All'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                side: const BorderSide(color: AppColors.danger),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 16),

                        // ── Position rows ────────────────────────────
                        ...positions.map(
                          (pos) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            pos.symbol,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: (pos.direction == OrderType.buy
                                                      ? AppColors.success
                                                      : AppColors.danger)
                                                  .withOpacity(0.12),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              pos.direction == OrderType.buy
                                                  ? 'LONG'
                                                  : 'SHORT',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                color: pos.direction ==
                                                        OrderType.buy
                                                    ? AppColors.success
                                                    : AppColors.danger,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        'Qty: ${pos.quantity}  Avg: ₹${pos.entryPrice.toStringAsFixed(2)}  ${pos.product}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '₹${pos.entryValue.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        pos.exchange,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton(
                                  onPressed: () => _confirmForceClose(
                                    context,
                                    admin,
                                    userId,
                                    pos.entryOrderId,
                                    pos.symbol,
                                  ),
                                  icon: const Icon(
                                    LucideIcons.x,
                                    size: 16,
                                    color: AppColors.danger,
                                  ),
                                  tooltip: 'Force Close',
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        AppColors.danger.withOpacity(0.1),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }

  void _confirmForceClose(
    BuildContext context,
    dynamic admin,
    String userId,
    String positionId,
    String stock,
  ) {
    AppDialog.destructive(
      context,
      title: 'Force Close Position?',
      message:
          'Close $stock position for this user? This action is logged and cannot be undone.',
      confirmLabel: 'Force Close',
      onConfirm: () {
        admin.forceClosePosition(userId, positionId);
        AppToast.warning(context, '$stock position force-closed.');
      },
    );
  }

  void _confirmForceCloseAll(
    BuildContext context,
    dynamic admin,
    String userId,
    String userName,
  ) {
    AppDialog.destructive(
      context,
      title: 'Force Close All Positions?',
      message:
          'Close ALL open positions for $userName? This action is logged and cannot be undone.',
      confirmLabel: 'Close All',
      onConfirm: () {
        admin.forceCloseAllPositions(userId);
        AppToast.warning(context, 'All positions for $userName force-closed.');
      },
    );
  }
}
