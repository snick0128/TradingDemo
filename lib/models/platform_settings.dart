/// Platform-level settings loaded from backend at startup.
///
/// Covers:
///   - Short sell leverage config (admin-controlled)
///   - RMS settings
///   - Support contact config
library;

class SupportConfig {
  final String whatsappNumber;
  final String phoneNumber;
  final String email;
  final String messageTemplate;
  final bool enabled;

  const SupportConfig({
    this.whatsappNumber = '',
    this.phoneNumber = '',
    this.email = '',
    this.messageTemplate = 'Hello, I need help with my account.',
    this.enabled = true,
  });

  factory SupportConfig.fromMap(Map<String, dynamic> m) => SupportConfig(
    whatsappNumber:  (m['supportWhatsappNumber']  as String?) ?? '',
    phoneNumber:     (m['supportPhoneNumber']     as String?) ?? '',
    email:           (m['supportEmail']           as String?) ?? '',
    messageTemplate: (m['supportMessageTemplate'] as String?) ?? 'Hello, I need help with my account.',
    enabled:         (m['supportEnabled'] as bool?) ?? true,
  );

  Map<String, dynamic> toMap() => {
    'supportWhatsappNumber':  whatsappNumber,
    'supportPhoneNumber':     phoneNumber,
    'supportEmail':           email,
    'supportMessageTemplate': messageTemplate,
    'supportEnabled':         enabled,
  };

  SupportConfig copyWith({
    String? whatsappNumber,
    String? phoneNumber,
    String? email,
    String? messageTemplate,
    bool? enabled,
  }) => SupportConfig(
    whatsappNumber:  whatsappNumber  ?? this.whatsappNumber,
    phoneNumber:     phoneNumber     ?? this.phoneNumber,
    email:           email           ?? this.email,
    messageTemplate: messageTemplate ?? this.messageTemplate,
    enabled:         enabled         ?? this.enabled,
  );
}

class PaymentConfig {
  final String upiId;
  final String merchantName;
  final bool enabled;

  const PaymentConfig({
    this.upiId = '',
    this.merchantName = 'TradeKosh',
    this.enabled = false,
  });

  factory PaymentConfig.fromMap(Map<String, dynamic> m) => PaymentConfig(
    upiId:        (m['paymentUpiId']        as String?) ?? '',
    merchantName: (m['paymentMerchantName'] as String?) ?? 'TradeKosh',
    enabled:      (m['paymentEnabled']      as bool?)   ?? false,
  );

  Map<String, dynamic> toMap() => {
    'paymentUpiId':        upiId,
    'paymentMerchantName': merchantName,
    'paymentEnabled':      enabled,
  };

  PaymentConfig copyWith({
    String? upiId,
    String? merchantName,
    bool? enabled,
  }) => PaymentConfig(
    upiId:        upiId        ?? this.upiId,
    merchantName: merchantName ?? this.merchantName,
    enabled:      enabled      ?? this.enabled,
  );
}

class PlatformRmsSettings {
  final double intradayShortSellLeverage;
  final double maxShortSellMultiplier;
  final bool enableShortSelling;
  final bool allowEquityIntradayShortSell;
  final bool enableAutoSquareOff;
  final double rmsLossThresholdPercent;
  final double intradayLeverage;
  final double shortSellLeverage;
  final double nrmlBuyLeverage;
  final double nrmlSellLeverage;
  final bool blockOvernightEquityShortSell;
  final bool enableRealtimeRms;
  /// Equity-based auto square-off threshold (₹). Default ₹500.
  /// All positions are closed when equity drops to or below this level.
  final double safeLevelRupees;
  /// Execution slippage applied to MARKET orders (% of LTP).
  /// BUY fills at ltp × (1 + slippage%), SELL at ltp × (1 - slippage%).
  final double slippagePercent;

  const PlatformRmsSettings({
    this.intradayShortSellLeverage       = 5.0,
    this.maxShortSellMultiplier          = 5.0,
    this.enableShortSelling              = true,
    this.allowEquityIntradayShortSell    = true,
    this.enableAutoSquareOff             = true,
    this.rmsLossThresholdPercent         = 100.0,
    this.intradayLeverage                = 5.0,
    this.shortSellLeverage               = 5.0,
    this.nrmlBuyLeverage                 = 1.0,
    this.nrmlSellLeverage                = 1.0,
    this.blockOvernightEquityShortSell   = true,
    this.enableRealtimeRms               = true,
    this.safeLevelRupees                 = 500.0,
    this.slippagePercent                 = 0.90,
  });

  static const PlatformRmsSettings defaults = PlatformRmsSettings();

