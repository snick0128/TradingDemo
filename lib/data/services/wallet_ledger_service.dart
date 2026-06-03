import 'package:cloud_firestore/cloud_firestore.dart';

/// Reusable helpers for writing wallet ledger + audit log entries inside
/// Firestore transactions.  All methods are pure transaction writers — they
/// do NOT start a new transaction themselves so callers can compose them.
class WalletLedgerService {
  // ── Ledger entry ─────────────────────────────────────────────────────────────

  /// Write a ledger entry inside [tx].  Returns the new document reference.
  static DocumentReference writeLedgerEntry(
    Transaction tx,
    FirebaseFirestore db, {
    required String userId,
    required String type,
    double credit = 0,
    double debit = 0,
    required double balanceBefore,
    required double balanceAfter,
    String referenceId = '',
    String referenceType = '',
    String remarks = '',
    String createdBy = '',
  }) {
    final ref = db.collection('ledger').doc();
    tx.set(ref, {
      'userId':        userId,
      'type':          type,
      'amount':        credit > 0 ? credit : debit,
      'credit':        credit,
      'debit':         debit,
      'balanceBefore': balanceBefore,
      'balanceAfter':  balanceAfter,
      'referenceId':   referenceId,
      'referenceType': referenceType,
      'remarks':       remarks,
      'createdBy':     createdBy,
      'createdAt':     Timestamp.now(),
    });
    return ref;
  }

  // ── Audit log ─────────────────────────────────────────────────────────────────

  /// Write an audit log entry inside [tx].
  static void writeAuditLog(
    Transaction tx,
    FirebaseFirestore db, {
    required String action,
    required String userId,
    String adminId = 'SYSTEM',
    required double balanceBefore,
    required double balanceAfter,
    required double amount,
    String referenceId = '',
    String referenceType = '',
    String remarks = '',
  }) {
    final ref = db.collection('audit_logs').doc();
    tx.set(ref, {
      'action':        action,
      'userId':        userId,
      'adminId':       adminId,
      'balanceBefore': balanceBefore,
      'balanceAfter':  balanceAfter,
      'amount':        amount,
      'referenceId':   referenceId,
      'referenceType': referenceType,
      'remarks':       remarks,
      'timestamp':     Timestamp.now(),
    });
  }
}
