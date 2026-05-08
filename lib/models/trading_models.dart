import 'dart:collection';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum ChartType { candles, line, area, heikinAshi, bar, hollowCandle }

enum ChartTimeframe { m1, m3, m5, m10, m15, m30, h1, h4, d1, w1, mo1 }

enum ChartDateRange { d1, d5, mo1, mo3, mo6, y1, y3, y5, max }

enum OrderStatus {
  pending,
  approved,
  rejected,
  cancelled,
  executed,
  partiallyExecuted,
}

enum OrderType { buy, sell }

enum OrderVariety { market, limit, sl, amo, iceberg }

enum ProductType { mis, nrml, overnight, mtf }

enum OrderValidity { day, ioc, gtc, gtd }

enum GTTType { single, oco }

enum AlertType {
  priceAbove,
  priceBelow,
  percentageMove,
  volumeSpike,
  orderExecution,
  orderRejection,
  slTriggered,
  marginWarning,
  autoSquareOffWarning,
  pnlTarget,
  news,
}

enum IPOStatus { upcoming, ongoing, closed, listed }

enum TransactionType {
  deposit,
  withdrawal,
  marginBlocked,
  marginReleased,
  brokerage,
  stt,
  gst,
  exchangeCharges,
}

// ─── Stock ────────────────────────────────────────────────────────────────────

class Stock {
  final String symbol;
  final String name;
  final double currentPrice;
  final double changePercentage;
  final String sector;
  final String exchange;
  /// Angel One instrument token — required for MCX/NFO/CDS historical data
  /// and quote lookups. Empty string for watchlist stocks seeded from REST.
  final String token;
  final double? open;
  final double? high;
  final double? low;
  final double? prevClose;
  final double? week52High;
  final double? week52Low;
  final double? upperCircuit;
  final double? lowerCircuit;
  final double? volume;
  final double? marketCap;
  /// True when the price data is stale (market closed or no recent tick).
  final bool isStale;

  Stock({
    required this.symbol,
    required this.name,
    required this.currentPrice,
    required this.changePercentage,
    required this.sector,
    this.exchange = 'NSE',
    this.token = '',
    this.open,
    this.high,
    this.low,
    this.prevClose,
    this.week52High,
    this.week52Low,
    this.upperCircuit,
    this.lowerCircuit,
    this.volume,
    this.marketCap,
    this.isStale = false,
  });

  bool get isPositive => changePercentage >= 0;
}

// ─── Order ────────────────────────────────────────────────────────────────────

class Order {
  final String id;
  final String symbol;
  final String name;
  final int quantity;
  final double price;
  final OrderType type;
  final OrderStatus status;
  final DateTime dateTime;

  // Extended fields
  final OrderVariety variety;
  final ProductType product;
  final OrderValidity validity;
  final DateTime? validityDate;
  final double? triggerPrice;
  final int? disclosedQuantity;
  final DateTime? executedAt;
  final double? executedPrice;
  final int? executedQuantity;
  final String? rejectionReason;
  final double? targetPrice;
  final double? stopLossPrice;
  final bool isBracketOrder;
  final bool isCoverOrder;

  Order({
    required this.id,
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.price,
    required this.type,
    required this.status,
    required this.dateTime,
    this.variety = OrderVariety.market,
    this.product = ProductType.mis,
    this.validity = OrderValidity.day,
    this.validityDate,
    this.triggerPrice,
    this.disclosedQuantity,
    this.executedAt,
    this.executedPrice,
    this.executedQuantity,
    this.rejectionReason,
    this.targetPrice,
    this.stopLossPrice,
    this.isBracketOrder = false,
    this.isCoverOrder = false,
  });

