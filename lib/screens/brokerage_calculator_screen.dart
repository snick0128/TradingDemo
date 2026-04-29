import 'package:flutter/material.dart';

import '../models/trading_models.dart';
import '../services/brokerage_calculator.dart';
import '../theme.dart';
import '../widgets/shared_widgets.dart';

class BrokerageCalculatorScreen extends StatefulWidget {
  final bool showAppBar;

  const BrokerageCalculatorScreen({super.key, this.showAppBar = true});

  @override
  State<BrokerageCalculatorScreen> createState() =>
      _BrokerageCalculatorScreenState();
}

class _BrokerageCalculatorScreenState extends State<BrokerageCalculatorScreen> {
  final _tradeValueController = TextEditingController();
  ProductType _productType = ProductType.cnc;
  BrokerageResult? _result;

  @override
  void initState() {
    super.initState();
    _tradeValueController.addListener(_recalculate);
  }

  @override
  void dispose() {
    _tradeValueController.dispose();
    super.dispose();
  }

  void _recalculate() {
    final val = double.tryParse(_tradeValueController.text);
    if (val != null && val > 0) {
      setState(() {
        _result = BrokerageCalculator.compute(val, _productType);
      });
    } else {
      setState(() => _result = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Brokerage Calculator',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Estimate charges before placing a trade.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _tradeValueController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Trade Value',
                  prefixText: '₹ ',
                  hintText: 'e.g. 100000',
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<ProductType>(
                value: _productType,
                decoration: const InputDecoration(labelText: 'Product Type'),
                items: const [
                  DropdownMenuItem(
                    value: ProductType.cnc,
                    child: Text('CNC (Delivery)'),
                  ),
                  DropdownMenuItem(
                    value: ProductType.mis,
                    child: Text('MIS (Intraday)'),
                  ),
                  DropdownMenuItem(
                    value: ProductType.nrml,
                    child: Text('NRML (F&O)'),
                  ),
                ],
                onChanged: (v) {
                  setState(() => _productType = v!);
                  _recalculate();
                },
              ),
              const SizedBox(height: 32),
              if (_result != null) _buildResults(context, _result!),
            ],
          ),
        ),
      ),
    );

    if (!widget.showAppBar) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Brokerage Calculator')),
      body: body,
    );
  }

  Widget _buildResults(BuildContext context, BrokerageResult r) {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Charge Breakdown',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          InfoRow(
            label: 'Trade Value',
            value: '₹${r.tradeValue.toStringAsFixed(2)}',
          ),
          InfoRow(
            label: 'Brokerage',
            value: '₹${r.brokerage.toStringAsFixed(2)}',
            valueColor: AppColors.danger,
          ),
          InfoRow(
            label: 'STT (0.1%)',
            value: '₹${r.stt.toStringAsFixed(2)}',
            valueColor: AppColors.danger,
          ),
          InfoRow(
            label: 'GST (18% of brokerage)',
            value: '₹${r.gst.toStringAsFixed(2)}',
            valueColor: AppColors.danger,
          ),
          InfoRow(
            label: 'Exchange Charges (0.00325%)',
            value: '₹${r.exchangeCharges.toStringAsFixed(4)}',
            valueColor: AppColors.danger,
          ),
          const Divider(height: 24),
          InfoRow(
            label: 'Total Charges',
            value: '₹${r.totalCharges.toStringAsFixed(2)}',
            valueColor: AppColors.danger,
          ),
          InfoRow(
            label: 'Net P&L after charges',
            value: '₹${r.netPnl.toStringAsFixed(2)}',
            valueColor: r.netPnl >= 0 ? AppColors.success : AppColors.danger,
          ),
        ],
      ),
    );
  }
}
