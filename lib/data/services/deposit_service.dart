// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../config/backend_config.dart';
import 'backend_api_service.dart';

/// Encapsulates the deposit-request write and its side effects (submission
/// notification) so screens stay free of Firestore/HTTP wiring. The user is
/// never asked for a UTR/reference — a short reference code is derived from
/// the request's own document ID and silently embedded in the UPI payment
/// note, giving admin something to match against their bank statement
/// without any manual entry.
class DepositService {
  DepositService._();

  static final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);

  /// Pre-allocates a `deposit_requests` document reference (no write yet) so
  /// the reference code can be embedded in the UPI note shown to the user
  /// *before* they pay, while the actual PENDING document is only created
  /// once payment is asserted (app-resume detection or the manual fallback).
  static DocumentReference<Map<String, dynamic>> prepareRef(FirebaseFirestore db) {
    return db.collection('deposit_requests').doc();
  }

  /// Short, human-glanceable code derived from the doc ID — e.g. `TK-4F92A1`.
  static String referenceCodeFor(DocumentReference ref) {
    return 'TK-${ref.id.substring(0, 6).toUpperCase()}';
  }

  /// Each UPI app registers its own custom URL scheme so a link can be routed
  /// straight to it. Without this, every method falls back to the generic
  /// `upi://` intent and the OS (not the user's chosen app) decides what
  /// opens — the same app every time, regardless of which button was tapped.
  static String schemeForMethod(String paymentMethod) {
    switch (paymentMethod) {
      case 'gpay':
        return 'tez';
      case 'phonepe':
        return 'phonepe';
      case 'paytm':
        return 'paytmmp';
      default:
        return 'upi'; // 'upi' (any app) and 'bank_transfer' both use the generic intent.
    }
  }

  /// Builds a UPI pay intent URI on the given [scheme] (defaults to the
  /// generic `upi://pay`, understood by every UPI app and used for the QR
  /// code). Pass [schemeForMethod] to target one specific app instead.
  /// Transaction note carries the reference code so it shows up in the
  /// user's payment app and, usually, in the receiving bank statement — with
  /// zero typing required from them.
  static String buildUpiUri({
    required String upiId,
    required String merchantName,
    required double amount,
    required String referenceCode,
    String scheme = 'upi',
  }) {
    final params = {
      'pa': upiId,
      'pn': merchantName,
      'am': amount.toStringAsFixed(2),
      'cu': 'INR',
      'tn': referenceCode,
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    // Google Pay's deep link is registered at tez://upi/pay, not tez://pay —
    // every other scheme (generic upi, phonepe, paytmmp) uses a bare /pay
    // path. Hitting the wrong path still opens the app (it owns the tez://
    // scheme broadly) but lands on its home screen instead of the prefilled
    // payment confirmation, which is why "Google Pay opens but nothing is
    // filled in" happened.
    final path = scheme == 'tez' ? 'upi/pay' : 'pay';
    return '$scheme://$path?$query';
  }

  /// Best-effort deep link into a UPI app. Silently no-ops on platforms that
  /// don't understand the scheme (desktop browsers, iOS Safari) — the QR
  /// code remains the guaranteed path to pay.
  static void launchUpiUri(String upiUri) {
    html.window.open(upiUri, '_self');
  }

  static String get _appVersion =>
      const String.fromEnvironment('APP_BUILD_ID', defaultValue: 'dev');

  static String get _device {
    try {
      final ua = html.window.navigator.userAgent;
      return ua.length > 120 ? ua.substring(0, 120) : ua;
    } catch (_) {
      return 'web';
    }
  }

  /// Creates the PENDING deposit request document and fires the
  /// "request submitted" in-app notification. Called the moment payment is
  /// asserted (app-resume detection or the manual "I've Paid" fallback) —
  /// never earlier, so no request is created for a payment screen the user
  /// simply backed out of.
  static Future<void> createDepositRequest({
    required DocumentReference<Map<String, dynamic>> ref,
    required String userId,
    required String userName,
    required String email,
    required String phone,
    required double amount,
    required String paymentMethod,
    required String referenceCode,
  }) async {
    await ref.set({
      'depositId':     ref.id,
      'userId':        userId,
      'userName':      userName,
      'email':         email,
      'phone':         phone,
      'amount':        amount,
      'paymentMethod': paymentMethod,
      'referenceCode': referenceCode,
      'device':        _device,
      'platform':      'web',
      'appVersion':    _appVersion,
      'status':        'PENDING',
      'createdAt':     Timestamp.now(),
      'updatedAt':     Timestamp.now(),
    });

    try {
      await _api.sendNotificationToUserId(
        userId: userId,
        title: 'Deposit Request Submitted',
        message: 'Your deposit request of ₹${amount.toStringAsFixed(2)} has been submitted and is pending verification.',
        data: {'type': 'deposit_pending', 'depositId': ref.id},
      );
    } catch (_) {
      // Non-fatal — the request itself is already saved; notification is best-effort.
    }
  }
}
