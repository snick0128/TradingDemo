import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../domain/pricing/price_provider.dart';
import 'firestore_service.dart';

/// Production-grade execution engine.
///
/// Firestore schema:
///   users/{uid}
///     available_balance, reserved_balance, tradingEnabled
///
///   orders/{clientOrderId}           ← deterministic doc ID = clientOrderId
///     userId, stock, type, qty, price, executed_price, total
///     status: EXECUTED | FAILED
///     execution_meta: { attempt, lastError, source }
///     createdAt, executedAt
///
///   portfolios/{uid}/holdings/{stock}
///     qty, avg_price, last_price, unrealized_pnl, updatedAt
///
///   ledger/{entryId}
///     userId, type, subType, amount, before_balance, balance_after,
///     referenceType, referenceId, stock, qty, price, createdAt
///
///   trades/{tradeId}
///     orderId, userId, stock, type, qty, price, total, createdAt
///
///   trade_feed/{tradeId}             ← denormalized admin feed (same ID as trade)
///     userId, stock, type, qty, price, total, createdAt
///
///   audit_logs/{logId}
///     action, adminId, targetId, metadata, timestamp
///
/// Fixes applied (Phase 1 + 2):
///   1. addBalance ledger write is inside the same transaction (atomic)
///   2. clientOrderId is required — UI must generate it (cross-tab idempotency)
///   3. globalTradingHalt read inside transaction before execution
///   4. stocks/{symbol}.tradable checked inside transaction
///   5. approveOrder / rejectOrder removed (auto-execution model)
///   6. Transaction body is pure — no external calls, no randomness inside
///   7. All doc IDs pre-computed outside transaction
///   8. avg_price field name standardized (snake_case everywhere)
///   9. In-flight guard REMOVED (was causing deadlocks on Firestore errors)
///   10. Firestore retry logic added for internal assertion failures
class TradingService {
  TradingService({
    required FirestoreService firestore,
    required PriceProvider priceProvider,
  }) : _firestore = firestore,
       _priceProvider = priceProvider;

  final FirestoreService _firestore;
  final PriceProvider _priceProvider;
  final _uuid = const Uuid();
  static const int _defaultMaxFillQtyPerTick = 250;

  /// Retry wrapper for Firestore operations that may hit internal assertion failures.
  /// Uses exponential backoff with up to 3 attempts.
  Future<T> _retryFirestore<T>(Future<T> Function() fn) async {
    const delays = [300, 800, 2000]; // ms between attempts
    Object? lastError;
    for (int attempt = 0; attempt <= delays.length; attempt++) {
      try {
        return await fn();
      } catch (e) {
        lastError = e;
        final errorStr = e.toString();
        final isRetryable =
            errorStr.contains('ASSERTION') ||
            errorStr.contains('WatchChangeAggregator') ||
            errorStr.contains('PersistentListenStream') ||
            errorStr.contains('Transaction failed:') ||
            errorStr.contains('UNAVAILABLE') ||
            errorStr.contains('INTERNAL');
        if (!isRetryable || attempt == delays.length) rethrow;
        await Future.delayed(Duration(milliseconds: delays[attempt]));
      }
    }
    throw lastError!;
  }

  // ── Streams ────────────────────────────────────────────────────────────────

  Stream<QuerySnapshot<Map<String, dynamic>>> ordersStreamForUser(String uid) =>
      _firestore.raw
          .collection('orders')
          .where('userId', isEqualTo: uid)
          .limit(100)
          .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> gttOrdersStreamForUser(
    String uid,
  ) => _firestore.raw
      .collection('gtt_orders')
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> tradesStreamForUser(String uid) =>
      _firestore.raw
          .collection('trades')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> holdingsStreamForUser(
    String uid,
  ) => _firestore.getCollectionStream('portfolios/$uid/holdings');

  Stream<QuerySnapshot<Map<String, dynamic>>> ledgerStreamForUser(String uid) =>
      _firestore.raw
          .collection('ledger')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> usersStream() => _firestore.raw
      .collection('users')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> ordersStream() => _firestore.raw
      .collection('orders')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> orderRequestsStream() =>
      _firestore.raw
          .collection('order_requests')
          .where('status', isEqualTo: 'QUEUED')
          .snapshots();

  /// Live trade feed for admin — denormalized, no joins needed.
  Stream<QuerySnapshot<Map<String, dynamic>>> tradeFeedStream() => _firestore
      .raw
      .collection('trade_feed')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots();

  // Intraday/net positions are stored separately from delivery holdings.
  Stream<QuerySnapshot<Map<String, dynamic>>> positionsStreamForUser(
    String uid,
  ) => _firestore.getCollectionStream('portfolios/$uid/positions');

  // ── Place Order ────────────────────────────────────────────────────────────

  /// Customer-side order submission.
  ///
  /// This method only writes to `order_requests/{clientOrderId}`.
  /// Financial execution is performed by an admin-side processor via
  /// [processOrderRequest].
  ///
  /// [clientOrderId] is a deterministic idempotency key generated by UI.
  Future<String> placeOrder({
    required String userId,
    required String stock,
    required int qty,
    required String type,
    String variety = 'MARKET',
    String product = 'MIS',
    String validity = 'DAY',
    double? price,
    double? triggerPrice,
    required String clientOrderId,
  }) async {
    if (qty <= 0) throw Exception('Quantity must be greater than zero.');

    final symbol = stock.toUpperCase();
    final side = type.toUpperCase();
    final orderVariety = _normalizeVariety(variety);
    final orderProduct = _normalizeProduct(product);
    final orderValidity = _normalizeValidity(validity);

    if (side != 'BUY' && side != 'SELL') {
      throw Exception('Order type must be BUY or SELL.');
    }
    _validateOrderInputs(
      variety: orderVariety,
      price: price,
      triggerPrice: triggerPrice,
    );

    // Use client-side Timestamp.now() instead of FieldValue.serverTimestamp().
    // FieldValue sentinels cause a JS interop error on Firestore Web SDK 11.x.
    // Timestamp.now() is accurate enough for the order request queue.
    final now = Timestamp.now();

    // Do NOT wrap set() in _retryFirestore — the generic void return causes
    // a Dart→JS interop error. Call directly with manual retry.
    Exception? lastError;
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        print(
          '[TradingService] Placing order request for $userId: $symbol $qty@$price (Attempt ${attempt + 1})',
        );

        final docRef = _firestore.raw
            .collection('order_requests')
            .doc(clientOrderId);

        // Use a simple get() then set() to avoid runTransaction interop issues on Web.
        // clientOrderId is a unique UUID per click, so race conditions are minimal.
        final snap = await docRef.get();
        if (snap.exists) {
          print(
            '[TradingService] Order request $clientOrderId already exists. Skipping write.',
          );
          return clientOrderId;
        }

        await docRef.set({
          'clientOrderId': clientOrderId,
          'userId': userId,
          'stock': symbol,
          'type': side,
          'qty': qty,
          'variety': orderVariety,
          'product': orderProduct,
          'validity': orderValidity,
          'price': price,
          'triggerPrice': triggerPrice,
          'status': 'QUEUED',
          'attempt': 0,
          'source': 'CUSTOMER_APP',
          'createdAt': now,
          'updatedAt': now,
        });

        print(
          '[TradingService] Order request created successfully: $clientOrderId',
        );
        return clientOrderId;
      } catch (e) {
        print('[TradingService] Order request failed: $e');
        final msg = e.toString();
        final retryable =
            msg.contains('UNAVAILABLE') ||
            msg.contains('INTERNAL') ||
            msg.contains('WatchChangeAggregator');
        if (!retryable || attempt == 2) {
          rethrow;
        }
        lastError = Exception(msg);
        await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    throw lastError ?? Exception('Order submission failed.');
  }

