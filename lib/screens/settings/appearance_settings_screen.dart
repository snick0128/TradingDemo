import 'package:flutter/material.dart';

import '../../state/trading_scope.dart';
import '../../theme.dart';
import '../../widgets/shared_widgets.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final store = TradingScope.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Appearance'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Font size
            Text('Font Size', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            CustomCard(
              child: Column(
                children: ['Small', 'Medium', 'Large'].map((size) {
                  return RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(size),
                    subtitle: Text(_fontSizeDescription(size)),
                    value: size,
                    groupValue: store.fontSizePreset,
                    onChanged: (v) {
                      if (v == null) return;
                      store.setFontSizePreset(v);
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),

            // Preview
            Text('Preview', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RELIANCE',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: _previewFontSize(store.fontSizePreset),
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    'Reliance Industries Ltd.',
                    style: TextStyle(
                      fontSize: _previewFontSize(store.fontSizePreset) - 2,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₹2,814.65',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: _previewFontSize(store.fontSizePreset) + 4,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _previewFontSize(String preset) {
    switch (preset) {
      case 'Small':
        return 12;
      case 'Large':
        return 16;
      default:
        return 14;
    }
  }

  String _fontSizeDescription(String size) {
    switch (size) {
      case 'Small':
        return 'Compact view, more data visible';
      case 'Large':
        return 'Easier to read, less data visible';
      default:
        return 'Balanced view (recommended)';
    }
  }
}
