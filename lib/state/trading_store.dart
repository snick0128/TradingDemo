import 'dart:async';
import 'dart:collection';

// RMS FIX Bug #9: cloud_firestore exports 'Order' and 'Transaction' which
// clash with our trading_models.dart classes of the same name.
// Solution: hide the conflicting Firestore types — we only need
// FirebaseFirestore, DocumentSnapshot, QuerySnapshot, and Timestamp.
import 'package:cloud_firestore/cloud_firestore.dart'
    hide Order, Transaction;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../data/services/live_market_service.dart';
import '../models/trading_models.dart';
import '../services/alert_service.dart';
import '../services/market_data_service.dart';

// RMS FIX:
// Bug #9  — Flutter state was in-memory only, lost on refresh.
// Bug #12 — Sell credited ₹0 to balance in offline path.
// Bug #13 — Opening balance hardcoded to ₹45,000 vs backend ₹1,00,000.
// Solution: TradingStore now streams Firestore for balance, holdings, orders.
//           Flutter is a rendering layer — backend is source of truth.
//           Local mutations are kept ONLY for the offline/mock path.
//           When Firebase auth is present, all state comes from Firestore.

class OrderResult {
  final bool success;
  final String? orderId;
  final String? errorMessage;

  const OrderResult({required this.success, this.orderId, this.errorMessage});

  /// Backward-compatible message getter
  String get message =>
      success ? (orderId ?? 'Success') : (errorMessage ?? 'Error');
}

