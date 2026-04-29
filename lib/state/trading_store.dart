import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../models/trading_models.dart';
import '../services/alert_service.dart';
import '../services/market_data_service.dart';
import '../services/mock_data_service.dart';

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
    : _watchlist = List<Stock>.of(MockData.watchlist),
      _watchlistUniverse = {
        for (final stock in MockData.watchlist) stock.symbol: stock,
      },
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
    _marketDataService = MarketDataService(
      Map.fromEntries(
        MockData.watchlist.map((s) => MapEntry(s.symbol, s.currentPrice)),
      ),
    );
    _priceSubscription = _marketDataService.priceUpdates.listen(_onPriceUpdate);
    _alertService = AlertService(this, _marketDataService);
  }

  late final MarketDataService _marketDataService;
  MarketDataService get marketDataService => _marketDataService;
  late final AlertService _alertService;
  StreamSubscription<Map<String, double>>? _priceSubscription;

  final List<Stock> _watchlist;
  final Map<String, Stock> _watchlistUniverse;
  final List<Order> _orders;
  final List<PortfolioItem> _portfolio;
  final List<Position> _positions;
  final List<Holding> _holdings;
  final List<Transaction> _transactions;
  User _currentUser;

  double _balance;
  final double _openingBalance = 45000;
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

  void _onPriceUpdate(Map<String, double> updates) {
    for (var i = 0; i < _watchlist.length; i++) {
      final newPrice = updates[_watchlist[i].symbol];
      if (newPrice != null) {
        _watchlist[i] = Stock(
          symbol: _watchlist[i].symbol,
          name: _watchlist[i].name,
          currentPrice: newPrice,
          changePercentage: _watchlist[i].changePercentage,
          sector: _watchlist[i].sector,
          exchange: _watchlist[i].exchange,
          open: _watchlist[i].open,
          high: _watchlist[i].high,
          low: _watchlist[i].low,
          prevClose: _watchlist[i].prevClose,
          week52High: _watchlist[i].week52High,
          week52Low: _watchlist[i].week52Low,
          upperCircuit: _watchlist[i].upperCircuit,
          lowerCircuit: _watchlist[i].lowerCircuit,
          volume: _watchlist[i].volume,
          marketCap: _watchlist[i].marketCap,
        );
        _watchlistUniverse[_watchlist[i].symbol] = _watchlist[i];
      }
    }

    for (var i = 0; i < _positions.length; i++) {
      final newPrice = updates[_positions[i].symbol];
      if (newPrice != null) {
        _positions[i] = _positions[i].copyWith(currentPrice: newPrice);
      }
    }

    for (var i = 0; i < _holdings.length; i++) {
      final newPrice = updates[_holdings[i].symbol];
      if (newPrice != null) {
        _holdings[i] = _holdings[i].copyWith(currentPrice: newPrice);
      }
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _priceSubscription?.cancel();
    _alertService.dispose();
    _marketDataService.dispose();
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

  Stock stockBySymbol(String symbol) => _watchlist.firstWhere(
    (item) => item.symbol == symbol,
    orElse: () =>
        _watchlistUniverse[symbol] ??
        (_watchlist.isNotEmpty ? _watchlist.first : MockData.watchlist.first),
  );

  bool isInWatchlist(String symbol) =>
      _watchlist.any((stock) => stock.symbol == symbol);

  void addToWatchlist(String symbol) {
    if (isInWatchlist(symbol)) return;
    final stock = _watchlistUniverse[symbol];
    if (stock == null) return;
    _watchlist.add(stock);
    notifyListeners();
  }

  void removeFromWatchlist(String symbol) {
    _watchlist.removeWhere((stock) => stock.symbol == symbol);
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
  /// MIS and MTF: 1/5 of full value
  double requiredMargin(int quantity, double price, ProductType product) {
    final fullValue = quantity * price;
    if (product == ProductType.mis || product == ProductType.mtf) {
      return fullValue / 5;
    }
    return fullValue;
  }

  OrderResult placeOrder({
    required String symbol,
    required int quantity,
    required OrderType type,
    OrderVariety variety = OrderVariety.market,
    ProductType product = ProductType.cnc,
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
        errorMessage: 'Quantity should be greater than 0.',
      );
    }

    final effectivePrice = price > 0
        ? price
        : stockBySymbol(symbol).currentPrice;

    if (variety == OrderVariety.limit || variety == OrderVariety.slLimit) {
      if (price < 0) {
        return const OrderResult(
          success: false,
          errorMessage: 'Price must be >= 0 for limit orders.',
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
              'Insufficient wallet balance for this margin requirement.',
        );
      }

      _balance -= margin;
      _applyBuy(stock, quantity);

      // Update positions or holdings based on product type
      if (product == ProductType.mis || product == ProductType.nrml) {
        _applyPositionBuy(stock, quantity, effectivePrice, product, type);
      } else {
        // CNC or MTF -> holdings
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
          errorMessage: 'No holdings available to sell this symbol.',
        );
      }

      final holding = _portfolio[holdingIndex];
      if (quantity > holding.totalQuantity) {
        return OrderResult(
          success: false,
          errorMessage:
              'Only ${holding.totalQuantity} quantity available to sell.',
        );
      }

      _balance += margin;
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
          amount: margin,
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
        errorMessage: 'Deposit amount should be greater than zero.',
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
        errorMessage: 'Withdrawal amount should be greater than zero.',
      );
    }

    if (amount > _balance) {
      return const OrderResult(
        success: false,
        errorMessage: 'Withdrawal exceeds available balance.',
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

  final List<GTTOrder> _gttOrders = [
    GTTOrder(
      id: 'GTT-001',
      symbol: 'RELIANCE',
      type: GTTType.single,
      triggerPrice: 2400.0,
      orderType: OrderType.buy,
      quantity: 10,
      limitPrice: 2410.0,
      createdAt: DateTime(2024, 1, 10),
    ),
    GTTOrder(
      id: 'GTT-002',
      symbol: 'TCS',
      type: GTTType.oco,
      triggerPrice: 3800.0,
      secondTriggerPrice: 3500.0,
      orderType: OrderType.sell,
      quantity: 5,
      limitPrice: 3790.0,
      createdAt: DateTime(2024, 1, 12),
    ),
  ];

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

  final List<BasketOrder> _basketOrders = [
    BasketOrder(
      id: 'BASKET-001',
      name: 'Tech Basket',
      entries: [
        const BasketOrderEntry(
          symbol: 'INFY',
          type: OrderType.buy,
          quantity: 10,
          variety: OrderVariety.market,
          product: ProductType.cnc,
          estimatedMargin: 14500.0,
        ),
        const BasketOrderEntry(
          symbol: 'WIPRO',
          type: OrderType.buy,
          quantity: 20,
          variety: OrderVariety.limit,
          price: 450.0,
          product: ProductType.cnc,
          estimatedMargin: 9000.0,
        ),
      ],
      createdAt: DateTime(2024, 1, 15),
    ),
  ];

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
        errorMessage: 'Basket not found.',
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
          errorMessage: 'Failed on ${entry.symbol}: ${result.errorMessage}',
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

  final List<Alert> _alerts = [
    Alert(
      id: 'ALERT-001',
      symbol: 'NIFTY',
      type: AlertType.priceAbove,
      targetPrice: 22000.0,
      createdAt: DateTime(2024, 1, 8),
    ),
    Alert(
      id: 'ALERT-002',
      symbol: 'HDFC',
      type: AlertType.priceBelow,
      targetPrice: 1500.0,
      createdAt: DateTime(2024, 1, 9),
    ),
  ];

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