  Order copyWith({
    String? id,
    String? symbol,
    String? name,
    int? quantity,
    double? price,
    OrderType? type,
    OrderStatus? status,
    DateTime? dateTime,
    OrderVariety? variety,
    ProductType? product,
    OrderValidity? validity,
    DateTime? validityDate,
    double? triggerPrice,
    int? disclosedQuantity,
    DateTime? executedAt,
    double? executedPrice,
    int? executedQuantity,
    String? rejectionReason,
    double? targetPrice,
    double? stopLossPrice,
    bool? isBracketOrder,
    bool? isCoverOrder,
  }) {
    return Order(
      id: id ?? this.id,
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      type: type ?? this.type,
      status: status ?? this.status,
      dateTime: dateTime ?? this.dateTime,
      variety: variety ?? this.variety,
      product: product ?? this.product,
      validity: validity ?? this.validity,
      validityDate: validityDate ?? this.validityDate,
      triggerPrice: triggerPrice ?? this.triggerPrice,
      disclosedQuantity: disclosedQuantity ?? this.disclosedQuantity,
      executedAt: executedAt ?? this.executedAt,
      executedPrice: executedPrice ?? this.executedPrice,
      executedQuantity: executedQuantity ?? this.executedQuantity,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      targetPrice: targetPrice ?? this.targetPrice,
      stopLossPrice: stopLossPrice ?? this.stopLossPrice,
      isBracketOrder: isBracketOrder ?? this.isBracketOrder,
      isCoverOrder: isCoverOrder ?? this.isCoverOrder,
    );
  }
}

// ─── PortfolioItem ────────────────────────────────────────────────────────────

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
  double get pnlPercentage =>
      investedValue == 0 ? 0 : (pnl / investedValue) * 100;
}

// ─── Position ─────────────────────────────────────────────────────────────────

class Position {
  final String symbol;
  final String name;
  final ProductType product;
  final int quantity;
  final double avgPrice;
  final double currentPrice;
  final OrderType side;
  final DateTime openedAt;

  Position({
    required this.symbol,
    required this.name,
    required this.product,
    required this.quantity,
    required this.avgPrice,
    required this.currentPrice,
    required this.side,
    required this.openedAt,
  });

  double get investedValue => quantity * avgPrice;
  double get currentValue => quantity * currentPrice;
  double get unrealizedPnl => side == OrderType.buy
      ? currentValue - investedValue
      : investedValue - currentValue;
  double get pnlPercentage =>
      investedValue == 0 ? 0 : (unrealizedPnl / investedValue) * 100;

  Position copyWith({
    String? symbol,
    String? name,
    ProductType? product,
    int? quantity,
    double? avgPrice,
    double? currentPrice,
    OrderType? side,
    DateTime? openedAt,
  }) {
    return Position(
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      avgPrice: avgPrice ?? this.avgPrice,
      currentPrice: currentPrice ?? this.currentPrice,
      side: side ?? this.side,
      openedAt: openedAt ?? this.openedAt,
    );
  }
}

// ─── Holding ──────────────────────────────────────────────────────────────────

class Holding {
  final String symbol;
  final String name;
  final int quantity;
  final double avgPrice;
  final double currentPrice;
  final DateTime purchaseDate;
  final double? dividendReceived;

  Holding({
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.avgPrice,
    required this.currentPrice,
    required this.purchaseDate,
    this.dividendReceived,
  });

  double get investedValue => quantity * avgPrice;
  double get currentValue => quantity * currentPrice;
  double get pnl => currentValue - investedValue;
  double get pnlPercentage =>
      investedValue == 0 ? 0 : (pnl / investedValue) * 100;
  double get totalReturn => pnl + (dividendReceived ?? 0);

  Holding copyWith({
    String? symbol,
    String? name,
    int? quantity,
    double? avgPrice,
    double? currentPrice,
    DateTime? purchaseDate,
    double? dividendReceived,
  }) {
    return Holding(
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      avgPrice: avgPrice ?? this.avgPrice,
      currentPrice: currentPrice ?? this.currentPrice,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      dividendReceived: dividendReceived ?? this.dividendReceived,
    );
  }
}

