import 'package:flutter/material.dart';
import '../../app/app_scope.dart';
import '../../theme.dart';
import '../../widgets/shared_widgets.dart';

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _emailCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: CustomCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Reset Password',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Registered email',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'We will send a reset link to your email. If you forgot PIN, reset password first then set a new app PIN after login.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _sending ? null : _sendReset,
                  child: Text(_sending ? 'Sending...' : 'Send reset link'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _showWhatsappHelp(context),
                  child: const Text('Need help? WhatsApp support'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendReset() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    final authService = AppScope.of(context).authService;
    setState(() => _sending = true);
    try {
      await authService.sendPasswordResetEmail(email);
      if (!mounted) return;
      await authService.invalidateCurrentSession();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reset link sent. Please check your email.'),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not send reset link: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showWhatsappHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('WhatsApp Support'),
        content: const SelectableText(
          'Message us at: https://wa.me/919999999999',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
