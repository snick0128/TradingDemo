enum OrderStatus { pending, approved, rejected }
enum OrderType { buy, sell }

class Stock {
  final String symbol;
  final String name;
  final double currentPrice;
  final double changePercentage;
  final String sector;

  Stock({
    required this.symbol,
    required this.name,
    required this.currentPrice,
    required this.changePercentage,
    required this.sector,
  });

  bool get isPositive => changePercentage >= 0;
}

class Order {
  final String id;
  final String symbol;
  final String name;
  final int quantity;
  final double price;
  final OrderType type;
  final OrderStatus status;
  final DateTime dateTime;

  Order({
    required this.id,
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.price,
    required this.type,
    required this.status,
    required this.dateTime,
  });
}

class PortfolioItem {
  final String symbol;
  final String name;
  final int totalQuantity;
  final double avgPrice;
  final double currentPrice;

  PortfolioItem({
    required this.symbol,
    required this.name,
    required this.totalQuantity,
    required this.avgPrice,
    required this.currentPrice,
  });

  double get investedValue => totalQuantity * avgPrice;
  double get currentValue => totalQuantity * currentPrice;
  double get pnl => currentValue - investedValue;
  double get pnlPercentage => investedValue == 0 ? 0 : (pnl / investedValue) * 100;
}

class Transaction {
  final String id;
  final String title;
  final double amount;
  final DateTime dateTime;
  final bool isDeposit;

  Transaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.dateTime,
    required this.isDeposit,
  });
}
