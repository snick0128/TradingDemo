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
  final _rmsThresholdCtrl  = TextEditingController();
  final _slippageCtrl      = TextEditingController();
  bool _enableAutoSquareOff = true;
  bool _enableRealtimeRms   = true;

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
    _rmsThresholdCtrl.dispose();
    _slippageCtrl.dispose();
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

      _rmsThresholdCtrl.text = rms.rmsLossThresholdPercent.toStringAsFixed(0);
      _slippageCtrl.text     = rms.slippagePercent.toStringAsFixed(2);
      _enableAutoSquareOff   = rms.enableAutoSquareOff;
      _enableRealtimeRms     = rms.enableRealtimeRms;

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
      final slippage = double.tryParse(_slippageCtrl.text) ?? 0.90;
      await _api.updateRmsSettings({
        'rmsLossThresholdPercent': double.tryParse(_rmsThresholdCtrl.text) ?? 100,
        'enableAutoSquareOff':     _enableAutoSquareOff,
        'enableRealtimeRms':       _enableRealtimeRms,
        'slippagePercent':         slippage.clamp(0.0, 10.0),
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

            // ── RMS / Auto Square-Off ───────────────────────────────────────
            Text('Risk Management (RMS)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Controls auto square-off and real-time margin monitoring. '
                    'Leverage and short selling policy are configured in the Leverage tab.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _rmsThresholdCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'RMS Loss Threshold (%)',
                      hintText: '100 = full margin exhausted triggers auto-exit',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _slippageCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Execution Slippage (%)',
                      hintText: '0.90 = BUY fills 0.9% above LTP, SELL 0.9% below',
                      helperText: 'Applied to MARKET orders only. Range: 0–10%. Default: 0.90%',
                    ),
                  ),
                  const SizedBox(height: 8),
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
