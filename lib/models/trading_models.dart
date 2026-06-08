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
  adminCredit,
  bonus,
  referral,
  ipoProfit,
  ipoLoss,
  ipoMarginBlocked,
  manualAdjustment,
}

enum IpoRequestStatus { pending, accepted, rejected }

enum LedgerEntryType {
  deposit,
  adminCredit,
  bonus,
  referral,
  ipoProfit,
  ipoLoss,
  ipoMarginBlocked,
  withdrawal,
  manualAdjustment,
  marginBlocked,
  marginReleased,
  brokerage,
  other;

  static LedgerEntryType fromString(String s) {
    switch (s.toUpperCase()) {
      case 'DEPOSIT':              return LedgerEntryType.deposit;
      case 'ADMIN_CREDIT':         return LedgerEntryType.adminCredit;
      case 'BONUS':                return LedgerEntryType.bonus;
      case 'REFERRAL':             return LedgerEntryType.referral;
      case 'IPO_PROFIT':           return LedgerEntryType.ipoProfit;
      case 'IPO_LOSS':             return LedgerEntryType.ipoLoss;
      case 'IPO_MARGIN_BLOCKED':   return LedgerEntryType.ipoMarginBlocked;
      case 'WITHDRAWAL':           return LedgerEntryType.withdrawal;
      case 'MANUAL_ADJUSTMENT':    return LedgerEntryType.manualAdjustment;
      case 'MARGIN_BLOCKED':       return LedgerEntryType.marginBlocked;
      case 'MARGIN_RELEASED':      return LedgerEntryType.marginReleased;
      case 'BROKERAGE':            return LedgerEntryType.brokerage;
      default:                     return LedgerEntryType.other;
    }
  }

  String get displayName {
    switch (this) {
      case LedgerEntryType.deposit:           return 'Deposit';
      case LedgerEntryType.adminCredit:       return 'Admin Credit';
      case LedgerEntryType.bonus:             return 'Bonus';
      case LedgerEntryType.referral:          return 'Referral';
      case LedgerEntryType.ipoProfit:         return 'IPO Profit';
      case LedgerEntryType.ipoLoss:           return 'IPO Loss';
      case LedgerEntryType.ipoMarginBlocked:  return 'IPO Margin';
      case LedgerEntryType.withdrawal:        return 'Withdrawal';
      case LedgerEntryType.manualAdjustment:  return 'Adjustment';
      case LedgerEntryType.marginBlocked:     return 'Margin Blocked';
      case LedgerEntryType.marginReleased:    return 'Margin Released';
      case LedgerEntryType.brokerage:         return 'Brokerage';
      case LedgerEntryType.other:             return 'Other';
    }
  }

  bool get isCredit {
    return this == LedgerEntryType.deposit ||
        this == LedgerEntryType.adminCredit ||
        this == LedgerEntryType.bonus ||
        this == LedgerEntryType.referral ||
        this == LedgerEntryType.ipoProfit ||
        this == LedgerEntryType.marginReleased ||
        this == LedgerEntryType.manualAdjustment;
  }
}

// ─── InstrumentType ───────────────────────────────────────────────────────────

/// Classifies what kind of financial instrument a [Stock] represents.
/// Set via [TradingStore.registerSearchResult] using the Angel One
/// `instrumentType` field returned by the search API.
enum InstrumentType {
  equity,        // NSE/BSE cash equity — RELIANCE, TCS, SBIN
  marketIndex,   // Market index — NIFTY, BANKNIFTY, SENSEX
  etf,           // Exchange-traded fund — GOLDBEES, NIFTYBEES
  futuresStkIdx, // NSE stock/index futures — RELIANCE25JUNFUT, NIFTY25JUNFUT
  futuresCom,    // MCX commodity futures — GOLD, SILVER, CRUDEOIL
  optionCE,      // Call option — NIFTY25JUN24000CE
  optionPE,      // Put option — NIFTY25JUN24000PE
  currency,      // CDS currency pair — USDINR
  unknown,       // Fallback — exchange-based heuristics apply
}

