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

class PlatformRmsSettings {
  final double intradayShortSellLeverage;
  final double maxShortSellMultiplier;
  final bool enableShortSelling;
  final bool allowEquityIntradayShortSell;
  final bool enableAutoSquareOff;
  final double rmsLossThresholdPercent;
  final double intradayLeverage;
  final double shortSellLeverage;
  final bool enableRealtimeRms;

  const PlatformRmsSettings({
    this.intradayShortSellLeverage    = 5.0,
    this.maxShortSellMultiplier       = 5.0,
    this.enableShortSelling           = true,
    this.allowEquityIntradayShortSell = true,
    this.enableAutoSquareOff          = true,
    this.rmsLossThresholdPercent      = 100.0,
    this.intradayLeverage             = 5.0,
    this.shortSellLeverage            = 5.0,
    this.enableRealtimeRms            = true,
  });

  static const PlatformRmsSettings defaults = PlatformRmsSettings();

  factory PlatformRmsSettings.fromMap(Map<String, dynamic> m) => PlatformRmsSettings(
    intradayShortSellLeverage:    ((m['intradayShortSellLeverage']    as num?) ?? 5).toDouble(),
    maxShortSellMultiplier:       ((m['maxShortSellMultiplier']       as num?) ?? 5).toDouble(),
    enableShortSelling:           (m['enableShortSelling']           as bool?) ?? true,
    allowEquityIntradayShortSell: (m['allowEquityIntradayShortSell'] as bool?) ?? true,
    enableAutoSquareOff:          (m['enableAutoSquareOff']          as bool?) ?? true,
    rmsLossThresholdPercent:      ((m['rmsLossThresholdPercent']      as num?) ?? 100).toDouble(),
    intradayLeverage:             ((m['intradayLeverage']             as num?) ?? 5).toDouble(),
    shortSellLeverage:            ((m['shortSellLeverage']            as num?) ?? 5).toDouble(),
    enableRealtimeRms:            (m['enableRealtimeRms']            as bool?) ?? true,
  );

  Map<String, dynamic> toMap() => {
    'intradayShortSellLeverage':    intradayShortSellLeverage,
    'maxShortSellMultiplier':       maxShortSellMultiplier,
    'enableShortSelling':           enableShortSelling,
    'allowEquityIntradayShortSell': allowEquityIntradayShortSell,
    'enableAutoSquareOff':          enableAutoSquareOff,
    'rmsLossThresholdPercent':      rmsLossThresholdPercent,
    'intradayLeverage':             intradayLeverage,
    'shortSellLeverage':            shortSellLeverage,
    'enableRealtimeRms':            enableRealtimeRms,
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
    bool? enableRealtimeRms,
  }) => PlatformRmsSettings(
    intradayShortSellLeverage:    intradayShortSellLeverage    ?? this.intradayShortSellLeverage,
    maxShortSellMultiplier:       maxShortSellMultiplier       ?? this.maxShortSellMultiplier,
    enableShortSelling:           enableShortSelling           ?? this.enableShortSelling,
    allowEquityIntradayShortSell: allowEquityIntradayShortSell ?? this.allowEquityIntradayShortSell,
    enableAutoSquareOff:          enableAutoSquareOff          ?? this.enableAutoSquareOff,
    rmsLossThresholdPercent:      rmsLossThresholdPercent      ?? this.rmsLossThresholdPercent,
    intradayLeverage:             intradayLeverage             ?? this.intradayLeverage,
    shortSellLeverage:            shortSellLeverage            ?? this.shortSellLeverage,
    enableRealtimeRms:            enableRealtimeRms            ?? this.enableRealtimeRms,
  );
}