class TradingStore extends ChangeNotifier {
  TradingStore()
    : _watchlist = <Stock>[],
      _watchlistUniverse = {},
      _orders = <Order>[],
      _portfolio = <PortfolioItem>[],
      _positions = <Position>[],
      _holdings = <Holding>[],
      _transactions = <Transaction>[],
      _currentUser = User(
        id: '',
        clientId: '',
        name: '',
        email: '',
        isActive: false,
        balance: 0.0,
        marginLimit: 0.0,
        registeredAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      _balance = 0.0 {
    // Stub service — no random prices. Live backend fills the watchlist.
    _marketDataService = MarketDataService({});
    _alertService = AlertService(this, _marketDataService);
  }

  late final MarketDataService _marketDataService;
  MarketDataService get marketDataService => _marketDataService;
  late final AlertService _alertService;
  // No mock price subscription — live backend is the only price source.
  StreamSubscription<Map<String, double>>? _priceSubscription;

  // ── Live backend wiring ────────────────────────────────────────────────────
  LiveMarketService? _liveMarketService;
  StreamSubscription<List<Stock>>? _liveStockSub;
  bool _usingLiveBackend = false;
  bool get usingLiveBackend => _usingLiveBackend;

  /// Call this once after the store is created to switch from mock prices
  /// to live prices from the Node.js backend.
  ///
  /// Safe to call multiple times — idempotent.
  void connectLiveBackend({String? baseUrl}) {
    if (_usingLiveBackend) return;

    final api = BackendApiService(
      baseUrl: baseUrl ?? BackendConfig.backendBaseUrl,
    );
    _liveMarketService = LiveMarketService(
      api: api,
      onError: (isError, message) {
        setBackendError(isError, message: message);
      },
    );

    // Stop mock price timer — live service takes over
    _priceSubscription?.cancel();
    _marketDataService.dispose();

    _liveStockSub = _liveMarketService!.stockUpdates.listen(_onLiveStockUpdate);
    unawaited(_liveMarketService!.start());
    _refreshMarketSubscriptions();
    _usingLiveBackend = true;
  }

  /// Disconnect from live backend.
  void disconnectLiveBackend() {
    if (!_usingLiveBackend) return;
    _liveStockSub?.cancel();
    _liveMarketService?.dispose();
    _liveMarketService = null;
    _usingLiveBackend = false;
  }

  // ── Live backend status ────────────────────────────────────────────────────
  bool _backendError = false;
  bool get backendError => _backendError;
  String _backendErrorMessage = '';
  String get backendErrorMessage => _backendErrorMessage;

  void setBackendError(bool error, {String message = ''}) {
    if (_backendError == error && _backendErrorMessage == message) return;
    _backendError = error;
    _backendErrorMessage = message;
    notifyListeners();
  }

  // ── RMS FIX Bug #9: Firestore state streaming ─────────────────────────────
  // When a Firebase user is authenticated, stream balance, holdings, and orders
  // directly from Firestore. This makes Flutter a rendering layer only —
  // the backend is the single source of truth.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?    _holdingsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?    _ordersSub;
  bool _firestoreStreamsActive = false;

  /// Bind Firestore real-time streams for a logged-in user.
  /// Call this once after Firebase auth succeeds.
  void bindFirestoreStreams(String userId) {
    if (_firestoreStreamsActive) return;
    _firestoreStreamsActive = true;

    final db = FirebaseFirestore.instance;

    // Stream user document → balance
    _userDocSub = db.collection('users').doc(userId).snapshots().listen(
      (snap) {
        if (!snap.exists) return;
        final data = snap.data()!;
        final newBalance = ((data['balance'] as num?) ??
                           (data['available_balance'] as num?) ?? 0)
            .toDouble();
        if (_balance != newBalance) {
          _balance = newBalance;
          notifyListeners();
        }
      },
      onError: (e) => debugPrint('[TradingStore] User doc stream error: $e'),
    );

    // Stream holdings → positions + holdings lists
    _holdingsSub = db
        .collection('portfolios')
        .doc(userId)
        .collection('holdings')
        .snapshots()
        .listen(
      (snap) {
        _syncHoldingsFromFirestore(snap.docs);
        notifyListeners();
      },
      onError: (e) => debugPrint('[TradingStore] Holdings stream error: $e'),
    );

    // Stream orders → orders list
    _ordersSub = db
        .collection('orders')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen(
      (snap) {
        _syncOrdersFromFirestore(snap.docs);
        notifyListeners();
      },
      onError: (e) => debugPrint('[TradingStore] Orders stream error: $e'),
    );

    debugPrint('[TradingStore] Firestore streams bound for userId=$userId');
  }

  /// Unbind Firestore streams (on logout).
  void unbindFirestoreStreams() {
    _userDocSub?.cancel();
    _holdingsSub?.cancel();
    _ordersSub?.cancel();
    _userDocSub  = null;
    _holdingsSub = null;
    _ordersSub   = null;
    _firestoreStreamsActive = false;
    debugPrint('[TradingStore] Firestore streams unbound.');
  }

  /// Map Firestore holdings documents into _holdings and _portfolio.
  void _syncHoldingsFromFirestore(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    _holdings.clear();
    _portfolio.clear();
    _positions.clear();

    for (final doc in docs) {
      final d          = doc.data();
      final symbol     = (d['stock'] as String? ?? doc.id).toUpperCase();
      final qty        = ((d['qty'] as num?) ?? 0).toInt();
      final avgPrice   = ((d['avg_price'] as num?) ?? 0).toDouble();
      final productType = (d['productType'] as String?) ?? 'CNC';

      if (qty <= 0) continue;

      // Get current price from live market feed
      final stock        = stockBySymbolOrNull(symbol);
      final currentPrice = stock?.currentPrice ?? avgPrice;

      // Populate _portfolio (used by dashboard P&L)
      _portfolio.add(PortfolioItem(
        symbol:        symbol,
        name:          stock?.name ?? symbol,
        totalQuantity: qty,
        avgPrice:      avgPrice,
        currentPrice:  currentPrice,
      ));

      // Populate _holdings (delivery / CNC)
      if (productType == 'CNC' || productType == 'NRML') {
        _holdings.add(Holding(
          symbol:       symbol,
          name:         stock?.name ?? symbol,
          quantity:     qty,
          avgPrice:     avgPrice,
          currentPrice: currentPrice,
          purchaseDate: DateTime.now(),
        ));
      }

      // Populate _positions (intraday / MIS)
      if (productType == 'MIS') {
        _positions.add(Position(
          symbol:       symbol,
          name:         stock?.name ?? symbol,
          product:      ProductType.mis,
          quantity:     qty,
          avgPrice:     avgPrice,
          currentPrice: currentPrice,
          side:         OrderType.buy,
          openedAt:     DateTime.now(),
        ));
      }
    }
  }

  /// Map Firestore order documents into _orders list.
  void _syncOrdersFromFirestore(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    _orders.clear();
    for (final doc in docs) {
      final d      = doc.data();
      final typeStr = (d['type'] as String? ?? 'BUY').toUpperCase();
      final statusStr = (d['status'] as String? ?? 'EXECUTED').toUpperCase();

      _orders.add(Order(
        id:       doc.id,
        symbol:   (d['stock'] as String? ?? '').toUpperCase(),
        name:     (d['stock'] as String? ?? '').toUpperCase(),
        quantity: ((d['qty'] as num?) ?? 0).toInt(),
        price:    ((d['price'] as num?) ?? 0).toDouble(),
        type:     typeStr == 'SELL' ? OrderType.sell : OrderType.buy,
        status:   _orderStatusFromString(statusStr),
        dateTime: _timestampToDate(d['createdAt']),
        executedAt: _timestampToDate(d['executedAt'] ?? d['createdAt']),
        executedPrice: ((d['executed_price'] as num?) ?? (d['price'] as num?))?.toDouble(),
        pnl: ((d['pnl'] as num?) ?? 0).toDouble(),
      ));
    }
  }

  OrderStatus _orderStatusFromString(String s) {
    switch (s) {
      case 'EXECUTED':  return OrderStatus.executed;
      case 'REJECTED':  return OrderStatus.rejected;
      case 'CANCELLED': return OrderStatus.cancelled;
      case 'PENDING':   return OrderStatus.pending;
      default:          return OrderStatus.executed;
    }
  }

  DateTime _timestampToDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is int)       return DateTime.fromMillisecondsSinceEpoch(v);
    return DateTime.now();
  }

  /// Called when the live backend emits a fresh batch of stocks.
  void _onLiveStockUpdate(List<Stock> stocks) {
    if (stocks.isEmpty) return;

    // Clear error state — backend is responding
    if (_backendError) {
      _backendError = false;
      _backendErrorMessage = '';
    }

    for (final stock in stocks) {
      final existing = _watchlistUniverse[stock.symbol];
      final oldPrice = existing?.currentPrice;

      // Update watchlist entry
      final idx = _watchlist.indexWhere((s) => s.symbol == stock.symbol);
      if (idx >= 0) {
        _watchlist[idx] = stock;
      } else {
        _watchlist.add(stock);
      }
      _watchlistUniverse[stock.symbol] = stock;

      // Record direction for price flash arrows
      if (oldPrice != null) {
        _marketDataService.recordDirection(
          stock.symbol,
          oldPrice,
          stock.currentPrice,
        );
      }

      // Update open positions
      for (var i = 0; i < _positions.length; i++) {
        if (_positions[i].symbol == stock.symbol) {
          _positions[i] = _positions[i].copyWith(
            currentPrice: stock.currentPrice,
          );
        }
      }

      // Update holdings
      for (var i = 0; i < _holdings.length; i++) {
        if (_holdings[i].symbol == stock.symbol) {
          _holdings[i] = _holdings[i].copyWith(
            currentPrice: stock.currentPrice,
          );
        }
      }
    }
    _refreshMarketSubscriptions();
    notifyListeners();
  }

  void _refreshMarketSubscriptions() {
    final service = _liveMarketService;
    if (service == null) return;
    final symbols = _watchlist.map((s) => s.symbol).toSet();
    if (symbols.isEmpty) {
      // Default subscription covers all tracked symbols — NSE + MCX
      symbols.addAll(const [
        // NSE Equities
        'RELIANCE', 'TCS', 'INFY', 'HDFCBANK', 'ICICIBANK',
        'SBIN', 'WIPRO', 'AXISBANK', 'BAJFINANCE', 'HINDUNILVR',
        // MCX Commodities
        'GOLD', 'SILVER', 'CRUDEOIL', 'NATURALGAS',
        'COPPER', 'ZINC', 'LEAD', 'ALUMINIUM', 'NICKEL', 'COTTON',
      ]);
    }
    service.setSubscribedSymbols(symbols);
  }

  final List<Stock> _watchlist;
  final Map<String, Stock> _watchlistUniverse;
  final List<Order> _orders;
  final List<PortfolioItem> _portfolio;
  final List<Position> _positions;
  final List<Holding> _holdings;
  final List<Transaction> _transactions;
  User _currentUser;

  double _balance;
  // RMS FIX Bug #13: Opening balance was hardcoded to ₹45,000.
  // Backend creates users with ₹1,00,000. Use backend default as reference.
  // When Firestore streams are active, _balance is overwritten from Firestore.
  final double _openingBalance = 100000;
  String _fontSizePreset = 'Medium';
  double _textScaleFactor = 1.0;

  bool _showMisSquareOffWarning = false;
  bool get showMisSquareOffWarning => _showMisSquareOffWarning;

  void setMisSquareOffWarning(bool value) {
    if (_showMisSquareOffWarning == value) return;
    _showMisSquareOffWarning = value;
    notifyListeners();
  }

  bool? getPriceDirection(String symbol) =>
      _marketDataService.getPriceDirection(symbol);

  @override
  void dispose() {
    _priceSubscription?.cancel();
    _liveStockSub?.cancel();
    _liveMarketService?.dispose();
    _alertService.dispose();
    _marketDataService.dispose();
    // RMS FIX Bug #9: Cancel Firestore streams on dispose
    unbindFirestoreStreams();
    super.dispose();
  }

  UnmodifiableListView<Stock> get watchlist => UnmodifiableListView(_watchlist);
  UnmodifiableListView<Order> get orders => UnmodifiableListView(_orders);
  UnmodifiableListView<PortfolioItem> get portfolio =>
      UnmodifiableListView(_portfolio);
  UnmodifiableListView<Position> get positions =>
      UnmodifiableListView(_positions);
  UnmodifiableListView<Holding> get holdings => UnmodifiableListView(_holdings);
  UnmodifiableListView<Transaction> get transactions =>
      UnmodifiableListView(_transactions);
  User get currentUser => _currentUser;

  double get balance => _balance;
  double get openingBalance => _openingBalance;
  String get fontSizePreset => _fontSizePreset;
  double get textScaleFactor => _textScaleFactor;

  double get payIn => _transactions
      .where((tx) => tx.isDeposit && tx.title.contains('Funds'))
      .fold(0.0, (sum, tx) => sum + tx.amount);
  double get payOut => _transactions
      .where((tx) => !tx.isDeposit && tx.title.contains('Withdrawal'))
      .fold(0.0, (sum, tx) => sum + tx.amount);
  double get usedMargin =>
      _transactions
          .where((tx) => !tx.isDeposit && tx.title.contains('Margin blocked'))
          .fold(0.0, (sum, tx) => sum + tx.amount) -
      _transactions
          .where((tx) => tx.isDeposit && tx.title.contains('Margin released'))
          .fold(0.0, (sum, tx) => sum + tx.amount);

  double get totalInvestment =>
      _portfolio.fold(0, (sum, item) => sum + item.investedValue);
  double get totalCurrentValue =>
      _portfolio.fold(0, (sum, item) => sum + item.currentValue);
  double get totalPnl => totalCurrentValue - totalInvestment;
  double get totalBalance => _balance + usedMargin;

  MarginBreakdown get marginBreakdown {
    final spanMargin = usedMargin * 0.6;
    final exposureMargin = usedMargin * 0.4;
    final collateralValue = _holdings.fold<double>(
      0,
      (sum, h) => sum + h.currentValue * 0.5,
    );
    final marginAvailable = _balance + collateralValue;
    return MarginBreakdown(
      availableCash: _balance,
      marginUsed: usedMargin,
      marginAvailable: marginAvailable,
      collateralValue: collateralValue,
      spanMargin: spanMargin,
      exposureMargin: exposureMargin,
      peakMargin: usedMargin * 1.1,
    );
  }

  Stock? stockBySymbolOrNull(String symbol) {
    // Exact match first
    final exact =
        _watchlistUniverse[symbol] ??
        _watchlist.where((s) => s.symbol == symbol).firstOrNull;
    if (exact != null) return exact;
    // Case-insensitive fallback (handles RELIANCE vs reliance)
    final upper = symbol.toUpperCase();
    return _watchlistUniverse[upper] ??
        _watchlist.where((s) => s.symbol.toUpperCase() == upper).firstOrNull;
  }

  Stock stockBySymbol(String symbol) {
    return stockBySymbolOrNull(symbol) ??
        // Never fall back to _watchlist.first — return a placeholder with the
        // correct symbol so the detail screen shows the right name/symbol.
        Stock(
          symbol: symbol,
          name: symbol,
          currentPrice: 0,
          changePercentage: 0,
          sector: '',
        );
  }

  /// Register a stock from a search result so the detail screen can access
  /// its exchange and token even if it's not in the watchlist.
  /// Does NOT add it to the watchlist — only to the universe map.
  ///
  /// ALWAYS updates exchange+token — never skips if already registered,
  /// because the existing entry may have been seeded with wrong defaults
  /// (e.g. NSE from the bootstrap snapshot before the search result arrived).
  void registerSearchResult({
    required String symbol,
    required String displayName,
    required String exchange,
    required String token,
    double ltp = 0,
    double changePercent = 0,
  }) {
    final resolvedExchange = exchange.isNotEmpty ? exchange.toUpperCase() : 'NSE';

    debugPrint('[DETAIL_OPEN] symbol=$symbol exchange=$resolvedExchange token=$token');

    final existing = _watchlistUniverse[symbol];
    if (existing != null) {
      // Always overwrite exchange+token from the search result — the existing
      // entry may have been seeded with NSE defaults from the market bootstrap.
      _watchlistUniverse[symbol] = Stock(
        symbol: existing.symbol,
        name: displayName.isNotEmpty ? displayName : existing.name,
        currentPrice: ltp > 0 ? ltp : existing.currentPrice,
        changePercentage: changePercent != 0 ? changePercent : existing.changePercentage,
        sector: existing.sector,
        exchange: resolvedExchange,   // ← always use the search result exchange
        token: token.isNotEmpty ? token : existing.token,
        prevClose: existing.prevClose,
        volume: existing.volume,
        isStale: existing.isStale,
      );
    } else {
      _watchlistUniverse[symbol] = Stock(
        symbol: symbol,
        name: displayName.isNotEmpty ? displayName : symbol,
        currentPrice: ltp,
        changePercentage: changePercent,
        sector: '',
        exchange: resolvedExchange,
        token: token,
      );
    }
    // No notifyListeners — this is a silent registration
  }

  bool isInWatchlist(String symbol) =>
      _watchlist.any((stock) => stock.symbol == symbol);

  void addToWatchlist(String symbol) {
    if (isInWatchlist(symbol)) return;
    final stock = _watchlistUniverse[symbol];
    if (stock == null) return;
    _watchlist.add(stock);
    _refreshMarketSubscriptions();
    notifyListeners();
  }

  void removeFromWatchlist(String symbol) {
    _watchlist.removeWhere((stock) => stock.symbol == symbol);
    _refreshMarketSubscriptions();
    notifyListeners();
  }

  void setFontSizePreset(String preset) {
    if (_fontSizePreset == preset) return;
    _fontSizePreset = preset;
    switch (preset) {
      case 'Small':
        _textScaleFactor = 0.9;
        break;
      case 'Large':
        _textScaleFactor = 1.12;
        break;
      default:
        _textScaleFactor = 1.0;
        break;
    }
    notifyListeners();
  }

  /// Returns the required margin for an order.
  /// CNC and NRML: full value (quantity * price)
  /// Returns required margin for an order.
  /// - MIS/MTF: 20% of trade value (5x leverage)
  /// - NRML: 100% of trade value
  /// - Overnight (carry-forward): 100% of trade value
  /// - SELL orders: always 0 (exit trade, no new margin required)
  double requiredMargin(
    int quantity,
    double price,
    ProductType product, {
    bool isSell = false,
  }) {
    if (isSell) return 0; // Exit orders never require margin
    final fullValue = quantity * price;
    if (product == ProductType.mis || product == ProductType.mtf) {
      return fullValue / 5;
    }
    return fullValue; // nrml, overnight
  }

  OrderResult placeOrder({
    required String symbol,
    required int quantity,
    required OrderType type,
    OrderVariety variety = OrderVariety.market,
    ProductType product = ProductType.mis,
    OrderValidity validity = OrderValidity.day,
    DateTime? validityDate,
    double price = 0,
    double? triggerPrice,
    int? disclosedQuantity,
    double? targetPrice,
    double? stopLossPrice,
  }) {
    // Validation
    if (quantity <= 0) {
      return const OrderResult(
        success: false,
        errorMessage: 'Please enter a quantity greater than zero.',
      );
    }

    final effectivePrice = price > 0
        ? price
        : stockBySymbol(symbol).currentPrice;

    if (variety == OrderVariety.limit || variety == OrderVariety.sl) {
      if (price < 0) {
        return const OrderResult(
          success: false,
          errorMessage: 'Limit price cannot be negative. Please enter a valid price.',
        );
      }
    }

    final stock = stockBySymbol(symbol);
    final margin = requiredMargin(quantity, effectivePrice, product);

    if (type == OrderType.buy) {
      if (_balance < margin) {
        return const OrderResult(
          success: false,
          errorMessage:
              'Not enough funds to place this order. Please add funds or reduce your order size.',
        );
      }

      _balance -= margin;
      _applyBuy(stock, quantity);

      // Update positions or holdings based on product type
      if (product == ProductType.mis || product == ProductType.nrml) {
        _applyPositionBuy(stock, quantity, effectivePrice, product, type);
      } else {
        // Overnight or MTF -> holdings (carry-forward delivery)
        _applyHoldingBuy(stock, quantity, effectivePrice);
      }

      _transactions.insert(
        0,
        Transaction(
          id: 'TX-${DateTime.now().millisecondsSinceEpoch}',
          title: 'Margin blocked • BUY ${stock.symbol}',
          amount: margin,
          dateTime: DateTime.now(),
          isDeposit: false,
        ),
      );
    } else {
      // Sell
      final holdingIndex = _portfolio.indexWhere(
        (item) => item.symbol == stock.symbol,
      );
      if (holdingIndex < 0) {
        return const OrderResult(
          success: false,
          errorMessage: 'You don\'t have any holdings of this stock to sell.',
        );
      }

      final holding = _portfolio[holdingIndex];
      if (quantity > holding.totalQuantity) {
        return OrderResult(
          success: false,
          errorMessage:
              'You only have ${holding.totalQuantity} shares available. Please reduce your sell quantity.',
        );
      }

      // RMS FIX Bug #12: Sell must credit FULL PROCEEDS to balance.
      // Old code: _balance += margin (which was 0 for sells — completely wrong).
      // New code: _balance += price × qty (full sell proceeds).
      final sellProceeds = quantity * effectivePrice;
      _balance += sellProceeds;

      _applySell(stock, quantity, holdingIndex);

      // Update positions or holdings based on product type
      if (product == ProductType.mis || product == ProductType.nrml) {
        _applyPositionSell(stock, quantity, effectivePrice, product);
      } else {
        _applyHoldingSell(stock, quantity);
      }

      _transactions.insert(
        0,
        Transaction(
          id: 'TX-${DateTime.now().millisecondsSinceEpoch}',
          title: 'Margin released • SELL ${stock.symbol}',
          amount: sellProceeds,
          dateTime: DateTime.now(),
          isDeposit: true,
        ),
      );
    }

    final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch}';
    final newOrder = Order(
      id: orderId,
      symbol: stock.symbol,
      name: stock.name,
      quantity: quantity,
      price: effectivePrice,
      type: type,
      status: OrderStatus.pending,
      dateTime: DateTime.now(),
      variety: variety,
      product: product,
      validity: validity,
      validityDate: validityDate,
      triggerPrice: triggerPrice,
      disclosedQuantity: disclosedQuantity,
      targetPrice: targetPrice,
      stopLossPrice: stopLossPrice,
    );
    _orders.insert(0, newOrder);

    notifyListeners();

    return OrderResult(success: true, orderId: orderId);
  }

  OrderResult deposit(double amount) {
    if (amount <= 0) {
      return const OrderResult(
        success: false,
        errorMessage: 'Please enter an amount greater than zero to deposit.',
      );
    }

    _balance += amount;
    _transactions.insert(
      0,
      Transaction(
        id: 'TX-${DateTime.now().millisecondsSinceEpoch}',
        title: 'Funds added',
        amount: amount,
        dateTime: DateTime.now(),
        isDeposit: true,
      ),
    );

    notifyListeners();
    return const OrderResult(success: true, orderId: 'Funds added to wallet.');
  }

  OrderResult withdraw(double amount) {
    if (amount <= 0) {
      return const OrderResult(
        success: false,
        errorMessage: 'Please enter an amount greater than zero to withdraw.',
      );
    }

    if (amount > _balance) {
      return const OrderResult(
        success: false,
        errorMessage: 'Withdrawal amount exceeds your available balance.',
      );
    }

    _balance -= amount;
    _transactions.insert(
      0,
      Transaction(
        id: 'TX-${DateTime.now().millisecondsSinceEpoch}',
        title: 'Withdrawal',
        amount: amount,
        dateTime: DateTime.now(),
        isDeposit: false,
      ),
    );

    notifyListeners();
    return const OrderResult(success: true, orderId: 'Withdrawal successful.');
  }

  // ─── Portfolio (PortfolioItem) helpers ────────────────────────────────────

  void _applyBuy(Stock stock, int quantity) {
    final index = _portfolio.indexWhere((item) => item.symbol == stock.symbol);

    if (index < 0) {
      _portfolio.add(
        PortfolioItem(
          symbol: stock.symbol,
          name: stock.name,
          totalQuantity: quantity,
          avgPrice: stock.currentPrice,
          currentPrice: stock.currentPrice,
        ),
      );
      return;
    }

    final current = _portfolio[index];
    final newQty = current.totalQuantity + quantity;
    final weightedAvg =
        ((current.avgPrice * current.totalQuantity) +
            (stock.currentPrice * quantity)) /
        newQty;

    _portfolio[index] = PortfolioItem(
      symbol: current.symbol,
      name: current.name,
      totalQuantity: newQty,
      avgPrice: weightedAvg,
      currentPrice: stock.currentPrice,
    );
  }

  void _applySell(Stock stock, int quantity, int holdingIndex) {
    final current = _portfolio[holdingIndex];
    final remainingQty = current.totalQuantity - quantity;

    if (remainingQty <= 0) {
      _portfolio.removeAt(holdingIndex);
      return;
    }

    _portfolio[holdingIndex] = PortfolioItem(
      symbol: current.symbol,
      name: current.name,
      totalQuantity: remainingQty,
      avgPrice: current.avgPrice,
      currentPrice: stock.currentPrice,
    );
  }

  // ─── Position helpers (MIS / NRML) ────────────────────────────────────────

  void _applyPositionBuy(
    Stock stock,
    int quantity,
    double price,
    ProductType product,
    OrderType side,
  ) {
    final index = _positions.indexWhere(
      (p) => p.symbol == stock.symbol && p.product == product,
    );

    if (index < 0) {
      _positions.add(
        Position(
          symbol: stock.symbol,
          name: stock.name,
          product: product,
          quantity: quantity,
          avgPrice: price,
          currentPrice: stock.currentPrice,
          side: side,
          openedAt: DateTime.now(),
        ),
      );
      return;
    }

    final current = _positions[index];
    final newQty = current.quantity + quantity;
    final weightedAvg =
        ((current.avgPrice * current.quantity) + (price * quantity)) / newQty;

    _positions[index] = current.copyWith(
      quantity: newQty,
      avgPrice: weightedAvg,
      currentPrice: stock.currentPrice,
    );
  }

  void _applyPositionSell(
    Stock stock,
    int quantity,
    double price,
    ProductType product,
  ) {
    final index = _positions.indexWhere(
      (p) => p.symbol == stock.symbol && p.product == product,
    );

    if (index < 0) return;

    final current = _positions[index];
    final remainingQty = current.quantity - quantity;

    if (remainingQty <= 0) {
      _positions.removeAt(index);
      return;
    }

    _positions[index] = current.copyWith(
      quantity: remainingQty,
      currentPrice: stock.currentPrice,
    );
  }

  // ─── Holding helpers (CNC / MTF) ──────────────────────────────────────────

  void _applyHoldingBuy(Stock stock, int quantity, double price) {
    final index = _holdings.indexWhere((h) => h.symbol == stock.symbol);

    if (index < 0) {
      _holdings.add(
        Holding(
          symbol: stock.symbol,
          name: stock.name,
          quantity: quantity,
          avgPrice: price,
          currentPrice: stock.currentPrice,
          purchaseDate: DateTime.now(),
        ),
      );
      return;
    }

    final current = _holdings[index];
    final newQty = current.quantity + quantity;
    final weightedAvg =
        ((current.avgPrice * current.quantity) + (price * quantity)) / newQty;

    _holdings[index] = current.copyWith(
      quantity: newQty,
      avgPrice: weightedAvg,
      currentPrice: stock.currentPrice,
    );
  }

  void _applyHoldingSell(Stock stock, int quantity) {
    final index = _holdings.indexWhere((h) => h.symbol == stock.symbol);
    if (index < 0) return;

    final current = _holdings[index];
    final remainingQty = current.quantity - quantity;

    if (remainingQty <= 0) {
      _holdings.removeAt(index);
      return;
    }

    _holdings[index] = current.copyWith(
      quantity: remainingQty,
      currentPrice: stock.currentPrice,
    );
  }

  // ─── Position product conversion ─────────────────────────────────────────

  void convertPositionProduct(String symbol, ProductType from, ProductType to) {
    final index = _positions.indexWhere(
      (p) => p.symbol == symbol && p.product == from,
    );
    if (index < 0) return;
    _positions[index] = _positions[index].copyWith(product: to);
    notifyListeners();
  }

  // ─── Cancel Order ─────────────────────────────────────────────────────────

  void cancelOrder(String orderId) {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index < 0) return;
    final order = _orders[index];
    if (order.status != OrderStatus.pending) return;
    _orders[index] = order.copyWith(status: OrderStatus.cancelled);
    notifyListeners();
  }

  // ─── GTT Orders ───────────────────────────────────────────────────────────

  final List<GTTOrder> _gttOrders = [];

  UnmodifiableListView<GTTOrder> get gttOrders =>
      UnmodifiableListView(_gttOrders);

  void createGTTOrder(GTTOrder order) {
    _gttOrders.add(order);
    notifyListeners();
  }

  void editGTTOrder(String id, GTTOrder updated) {
    final index = _gttOrders.indexWhere((o) => o.id == id);
    if (index >= 0) {
      _gttOrders[index] = updated;
      notifyListeners();
    }
  }

  void cancelGTTOrder(String id) {
    _gttOrders.removeWhere((o) => o.id == id);
    notifyListeners();
  }

  // ─── Basket Orders ────────────────────────────────────────────────────────

  final List<BasketOrder> _basketOrders = [];

  UnmodifiableListView<BasketOrder> get basketOrders =>
      UnmodifiableListView(_basketOrders);

  void createBasket(BasketOrder basket) {
    _basketOrders.add(basket);
    notifyListeners();
  }

  OrderResult executeBasket(String basketId) {
    final index = _basketOrders.indexWhere((b) => b.id == basketId);
    if (index < 0) {
      return const OrderResult(
        success: false,
        errorMessage: 'Basket order not found. It may have been removed.',
      );
    }

    final basket = _basketOrders[index];
    for (final entry in basket.entries) {
      final result = placeOrder(
        symbol: entry.symbol,
        quantity: entry.quantity,
        type: entry.type,
        variety: entry.variety,
        product: entry.product,
        price: entry.price ?? 0,
      );
      if (!result.success) {
        return OrderResult(
          success: false,
          errorMessage: 'Order for ${entry.symbol} failed: ${result.errorMessage}',
        );
      }
    }

    _basketOrders[index] = basket.copyWith(executedAt: DateTime.now());
    notifyListeners();
    return OrderResult(success: true, orderId: basketId);
  }

  void saveBasket(BasketOrder basket) {
    final index = _basketOrders.indexWhere((b) => b.id == basket.id);
    if (index >= 0) {
      _basketOrders[index] = basket;
    } else {
      _basketOrders.add(basket);
    }
    notifyListeners();
  }

  // ─── Alerts ───────────────────────────────────────────────────────────────

  final List<Alert> _alerts = [];

  UnmodifiableListView<Alert> get alerts => UnmodifiableListView(_alerts);

  void createAlert(Alert alert) {
    _alerts.add(alert);
    notifyListeners();
  }

  void deleteAlert(String id) {
    _alerts.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  // ─── Notifications ────────────────────────────────────────────────────────

  final List<AppNotification> _notifications = [];

  UnmodifiableListView<AppNotification> get notifications =>
      UnmodifiableListView(_notifications);

  int get unreadNotificationCount =>
      _notifications.where((n) => !n.isRead).length;

  void addNotification(AppNotification notification) {
    _notifications.insert(0, notification);
    notifyListeners();
  }

  void markNotificationRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index >= 0) {
      _notifications[index] = _notifications[index].copyWith(isRead: true);
      notifyListeners();
    }
  }

  void markAllNotificationsRead() {
    for (var i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].isRead) {
        _notifications[i] = _notifications[i].copyWith(isRead: true);
      }
    }
    notifyListeners();
  }

  void clearNotifications() {
    _notifications.clear();
    notifyListeners();
  }

  void addOrUpdateOrder(Order order) {
    final index = _orders.indexWhere((o) => o.id == order.id);
    if (index >= 0) {
      _orders[index] = order;
    } else {
      _orders.insert(0, order);
    }
    notifyListeners();
  }

  void replaceOrders(List<Order> orders) {
    _orders
      ..clear()
      ..addAll(orders);
    notifyListeners();
  }

  void replacePositions(List<Position> positions) {
    _positions
      ..clear()
      ..addAll(positions);
    notifyListeners();
  }

  void replaceHoldings(List<Holding> holdings) {
    _holdings
      ..clear()
      ..addAll(holdings);
    notifyListeners();
  }

  void replaceGttOrders(List<GTTOrder> gttOrders) {
    _gttOrders
      ..clear()
      ..addAll(gttOrders);
    notifyListeners();
  }

  // ─── User update ──────────────────────────────────────────────────────────

  void updateUser(User updated, {bool updateBalance = false}) {
    _currentUser = updated;
    if (updateBalance) {
      _balance = updated.balance;
    }
    notifyListeners();
  }

  // ─── Recent Searches ──────────────────────────────────────────────────────

  final List<String> _recentSearches = [];

  UnmodifiableListView<String> get recentSearches =>
      UnmodifiableListView(_recentSearches);

  void addRecentSearch(String symbol) {
    _recentSearches.remove(symbol);
    _recentSearches.insert(0, symbol);
    if (_recentSearches.length > 10) {
      _recentSearches.removeLast();
    }
    notifyListeners();
  }

  void clearRecentSearches() {
    _recentSearches.clear();
    notifyListeners();
  }
}