// ─── Transaction ──────────────────────────────────────────────────────────────

class Transaction {
  final String id;
  final String title;
  final double amount;
  final DateTime dateTime;
  final bool isDeposit;
  final TransactionType type;
  final String? orderId;
  final String? symbol;

  Transaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.dateTime,
    required this.isDeposit,
    this.type = TransactionType.deposit,
    this.orderId,
    this.symbol,
  });
}

// ─── Market Depth ─────────────────────────────────────────────────────────────

class MarketDepthLevel {
  final double price;
  final int quantity;
  final int orders;

  const MarketDepthLevel({
    required this.price,
    required this.quantity,
    required this.orders,
  });
}

class MarketDepth {
  final String symbol;
  final List<MarketDepthLevel> bids;
  final List<MarketDepthLevel> asks;
  final DateTime timestamp;

  MarketDepth({
    required this.symbol,
    required this.bids,
    required this.asks,
    required this.timestamp,
  });

  int get totalBuyQuantity =>
      bids.fold(0, (sum, level) => sum + level.quantity);
  int get totalSellQuantity =>
      asks.fold(0, (sum, level) => sum + level.quantity);
  double get buyToSellRatio =>
      totalSellQuantity == 0 ? 0 : totalBuyQuantity / totalSellQuantity;
}

// ─── Trade ────────────────────────────────────────────────────────────────────

class Trade {
  final DateTime time;
  final double price;
  final int quantity;
  final bool isBuyerInitiated;

  const Trade({
    required this.time,
    required this.price,
    required this.quantity,
    required this.isBuyerInitiated,
  });
}

// ─── Options ──────────────────────────────────────────────────────────────────

class OptionData {
  final double ltp;
  final int oi;
  final int changeInOi;
  final double iv;
  final int volume;
  final double delta;
  final double gamma;
  final double theta;
  final double vega;
  final double bid;
  final double ask;

  const OptionData({
    required this.ltp,
    required this.oi,
    required this.changeInOi,
    required this.iv,
    required this.volume,
    required this.delta,
    required this.gamma,
    required this.theta,
    required this.vega,
    required this.bid,
    required this.ask,
  });
}

class OptionStrike {
  final double strike;
  final OptionData ce;
  final OptionData pe;
  final bool isAtm;

  const OptionStrike({
    required this.strike,
    required this.ce,
    required this.pe,
    this.isAtm = false,
  });
}

class OptionsChain {
  final String underlying;
  final DateTime expiry;
  final double underlyingPrice;
  final List<OptionStrike> strikes;
  final double maxPain;

  OptionsChain({
    required this.underlying,
    required this.expiry,
    required this.underlyingPrice,
    required this.strikes,
    required this.maxPain,
  });

  OptionStrike get atmStrike =>
      strikes.firstWhere((s) => s.isAtm, orElse: () => strikes.first);

  UnmodifiableListView<OptionStrike> get strikesView =>
      UnmodifiableListView(strikes);
}

// ─── Margin Breakdown ─────────────────────────────────────────────────────────

class MarginBreakdown {
  final double availableCash;
  final double marginUsed;
  final double marginAvailable;
  final double collateralValue;
  final double spanMargin;
  final double exposureMargin;
  final double peakMargin;

  const MarginBreakdown({
    required this.availableCash,
    required this.marginUsed,
    required this.marginAvailable,
    required this.collateralValue,
    required this.spanMargin,
    required this.exposureMargin,
    required this.peakMargin,
  });

  double get totalMargin => availableCash + collateralValue;
}

// ─── Alert ────────────────────────────────────────────────────────────────────

class Alert {
  final String id;
  final String symbol;
  final AlertType type;
  final double? targetPrice;
  final double? percentageThreshold;
  final double? basePrice;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? triggeredAt;