  // ── Instant Execution (Direct Transaction) ──────────────────────────────

  Future<void> buyStock({
    required String userId,
    required String stock,
    required int qty,
    required double price,
  }) async {
    final total = qty * price;
    final symbol = stock.toUpperCase();

    final userRef = _firestore.raw.doc('users/$userId');
    final holdingRef = _firestore.raw.doc(
      'portfolios/$userId/holdings/$symbol',
    );
    final orderRef = _firestore.raw.collection('orders').doc();

    await _firestore.raw.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      final userData = userSnap.data() ?? {};
      final balance = _double(
        userData['balance'] ?? userData['available_balance'],
      );

      if (balance < total) {
        throw Exception(
          "Insufficient balance. Required: ₹${total.toStringAsFixed(2)}, Available: ₹${balance.toStringAsFixed(2)}",
        );
      }

      final holdingSnap = await tx.get(holdingRef);
      final holdingData = holdingSnap.data() ?? {};
      final oldQty = _int(holdingData['qty']);
      final oldAvg = _double(holdingData['avg_price']);

      final newQty = oldQty + qty;
      final newAvg = newQty == 0
          ? 0.0
          : ((oldQty * oldAvg) + (qty * price)) / newQty;

      tx.update(userRef, {
        'balance': balance - total,
        'available_balance': balance - total,
        'updatedAt': Timestamp.now(),
      });

      tx.set(holdingRef, {
        'qty': newQty,
        'avg_price': newAvg,
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));

      tx.set(orderRef, {
        'userId': userId,
        'stock': symbol,
        'qty': qty,
        'price': price,
        'type': 'BUY',
        'status': 'EXECUTED',
        'createdAt': Timestamp.now(),
      });
    });
  }

  Future<void> sellStock({
    required String userId,
    required String stock,
    required int qty,
    required double price,
  }) async {
    final total = qty * price;
    final symbol = stock.toUpperCase();

    final userRef = _firestore.raw.doc('users/$userId');
    final holdingRef = _firestore.raw.doc(
      'portfolios/$userId/holdings/$symbol',
    );
    final orderRef = _firestore.raw.collection('orders').doc();

    await _firestore.raw.runTransaction((tx) async {
      final holdingSnap = await tx.get(holdingRef);

      if (!holdingSnap.exists) {
        throw Exception("No holdings found for $symbol");
      }

      final holdingData = holdingSnap.data() ?? {};
      final currentQty = _int(holdingData['qty']);

      if (currentQty < qty) {
        throw Exception(
          "Not enough shares. You have $currentQty, trying to sell $qty.",
        );
      }

      final userSnap = await tx.get(userRef);
      final userData = userSnap.data() ?? {};
      final balance = _double(
        userData['balance'] ?? userData['available_balance'],
      );

      final newQty = currentQty - qty;

      if (newQty == 0) {
        tx.delete(holdingRef);
      } else {
        tx.update(holdingRef, {'qty': newQty, 'updatedAt': Timestamp.now()});
      }

      tx.update(userRef, {
        'balance': balance + total,
        'available_balance': balance + total,
        'updatedAt': Timestamp.now(),
      });

      tx.set(orderRef, {
        'userId': userId,
        'stock': symbol,
        'qty': qty,
        'price': price,
        'type': 'SELL',
        'status': 'EXECUTED',
        'createdAt': Timestamp.now(),
      });
    });
  }

  /// Admin-side execution path for queued requests.
  Future<bool> processOrderRequest(
    String requestId, {
    String processorId = 'SYSTEM',
  }) async {
    final requestRef = _firestore.raw.doc('order_requests/$requestId');
    final now = Timestamp.now();

    final claimed = await _retryFirestore(
      () => _firestore.raw.runTransaction((tx) async {
        print('[TradingService] Attempting to claim request: $requestId');
        final requestSnap = await tx.get(requestRef);
        if (!requestSnap.exists) {
          print('[TradingService] Request not found: $requestId');
          return false;
        }
        final requestData = requestSnap.data() ?? {};
        final status = (requestData['status'] as String?)?.toUpperCase() ?? '';
        final processedAt = requestData['processedAt'];

        // IDEMPOTENCY: Don't process if already COMPLETED, FAILED, or currently PROCESSING by another node.
        if (status != 'QUEUED' || processedAt != null) {
          print(
            '[TradingService] Request $requestId skip: status=$status, processedAt=$processedAt',
          );
          return false;
        }

        tx.update(requestRef, {
          'status': 'PROCESSING',
          'attempt': _int(requestData['attempt']) + 1,
          'processorId': processorId,
          'processingStartedAt': now,
          'updatedAt': now,
        });
        print('[TradingService] Request $requestId claimed by $processorId');
        return true;
      }),
    );

    if (!claimed) return false;

    final requestSnap = await requestRef.get();
    if (!requestSnap.exists) return false;
    final requestData = requestSnap.data() ?? {};

    try {
      print('[TradingService] Processing order request $requestId...');
      final orderId = await _executeOrderRequest(
        requestData,
        fallbackOrderId: requestId,
      );
      print(
        '[TradingService] Order request $requestId execution successful: $orderId',
      );

      await requestRef.update({
        'status': 'COMPLETED',
        'orderId': orderId,
        'processedAt': Timestamp.now(),
        'lastError': null,
        'updatedAt': Timestamp.now(),
      });
      return true;
    } catch (e, stack) {
      print('[TradingService] Order request $requestId failed: $e');
      print(stack);

      final retryCount = _int(requestData['attempt']);
      final isRetryable =
          e.toString().contains('Price feed timeout') ||
          e.toString().contains('UNAVAILABLE');

      if (isRetryable && retryCount < 3) {
        print(
          '[TradingService] Transient error for $requestId, resetting to QUEUED for retry.',
        );
        await requestRef.update({
          'status': 'QUEUED',
          'lastError': 'Retryable error: $e',
          'updatedAt': Timestamp.now(),
        });
      } else {
        await _writeFailedOrderFromRequest(
          requestData: requestData,
          fallbackOrderId: requestId,
          error: e.toString(),
        );

        await requestRef.update({
          'status': 'FAILED',
          'lastError': e.toString(),
          'failedAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
        });
      }
      return false;
    }
  }

  Future<String> _executeOrderRequest(
    Map<String, dynamic> requestData, {
    required String fallbackOrderId,
  }) async {
    final userId = (requestData['userId'] as String?)?.trim();
    final symbol = (requestData['stock'] as String?)?.trim().toUpperCase();
    final side = (requestData['type'] as String?)?.trim().toUpperCase();
    final qty = _int(requestData['qty']);
    final orderVariety = _normalizeVariety(
      (requestData['variety'] as String?) ?? 'MARKET',
    );
    final orderProduct = _normalizeProduct(
      (requestData['product'] as String?) ?? 'MIS',
    );
    final orderValidity = _normalizeValidity(
      (requestData['validity'] as String?) ?? 'DAY',
    );
    final price = requestData['price'] is num
        ? (requestData['price'] as num).toDouble()
        : null;
    final triggerPrice = requestData['triggerPrice'] is num
        ? (requestData['triggerPrice'] as num).toDouble()
        : null;
    final orderId =
        (requestData['clientOrderId'] as String?)?.trim().isNotEmpty == true
        ? (requestData['clientOrderId'] as String).trim()
        : fallbackOrderId;

    if (userId == null || userId.isEmpty) {
      throw Exception('Invalid request payload: missing userId.');
    }
    if (symbol == null || symbol.isEmpty) {
      throw Exception('Invalid request payload: missing stock.');
    }
    if (side != 'BUY' && side != 'SELL') {
      throw Exception('Invalid request payload: type must be BUY or SELL.');
    }
    if (qty <= 0) {
      throw Exception(
        'Invalid request payload: qty must be greater than zero.',
      );
    }

    // Promote nullable locals to non-nullable after validation
    final nonNullUserId = userId;
    final nonNullSymbol = symbol;
    final nonNullSide = side!;
    _validateOrderInputs(
      variety: orderVariety,
      price: price,
      triggerPrice: triggerPrice,
    );

    // ── Fetch current market price ───────────────────────────────────────────
    print('[ENGINE] Start execution for $orderId ($nonNullSymbol)');
    print('[ENGINE] Fetching price for $nonNullSymbol...');

    double currentPrice;
    try {
      currentPrice = await _priceProvider
          .getPrice(nonNullSymbol)
          .first
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      print('[ENGINE] Price fetch failed for $nonNullSymbol: $e');
      throw Exception(
        'Live market price unavailable for $nonNullSymbol. '
        'Order rejected to prevent unsafe execution.',
      );
    }

    print('[ENGINE] Execution price determined: $currentPrice');

    if (currentPrice <= 0) throw Exception('Invalid price for $nonNullSymbol.');

    bool shouldExecute = false;
    String? pendingReason;
    double executionPrice = currentPrice;

    if (orderVariety == 'MARKET' || orderVariety == 'ICEBERG') {
      shouldExecute = true;
      executionPrice = currentPrice;
    } else if (orderVariety == 'LIMIT') {
      final limitPrice = price!;
      shouldExecute = nonNullSide == 'BUY'
          ? currentPrice <= limitPrice
          : currentPrice >= limitPrice;
      executionPrice = limitPrice;
      if (!shouldExecute) pendingReason = 'LIMIT_WAIT';
    } else if (orderVariety == 'SL') {
      final trigger = triggerPrice!;
      shouldExecute = nonNullSide == 'BUY'
          ? currentPrice >= trigger
          : currentPrice <= trigger;
      executionPrice = price ?? trigger;
      if (!shouldExecute) pendingReason = 'TRIGGER_WAIT';
    } else if (orderVariety == 'AMO') {
      shouldExecute = _isMarketHours(DateTime.now());
      executionPrice = currentPrice;
      if (!shouldExecute) pendingReason = 'MARKET_CLOSED';
    }

    final priceTimestamp = DateTime.now().millisecondsSinceEpoch;

    final orderRef = _firestore.raw.doc('orders/$orderId');
    final userRef = _firestore.raw.doc('users/$nonNullUserId');
    final inventoryRef = _inventoryRefForOrder(
      userId: nonNullUserId,
      symbol: nonNullSymbol,
      product: orderProduct,
    );
    final configRef = _firestore.raw.doc('admin_config/platform');
    final stockRef = _firestore.raw.doc('stocks/$nonNullSymbol');
    final serverTs = Timestamp.now();
    final tradeId = _uuid.v4();
    final tradeRef = _firestore.raw.doc('trades/$tradeId');
    final tradeFeedRef = _firestore.raw.doc('trade_feed/$tradeId');
    final ledgerId = _uuid.v4();
    final ledgerRef = _firestore.raw.doc('ledger/$ledgerId');

    await _retryFirestore(
      () => _firestore.raw.runTransaction((tx) async {
        final existingOrder = await tx.get(orderRef);
        if (existingOrder.exists) return;

        final configSnap = await tx.get(configRef);
        final configData = configSnap.data() ?? {};
        if ((configData['globalTradingHalt'] as bool?) == true) {
          throw Exception('Trading is currently halted by the platform.');
        }

        final stockSnap = await tx.get(stockRef);
        if (stockSnap.exists) {
          final tradable = (stockSnap.data()?['tradable'] as bool?) ?? true;
          if (!tradable) throw Exception('$nonNullSymbol is not tradable.');
        }

        final userSnap = await tx.get(userRef);
        final userData = userSnap.data() ?? {};
        if (!((userData['tradingEnabled'] as bool?) ?? true)) {
          throw Exception('Trading is disabled for this account.');
        }
        final maxFillQty = _resolveMaxFillQty(configData['maxFillQtyPerTick']);
        final inventorySnap = await tx.get(inventoryRef);

        if (!shouldExecute) {
          _writePendingOrder(
            tx: tx,
            orderRef: orderRef,
            orderId: orderId,
            userId: nonNullUserId,
            symbol: nonNullSymbol,
            type: nonNullSide,
            qty: qty,
            price: price ?? executionPrice,
            triggerPrice: triggerPrice,
            variety: orderVariety,
            product: orderProduct,
            validity: orderValidity,
            pendingReason: pendingReason,
            serverTs: serverTs,
          );
          return;
        }

        final fillQty = qty > maxFillQty ? maxFillQty : qty;
        if (fillQty <= 0) {
          throw Exception('Unable to execute order: zero fill quantity.');
        }
        final fillTotal = fillQty * executionPrice;

        if (nonNullSide == 'BUY') {
          _writeBuy(
            tx: tx,
            userRef: userRef,
            inventoryRef: inventoryRef,
            inventorySnap: inventorySnap,
            orderRef: orderRef,
            tradeRef: tradeRef,
            tradeFeedRef: tradeFeedRef,
            ledgerRef: ledgerRef,
            userData: userData,
            userId: nonNullUserId,
            symbol: nonNullSymbol,
            orderQty: qty,
            fillQty: fillQty,
            previousFilledQty: 0,
            previousFilledValue: 0,
            executedPrice: executionPrice,
            priceTimestamp: priceTimestamp,
            total: fillTotal,
            orderId: orderId,
            serverTs: serverTs,
            product: orderProduct,
            validity: orderValidity,
            variety: orderVariety,
          );
        } else {
          _writeSell(
            tx: tx,
            userRef: userRef,
            inventoryRef: inventoryRef,
            inventorySnap: inventorySnap,
            orderRef: orderRef,
            tradeRef: tradeRef,
            tradeFeedRef: tradeFeedRef,
            ledgerRef: ledgerRef,
            userData: userData,
            userId: nonNullUserId,
            symbol: nonNullSymbol,
            orderQty: qty,
            fillQty: fillQty,
            previousFilledQty: 0,
            previousFilledValue: 0,
            executedPrice: executionPrice,
            priceTimestamp: priceTimestamp,
            total: fillTotal,
            orderId: orderId,
            serverTs: serverTs,
            product: orderProduct,
            validity: orderValidity,
            variety: orderVariety,
          );
        }
      }),
    );

    return orderId;
  }

  Future<void> _writeFailedOrderFromRequest({
    required Map<String, dynamic> requestData,
    required String fallbackOrderId,
    required String error,
  }) async {
    final orderId =
        (requestData['clientOrderId'] as String?)?.trim().isNotEmpty == true
        ? (requestData['clientOrderId'] as String).trim()
        : fallbackOrderId;
    final userId = (requestData['userId'] as String?) ?? 'UNKNOWN';
    final symbol = (requestData['stock'] as String?)?.toUpperCase() ?? 'N/A';
    final side = (requestData['type'] as String?)?.toUpperCase() ?? 'BUY';
    final qty = _int(requestData['qty']);
    final price = _double(requestData['price']);
    final variety = _normalizeVariety(
      (requestData['variety'] as String?) ?? 'MARKET',
    );
    final product = _normalizeProduct(
      (requestData['product'] as String?) ?? 'MIS',
    );
    final validity = _normalizeValidity(
      (requestData['validity'] as String?) ?? 'DAY',
    );
    final orderRef = _firestore.raw.doc('orders/$orderId');

    await _retryFirestore(
      () => _firestore.raw.runTransaction((tx) async {
        final existing = await tx.get(orderRef);
        if (existing.exists) return;

        tx.set(orderRef, {
          'clientOrderId': orderId,
          'userId': userId,
          'stock': symbol,
          'type': side,
          'qty': qty,
          'price': price,
          'variety': variety,
          'product': product,
          'validity': validity,
          'total': qty * price,
          'filled_qty': 0,
          'remaining_qty': qty,
          'status': 'FAILED',
          'rejectionReason': error,
          'rejectedAt': Timestamp.now(),
          'execution_meta': {
            'attempt': 1,
            'lastError': error,
            'source': 'ADMIN_ENGINE',
          },
          'createdAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
        });
      }),
    );
  }

  // ── Cancel Order ──────────────────────────────────────────────────────────

  Future<void> cancelOrder(String orderId) async {
    final orderRef = _firestore.raw.doc('orders/$orderId');
    await _retryFirestore(
      () => _firestore.raw.runTransaction((tx) async {
        final snap = await tx.get(orderRef);
        if (!snap.exists) throw Exception('Order not found.');
        final data = snap.data() ?? {};
        final status = (data['status'] as String?)?.toUpperCase() ?? '';
        if (status != 'PENDING' && status != 'PARTIALLY_EXECUTED') {
          throw Exception('Only open orders can be cancelled.');
        }
        tx.update(orderRef, {
          'status': 'CANCELLED',
          'cancelledAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
        });
      }),
    );
  }

  // ── GTT Orders ────────────────────────────────────────────────────────────

  Future<String> placeGttOrder({
    required String userId,
    required String symbol,
    required String gttType,
    required double triggerPrice,
    double? secondTriggerPrice,
    required String side,
    required int qty,
    double? limitPrice,
  }) async {
    final id = _uuid.v4();

    await _firestore.setDocument('gtt_orders/$id', {
      'userId': userId,
      'symbol': symbol.toUpperCase(),
      'type': gttType.toUpperCase(),
      'triggerPrice': triggerPrice,
      'secondTriggerPrice': secondTriggerPrice,
      'orderType': side.toUpperCase(),
      'quantity': qty,
      'limitPrice': limitPrice,
      'isActive': true,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });

    return id;
  }

  Future<void> cancelGttOrder(String gttId) async {
    await _firestore.deleteDocument('gtt_orders/$gttId');
  }

  Future<void> processGttTrigger(String gttId, double currentPrice) async {
    final gttRef = _firestore.raw.doc('gtt_orders/$gttId');

    await _retryFirestore(
      () => _firestore.raw.runTransaction((tx) async {
        final gttSnap = await tx.get(gttRef);
        if (!gttSnap.exists) return;

        final data = gttSnap.data()!;
        if (!(data['isActive'] as bool)) return;

        final userId = data['userId'] as String;
        final symbol = data['symbol'] as String;
        final triggerPrice = _double(data['triggerPrice']);
        final secondTrigger = _double(data['secondTriggerPrice']);
        final type = data['type'] as String;
        final side = data['orderType'] as String;
        final qty = data['quantity'] as int;
        final limitPrice = _double(data['limitPrice']);

        bool triggered = false;
        if (type == 'SINGLE') {
          if (side == 'BUY') {
            triggered = currentPrice <= triggerPrice;
          } else {
            triggered = currentPrice >= triggerPrice;
          }
        } else if (type == 'OCO') {
          if (side == 'BUY') {
            triggered =
                currentPrice <= triggerPrice || currentPrice >= secondTrigger;
          } else {
            triggered =
                currentPrice >= triggerPrice || currentPrice <= secondTrigger;
          }
        }

        if (!triggered) return;

        // Mark GTT as triggered
        tx.update(gttRef, {
          'isActive': false,
          'triggeredAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
        });

        // Place actual order - Note: we can't call placeOrder inside a transaction
        // because placeOrder starts its own transaction.
        // Instead, we manually write a PENDING order doc.
        final orderId = 'ORD-GTT-${_uuid.v4()}';
        final orderRef = _firestore.raw.doc('orders/$orderId');

        _writePendingOrder(
          tx: tx,
          orderRef: orderRef,
          orderId: orderId,
          userId: userId,
          symbol: symbol,
          type: side,
          qty: qty,
          price: limitPrice > 0 ? limitPrice : currentPrice,
          triggerPrice: null,
          variety: limitPrice > 0 ? 'LIMIT' : 'MARKET',
          product: 'MIS',
          validity: 'DAY',
          pendingReason: 'GTT_TRIGGERED',
          serverTs: Timestamp.now(),
        );
      }),
    );
  }

  // ── BUY (pure — synchronous, no external calls) ───────────────────────────

  void _writeBuy({
    required Transaction tx,
    required DocumentReference userRef,
    required DocumentReference inventoryRef,
    required DocumentSnapshot inventorySnap,
    required DocumentReference orderRef,
    required DocumentReference tradeRef,
    required DocumentReference tradeFeedRef,
    required DocumentReference ledgerRef,
    required Map<String, dynamic> userData,
    required String userId,
    required String symbol,
    required int orderQty,
    required int fillQty,
    required int previousFilledQty,
    required double previousFilledValue,
    required double executedPrice,
    required int priceTimestamp,
    required double total,
    required String orderId,
    required Object serverTs,
    required String product,
    required String validity,
    String variety = 'MARKET',
  }) {
    final available = _balance(userData);
    final marginRequired = _requiredMargin(total, product);

    if (available < marginRequired) {
      throw Exception(
        'Insufficient balance. Required ₹${marginRequired.toStringAsFixed(2)}, '
        'available ₹${available.toStringAsFixed(2)}.',
      );
    }

    final balanceAfter = available - marginRequired;

    // Wallet
    tx.update(userRef, {
      'available_balance': balanceAfter,
      'balance': balanceAfter,
      'updatedAt': serverTs,
    });

    final inventoryData = inventorySnap.data() as Map<String, dynamic>?;
    final oldQty = _int(inventoryData?['qty']);
    final oldAvg = _double(inventoryData?['avg_price']);
    final newQty = oldQty + fillQty;
    final newAvg = newQty == 0
        ? 0.0
        : ((oldQty * oldAvg) + (fillQty * executedPrice)) / newQty;
    final unrealizedPnl = (executedPrice - newAvg) * newQty;
    final isIntraday = _isIntradayProduct(product);

    tx.set(inventoryRef, {
      'stock': symbol,
      'product': product,
      'qty': newQty,
      'avg_price': _safeDouble(newAvg),
      if (isIntraday) 'side': 'BUY',
      'last_price': executedPrice,
      'unrealized_pnl': _safeDouble(unrealizedPnl),
      'updatedAt': serverTs,
    }, SetOptions(merge: true));

    final filledQty = previousFilledQty + fillQty;
    final filledValue = previousFilledValue + total;
    final remainingQty = orderQty - filledQty;
    final avgExecutedPrice = filledQty == 0 ? 0.0 : filledValue / filledQty;
    final status = remainingQty > 0 ? 'PARTIALLY_EXECUTED' : 'EXECUTED';
    final orderMap = <String, dynamic>{
      'clientOrderId': orderId,
      'userId': userId,
      'stock': symbol,
      'type': 'BUY',
      'qty': orderQty,
      'price': executedPrice,
      'product': product,
      'validity': validity,
      'variety': variety,
      'executed_price': _safeDouble(avgExecutedPrice),
      'avg_executed_price': _safeDouble(avgExecutedPrice),
      'filled_qty': filledQty,
      'remaining_qty': remainingQty,
      'last_fill_qty': fillQty,
      'last_fill_price': executedPrice,
      'filled_total': _safeDouble(filledValue),
      'total': _safeDouble(filledValue),
      'price_timestamp': priceTimestamp,
      'status': status,
      'pending_reason': remainingQty > 0 ? 'PENDING_REMAINING_QTY' : null,
      'execution_meta': {
        'attempt': 1,
        'lastError': null,
        'source': 'ADMIN_ENGINE',
      },
      'updatedAt': serverTs,
      if (remainingQty == 0) 'executedAt': serverTs,
      if (previousFilledQty == 0) 'createdAt': serverTs,
    };
    tx.set(orderRef, orderMap, SetOptions(merge: true));

    tx.set(tradeRef, {
      'orderId': orderId,
      'userId': userId,
      'stock': symbol,
      'type': 'BUY',
      'qty': fillQty,
      'price': executedPrice,
      'total': total,
      'createdAt': serverTs,
    });

    tx.set(tradeFeedRef, {
      'orderId': orderId,
      'userId': userId,
      'stock': symbol,
      'type': 'BUY',
      'qty': fillQty,
      'price': executedPrice,
      'total': total,
      'createdAt': serverTs,
    });

    tx.set(ledgerRef, {
      'userId': userId,
      'type': 'DEBIT',
      'subType': 'BUY',
      'amount': marginRequired,
      'trade_value': total,
      'before_balance': available,
      'balance_after': balanceAfter,
      'referenceType': 'ORDER',
      'referenceId': orderId,
      'stock': symbol,
      'qty': fillQty,
      'price': executedPrice,
      'createdAt': serverTs,
    });
  }

  // ── SELL (pure) ────────────────────────────────────────────────────────────

  void _writeSell({
    required Transaction tx,
    required DocumentReference userRef,
    required DocumentReference inventoryRef,
    required DocumentSnapshot inventorySnap,
    required DocumentReference orderRef,
    required DocumentReference tradeRef,
    required DocumentReference tradeFeedRef,
    required DocumentReference ledgerRef,
    required Map<String, dynamic> userData,
    required String userId,
    required String symbol,
    required int orderQty,
    required int fillQty,
    required int previousFilledQty,
    required double previousFilledValue,
    required double executedPrice,
    required int priceTimestamp,
    required double total,
    required String orderId,
    required Object serverTs,
    required String product,
    required String validity,
    String variety = 'MARKET',
  }) {
    final inventoryData = inventorySnap.data() as Map<String, dynamic>?;
    final currentQty = _int(inventoryData?['qty']);
    final isIntraday = _isIntradayProduct(product);
    final existingSide =
        (inventoryData?['side'] as String?)?.trim().toUpperCase() ?? 'BUY';
    final available = _balance(userData);
    double balanceAfter;
    double realizedPnl = 0;
    String ledgerType;
    String ledgerSubType;
    double ledgerAmount;

    if (!isIntraday && currentQty < fillQty) {
      throw Exception(
        'Insufficient holdings. You have $currentQty shares of $symbol, '
        'tried to sell $fillQty.',
      );
    }

    final avgPrice = _double(inventoryData?['avg_price']);
    if (isIntraday && (existingSide == 'SELL' || currentQty < fillQty)) {
      final closingLongQty = existingSide == 'BUY'
          ? (currentQty < fillQty ? currentQty : fillQty)
          : 0;
      final shortQty = fillQty - closingLongQty;
      final marginRequired = _requiredMargin(shortQty * executedPrice, product);
      if (available < marginRequired) {
        throw Exception(
          'Insufficient balance for short sell margin. Required ₹${marginRequired.toStringAsFixed(2)}, '
          'available ₹${available.toStringAsFixed(2)}.',
        );
      }

      if (closingLongQty > 0) {
        realizedPnl += (executedPrice - avgPrice) * closingLongQty;
      }

      final oldShortQty = existingSide == 'SELL' ? currentQty : 0;
      final newShortQty = oldShortQty + shortQty;
      final oldShortAvg = existingSide == 'SELL' ? avgPrice : 0.0;
      final newShortAvg = newShortQty == 0
          ? 0.0
          : ((oldShortAvg * oldShortQty) + (executedPrice * shortQty)) /
                newShortQty;

      if (newShortQty > 0) {
        tx.set(inventoryRef, {
          'stock': symbol,
          'product': product,
          'qty': newShortQty,
          'avg_price': _safeDouble(newShortAvg),
          'side': 'SELL',
          'last_price': executedPrice,
          'unrealized_pnl': _safeDouble(
            (newShortAvg - executedPrice) * newShortQty,
          ),
          'updatedAt': serverTs,
        }, SetOptions(merge: false));
      } else {
        tx.delete(inventoryRef);
      }

      balanceAfter = available - marginRequired;
      ledgerType = 'DEBIT';
      ledgerSubType = 'SHORT_MARGIN';
      ledgerAmount = marginRequired;
    } else {
      final newQty = currentQty - fillQty;

      if (newQty == 0) {
        tx.delete(inventoryRef);
      } else {
        final unrealizedPnl = (executedPrice - avgPrice) * newQty;
        tx.update(inventoryRef, {
          'qty': newQty,
          'product': product,
          if (isIntraday) 'side': 'BUY',
          'last_price': executedPrice,
          'unrealized_pnl': unrealizedPnl,
          'updatedAt': serverTs,
        });
      }

      realizedPnl = (executedPrice - avgPrice) * fillQty;
      balanceAfter = available + total;
      ledgerType = 'CREDIT';
      ledgerSubType = 'SELL';
      ledgerAmount = total;
    }

    tx.update(userRef, {
      'available_balance': balanceAfter,
      'balance': balanceAfter,
      'updatedAt': serverTs,
    });

    final filledQty = previousFilledQty + fillQty;
    final filledValue = previousFilledValue + total;
    final remainingQty = orderQty - filledQty;
    final avgExecutedPrice = filledQty == 0 ? 0.0 : filledValue / filledQty;
    final status = remainingQty > 0 ? 'PARTIALLY_EXECUTED' : 'EXECUTED';

    tx.set(orderRef, {
      'clientOrderId': orderId,
      'userId': userId,
      'stock': symbol,
      'type': 'SELL',
      'qty': orderQty,
      'price': executedPrice,
      'product': product,
      'validity': validity,
      'variety': variety,
      'executed_price': _safeDouble(avgExecutedPrice),
      'avg_executed_price': _safeDouble(avgExecutedPrice),
      'filled_qty': filledQty,
      'remaining_qty': remainingQty,
      'last_fill_qty': fillQty,
      'last_fill_price': executedPrice,
      'filled_total': _safeDouble(filledValue),
      'total': _safeDouble(filledValue),
      'price_timestamp': priceTimestamp,
      'status': status,
      'pending_reason': remainingQty > 0 ? 'PENDING_REMAINING_QTY' : null,
      'execution_meta': {
        'attempt': 1,
        'lastError': null,
        'source': 'ADMIN_ENGINE',
      },
      'updatedAt': serverTs,
      if (remainingQty == 0) 'executedAt': serverTs,
      if (previousFilledQty == 0) 'createdAt': serverTs,
    }, SetOptions(merge: true));

    tx.set(tradeRef, {
      'orderId': orderId,
      'userId': userId,
      'stock': symbol,
      'type': 'SELL',
      'qty': fillQty,
      'price': executedPrice,
      'total': total,
      'createdAt': serverTs,
    });

    // Trade feed — same transaction
    tx.set(tradeFeedRef, {
      'orderId': orderId,
      'userId': userId,
      'stock': symbol,
      'type': 'SELL',
      'qty': fillQty,
      'price': executedPrice,
      'total': total,
      'createdAt': serverTs,
    });

    // Ledger CREDIT — inside transaction (atomic with balance update)
    tx.set(ledgerRef, {
      'userId': userId,
      'type': ledgerType,
      'subType': ledgerSubType,
      'amount': ledgerAmount,
      'trade_value': total,
      'realized_pnl': realizedPnl,
      'before_balance': available,
      'balance_after': balanceAfter,
      'referenceType': 'ORDER',
      'referenceId': orderId,
      'stock': symbol,
      'qty': fillQty,
      'price': executedPrice,
      'createdAt': serverTs,
    });
  }

  void _writePendingOrder({
    required Transaction tx,
    required DocumentReference orderRef,
    required String orderId,
    required String userId,
    required String symbol,
    required String type,
    required int qty,
    required double price,
    double? triggerPrice,
    required String variety,
    required String product,
    required String validity,
    String? pendingReason,
    required Object serverTs,
  }) {
    tx.set(orderRef, {
      'clientOrderId': orderId,
      'userId': userId,
      'stock': symbol,
      'type': type,
      'qty': qty,
      'price': price,
      'triggerPrice': triggerPrice,
      'variety': variety,
      'product': product,
      'validity': validity,
      'filled_qty': 0,
      'remaining_qty': qty,
      'status': 'PENDING',
      'pending_reason': pendingReason,
      'execution_meta': {
        'attempt': 1,
        'lastError': null,
        'source': 'ADMIN_ENGINE',
      },
      'createdAt': serverTs,
      'updatedAt': serverTs,
    });
  }

  /// Processes a single pending order against the current market price.
  Future<void> processPendingOrder(String orderId, double currentPrice) async {
    final orderRef = _firestore.raw.doc('orders/$orderId');
    final serverTs = Timestamp.now();

    await _retryFirestore(
      () => _firestore.raw.runTransaction((tx) async {
        final orderSnap = await tx.get(orderRef);
        if (!orderSnap.exists) return;

        final orderData = orderSnap.data()!;
        final status = (orderData['status'] as String?)?.toUpperCase() ?? '';
        if (status != 'PENDING' && status != 'PARTIALLY_EXECUTED') return;

        final symbol = orderData['stock'] as String;
        final side = orderData['type'] as String;
        final variety = _normalizeVariety(
          (orderData['variety'] as String?) ?? 'MARKET',
        );
        final product = _normalizeProduct(
          (orderData['product'] as String?) ?? 'MIS',
        );
        final validity = _normalizeValidity(
          (orderData['validity'] as String?) ?? 'DAY',
        );
        final orderQty = _int(orderData['qty']);
        final previousFilledQty = _int(orderData['filled_qty']);
        final previousFilledValue = _double(orderData['filled_total']);
        final derivedRemaining = orderQty - previousFilledQty;
        final remainingQty = _int(orderData['remaining_qty']) > 0
            ? _int(orderData['remaining_qty'])
            : derivedRemaining;
        final userId = orderData['userId'] as String;
        final limitPrice = _double(orderData['price']);
        final triggerPrice = _double(orderData['triggerPrice']);
        if (remainingQty <= 0) return;

        bool shouldExecute = false;
        double executionPrice = currentPrice;

        if (variety == 'LIMIT') {
          if (side == 'BUY') {
            shouldExecute = currentPrice <= limitPrice;
          } else {
            shouldExecute = currentPrice >= limitPrice;
          }
          executionPrice = limitPrice;
        } else if (variety == 'SL') {
          if (side == 'BUY') {
            shouldExecute = currentPrice >= triggerPrice;
          } else {
            shouldExecute = currentPrice <= triggerPrice;
          }
          executionPrice = limitPrice > 0 ? limitPrice : currentPrice;
        } else if (variety == 'MARKET' || variety == 'ICEBERG') {
          shouldExecute = true;
        } else if (variety == 'AMO') {
          shouldExecute = _isMarketHours(DateTime.now());
        }

        if (!shouldExecute) {
          if (validity == 'IOC') {
            tx.update(orderRef, {
              'status': 'REJECTED',
              'rejectionReason': 'IOC order not executable at current price.',
              'rejectedAt': serverTs,
              'updatedAt': serverTs,
            });
          }
          return;
        }

        // ── Execution inside the same transaction ──
        final userRef = _firestore.raw.doc('users/$userId');
        final inventoryRef = _inventoryRefForOrder(
          userId: userId,
          symbol: symbol,
          product: product,
        );
        final configRef = _firestore.raw.doc('admin_config/platform');
        final tradeId = _uuid.v4();
        final tradeRef = _firestore.raw.doc('trades/$tradeId');
        final tradeFeedRef = _firestore.raw.doc('trade_feed/$tradeId');
        final ledgerId = _uuid.v4();
        final ledgerRef = _firestore.raw.doc('ledger/$ledgerId');

        final configSnap = await tx.get(configRef);
        final configData = configSnap.data() ?? {};
        final maxFillQty = _resolveMaxFillQty(configData['maxFillQtyPerTick']);
        final fillQty = remainingQty > maxFillQty ? maxFillQty : remainingQty;
        if (fillQty <= 0) return;

        final userSnap = await tx.get(userRef);
        final userData = userSnap.data() ?? {};
        final inventorySnap = await tx.get(inventoryRef);

        final total = fillQty * executionPrice;
        final priceTimestamp = DateTime.now().millisecondsSinceEpoch;

        final marginRequired = _requiredMargin(total, product);
        if (side == 'BUY' && _balance(userData) < marginRequired) {
          tx.update(orderRef, {
            'status': 'REJECTED',
            'rejectionReason': 'Insufficient funds at trigger time.',
            'rejectedAt': serverTs,
            'updatedAt': serverTs,
          });
          return;
        }

        if (side == 'SELL') {
          final inventoryData = inventorySnap.data();
          final currentQty = _int(inventoryData?['qty']);
          if (!_isIntradayProduct(product) && currentQty < fillQty) {
            tx.update(orderRef, {
              'status': 'REJECTED',
              'rejectionReason': 'Insufficient quantity at trigger time.',
              'rejectedAt': serverTs,
              'updatedAt': serverTs,
            });
            return;
          }
        }

        if (side == 'BUY') {
          _writeBuy(
            tx: tx,
            userRef: userRef,
            inventoryRef: inventoryRef,
            inventorySnap: inventorySnap,
            orderRef: orderRef,
            tradeRef: tradeRef,
            tradeFeedRef: tradeFeedRef,
            ledgerRef: ledgerRef,
            userData: userData,
            userId: userId,
            symbol: symbol,
            orderQty: orderQty,
            fillQty: fillQty,
            previousFilledQty: previousFilledQty,
            previousFilledValue: previousFilledValue,
            executedPrice: executionPrice,
            priceTimestamp: priceTimestamp,
            total: total,
            orderId: orderId,
            serverTs: serverTs,
            product: product,
            validity: validity,
            variety: variety,
          );
        } else {
          _writeSell(
            tx: tx,
            userRef: userRef,
            inventoryRef: inventoryRef,
            inventorySnap: inventorySnap,
            orderRef: orderRef,
            tradeRef: tradeRef,
            tradeFeedRef: tradeFeedRef,
            ledgerRef: ledgerRef,
            userData: userData,
            userId: userId,
            symbol: symbol,
            orderQty: orderQty,
            fillQty: fillQty,
            previousFilledQty: previousFilledQty,
            previousFilledValue: previousFilledValue,
            executedPrice: executionPrice,
            priceTimestamp: priceTimestamp,
            total: total,
            orderId: orderId,
            serverTs: serverTs,
            product: product,
            validity: validity,
            variety: variety,
          );
        }
      }),
    );
  }

  // ── Admin: Add Balance ─────────────────────────────────────────────────────

  Future<void> addBalance({
    required String adminId,
    required String userId,
    required double amount,
  }) async {
    if (amount == 0) return;

    double before = 0;
    double after = 0;
    final ledgerId = _uuid.v4();
    final serverTs = Timestamp.now();

    // Balance update AND ledger entry in the same transaction — atomic.
    // If either fails, both roll back. No orphaned balance changes.
    await _retryFirestore(
      () => _firestore.raw.runTransaction((tx) async {
        final userRef = _firestore.raw.doc('users/$userId');
        final snap = await tx.get(userRef);
        before = _balance(snap.data() ?? {});
        after = before + amount;

        tx.set(userRef, {
          'available_balance': after,
          'balance': after,
          'updatedAt': serverTs,
        }, SetOptions(merge: true));

        final ledgerRef = _firestore.raw.doc('ledger/$ledgerId');
        tx.set(ledgerRef, {
          'userId': userId,
          'type': 'CREDIT',
          'subType': 'DEPOSIT',
          'amount': amount,
          'before_balance': before,
          'balance_after': after,
          'referenceType': 'ADMIN',
          'referenceId': adminId,
          'createdAt': serverTs,
        });
      }),
    );

    // Audit log is best-effort — failure here does not affect financial data
    await _logAudit(
      action: 'ADD_BALANCE',
      adminId: adminId,
      targetId: userId,
      metadata: {'amount': amount, 'before': before, 'after': after},
    );
  }

  // ── Admin: Toggle Trading ──────────────────────────────────────────────────

  Future<void> setTradingEnabled({
    required String adminId,
    required String userId,
    required bool enabled,
  }) async {
    await _firestore.updateDocument('users/$userId', {
      'tradingEnabled': enabled,
      'updatedAt': Timestamp.now(),
    });
    await _logAudit(
      action: 'SET_TRADING_ENABLED',
      adminId: adminId,
      targetId: userId,
      metadata: {'enabled': enabled},
    );
  }

  // ── Admin: Broadcast ──────────────────────────────────────────────────────

  Future<void> broadcast({
    required String adminId,
    required String message,
  }) async {
    await _firestore.addDocument('notifications', {
      'message': message,
      'type': 'BROADCAST',
      'createdBy': adminId,
      'createdAt': Timestamp.now(),
    });
    await _logAudit(
      action: 'BROADCAST',
      adminId: adminId,
      targetId: 'notifications',
      metadata: {'message': message},
    );
  }

  // ── Admin: Set Leverage ────────────────────────────────────────────────────

  Future<void> setUserLeverage({
    required String adminId,
    required String userId,
    required String stock,
    required double leverage,
  }) async {
    await _firestore
        .setDocument('user_stock_leverage/${userId}_${stock.toUpperCase()}', {
          'userId': userId,
          'stock': stock.toUpperCase(),
          'leverage': leverage,
          'updatedAt': Timestamp.now(),
        });
    await _logAudit(
      action: 'SET_LEVERAGE',
      adminId: adminId,
      targetId: userId,
      metadata: {'stock': stock, 'leverage': leverage},
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Normalizes order variety strings to canonical uppercase form.
  /// Normalizes order variety strings to canonical uppercase form.
  String _normalizeVariety(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'MARKET':
        return 'MARKET';
      case 'LIMIT':
        return 'LIMIT';
      case 'SL':
      case 'SL_LIMIT':
      case 'SL-LIMIT':
      case 'SLLIMIT':
        return 'SL';
      case 'AMO':
        return 'AMO';
      case 'ICEBERG':
        return 'ICEBERG';
      default:
        return 'MARKET';
    }
  }

  String _normalizeProduct(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'MIS':
        return 'MIS';
      case 'NRML':
        return 'NRML';
      case 'OVERNIGHT':
        return 'OVERNIGHT';
      case 'MTF':
        return 'MTF';
      default:
        return 'MIS';
    }
  }

  String _normalizeValidity(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'IOC':
        return 'IOC';
      case 'GTC':
        return 'GTC';
      case 'GTD':
        return 'GTD';
      case 'DAY':
      default:
        return 'DAY';
    }
  }

  bool _isIntradayProduct(String product) => product == 'MIS';

  double _requiredMargin(double tradeValue, String product) {
    final normalized = _normalizeProduct(product);
    if (normalized == 'MIS' || normalized == 'MTF') {
      return tradeValue / 5;
    }
    return tradeValue;
  }

  DocumentReference<Map<String, dynamic>> _inventoryRefForOrder({
    required String userId,
    required String symbol,
    required String product,
  }) {
    final normalizedProduct = _normalizeProduct(product);
    if (_isIntradayProduct(normalizedProduct)) {
      return _firestore.raw.doc(
        'portfolios/$userId/positions/${symbol}_$normalizedProduct',
      );
    }
    return _firestore.raw.doc('portfolios/$userId/holdings/$symbol');
  }

  int _resolveMaxFillQty(dynamic configured) {
    final parsed = _int(configured);
    if (parsed <= 0) return _defaultMaxFillQtyPerTick;
    return parsed;
  }

  /// Validates that required price/trigger fields are present for the variety.
  void _validateOrderInputs({
    required String variety,
    double? price,
    double? triggerPrice,
  }) {
    if (variety == 'LIMIT' && (price == null || price <= 0)) {
      throw Exception('Limit price is required for LIMIT orders.');
    }
    if (variety == 'SL') {
      if (triggerPrice == null || triggerPrice <= 0) {
        throw Exception('Trigger price is required for SL orders.');
      }
    }
  }

  /// Returns true if the current time is within NSE market hours (09:15–15:30 IST).
  bool _isMarketHours(DateTime now) {
    // Convert to IST (UTC+5:30)
    final ist = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    final openMinutes = 9 * 60 + 15; // 09:15
    final closeMinutes = 15 * 60 + 30; // 15:30
    final currentMinutes = ist.hour * 60 + ist.minute;
    final isWeekday =
        ist.weekday >= DateTime.monday && ist.weekday <= DateTime.friday;
    return isWeekday &&
        currentMinutes >= openMinutes &&
        currentMinutes <= closeMinutes;
  }

  double _balance(Map<String, dynamic> data) {
    final available = data['available_balance'];
    final balance = data['balance'];
    return _double(available ?? balance);
  }

  int _int(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  double _double(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  double _safeDouble(double v) {
    if (v.isNaN || v.isInfinite) return 0.0;
    return v;
  }

  Future<void> _logAudit({
    required String action,
    required String adminId,
    required String targetId,
    required Map<String, dynamic> metadata,
  }) {
    return _firestore.addDocument('audit_logs', {
      'action': action,
      'adminId': adminId,
      'targetId': targetId,
      'metadata': metadata,
      'timestamp': Timestamp.now(),
    });
  }
}