extension InstrumentTypeX on InstrumentType {
  /// Parse an Angel One `instrumentType` string into an [InstrumentType].
  /// Handles both the `/search` endpoint (`type`) and the
  /// `/derivatives/search` endpoint (`instrumentType`).
  static InstrumentType fromAngelOne(String raw, {String symbol = ''}) {
    switch (raw.toUpperCase()) {
      case 'EQ':
        return InstrumentType.equity;
      case 'ETF':
      case 'ETFS':
        return InstrumentType.etf;
      case 'INDEX':
      case 'UNDIND':
        return InstrumentType.marketIndex;
      case 'FUTSTK':
      case 'FUTIDX':
        return InstrumentType.futuresStkIdx;
      case 'FUTCOM':
        return InstrumentType.futuresCom;
      case 'FUTCUR':
        return InstrumentType.currency;
      case 'OPTSTK':
      case 'OPTIDX':
        final upper = symbol.toUpperCase();
        if (upper.endsWith('CE')) return InstrumentType.optionCE;
        if (upper.endsWith('PE')) return InstrumentType.optionPE;
        return InstrumentType.optionCE; // safe default
      case 'OPTCUR':
        final upper = symbol.toUpperCase();
        if (upper.endsWith('PE')) return InstrumentType.optionPE;
        return InstrumentType.optionCE;
      default:
        return InstrumentType.unknown;
    }
  }

  bool get isDerivative =>
      this == InstrumentType.futuresStkIdx ||
      this == InstrumentType.futuresCom ||
      this == InstrumentType.optionCE ||
      this == InstrumentType.optionPE;

  /// True for instruments that can have an option chain (index + large-cap equity).
  bool get hasFnoChain =>
      this == InstrumentType.equity ||
      this == InstrumentType.marketIndex ||
      this == InstrumentType.unknown;

  bool get isOption =>
      this == InstrumentType.optionCE || this == InstrumentType.optionPE;

  bool get isFuturesContract =>
      this == InstrumentType.futuresStkIdx ||
      this == InstrumentType.futuresCom;
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

  /// Expiry date for futures/options contracts. Null for equities.
  final DateTime? expiry;

  /// What kind of instrument this is. Defaults to [InstrumentType.unknown]
  /// for backward-compat with stocks seeded before the type system existed.
  final InstrumentType instrumentType;

  /// Strike price — populated for options contracts only.
  final double? strikePrice;

  /// Best bid price from live Angel One tick (null when not yet received).
  final double? bid;

  /// Best ask price from live Angel One tick (null when not yet received).
  final double? ask;

  /// Top-5 market depth levels — populated from Angel One WS ticks.
  /// Null on first load; updated on every tick that carries depth data.
  final MarketDepth? depth;

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
    this.expiry,
    this.instrumentType = InstrumentType.unknown,
    this.strikePrice,
    this.bid,
    this.ask,
    this.depth,
  });

  bool get isPositive => changePercentage >= 0;

  /// True if this instrument IS a futures contract (not an equity with futures).
  bool get isFutures =>
      instrumentType.isFuturesContract || expiry != null;

  /// True if this instrument IS an option (CE or PE).
  bool get isOption => instrumentType.isOption;

  /// True if an option chain should be available for this instrument.
  bool get hasFnoChain => instrumentType.hasFnoChain;

  /// Days until expiry. Null for equities or if expiry is unknown.
  int? get daysToExpiry {
    if (expiry == null) return null;
    return expiry!.difference(DateTime.now()).inDays;
  }
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
  final double? pnl;
  final String? rejectionReason;
  final double? targetPrice;
  final double? stopLossPrice;
  final bool isBracketOrder;
  final bool isCoverOrder;
  final double? chargesApplied;
  final String? exchange;
  final double? leverageApplied;
  final double? marginUsed;
  final bool isAutoSquareOff;

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
    this.pnl,
    this.rejectionReason,
    this.targetPrice,
    this.stopLossPrice,
    this.isBracketOrder = false,
    this.isCoverOrder = false,
    this.chargesApplied,
    this.exchange,
    this.leverageApplied,
    this.marginUsed,
    this.isAutoSquareOff = false,
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
    double? pnl,
    String? rejectionReason,
    double? targetPrice,
    double? stopLossPrice,
    bool? isBracketOrder,
    bool? isCoverOrder,
    double? chargesApplied,
    String? exchange,
    double? leverageApplied,
    double? marginUsed,
    bool? isAutoSquareOff,
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
      pnl: pnl ?? this.pnl,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      targetPrice: targetPrice ?? this.targetPrice,
      stopLossPrice: stopLossPrice ?? this.stopLossPrice,
      isBracketOrder: isBracketOrder ?? this.isBracketOrder,
      isCoverOrder: isCoverOrder ?? this.isCoverOrder,
      chargesApplied: chargesApplied ?? this.chargesApplied,
      exchange: exchange ?? this.exchange,
      leverageApplied: leverageApplied ?? this.leverageApplied,
      marginUsed: marginUsed ?? this.marginUsed,
      isAutoSquareOff: isAutoSquareOff ?? this.isAutoSquareOff,
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
  final String exchange;
  final double marginUsed;
  /// Angel One instrument token. Empty when not yet persisted in Firestore.
  /// When non-empty, used as the primary position-index key instead of
  /// exchange:symbol — guarantees uniqueness across expiries, strikes, and
  /// option types for the same underlying.
  final String token;

  Position({
    required this.symbol,
    required this.name,
    required this.product,
    required this.quantity,
    required this.avgPrice,
    required this.currentPrice,
    required this.side,
    required this.openedAt,
    this.exchange = 'NSE',
    this.marginUsed = 0.0,
    this.token = '',
  });

  double get investedValue => quantity * avgPrice;

  /// currentPrice = 0 means no live tick has arrived yet (cold start / reconnect).
  /// Use avgPrice as a safe fallback so unrealizedPnl stays at 0 rather than
  /// reporting a fake catastrophic loss equal to the full invested value.
  double get _effectivePrice => currentPrice > 0 ? currentPrice : avgPrice;

  double get currentValue  => quantity * _effectivePrice;
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
    String? exchange,
    double? marginUsed,
    String? token,
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
      exchange: exchange ?? this.exchange,
      marginUsed: marginUsed ?? this.marginUsed,
      token: token ?? this.token,
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

