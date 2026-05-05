import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../state/admin_scope.dart';
import '../../theme.dart';
import '../../widgets/shared_widgets.dart';

/// Mock position data for display purposes.
class _MockPosition {
  final String positionId;
  final String userId;
  final String userName;
  final String stock;
  final int qty;
  final double avgPrice;
  final double currentPrice;

  const _MockPosition({
    required this.positionId,
    required this.userId,
    required this.userName,
    required this.stock,
    required this.qty,
    required this.avgPrice,
    required this.currentPrice,
  });

  double get unrealizedPnl => (currentPrice - avgPrice) * qty;
  double get pnlPercent =>
      avgPrice == 0 ? 0 : ((currentPrice - avgPrice) / avgPrice) * 100;
}

class ForceClosePositionsScreen extends StatefulWidget {
  const ForceClosePositionsScreen({super.key});

  @override
  State<ForceClosePositionsScreen> createState() =>
      _ForceClosePositionsScreenState();
}

class _ForceClosePositionsScreenState
    extends State<ForceClosePositionsScreen> {
  // Mock positions — in production these come from Firestore positions stream
  final List<_MockPosition> _positions = [
    const _MockPosition(
      positionId: 'POS-001',
      userId: 'USR-001',
      userName: 'John Doe',
      stock: 'RELIANCE',
      qty: 10,
      avgPrice: 2450.0,
      currentPrice: 2510.0,
    ),
    const _MockPosition(
      positionId: 'POS-002',
      userId: 'USR-001',
      userName: 'John Doe',
      stock: 'HDFC',
      qty: 5,
      avgPrice: 1680.0,
      currentPrice: 1620.0,
    ),
    const _MockPosition(
      positionId: 'POS-003',
      userId: 'USR-002',
      userName: 'Jane Smith',
      stock: 'INFY',
      qty: 20,
      avgPrice: 1540.0,
      currentPrice: 1590.0,
    ),
    const _MockPosition(
      positionId: 'POS-004',
      userId: 'USR-002',
      userName: 'Jane Smith',
      stock: 'TCS',
      qty: 8,
      avgPrice: 3800.0,
      currentPrice: 3720.0,
    ),
  ];

  // Group positions by userId
  Map<String, List<_MockPosition>> get _byUser {
    final map = <String, List<_MockPosition>>{};
    for (final p in _positions) {
      map.putIfAbsent(p.userId, () => []).add(p);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _byUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Force Close Positions'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              label: Text('${_positions.length} open'),
              backgroundColor: AppColors.danger.withOpacity(0.12),
              labelStyle: const TextStyle(
                  color: AppColors.danger, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: _positions.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.checkCircle2,
                      size: 48, color: AppColors.success),
                  SizedBox(height: 12),
                  Text('No open positions across all users.'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: grouped.entries.map((entry) {
                final userId = entry.key;
                final userPositions = entry.value;
                final userName = userPositions.first.userName;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: CustomCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // User header row
                        Row(
                          children: [
                            const Icon(LucideIcons.user,
                                size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 6),
                            Text(userName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(width: 6),
                            Text(userId,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary)),
                            const Spacer(),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _confirmForceCloseAll(userId, userName),
                              icon: const Icon(LucideIcons.xCircle, size: 14),
                              label: const Text('Close All'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                side: const BorderSide(
                                    color: AppColors.danger),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 16),

                        // Position rows
                        ...userPositions.map((pos) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(pos.stock,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        Text(
                                          'Qty: ${pos.qty}  Avg: ₹${pos.avgPrice.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '₹${pos.currentPrice.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        Text(
                                          '${pos.unrealizedPnl >= 0 ? '+' : ''}₹${pos.unrealizedPnl.toStringAsFixed(0)} (${pos.pnlPercent.toStringAsFixed(1)}%)',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: pos.unrealizedPnl >= 0
                                                ? AppColors.success
                                                : AppColors.danger,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  IconButton(
                                    onPressed: () => _confirmForceClose(
                                        userId, pos.positionId, pos.stock),
                                    icon: const Icon(LucideIcons.x,
                                        size: 16, color: AppColors.danger),
                                    tooltip: 'Force Close',
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppColors.danger
                                          .withOpacity(0.1),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }

  void _confirmForceClose(
      String userId, String positionId, String stock) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Force Close Position?'),
        content: Text(
            'Close $stock position for this user? This action is logged and cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              AdminScope.of(context).forceClosePosition(userId, positionId);
              setState(() =>
                  _positions.removeWhere((p) => p.positionId == positionId));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$stock position force-closed.'),
                  backgroundColor: AppColors.warning,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger),
            child: const Text('Force Close'),
          ),
        ],
      ),
    );
  }

  void _confirmForceCloseAll(String userId, String userName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Force Close All Positions?'),
        content: Text(
            'Close ALL open positions for $userName? This action is logged and cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              AdminScope.of(context).forceCloseAllPositions(userId);
              setState(() =>
                  _positions.removeWhere((p) => p.userId == userId));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('All positions for $userName force-closed.'),
                  backgroundColor: AppColors.warning,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger),
            child: const Text('Close All'),
          ),
        ],
      ),
    );
  }
}
