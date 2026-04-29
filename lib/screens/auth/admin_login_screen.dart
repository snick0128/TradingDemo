import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../app/app_scope.dart';
import '../../config/admin_auth_config.dart';
import '../../theme.dart';
import '../admin/admin_shell.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _clientIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String _error = '';

  @override
  void dispose() {
    _clientIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = '';
    });

    final appScope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    if (appScope == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Firebase is required for admin login.';
      });
      return;
    }
    try {
      final profile = await appScope.authService.loginAdmin(
        _clientIdController.text.trim(),
        _passwordController.text,
      );
      appScope.notifier!.setUser(profile);
      if (!mounted) return;
      setState(() => _loading = false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminShell()),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Invalid admin credentials.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      LucideIcons.shield,
                      color: AppColors.danger,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Admin Login',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Single primary admin access only.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _clientIdController,
                    decoration: const InputDecoration(
                      labelText: 'Admin Email / ID',
                      prefixIcon: Icon(LucideIcons.user, size: 18),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Admin ID is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(LucideIcons.lock, size: 18),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? LucideIcons.eyeOff
                              : LucideIcons.eye,
                          size: 18,
                        ),
                      ),
                    ),
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Password is required'
                        : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign In to Admin'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Primary Admin ID: $kPrimaryAdminEmail',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Primary Password: $kPrimaryAdminPassword',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
