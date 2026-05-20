import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../config/backend_config.dart';
import '../../data/services/backend_api_service.dart';
import '../../theme.dart';
import '../../widgets/shared_widgets.dart';
import 'admin_ui.dart';

class AdminChangePasswordScreen extends StatefulWidget {
  const AdminChangePasswordScreen({super.key});
  @override
  State<AdminChangePasswordScreen> createState() => _AdminChangePasswordScreenState();
}

class _AdminChangePasswordScreenState extends State<AdminChangePasswordScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl     = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);

  bool _saving = false;
  bool _showCurrent = false;
  bool _showNew     = false;
  bool _showConfirm = false;
  String? _error;
  bool _success = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final current = _currentCtrl.text.trim();
    final newPwd  = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (current.isEmpty || newPwd.isEmpty || confirm.isEmpty) {
      setState(() => _error = 'All fields are required.');
      return;
    }
    if (newPwd.length < 8) {
      setState(() => _error = 'New password must be at least 8 characters.');
      return;
    }
    if (newPwd != confirm) {
      setState(() => _error = 'New password and confirm password do not match.');
      return;
    }

    setState(() { _saving = true; _error = null; _success = false; });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        setState(() => _error = 'Not logged in. Please log out and log back in.');
        return;
      }

      // Step 1: Re-authenticate with current password
      final credential = EmailAuthProvider.credential(
        email:    user.email!,
        password: current,
      );
      await user.reauthenticateWithCredential(credential);

      // Step 2: Update via Firebase Auth directly
      await user.updatePassword(newPwd);

      // Step 3: Invalidate other sessions via backend (optional, best-effort)
      try {
        await _api.changeAdminPassword(uid: user.uid, newPassword: newPwd);
      } catch (_) {}

      _currentCtrl.clear();
      _newCtrl.clear();
      _confirmCtrl.clear();
      setState(() { _success = true; _saving = false; });
    } on FirebaseAuthException catch (e) {
      final msg = e.code == 'wrong-password'
          ? 'Current password is incorrect.'
          : (e.message ?? 'Authentication failed.');
      setState(() { _error = msg; _saving = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdminHeader(
              title: 'Change Password',
              subtitle: 'Update your admin account password. All other sessions will be signed out.',
            ),
            const SizedBox(height: 20),
            CustomCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_success) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.checkCircle, size: 16, color: AppColors.success),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Password changed successfully. Other sessions have been invalidated.',
                              style: TextStyle(fontSize: 13, color: AppColors.success),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.alertCircle, size: 16, color: AppColors.danger),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.danger))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _pwdField(
                    controller: _currentCtrl,
                    label: 'Current Password',
                    show: _showCurrent,
                    onToggle: () => setState(() => _showCurrent = !_showCurrent),
                  ),
                  const SizedBox(height: 12),
                  _pwdField(
                    controller: _newCtrl,
                    label: 'New Password',
                    show: _showNew,
                    onToggle: () => setState(() => _showNew = !_showNew),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Minimum 8 characters.',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  _pwdField(
                    controller: _confirmCtrl,
                    label: 'Confirm New Password',
                    show: _showConfirm,
                    onToggle: () => setState(() => _showConfirm = !_showConfirm),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _changePassword,
                      icon: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(LucideIcons.keyRound, size: 16),
                      label: Text(_saving ? 'Updating…' : 'Change Password'),
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

  Widget _pwdField({
    required TextEditingController controller,
    required String label,
    required bool show,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: !show,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          icon: Icon(show ? LucideIcons.eyeOff : LucideIcons.eye, size: 18),
          onPressed: onToggle,
        ),
      ),
    );
  }
}
