import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';
import 'alert_creation_screen.dart';

class PriceAlertsScreen extends StatelessWidget {
  final bool showAppBar;
  const PriceAlertsScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);
    final alerts = store.alerts;

    final body = alerts.isEmpty
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.bellOff, size: 48, color: AppColors.border),
                SizedBox(height: 16),
                Text('No active alerts',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 16)),
                SizedBox(height: 8),
                Text('Tap + to create a price alert.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: alerts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final alert = alerts[index];
              return _AlertCard(
                alert: alert,
                onDelete: () => store.deleteAlert(alert.id),
              );
            },
          );

    if (!showAppBar) {
      return Scaffold(
        body: body,
        floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AlertCreationScreen()),
          ),
          child: const Icon(LucideIcons.plus),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text('Price Alerts (${alerts.length})'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AlertCreationScreen()),
        ),
        child: const Icon(LucideIcons.plus),
      ),
      body: body,
    );
  }
}

class _AlertCard extends StatelessWidget {
  final Alert alert;
  final VoidCallback onDelete;

  const _AlertCard({required this.alert, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM, hh:mm a');
    final typeLabel = _alertTypeLabel(alert.type);
    final typeColor = _alertTypeColor(alert.type);

    return CustomCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: typeColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(LucideIcons.bell, color: typeColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      alert.symbol,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(label: typeLabel, color: typeColor),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _alertDescription(alert),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                Text(
                  'Created: ${fmt.format(alert.createdAt)}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(LucideIcons.trash2,
                size: 18, color: AppColors.danger),
            tooltip: 'Delete alert',
          ),
        ],
      ),
    );
  }

  String _alertTypeLabel(AlertType type) {
    switch (type) {
      case AlertType.priceAbove:
        return 'Above';
      case AlertType.priceBelow:
        return 'Below';
      case AlertType.percentageMove:
        return '% Move';
      case AlertType.volumeSpike:
        return 'Vol Spike';
      default:
        return type.name;
    }
  }

  Color _alertTypeColor(AlertType type) {
    switch (type) {
      case AlertType.priceAbove:
        return AppColors.success;
      case AlertType.priceBelow:
        return AppColors.danger;
      case AlertType.percentageMove:
        return AppColors.warning;
      case AlertType.volumeSpike:
        return AppColors.accent;
      default:
        return AppColors.primary;
    }
  }

  String _alertDescription(Alert alert) {
    switch (alert.type) {
      case AlertType.priceAbove:
        return 'Price above ₹${alert.targetPrice?.toStringAsFixed(2) ?? '-'}';
      case AlertType.priceBelow:
        return 'Price below ₹${alert.targetPrice?.toStringAsFixed(2) ?? '-'}';
      case AlertType.percentageMove:
        return '${alert.percentageThreshold?.toStringAsFixed(1) ?? '-'}% move';
      case AlertType.volumeSpike:
        return 'Volume spike detected';
      default:
        return alert.type.name;
    }
  }
}
