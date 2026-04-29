import '../models/trading_models.dart';

class MockData {
  // Only market stock seed data is mocked now.
  static final List<Stock> watchlist = [
    Stock(
      symbol: 'REL',
      name: 'Reliance Industries',
      currentPrice: 2945.50,
      changePercentage: 1.25,
      sector: 'Energy',
    ),
    Stock(
      symbol: 'TCS',
      name: 'Tata Consultancy Services',
      currentPrice: 4120.00,
      changePercentage: -0.45,
      sector: 'IT',
    ),
    Stock(
      symbol: 'HDFCBANK',
      name: 'HDFC Bank',
      currentPrice: 1530.25,
      changePercentage: 0.85,
      sector: 'Banking',
    ),
    Stock(
      symbol: 'INFY',
      name: 'Infosys',
      currentPrice: 1420.10,
      changePercentage: -1.15,
      sector: 'IT',
    ),
    Stock(
      symbol: 'ICICIBANK',
      name: 'ICICI Bank',
      currentPrice: 1085.00,
      changePercentage: 1.10,
      sector: 'Banking',
    ),
    Stock(
      symbol: 'BHARTIARTL',
      name: 'Bharti Airtel',
      currentPrice: 1210.45,
      changePercentage: 2.30,
      sector: 'Telecom',
    ),
    Stock(
      symbol: 'WIPRO',
      name: 'Wipro Limited',
      currentPrice: 480.20,
      changePercentage: -0.20,
      sector: 'IT',
    ),
    Stock(
      symbol: 'ITC',
      name: 'ITC Limited',
      currentPrice: 435.60,
      changePercentage: 0.15,
      sector: 'FMCG',
    ),
  ];
}
