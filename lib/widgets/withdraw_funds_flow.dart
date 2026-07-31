import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app/app_scope.dart';
import '../data/services/bank_account_service.dart';
import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../theme.dart';
import 'wallet_bottom_sheet.dart';

const _kQuickPercents = [0.25, 0.5, 0.75, 1.0];

/// Sentinel a "Back" button pops with — distinct from `null` (whole flow
/// cancelled) so the orchestrator knows to reopen the previous step instead
/// of giving up. Shared meaning across every step of this flow.
const _kBack = '__back__';

/// Withdrawal flow — Amount → Select Bank Account → Confirm → Processing, as
/// sequential modal bottom sheets (same visual system as [showAddFundsFlow]).
/// Still writes the same `withdrawal_requests` pending-approval document
/// [WithdrawFundsScreen] always has — this only changes presentation and
/// adds a real saved-bank-account picker in place of the old free-text field.
Future<void> showWithdrawFundsFlow(BuildContext context) async {
  final store = TradingScope.of(context);
  final uid = AppScope.of(context).notifier?.user?.uid ?? '';
  if (uid.isEmpty) return;

  final availableToWithdraw = store.balance;

  double? amount;
  BankAccount? account;
  var step = 0; // 0 = amount, 1 = select bank, 2 = confirm

  while (context.mounted) {
    if (step == 0) {
      amount = await showModalBottomSheet<double>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _WithdrawAmountSheet(
          availableToWithdraw: availableToWithdraw,
          initialAmount: amount,
        ),
      );
      if (amount == null || !context.mounted) return;
      step = 1;
      continue;
    }

    if (step == 1) {
      final result = await showModalBottomSheet<Object>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _SelectBankAccountSheet(amount: amount!, userId: uid),
      );
      if (!context.mounted) return;
      if (result == null) return; // closed via X / backdrop — cancel entirely
      if (result == _kBack) { step = 0; continue; }
      account = result as BankAccount;
      step = 2;
      continue;
    }

    // step == 2
    final confirmed = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConfirmWithdrawalSheet(amount: amount!, account: account!),
    );
    if (!context.mounted) return;
    if (confirmed == null) return;
    if (confirmed == _kBack) { step = 1; continue; }

    if (context.mounted) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => _buildWithdrawalProcessingSheet(sheetContext, amount!, account!),
      );
    }
    return;
  }
}

// ─── Step 1: Amount ───────────────────────────────────────────────────────────

class _WithdrawAmountSheet extends StatefulWidget {
  final double availableToWithdraw;
  final double? initialAmount;
  const _WithdrawAmountSheet({required this.availableToWithdraw, this.initialAmount});

  @override
  State<_WithdrawAmountSheet> createState() => _WithdrawAmountSheetState();
}

class _WithdrawAmountSheetState extends State<_WithdrawAmountSheet> {
  static const _step = 500.0;

  late final _amountCtrl = TextEditingController(
    text: widget.initialAmount != null ? widget.initialAmount!.toStringAsFixed(0) : '',
  );
  double? _selectedPercent;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(_amountCtrl.text.trim());
  bool get _exceedsAvailable => (_amount ?? 0) > widget.availableToWithdraw;
  bool get _canSubmit => (_amount ?? 0) > 0 && !_exceedsAvailable;

  void _setAmount(double value) {
    _amountCtrl.text = value.clamp(0, widget.availableToWithdraw).toStringAsFixed(0);
    setState(() {});
  }

  void _submit() {
    final amount = _amount;
    if (amount == null || amount <= 0 || _exceedsAvailable) return;
    Navigator.pop(context, amount);
  }