  factory PlatformRmsSettings.fromMap(Map<String, dynamic> m) => PlatformRmsSettings(
    intradayShortSellLeverage:     ((m['intradayShortSellLeverage']    as num?) ?? 5).toDouble(),
    maxShortSellMultiplier:        ((m['maxShortSellMultiplier']       as num?) ?? 5).toDouble(),
    enableShortSelling:            (m['enableShortSelling']           as bool?) ?? true,
    allowEquityIntradayShortSell:  (m['allowEquityIntradayShortSell'] as bool?) ?? true,
    enableAutoSquareOff:           (m['enableAutoSquareOff']          as bool?) ?? true,
    rmsLossThresholdPercent:       ((m['rmsLossThresholdPercent']      as num?) ?? 100).toDouble(),
    intradayLeverage:              ((m['intradayLeverage']             as num?) ?? 5).toDouble(),
    shortSellLeverage:             ((m['shortSellLeverage']            as num?) ?? 5).toDouble(),
    nrmlBuyLeverage:               ((m['nrmlBuyLeverage']              as num?) ?? 1).toDouble(),
    nrmlSellLeverage:              ((m['nrmlSellLeverage']             as num?) ?? 1).toDouble(),
    blockOvernightEquityShortSell: (m['blockOvernightEquityShortSell'] as bool?) ?? true,
    enableRealtimeRms:             (m['enableRealtimeRms']            as bool?) ?? true,
    safeLevelRupees:               ((m['safeLevel']                   as num?) ?? 500).toDouble(),
    slippagePercent:               ((m['slippagePercent']             as num?) ?? 0.90).toDouble(),
  );

  Map<String, dynamic> toMap() => {
    'intradayShortSellLeverage':     intradayShortSellLeverage,
    'maxShortSellMultiplier':        maxShortSellMultiplier,
    'enableShortSelling':            enableShortSelling,
    'allowEquityIntradayShortSell':  allowEquityIntradayShortSell,
    'enableAutoSquareOff':           enableAutoSquareOff,
    'rmsLossThresholdPercent':       rmsLossThresholdPercent,
    'intradayLeverage':              intradayLeverage,
    'shortSellLeverage':             shortSellLeverage,
    'nrmlBuyLeverage':               nrmlBuyLeverage,
    'nrmlSellLeverage':              nrmlSellLeverage,
    'blockOvernightEquityShortSell': blockOvernightEquityShortSell,
    'enableRealtimeRms':             enableRealtimeRms,
    'safeLevel':                     safeLevelRupees,
    'slippagePercent':               slippagePercent,
  };

  PlatformRmsSettings copyWith({
    double? intradayShortSellLeverage,
    double? maxShortSellMultiplier,
    bool? enableShortSelling,
    bool? allowEquityIntradayShortSell,
    bool? enableAutoSquareOff,
    double? rmsLossThresholdPercent,
    double? intradayLeverage,
    double? shortSellLeverage,
    double? nrmlBuyLeverage,
    double? nrmlSellLeverage,
    bool? blockOvernightEquityShortSell,
    bool? enableRealtimeRms,
    double? safeLevelRupees,
    double? slippagePercent,
  }) => PlatformRmsSettings(
    intradayShortSellLeverage:     intradayShortSellLeverage    ?? this.intradayShortSellLeverage,
    maxShortSellMultiplier:        maxShortSellMultiplier       ?? this.maxShortSellMultiplier,
    enableShortSelling:            enableShortSelling           ?? this.enableShortSelling,
    allowEquityIntradayShortSell:  allowEquityIntradayShortSell ?? this.allowEquityIntradayShortSell,
    enableAutoSquareOff:           enableAutoSquareOff          ?? this.enableAutoSquareOff,
    rmsLossThresholdPercent:       rmsLossThresholdPercent      ?? this.rmsLossThresholdPercent,
    intradayLeverage:              intradayLeverage             ?? this.intradayLeverage,
    shortSellLeverage:             shortSellLeverage            ?? this.shortSellLeverage,
    nrmlBuyLeverage:               nrmlBuyLeverage              ?? this.nrmlBuyLeverage,
    nrmlSellLeverage:              nrmlSellLeverage             ?? this.nrmlSellLeverage,
    blockOvernightEquityShortSell: blockOvernightEquityShortSell ?? this.blockOvernightEquityShortSell,
    enableRealtimeRms:             enableRealtimeRms            ?? this.enableRealtimeRms,
    safeLevelRupees:               safeLevelRupees              ?? this.safeLevelRupees,
    slippagePercent:               slippagePercent              ?? this.slippagePercent,
  );
}
