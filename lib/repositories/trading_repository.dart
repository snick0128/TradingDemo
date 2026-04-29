import '../models/trading_models.dart';

/// Abstract contract for all trading operations.
/// Swap: MockTradingRepository → ZerodhaTradingRepository
abstract class TradingRepository {
  // ─── Market Data ──────────────────────────────────────────────────────────

  /// Fetch full quote for a symbol.
  Future<Stock> getQuote(String symbol);

  /// Fetch multiple quotes at once.
  Future<List<Stock>> getQuotes(List<String> symbols);

  /// Stream of real-time price updates.
  Stream<Map<String, double>> get priceUpdates;

  /// Fetch OHLCV candle data.
  Future<List<Map<String, dynamic>>> getCandles({
    required String symbol,
    required String interval, // '1m', '5m', '1D', etc.
    required DateTime from,
    required DateTime to,
  });

  // ─── Orders ───────────────────────────────────────────────────────────────

  /// Place a new order.
  Future<OrderResult> placeOrder({
    required String symbol,
    required int quantity,
    required OrderType type,
    OrderVariety variety,
    ProductType product,
    OrderValidity validity,
    double price,
    double? triggerPrice,
  });

  /// Cancel a pending order.
  Future<bool> cancelOrder(String orderId);

  /// Modify a pending order.
  Future<OrderResult> modifyOrder({
    required String orderId,
    int? quantity,
    double? price,
    double? triggerPrice,
  });

  /// Fetch all orders for today.
  Future<List<Order>> getOrders();

  /// Fetch trade book (executed orders).
  Future<List<Order>> getTrades();

  // ─── Portfolio ────────────────────────────────────────────────────────────

  /// Fetch open positions.
  Future<List<Position>> getPositions();

  /// Fetch holdings (CNC).
  Future<List<Holding>> getHoldings();

  /// Convert position product type (MIS ↔ CNC).
  Future<bool> convertPosition({
    required String symbol,
    required ProductType from,
    required ProductType to,
  });

  // ─── Funds ────────────────────────────────────────────────────────────────

  /// Fetch margin/funds breakdown.
  Future<MarginBreakdown> getMarginBreakdown();

  /// Fetch transaction ledger.
  Future<List<Transaction>> getTransactions();

  // ─── GTT ──────────────────────────────────────────────────────────────────

  Future<List<GTTOrder>> getGttOrders();
  Future<GTTOrder> createGttOrder(GTTOrder order);
  Future<bool> cancelGttOrder(String id);
}

class OrderResult {
  final bool success;
  final String? orderId;
  final String? errorMessage;

  const OrderResult({required this.success, this.orderId, this.errorMessage});

  factory OrderResult.success(String orderId) => OrderResult(success: true, orderId: orderId);
  factory OrderResult.failure(String msg) => OrderResult(success: false, errorMessage: msg);

  String get message => success ? (orderId ?? 'Success') : (errorMessage ?? 'Error');
}