  @override
  Widget build(BuildContext context) {
    return WalletSheetShell(
      title: 'Withdraw Funds',
      onClose: () => Navigator.pop(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Available to withdraw', style: TextStyle(fontSize: 13, color: Color(0xFF757575))),
                Text('₹${widget.availableToWithdraw.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0D0D0D))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                const Text('Withdrawal Amount', style: TextStyle(fontSize: 13, color: Color(0xFF9E9E9E))),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _setAmount((_amount ?? 0) - _step),
                      icon: const Icon(Icons.remove_circle_outline, size: 22, color: Color(0xFF9E9E9E)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _amountCtrl,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() => _selectedPercent = null),
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Color(0xFF0D0D0D)),
                        decoration: const InputDecoration(
                          prefixText: '₹',
                          prefixStyle: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Color(0xFF9E9E9E)),
                          hintText: '0',
                          hintStyle: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Color(0xFFBDBDBD)),
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _setAmount((_amount ?? 0) + _step),
                      icon: const Icon(Icons.add_circle_outline, size: 22, color: Color(0xFF9E9E9E)),
                    ),
                  ],
                ),
                if (_exceedsAvailable) ...[
                  const SizedBox(height: 4),
                  Text('Exceeds available balance (₹${widget.availableToWithdraw.toStringAsFixed(0)})',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.danger, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: _kQuickPercents.map((p) {
              final selected = _selectedPercent == p;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () => setState(() {
                      _selectedPercent = p;
                      _setAmount(widget.availableToWithdraw * p);
                    }),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        p == 1.0 ? '100%' : '${(p * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : const Color(0xFF757575),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.info, size: 14, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 11.5, color: AppColors.warning.withOpacity(0.9), height: 1.5),
                      children: const [
                        TextSpan(text: 'Withdrawal Info\n', style: TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(
                          text: 'Funds reach your bank within 1 working day. Requests placed after 3:30 PM '
                              'are processed next business day.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _canSubmit ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                _canSubmit ? 'Withdraw ₹${_amount!.toStringAsFixed(0)}' : 'Enter a valid amount',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Step 2: Select Bank Account ──────────────────────────────────────────────

class _SelectBankAccountSheet extends StatefulWidget {
  final double amount;
  final String userId;
  const _SelectBankAccountSheet({required this.amount, required this.userId});

  @override
  State<_SelectBankAccountSheet> createState() => _SelectBankAccountSheetState();
}

class _SelectBankAccountSheetState extends State<_SelectBankAccountSheet> {
  String? _selectedId;

  Future<void> _addAccount() async {
    final created = await showModalBottomSheet<BankAccount>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddBankAccountSheet(userId: widget.userId),
    );
    if (created != null && mounted) setState(() => _selectedId = created.id);
  }

  @override
  Widget build(BuildContext context) {
    return WalletSheetShell(
      title: 'Select Bank Account',
      onClose: () => Navigator.pop(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Withdrawing', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                Text('₹${widget.amount.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'LINKED BANK ACCOUNTS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF9E9E9E), letterSpacing: 0.5),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: StreamBuilder<List<BankAccount>>(
              stream: BankAccountService.streamForUser(widget.userId),
              builder: (context, snapshot) {
                final accounts = snapshot.data ?? const <BankAccount>[];
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                if (accounts.isNotEmpty) {
                  _selectedId ??= accounts.firstWhere((a) => a.isPrimary, orElse: () => accounts.first).id;
                }
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final acc in accounts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _BankAccountTile(
                            account: acc,
                            selected: _selectedId == acc.id,
                            onTap: () => setState(() => _selectedId = acc.id),
                          ),
                        ),
                      if (accounts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Text(
                            'No saved bank accounts yet. Add one to continue.',
                            style: TextStyle(fontSize: 12.5, color: Color(0xFF9E9E9E)),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: _addAccount,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary.withOpacity(0.4), style: BorderStyle.solid),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 16, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text('Add New Bank Account',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, _kBack),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0D0D0D),
                      side: const BorderSide(color: Color(0xFFE0E0E0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Back', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: StreamBuilder<List<BankAccount>>(
                  stream: BankAccountService.streamForUser(widget.userId),
                  builder: (context, snapshot) {
                    final accounts = snapshot.data ?? const <BankAccount>[];
                    final selected = accounts.where((a) => a.id == _selectedId).toList();
                    final account = selected.isNotEmpty ? selected.first : null;
                    return SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: account == null ? null : () => Navigator.pop(context, account),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Continue', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BankAccountTile extends StatelessWidget {
  final BankAccount account;
  final bool selected;
  final VoidCallback onTap;
  const _BankAccountTile({required this.account, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.primary : const Color(0xFFE0E0E0), width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: const Color(0xFF546E7A).withOpacity(0.12), shape: BoxShape.circle),
              child: const Icon(LucideIcons.building2, color: Color(0xFF546E7A), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(account.bankName,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0D0D0D)),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (account.isPrimary) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('PRIMARY',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${account.maskedAccountNumber} · ${account.ifscCode}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? AppColors.primary : const Color(0xFFBDBDBD), width: 2),
                color: selected ? AppColors.primary : Colors.transparent,
              ),
              child: selected ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add New Bank Account ─────────────────────────────────────────────────────

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _AddBankAccountSheet extends StatefulWidget {
  final String userId;
  const _AddBankAccountSheet({required this.userId});

  @override
  State<_AddBankAccountSheet> createState() => _AddBankAccountSheetState();
}

class _AddBankAccountSheetState extends State<_AddBankAccountSheet> {
  static final _ifscPattern = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  static final _accountNumberPattern = RegExp(r'^\d{9,18}$');
  static final _namePattern = RegExp(r"^[A-Za-z][A-Za-z .'-]{1,}$");

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _confirmAccountCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bankCtrl.dispose();
    _accountCtrl.dispose();
    _confirmAccountCtrl.dispose();
    _ifscCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final account = await BankAccountService.addAccount(
        userId: widget.userId,
        accountHolderName: _nameCtrl.text,
        bankName: _bankCtrl.text,
        accountNumber: _accountCtrl.text,
        ifscCode: _ifscCtrl.text,
      );
      if (mounted) Navigator.pop(context, account);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save bank account: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WalletSheetShell(
      title: 'Add Bank Account',
      onClose: () => Navigator.pop(context),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Account Holder Name'),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Required';
                if (!_namePattern.hasMatch(value)) return 'Enter a valid name';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _bankCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Bank Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _accountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Account Number'),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Required';
                if (!_accountNumberPattern.hasMatch(value)) return 'Enter a valid 9–18 digit account number';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmAccountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Confirm Account Number'),
              validator: (v) {
                if ((v ?? '').trim() != _accountCtrl.text.trim()) return 'Account numbers do not match';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _ifscCtrl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                UpperCaseTextFormatter(),
              ],
              decoration: const InputDecoration(labelText: 'IFSC Code', hintText: 'e.g. SBIN0001234'),
              validator: (v) {
                final value = v?.trim().toUpperCase() ?? '';
                if (value.isEmpty) return 'Required';
                if (!_ifscPattern.hasMatch(value)) return 'Enter a valid 11-character IFSC code';
                return null;
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Bank Account', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step 3: Confirm ───────────────────────────────────────────────────────────

class _ConfirmWithdrawalSheet extends StatelessWidget {
  final double amount;
  final BankAccount account;
  const _ConfirmWithdrawalSheet({required this.amount, required this.account});

  /// Next business day (skips weekends) — matches the "1 working day"
  /// settlement claim shown here and on the amount step.
  DateTime get _settlementDate {
    var d = DateTime.now().add(const Duration(days: 1));
    while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  String get _settlementLabel {
    final now = DateTime.now();
    final d = _settlementDate;
    final isTomorrow = d.difference(DateTime(now.year, now.month, now.day)).inDays == 1;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return isTomorrow ? 'tomorrow 3:00 PM' : '${d.day} ${months[d.month - 1]}, 3:00 PM';
  }

  @override
  Widget build(BuildContext context) {
    return WalletSheetShell(
      title: 'Confirm Withdrawal',
      onClose: () => Navigator.pop(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                _DetailRow('Withdrawal Amount', '₹${amount.toStringAsFixed(0)}', valueColor: AppColors.primary, bold: true),
                _DetailRow('Bank Account', account.bankName),
                _DetailRow('Account Number', account.maskedAccountNumber),
                _DetailRow('IFSC Code', account.ifscCode),
                _DetailRow('Settlement', '1 Working Day'),
                _DetailRow('Charges', '₹0 (Free)', last: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 12, color: AppColors.success, height: 1.5),
                      children: [
                        const TextSpan(text: 'Funds will be credited to your bank account by '),
                        TextSpan(text: _settlementLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const TextSpan(text: '. You will receive an SMS confirmation.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, _kBack),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0D0D0D),
                      side: const BorderSide(color: Color(0xFFE0E0E0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Back', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, 'confirmed'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Confirm Withdrawal',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;
  final bool last;
  const _DetailRow(this.label, this.value, {this.valueColor, this.bold = false, this.last = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFF757575))),
          Text(value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                color: valueColor ?? const Color(0xFF0D0D0D),
              )),
        ],
      ),
    );
  }
}

// ─── Step 4: Processing → success ─────────────────────────────────────────────

Widget _buildWithdrawalProcessingSheet(BuildContext context, double amount, BankAccount account) {
  return WalletProcessingSheet(
    processingTitle: 'Processing Withdrawal',
    processingMessage: 'Please wait while we submit your withdrawal request...',
    action: () async {
      final appScope = AppScope.of(context);
      final user = appScope.notifier?.user;
      if (user == null) throw Exception('You need to be signed in to withdraw funds.');

      await appScope.firestoreService.addDocument('withdrawal_requests', {
        'userId': user.uid,
        'userName': user.name,
        'amount': amount,
        'bankAccount': '${account.bankName} ${account.maskedAccountNumber} · IFSC: ${account.ifscCode}',
        'upiId': '',
        'remarks': '',
        'status': 'PENDING',
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });
      return null;
    },
    successTitle: 'Request Submitted',
    errorMessage: (e) => 'Could not submit withdrawal request: $e',
    successBuilder: (context, result) => Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('₹${amount.toStringAsFixed(0)} withdrawal pending approval',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0D0D0D))),
        const SizedBox(height: 8),
        const Text(
          'Your withdrawal request has been submitted and is pending admin approval. '
          'You will be notified once it is processed.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: Color(0xFF757575), height: 1.5),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Done', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ],
    ),
  );
}