  Alert({
    required this.id,
    required this.symbol,
    required this.type,
    this.targetPrice,
    this.percentageThreshold,
    this.basePrice,
    this.isActive = true,
    required this.createdAt,
    this.triggeredAt,
  });

  Alert copyWith({
    String? id,
    String? symbol,
    AlertType? type,
    double? targetPrice,
    double? percentageThreshold,
    double? basePrice,
    bool? isActive,
    DateTime? createdAt,
    DateTime? triggeredAt,
  }) {
    return Alert(
      id: id ?? this.id,
      symbol: symbol ?? this.symbol,
      type: type ?? this.type,
      targetPrice: targetPrice ?? this.targetPrice,
      percentageThreshold: percentageThreshold ?? this.percentageThreshold,
      basePrice: basePrice ?? this.basePrice,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      triggeredAt: triggeredAt ?? this.triggeredAt,
    );
  }
}

// ─── AppNotification ──────────────────────────────────────────────────────────

class AppNotification {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final AlertType? relatedAlertType;
  final String? relatedSymbol;
  final String? relatedOrderId;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.relatedAlertType,
    this.relatedSymbol,
    this.relatedOrderId,
  });

  AppNotification copyWith({
    String? id,
    String? title,
    String? message,
    DateTime? timestamp,
    bool? isRead,
    AlertType? relatedAlertType,
    String? relatedSymbol,
    String? relatedOrderId,
  }) {
    return AppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      relatedAlertType: relatedAlertType ?? this.relatedAlertType,
      relatedSymbol: relatedSymbol ?? this.relatedSymbol,
      relatedOrderId: relatedOrderId ?? this.relatedOrderId,
    );
  }
}

// ─── Admin Models ─────────────────────────────────────────────────────────────

class User {
  final String id;
  final String clientId;
  final String name;
  final String email;
  final bool isActive;
  final double balance;
  final double marginLimit;
  final DateTime registeredAt;
  final DateTime? lastLoginAt;
  final String brokeragePlan;
  final bool isAdmin;

  User({
    required this.id,
    required this.clientId,
    required this.name,
    required this.email,
    this.isActive = true,
    required this.balance,
    this.marginLimit = 0,
    required this.registeredAt,
    this.lastLoginAt,
    this.brokeragePlan = 'Standard',
    this.isAdmin = false,
  });

  User copyWith({
    String? id,
    String? clientId,
    String? name,
    String? email,
    bool? isActive,
    double? balance,
    double? marginLimit,
    DateTime? registeredAt,
    DateTime? lastLoginAt,
    String? brokeragePlan,
    bool? isAdmin,
  }) {
    return User(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      name: name ?? this.name,
      email: email ?? this.email,
      isActive: isActive ?? this.isActive,
      balance: balance ?? this.balance,
      marginLimit: marginLimit ?? this.marginLimit,
      registeredAt: registeredAt ?? this.registeredAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      brokeragePlan: brokeragePlan ?? this.brokeragePlan,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }
}

class AuditLogEntry {
  final String id;
  final String adminId;
  final String action;
  final String targetId;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  const AuditLogEntry({
    required this.id,
    required this.adminId,
    required this.action,
    required this.targetId,
    required this.timestamp,
    this.metadata,
  });
}

// ─── Watchlist ────────────────────────────────────────────────────────────────

class Watchlist {
  final String id;
  final String name;
  final List<String> symbols;
  final int order;

  static const int maxWatchlists = 5;

  Watchlist({
    required this.id,
    required this.name,
    required this.symbols,
    required this.order,
  });

  UnmodifiableListView<String> get symbolsView => UnmodifiableListView(symbols);