// ─── Account Equity ───────────────────────────────────────────────────────────

/// Live account equity metrics, kept in sync with the backend.
///
/// Formulas (all server-authoritative):
///   walletBalance = freeBalance + usedMargin
///   equity        = walletBalance + runningPnL
///   freeMargin    = equity - usedMargin
///   marginLevel%  = (equity / usedMargin) × 100  (null = no open positions)
class AccountEquity {
  /// Total deposited cash (free cash + blocked margin).
  final double walletBalance;

  /// Cash not blocked by any position (= Firestore users.balance).
  final double freeBalance;

  /// Sum of margin blocked by all open positions.
  final double usedMargin;

  /// Cash available for new orders = equity - usedMargin.
  final double freeMargin;

  /// walletBalance + runningPnL — the real-time account value.
  final double equity;

  /// Margin level percentage = (equity / usedMargin) × 100.
  /// null when there are no open positions (no margin in use).
  final double? marginLevel;

  /// Sum of unrealized P&L across all open positions.
  final double runningPnL;

  /// When this snapshot was last updated by the backend.
  final DateTime? lastUpdated;

  const AccountEquity({
    this.walletBalance  = 0,
    this.freeBalance    = 0,
    this.usedMargin     = 0,
    this.freeMargin     = 0,
    this.equity         = 0,
    this.marginLevel,
    this.runningPnL     = 0,
    this.lastUpdated,
  });

  static const AccountEquity zero = AccountEquity();

  /// Parse from a Firestore users/{userId} document snapshot.
  factory AccountEquity.fromFirestore(Map<String, dynamic> data) {
    final balance     = (data['balance']       as num?)?.toDouble() ?? 0;
    final usedMargin  = (data['usedMargin']     as num?)?.toDouble() ?? 0;
    final freeMargin  = (data['freeMargin']     as num?)?.toDouble() ?? 0;
    final equity      = (data['equity']         as num?)?.toDouble() ?? 0;
    final marginLevel = (data['marginLevel']    as num?)?.toDouble();
    final runningPnL  = (data['runningPnL']     as num?)?.toDouble() ?? 0;
    final wallet      = (data['walletBalance']  as num?)?.toDouble() ?? (balance + usedMargin);
    final updatedMs   = data['lastEquityUpdate'] as int?;
    return AccountEquity(
      walletBalance: wallet,
      freeBalance:   balance,
      usedMargin:    usedMargin,
      freeMargin:    freeMargin.isNaN || freeMargin.isInfinite ? balance : freeMargin,
      equity:        equity.isNaN || equity.isInfinite ? balance : equity,
      marginLevel:   marginLevel,
      runningPnL:    runningPnL,
      lastUpdated:   updatedMs != null
          ? DateTime.fromMillisecondsSinceEpoch(updatedMs)
          : null,
    );
  }

  AccountEquity copyWith({
    double? walletBalance,
    double? freeBalance,
    double? usedMargin,
    double? freeMargin,
    double? equity,
    double? marginLevel,
    double? runningPnL,
    DateTime? lastUpdated,
  }) {
    return AccountEquity(
      walletBalance: walletBalance ?? this.walletBalance,
      freeBalance:   freeBalance   ?? this.freeBalance,
      usedMargin:    usedMargin    ?? this.usedMargin,
      freeMargin:    freeMargin    ?? this.freeMargin,
      equity:        equity        ?? this.equity,
      marginLevel:   marginLevel   ?? this.marginLevel,
      runningPnL:    runningPnL    ?? this.runningPnL,
      lastUpdated:   lastUpdated   ?? this.lastUpdated,
    );
  }

