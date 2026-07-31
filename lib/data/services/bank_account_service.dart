import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/trading_models.dart';

/// CRUD for a user's saved bank accounts — the `bank_accounts` collection,
/// filtered by userId like every other wallet-adjacent collection
/// (deposit_requests, withdrawal_requests, ledger).
class BankAccountService {
  BankAccountService._();

  static Stream<List<BankAccount>> streamForUser(String userId) {
    return FirebaseFirestore.instance
        .collection('bank_accounts')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => BankAccount.fromFirestore(d.id, d.data()))
            .toList());
  }

  /// Adds a new bank account and returns it (so callers can auto-select the
  /// newly created account without waiting on the stream to catch up). The
  /// very first account a user saves is automatically marked primary; later
  /// ones default to non-primary. Throws if this account number is already
  /// saved for this user.
  static Future<BankAccount> addAccount({
    required String userId,
    required String accountHolderName,
    required String bankName,
    required String accountNumber,
    required String ifscCode,
  }) async {
    final db = FirebaseFirestore.instance;
    final trimmedAccountNumber = accountNumber.trim();
    final existing = await db
        .collection('bank_accounts')
        .where('userId', isEqualTo: userId)
        .get();

    final alreadySaved = existing.docs.any(
      (d) => (d.data()['accountNumber'] as String?) == trimmedAccountNumber,
    );
    if (alreadySaved) {
      throw Exception('This account number is already saved.');
    }
    final isPrimary = existing.docs.isEmpty;

    final data = {
      'userId': userId,
      'accountHolderName': accountHolderName.trim(),
      'bankName': bankName.trim(),
      'accountNumber': accountNumber.trim(),
      'ifscCode': ifscCode.trim().toUpperCase(),
      'isPrimary': isPrimary,
      'createdAt': Timestamp.now(),
    };
    final ref = await db.collection('bank_accounts').add(data);
    return BankAccount(
      id: ref.id,
      userId: userId,
      accountHolderName: accountHolderName.trim(),
      bankName: bankName.trim(),
      accountNumber: accountNumber.trim(),
      ifscCode: ifscCode.trim().toUpperCase(),
      isPrimary: isPrimary,
      createdAt: DateTime.now(),
    );
  }
}
