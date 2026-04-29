import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';

class AlertCreationScreen extends StatefulWidget {
  final String? initialSymbol;

  const AlertCreationScreen({super.key, this.initialSymbol});

  @override
  State<AlertCreationScreen> createState() => _AlertCreationScreenState();
}

class _AlertCreationScreenState extends State<AlertCreationScreen> {
  late final TextEditingController _symbolController;
  final _targetPriceController = TextEditingController();
  final _percentageController = TextEditingController();
  AlertType _alertType = AlertType.priceAbove;

  @override
  void initState() {
    super.initState();
    _symbolController = TextEditingController(
      text: widget.initialSymbol?.toUpperCase() ?? '',
    );
  }

  @override
  void dispose() {
    _symbolController.dispose();
    _targetPriceController.dispose();
    _percentageController.dispose();
    super.dispose();
  }

  bool get _showPriceField =>
      _alertType == AlertType.priceAbove || _alertType == AlertType.priceBelow;

  bool get _showPercentageField => _alertType == AlertType.percentageMove;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Create Alert'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Symbol search
            const Text(
              'Symbol',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _symbolController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'e.g. NIFTY, RELIANCE, HDFC',
                prefixIcon: Icon(LucideIcons.search, size: 18),
              ),
            ),
            const SizedBox(height: 20),

            // Alert type
            const Text(
              'Alert Type',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<AlertType>(
              value: _alertType,
              decoration: const InputDecoration(),
              items: const [
                DropdownMenuItem(
                  value: AlertType.priceAbove,
                  child: Text('Price Above'),
                ),
                DropdownMenuItem(
                  value: AlertType.priceBelow,
                  child: Text('Price Below'),
                ),
                DropdownMenuItem(
                  value: AlertType.percentageMove,
                  child: Text('Percentage Move'),
                ),
                DropdownMenuItem(
                  value: AlertType.volumeSpike,
                  child: Text('Volume Spike'),
                ),
              ],
              onChanged: (v) => setState(() => _alertType = v!),
            ),
            const SizedBox(height: 20),

            // Conditional fields
            if (_showPriceField) ...[
              const Text(
                'Target Price',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _targetPriceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  hintText: '0.00',
                  prefixText: '₹ ',
                ),
              ),
              const SizedBox(height: 20),
            ],

            if (_showPercentageField) ...[
              const Text(
                'Percentage Threshold',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _percentageController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  hintText: '5.0',
                  suffixText: '%',
                ),
              ),
              const SizedBox(height: 20),
            ],

            if (_alertType == AlertType.volumeSpike) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(LucideIcons.info, size: 16, color: AppColors.primary),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Volume spike alert triggers when volume exceeds 2x the 20-day average.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Save button
            ElevatedButton.icon(
              onPressed: _saveAlert,
              icon: const Icon(LucideIcons.bellPlus, size: 18),
              label: const Text('Create Alert'),
            ),
          ],
        ),
      ),
    );
  }

  void _saveAlert() {
    final symbol = _symbolController.text.trim().toUpperCase();
    if (symbol.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a symbol.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final targetPrice = _showPriceField
        ? double.tryParse(_targetPriceController.text)
        : null;
    final percentage = _showPercentageField
        ? double.tryParse(_percentageController.text)
        : null;

    if (_showPriceField && targetPrice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid target price.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (_showPercentageField && percentage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid percentage.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final store = TradingScope.of(context);
    final currentStockPrice = store.stockBySymbol(symbol).currentPrice;

    store.createAlert(
      Alert(
        id: 'ALERT-${DateTime.now().millisecondsSinceEpoch}',
        symbol: symbol,
        type: _alertType,
        targetPrice: targetPrice,
        percentageThreshold: percentage,
        basePrice: _alertType == AlertType.percentageMove
            ? currentStockPrice
            : null,
        createdAt: DateTime.now(),
      ),
    );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Alert created for $symbol'),
        backgroundColor: AppColors.success,
      ),
    );
  }
}