  /// Whether the account is at risk (equity < 2× safeLevel or margin level < 200%)
  bool isAtRisk(double safeLevel) => equity < safeLevel * 2;

  /// Whether auto square-off is imminent (equity <= safeLevel)
  bool isCritical(double safeLevel) => equity > 0 && equity <= safeLevel;
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
  /// Angel One instrument token for the CE contract. Empty for mock/fallback strikes.
  final String ceToken;
  /// Angel One instrument token for the PE contract. Empty for mock/fallback strikes.
  final String peToken;

  const OptionStrike({
    required this.strike,
    required this.ce,
    required this.pe,
    this.isAtm = false,
    this.ceToken = '',
    this.peToken = '',
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
  /// Unrealized P&L from open positions — persisted by backend on every tick.
  final double runningPnL;

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
    this.runningPnL = 0,
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
    double? runningPnL,
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
      runningPnL: runningPnL ?? this.runningPnL,
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

// ─── IPO Request ──────────────────────────────────────────────────────────────

class IpoRequest {
  final String id;
  final String userId;
  final String userName;
  final String ipoId;
  final String ipoName;
  final int lots;
  final int lotSize;
  final double bidPrice;
  final double lotValue;
  final double marginBlocked;
  final int marginPercent;
  final IpoRequestStatus status;
  final DateTime appliedAt;

  // Settlement fields
  final double? profitAmount;
  final double? lossAmount;
  final double? returnAmount;
  final String? settledBy;
  final DateTime? settledAt;

  const IpoRequest({
    required this.id,
    required this.userId,
    required this.userName,
    required this.ipoId,
    required this.ipoName,
    required this.lots,
    required this.lotSize,
    required this.bidPrice,
    required this.lotValue,
    required this.marginBlocked,
    this.marginPercent = 10,
    required this.status,
    required this.appliedAt,
    this.profitAmount,
    this.lossAmount,
    this.returnAmount,
    this.settledBy,
    this.settledAt,
  });

  factory IpoRequest.fromFirestore(String id, Map<String, dynamic> d) {
    IpoRequestStatus parseStatus(String s) {
      switch (s.toUpperCase()) {
        case 'ACCEPTED':
        case 'APPROVED':
          return IpoRequestStatus.accepted;
        case 'REJECTED':
          return IpoRequestStatus.rejected;
        default:
          return IpoRequestStatus.pending;
      }
    }

    DateTime? parseTs(dynamic ts) {
      if (ts == null) return null;
      if (ts is DateTime) return ts;
      try {
        // Firestore Timestamp
        return (ts as dynamic).toDate() as DateTime;
      } catch (_) {
        return null;
      }
    }

    final batchPrice  = ((d['batchPrice'] as num?) ?? 0).toDouble();
    final lotValue    = ((d['lotValue']   as num?) ?? batchPrice).toDouble();
    final marginPct   = ((d['marginPercent'] as num?) ?? 10).toInt();
    final blocked     = ((d['blockedAmount'] as num?) ?? 0).toDouble();

    return IpoRequest(
      id:            id,
      userId:        (d['userId']       as String?) ?? '',
      userName:      (d['userName']     as String?) ?? '',
      ipoId:         (d['ipoId']        as String?) ?? '',
      ipoName:       (d['companyName']  as String?) ?? '',
      lots:          ((d['lots']        as num?) ?? 0).toInt(),
      lotSize:       ((d['lotSize']     as num?) ?? 0).toInt(),
      bidPrice:      ((d['bidPrice']    as num?) ?? 0).toDouble(),
      lotValue:      lotValue,
      marginBlocked: blocked,
      marginPercent: marginPct,
      status:        parseStatus((d['status'] as String?) ?? 'PENDING'),
      appliedAt:     parseTs(d['createdAt']) ?? DateTime.now(),
      profitAmount:  (d['profitAmount'] as num?)?.toDouble(),
      lossAmount:    (d['lossAmount']   as num? ?? d['cutAmount'] as num?)?.toDouble(),
      returnAmount:  (d['refundAmount'] as num?)?.toDouble(),
      settledBy:     (d['approvedBy']   as String?) ?? (d['rejectedBy'] as String?),
      settledAt:     parseTs(d['approvedAt'] ?? d['rejectedAt']),
    );
  }
}

// ─── Wallet Ledger Entry ──────────────────────────────────────────────────────

class WalletLedgerEntry {
  final String id;
  final String userId;
  final LedgerEntryType type;
  final String typeRaw;
  final double credit;
  final double debit;
  final double balanceBefore;
  final double balanceAfter;
  final String referenceId;
  final String referenceType;
  final String remarks;
  final DateTime createdAt;

  const WalletLedgerEntry({
    required this.id,
    required this.userId,
    required this.type,
    required this.typeRaw,
    required this.credit,
    required this.debit,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.referenceId,
    required this.referenceType,
    required this.remarks,
    required this.createdAt,
  });

  bool get isCredit => credit > 0;
  double get amount => credit > 0 ? credit : debit;

  factory WalletLedgerEntry.fromFirestore(String id, Map<String, dynamic> d) {
    DateTime parseTs(dynamic ts) {
      if (ts == null) return DateTime.now();
      try { return (ts as dynamic).toDate() as DateTime; } catch (_) { return DateTime.now(); }
    }

    final typeRaw = (d['type'] as String?) ?? 'OTHER';
    final type    = LedgerEntryType.fromString(typeRaw);

    // Handle both old format (amount + balance) and new format (credit + debit)
    final rawAmount  = ((d['amount'] as num?) ?? 0).toDouble();
    final rawCredit  = ((d['credit'] as num?) ?? 0).toDouble();
    final rawDebit   = ((d['debit']  as num?) ?? 0).toDouble();
    final credit     = rawCredit > 0 ? rawCredit : (type.isCredit ? rawAmount : 0.0);
    final debit      = rawDebit  > 0 ? rawDebit  : (!type.isCredit && rawAmount > 0 ? rawAmount : 0.0);
    final balAfter   = ((d['balanceAfter']  as num?) ?? (d['balance'] as num?) ?? 0).toDouble();
    final balBefore  = ((d['balanceBefore'] as num?) ?? 0).toDouble();

    return WalletLedgerEntry(
      id:            id,
      userId:        (d['userId']        as String?) ?? '',
      type:          type,
      typeRaw:       typeRaw,
      credit:        credit,
      debit:         debit,
      balanceBefore: balBefore,
      balanceAfter:  balAfter,
      referenceId:   (d['referenceId']   as String?) ?? '',
      referenceType: (d['referenceType'] as String?) ?? '',
      remarks:       (d['remarks']       as String?) ?? '',
      createdAt:     parseTs(d['createdAt']),
    );
  }
}

// ─── Withdrawal Request ───────────────────────────────────────────────────────

class WithdrawalRequest {
  final String id;
  final String userId;
  final String userName;
  final double amount;
  final String bankAccount;
  final String upiId;
  final String remarks;
  final String status; // PENDING | APPROVED | REJECTED
  final DateTime createdAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectedBy;
  final DateTime? rejectedAt;
  final String? rejectionReason;

  const WithdrawalRequest({
    required this.id,
    required this.userId,
    required this.userName,
    required this.amount,
    required this.bankAccount,
    required this.upiId,
    required this.remarks,
    required this.status,
    required this.createdAt,
    this.approvedBy,
    this.approvedAt,
    this.rejectedBy,
    this.rejectedAt,
    this.rejectionReason,
  });

  factory WithdrawalRequest.fromFirestore(String id, Map<String, dynamic> d) {
    DateTime parseTs(dynamic ts) {
      if (ts == null) return DateTime.now();
      try { return (ts as dynamic).toDate() as DateTime; } catch (_) { return DateTime.now(); }
    }
    DateTime? parseTsOpt(dynamic ts) {
      if (ts == null) return null;
      try { return (ts as dynamic).toDate() as DateTime; } catch (_) { return null; }
    }
    return WithdrawalRequest(
      id:              id,
      userId:          (d['userId']          as String?) ?? '',
      userName:        (d['userName']        as String?) ?? '',
      amount:          ((d['amount']         as num?) ?? 0).toDouble(),
      bankAccount:     (d['bankAccount']     as String?) ?? '',
      upiId:           (d['upiId']           as String?) ?? '',
      remarks:         (d['remarks']         as String?) ?? '',
      status:          (d['status']          as String?) ?? 'PENDING',
      createdAt:       parseTs(d['createdAt']),
      approvedBy:      d['approvedBy']       as String?,
      approvedAt:      parseTsOpt(d['approvedAt']),
      rejectedBy:      d['rejectedBy']       as String?,
      rejectedAt:      parseTsOpt(d['rejectedAt']),
      rejectionReason: d['rejectionReason']  as String?,
    );
  }
}
