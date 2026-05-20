import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../config/backend_config.dart';
import '../../data/services/backend_api_service.dart';
import '../../models/platform_settings.dart';
import '../../theme.dart';
import '../../widgets/shared_widgets.dart';
import 'admin_ui.dart';

class PlatformSettingsScreen extends StatefulWidget {
  const PlatformSettingsScreen({super.key});
  @override
  State<PlatformSettingsScreen> createState() => _PlatformSettingsScreenState();
}

class _PlatformSettingsScreenState extends State<PlatformSettingsScreen> {
  final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);

  bool _loading = true;
  String? _error;
  bool _saving = false;

  // RMS fields
  final _intradayLevCtrl    = TextEditingController();
  final _shortSellLevCtrl   = TextEditingController();
  final _rmsThresholdCtrl   = TextEditingController();
  bool _enableShortSelling           = true;
  bool _allowEquityIntradayShortSell = true;
  bool _enableAutoSquareOff          = true;
  bool _enableRealtimeRms            = true;

  // Support fields
  final _whatsappCtrl  = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _msgTplCtrl    = TextEditingController();
  bool _supportEnabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _intradayLevCtrl.dispose();
    _shortSellLevCtrl.dispose();
    _rmsThresholdCtrl.dispose();
    _whatsappCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _msgTplCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _api.getRmsSettings(),
        _api.getSupportConfig(),
      ]);

      final rms  = PlatformRmsSettings.fromMap(results[0]);
      final supp = SupportConfig.fromMap(results[1]);

      _intradayLevCtrl.text  = rms.intradayLeverage.toStringAsFixed(0);
      _shortSellLevCtrl.text = rms.shortSellLeverage.toStringAsFixed(0);
      _rmsThresholdCtrl.text = rms.rmsLossThresholdPercent.toStringAsFixed(0);
      _enableShortSelling           = rms.enableShortSelling;
      _allowEquityIntradayShortSell = rms.allowEquityIntradayShortSell;
      _enableAutoSquareOff          = rms.enableAutoSquareOff;
      _enableRealtimeRms            = rms.enableRealtimeRms;

      _whatsappCtrl.text = supp.whatsappNumber;
      _phoneCtrl.text    = supp.phoneNumber;
      _emailCtrl.text    = supp.email;
      _msgTplCtrl.text   = supp.messageTemplate;
      _supportEnabled    = supp.enabled;

      setState(() => _loading = false);
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _saveRms() async {
    setState(() => _saving = true);
    try {
      await _api.updateRmsSettings({
        'intradayLeverage':             double.tryParse(_intradayLevCtrl.text) ?? 5,
        'shortSellLeverage':            double.tryParse(_shortSellLevCtrl.text) ?? 5,
        'intradayShortSellLeverage':    double.tryParse(_shortSellLevCtrl.text) ?? 5,
        'rmsLossThresholdPercent':      double.tryParse(_rmsThresholdCtrl.text) ?? 100,
        'enableShortSelling':           _enableShortSelling,
        'allowEquityIntradayShortSell': _allowEquityIntradayShortSell,
        'enableAutoSquareOff':          _enableAutoSquareOff,
        'enableRealtimeRms':            _enableRealtimeRms,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('RMS settings saved.'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSupport() async {
    setState(() => _saving = true);
    try {
      await _api.updateSupportConfig({
        'supportWhatsappNumber':  _whatsappCtrl.text.trim(),
        'supportPhoneNumber':     _phoneCtrl.text.trim(),
        'supportEmail':           _emailCtrl.text.trim(),
        'supportMessageTemplate': _msgTplCtrl.text.trim(),
        'supportEnabled':         _supportEnabled,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Support config saved.'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AdminPage(child: Center(child: CircularProgressIndicator()));
    }

    return AdminPage(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdminHeader(
              title: 'Platform Settings',
              subtitle: 'Configure leverage, RMS rules, and support contact details.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              StatusBadge(label: _error!, color: AppColors.danger),
            ],
            const SizedBox(height: 20),

            // ── RMS / Leverage ──────────────────────────────────────────────
            Text('Risk Management (RMS)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'These settings control short sell leverage and auto square-off behavior. '
                    'Changes apply to all new orders immediately.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _intradayLevCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Intraday BUY Leverage (x)',
                            hintText: '5',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _shortSellLevCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Short Sell Leverage (x)',
                            hintText: '5',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _rmsThresholdCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'RMS Loss Threshold (%)',
                      hintText: '100 = full margin exhausted triggers auto-exit',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable Short Selling', style: TextStyle(fontSize: 13)),
                    value: _enableShortSelling,
                    onChanged: (v) => setState(() => _enableShortSelling = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow Equity Intraday Short Sell', style: TextStyle(fontSize: 13)),
                    value: _allowEquityIntradayShortSell,
                    onChanged: (v) => setState(() => _allowEquityIntradayShortSell = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable Auto Square-Off (end of day)', style: TextStyle(fontSize: 13)),
                    value: _enableAutoSquareOff,
                    onChanged: (v) => setState(() => _enableAutoSquareOff = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable Real-Time RMS (margin exhaustion)', style: TextStyle(fontSize: 13)),
                    value: _enableRealtimeRms,
                    onChanged: (v) => setState(() => _enableRealtimeRms = v),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _saveRms,
                      icon: const Icon(LucideIcons.save, size: 16),
                      label: const Text('Save RMS Settings'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Support Config ──────────────────────────────────────────────
            Text('Support Contact', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'These details appear in the Help & Support screen. '
                    'Leave a field blank to hide that contact option.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _whatsappCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'WhatsApp Number',
                      hintText: '919876543210 (country code + number, no +)',
                      prefixIcon: Icon(LucideIcons.messageCircle, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      hintText: '+91 1800-XXX-XXXX',
                      prefixIcon: Icon(LucideIcons.phone, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Support Email',
                      hintText: 'support@example.com',
                      prefixIcon: Icon(LucideIcons.mail, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _msgTplCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Default WhatsApp Message Template',
                      hintText: 'Hello, I need help with my account.',
                      alignLabelWithHint: true,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show Support Contact to Users', style: TextStyle(fontSize: 13)),
                    value: _supportEnabled,
                    onChanged: (v) => setState(() => _supportEnabled = v),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _saveSupport,
                      icon: const Icon(LucideIcons.save, size: 16),
                      label: const Text('Save Support Config'),
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
}
