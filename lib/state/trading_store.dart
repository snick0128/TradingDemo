import 'dart:collection';

import 'package:flutter/material.dart';

import '../models/trading_models.dart';
import '../services/mock_data_service.dart';

class OrderResult {
  final bool success;
  final String message;

  const OrderResult(this.success, this.message);
}

class TradingStore extends ChangeNotifier {
  TradingStore()
      : _watchlist = List<Stock>.of(MockData.watchlist),
        _orders = List<Order>.of(MockData.orders),
        _portfolio = List<PortfolioItem>.of(MockData.portfolio),
        _transactions = List<Transaction>.of(MockData.transactions),
        _balance = 50000;

  final List<Stock> _watchlist;
  final List<Order> _orders;
  final List<PortfolioItem> _portfolio;
  final List<Transaction> _transactions;

  double _balance;
  final double _openingBalance = 45000;

  UnmodifiableListView<Stock> get watchlist => UnmodifiableListView(_watchlist);
  UnmodifiableListView<Order> get orders => UnmodifiableListView(_orders);
  UnmodifiableListView<PortfolioItem> get portfolio => UnmodifiableListView(_portfolio);
  UnmodifiableListView<Transaction> get transactions => UnmodifiableListView(_transactions);
  
  double get balance => _balance;
  double get openingBalance => _openingBalance;
  
  double get payIn => _transactions.where((tx) => tx.isDeposit && tx.title.contains('Funds')).fold(0.0, (sum, tx) => sum + tx.amount);
  double get payOut => _transactions.where((tx) => !tx.isDeposit && tx.title.contains('Withdrawal')).fold(0.0, (sum, tx) => sum + tx.amount);
  double get usedMargin => _transactions.where((tx) => !tx.isDeposit && tx.title.contains('Margin blocked')).fold(0.0, (sum, tx) => sum + tx.amount) - 
                          _transactions.where((tx) => tx.isDeposit && tx.title.contains('Margin released')).fold(0.0, (sum, tx) => sum + tx.amount);

  double get totalInvestment => _portfolio.fold(0, (sum, item) => sum + item.investedValue);
  double get totalCurrentValue => _portfolio.fold(0, (sum, item) => sum + item.currentValue);
  double get totalPnl => totalCurrentValue - totalInvestment;
  double get totalBalance => _balance + usedMargin;

  Stock stockBySymbol(String symbol) =>
      _watchlist.firstWhere((item) => item.symbol == symbol, orElse: () => _watchlist.first);

  OrderResult placeOrder({
    required String symbol,
    required int quantity,
    required OrderType type,
  }) {
    if (quantity <= 0) {
      return const OrderResult(false, 'Quantity should be greater than 0.');
    }

    final stock = stockBySymbol(symbol);
    final margin = (stock.currentPrice * quantity) / 5;

    if (type == OrderType.buy) {
      if (_balance < margin) {
        return const OrderResult(false, 'Insufficient wallet balance for this margin requirement.');
      }
      _balance -= margin;
      _applyBuy(stock, quantity);
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
      final holdingIndex = _portfolio.indexWhere((item) => item.symbol == stock.symbol);
      if (holdingIndex < 0) {
        return const OrderResult(false, 'No holdings available to sell this symbol.');
      }

      final holding = _portfolio[holdingIndex];
      if (quantity > holding.totalQuantity) {
        return OrderResult(false, 'Only ${holding.totalQuantity} quantity available to sell.');
      }

      _balance += margin;
      _applySell(stock, quantity, holdingIndex);
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

    _orders.insert(
      0,
      Order(
        id: 'ORD-${DateTime.now().millisecondsSinceEpoch}',
        symbol: stock.symbol,
        name: stock.name,
        quantity: quantity,
        price: stock.currentPrice,
        type: type,
        status: OrderStatus.approved,
        dateTime: DateTime.now(),
      ),
    );

    notifyListeners();
    return OrderResult(true, 'Order executed: ${type.name.toUpperCase()} ${stock.symbol}');
  }

  OrderResult deposit(double amount) {
    if (amount <= 0) {
      return const OrderResult(false, 'Deposit amount should be greater than zero.');
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
    return const OrderResult(true, 'Funds added to wallet.');
  }

  OrderResult withdraw(double amount) {
    if (amount <= 0) {
      return const OrderResult(false, 'Withdrawal amount should be greater than zero.');
    }

    if (amount > _balance) {
      return const OrderResult(false, 'Withdrawal exceeds available balance.');
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
    return const OrderResult(true, 'Withdrawal successful.');
  }

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
        ((current.avgPrice * current.totalQuantity) + (stock.currentPrice * quantity)) / newQty;

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
}
