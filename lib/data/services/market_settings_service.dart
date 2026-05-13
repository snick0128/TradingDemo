/// Market Settings Service
///
/// Streams the Firestore marketSettings/config document in real-time.
/// Admin changes apply immediately to all connected clients.
///
/// Usage:
///   final service = MarketSettingsService();
///   service.stream.listen((settings) { ... });
///   await service.update(settings); // admin only
library;

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/market_settings.dart';

class MarketSettingsService {
  static const _collection = 'marketSettings';
  static const _docId = 'config';

  final FirebaseFirestore _db;

  MarketSettingsService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _ref =>
      _db.collection(_collection).doc(_docId);

  /// Real-time stream of market settings.
  /// Emits [MarketSettings.defaults] immediately if the doc doesn't exist yet.
  Stream<MarketSettings> get stream => _ref.snapshots().map((snap) {
    if (!snap.exists || snap.data() == null) {
      return MarketSettings.defaults;
    }
    try {
      return MarketSettings.fromMap(snap.data()!);
    } catch (_) {
      return MarketSettings.defaults;
    }
  });

  /// Fetch once (for admin panel initial load).
  Future<MarketSettings> fetch() async {
    final snap = await _ref.get();
    if (!snap.exists || snap.data() == null) return MarketSettings.defaults;
    return MarketSettings.fromMap(snap.data()!);
  }

  /// Write full settings to Firestore (admin only).
  Future<void> update(MarketSettings settings) =>
      _ref.set(settings.toMap(), SetOptions(merge: false));

  /// Update a single segment (stocks or mcx).
  Future<void> updateSegment(String segment, Map<String, dynamic> data) =>
      _ref.set({segment: data}, SetOptions(merge: true));
}
