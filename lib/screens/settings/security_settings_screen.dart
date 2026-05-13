import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../state/security_scope.dart';
import '../../theme.dart';
import '../../widgets/shared_widgets.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final _currentPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final security = SecurityScope.of(context);
    final sessionLog = security.sessionLog;
    final fmt = DateFormat('dd MMM yyyy, hh:mm a');

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Security Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Change PIN
            Text('Change PIN', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            CustomCard(
              child: Column(
                children: [
                  TextField(
                    controller: _currentPinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: 'Current PIN',
                      counterText: '',
                      prefixIcon: Icon(LucideIcons.lock, size: 18),
                    ),
                    onChanged: (_) => setState(() => _error = ''),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newPinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: 'New PIN',
                      counterText: '',
                      prefixIcon: Icon(LucideIcons.keyRound, size: 18),
                    ),
                    onChanged: (_) => setState(() => _error = ''),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmPinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      labelText: 'Confirm New PIN',
                      counterText: '',
                      prefixIcon: Icon(LucideIcons.shieldCheck, size: 18),
                    ),
                    onChanged: (_) => setState(() => _error = ''),
                  ),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _changePin(security),
                    icon: const Icon(LucideIcons.save, size: 16),
                    label: const Text('Update PIN'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Session Log
            Text('Session Log', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            CustomCard(
              padding: EdgeInsets.zero,
              child: sessionLog.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No session history.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : Column(
                      children: sessionLog.reversed
                          .take(10)
                          .toList()
                          .asMap()
                          .entries
                          .map(
                            (e) => Column(
                              children: [
                                ListTile(
                                  leading: const Icon(
                                    LucideIcons.logIn,
                                    size: 18,
                                    color: AppColors.success,
                                  ),
                                  title: Text(
                                    fmt.format(e.value),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  subtitle: const Text(
                                    'Login session',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                if (e.key < sessionLog.length.clamp(0, 10) - 1)
                                  const Divider(height: 1),
                              ],
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _changePin(security) {
    final current = _currentPinController.text.trim();
    final next = _newPinController.text.trim();
    final confirm = _confirmPinController.text.trim();

    if (next != confirm) {
      setState(() => _error = 'New PIN and confirm PIN do not match.');
      return;
    }

    final changed = security.changePin(currentPin: current, newPin: next);
    if (!changed) {
      setState(() => _error = 'Invalid PIN. Use 4 digits.');
      return;
    }

    _currentPinController.clear();
    _newPinController.clear();
    _confirmPinController.clear();
    setState(() => _error = '');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PIN changed successfully.'),
        backgroundColor: AppColors.success,
      ),
    );
  }
}