  Watchlist copyWith({
    String? id,
    String? name,
    List<String>? symbols,
    int? order,
  }) {
    return Watchlist(
      id: id ?? this.id,
      name: name ?? this.name,
      symbols: symbols ?? this.symbols,
      order: order ?? this.order,
    );
  }
}

// ─── GTT Order ────────────────────────────────────────────────────────────────

class GTTOrder {
  final String id;
  final String symbol;
  final GTTType type;
  final double triggerPrice;
  final double? secondTriggerPrice;
  final OrderType orderType;
  final int quantity;
  final double? limitPrice;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? triggeredAt;

  GTTOrder({
    required this.id,
    required this.symbol,
    required this.type,
    required this.triggerPrice,
    this.secondTriggerPrice,
    required this.orderType,
    required this.quantity,
    this.limitPrice,
    this.isActive = true,
    required this.createdAt,
    this.triggeredAt,
  });

  GTTOrder copyWith({
    String? id,
    String? symbol,
    GTTType? type,
    double? triggerPrice,
    double? secondTriggerPrice,
    OrderType? orderType,
    int? quantity,
    double? limitPrice,
    bool? isActive,
    DateTime? createdAt,
    DateTime? triggeredAt,
  }) {
    return GTTOrder(
      id: id ?? this.id,
      symbol: symbol ?? this.symbol,
      type: type ?? this.type,
      triggerPrice: triggerPrice ?? this.triggerPrice,
      secondTriggerPrice: secondTriggerPrice ?? this.secondTriggerPrice,
      orderType: orderType ?? this.orderType,
      quantity: quantity ?? this.quantity,
      limitPrice: limitPrice ?? this.limitPrice,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      triggeredAt: triggeredAt ?? this.triggeredAt,
    );
  }
}

// ─── Basket Order ─────────────────────────────────────────────────────────────

class BasketOrderEntry {
  final String symbol;
  final OrderType type;
  final int quantity;
  final OrderVariety variety;
  final double? price;
  final ProductType product;
  final double estimatedMargin;

  const BasketOrderEntry({
    required this.symbol,
    required this.type,
    required this.quantity,
    required this.variety,
    this.price,
    required this.product,
    required this.estimatedMargin,
  });
}

class BasketOrder {
  final String id;
  final String name;
  final List<BasketOrderEntry> entries;
  final DateTime createdAt;
  final DateTime? executedAt;

  BasketOrder({
    required this.id,
    required this.name,
    required this.entries,
    required this.createdAt,
    this.executedAt,
  });

  double get totalMargin =>
      entries.fold(0, (sum, entry) => sum + entry.estimatedMargin);

  UnmodifiableListView<BasketOrderEntry> get entriesView =>
      UnmodifiableListView(entries);

  BasketOrder copyWith({
    String? id,
    String? name,
    List<BasketOrderEntry>? entries,
    DateTime? createdAt,
    DateTime? executedAt,
  }) {
    return BasketOrder(
      id: id ?? this.id,
      name: name ?? this.name,
      entries: entries ?? this.entries,
      createdAt: createdAt ?? this.createdAt,
      executedAt: executedAt ?? this.executedAt,
    );
  }
}

// ─── IPO ──────────────────────────────────────────────────────────────────────

class IPO {
  final String id;
  final String companyName;
  final double priceMin;
  final double priceMax;
  final DateTime openDate;
  final DateTime closeDate;
  final DateTime? listingDate;
  final IPOStatus status;
  final int lotSize;
  final double? listingPrice;
  final double? listingGain;

  IPO({
    required this.id,
    required this.companyName,
    required this.priceMin,
    required this.priceMax,
    required this.openDate,
    required this.closeDate,
    this.listingDate,
    required this.status,
    required this.lotSize,
    this.listingPrice,
    this.listingGain,
  });
}

class IPOApplication {
  final String ipoId;
  final int lots;
  final double bidPrice;
  final DateTime appliedAt;
  final bool isAllotted;
  final int? allottedLots;

  const IPOApplication({
    required this.ipoId,
    required this.lots,
    required this.bidPrice,
    required this.appliedAt,
    this.isAllotted = false,
    this.allottedLots,
  });
}
