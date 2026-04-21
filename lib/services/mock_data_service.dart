import '../models/trading_models.dart';

class MockData {
  static List<Stock> watchlist = [
    Stock(symbol: 'REL', name: 'Reliance Industries', currentPrice: 2945.50, changePercentage: 1.25, sector: 'Energy'),
    Stock(symbol: 'TCS', name: 'Tata Consultancy Services', currentPrice: 4120.00, changePercentage: -0.45, sector: 'IT'),
    Stock(symbol: 'HDFCBANK', name: 'HDFC Bank', currentPrice: 1530.25, changePercentage: 0.85, sector: 'Banking'),
    Stock(symbol: 'INFY', name: 'Infosys', currentPrice: 1420.10, changePercentage: -1.15, sector: 'IT'),
    Stock(symbol: 'ICICIBANK', name: 'ICICI Bank', currentPrice: 1085.00, changePercentage: 1.10, sector: 'Banking'),
    Stock(symbol: 'BHARTIARTL', name: 'Bharti Airtel', currentPrice: 1210.45, changePercentage: 2.30, sector: 'Telecom'),
    Stock(symbol: 'WIPRO', name: 'Wipro Limited', currentPrice: 480.20, changePercentage: -0.20, sector: 'IT'),
    Stock(symbol: 'ITC', name: 'ITC Limited', currentPrice: 435.60, changePercentage: 0.15, sector: 'FMCG'),
  ];

  static List<Order> orders = [
    Order(
      id: '1',
      symbol: 'REL',
      name: 'Reliance Industries',
      quantity: 10,
      price: 2940.00,
      type: OrderType.buy,
      status: OrderStatus.approved,
      dateTime: DateTime.now().subtract(const Duration(days: 1)),
    ),
    Order(
      id: '2',
      symbol: 'TCS',
      name: 'Tata Consultancy Services',
      quantity: 5,
      price: 4130.00,
      type: OrderType.sell,
      status: OrderStatus.pending,
      dateTime: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    Order(
      id: '3',
      symbol: 'INFY',
      name: 'Infosys',
      quantity: 20,
      price: 1450.00,
      type: OrderType.buy,
      status: OrderStatus.rejected,
      dateTime: DateTime.now().subtract(const Duration(hours: 5)),
    ),
  ];

  static List<PortfolioItem> portfolio = [
    PortfolioItem(symbol: 'REL', name: 'Reliance Industries', totalQuantity: 10, avgPrice: 2850.00, currentPrice: 2945.50),
    PortfolioItem(symbol: 'HDFCBANK', name: 'HDFC Bank', totalQuantity: 25, avgPrice: 1580.00, currentPrice: 1530.25),
    PortfolioItem(symbol: 'ICICIBANK', name: 'ICICI Bank', totalQuantity: 50, avgPrice: 950.00, currentPrice: 1085.00),
  ];

  static List<Transaction> transactions = [
    Transaction(id: 'T1', title: 'Funds Added', amount: 50000, dateTime: DateTime.now().subtract(const Duration(days: 5)), isDeposit: true),
    Transaction(id: 'T2', title: 'Withdrawal', amount: 10000, dateTime: DateTime.now().subtract(const Duration(days: 2)), isDeposit: false),
    Transaction(id: 'T3', title: 'Funds Added', amount: 25000, dateTime: DateTime.now().subtract(const Duration(days: 1)), isDeposit: true),
  ];
}
