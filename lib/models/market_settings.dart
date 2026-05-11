/// Market settings model — mirrors the Firestore marketSettings/config document.
///
/// Admin controls these via the admin panel.
/// Flutter reads them via [MarketSettingsService] to disable buy/sell buttons
/// and to display leverage/margin limits to users.
library;

class SegmentSettings {
  final bool enabled;
  final bool buyEnabled;
  final bool sellEnabled;
  final String marketOpen;    // "HH:MM" IST
  final String marketClose;   // "HH:MM" IST
  final double maxLeverage;   // e.g. 20.0 for 20x
  final double marginPercent; // e.g. 5.0 for 5%

  const SegmentSettings({
    required this.enabled,
    required this.buyEnabled,
    required this.sellEnabled,
    required this.marketOpen,
    required this.marketClose,
    this.maxLeverage   = 20.0,
    this.marginPercent = 5.0,
  });

  factory SegmentSettings.fromMap(Map<String, dynamic> m) => SegmentSettings(
        enabled:       (m['enabled']       as bool?)   ?? true,
        buyEnabled:    (m['buyEnabled']    as bool?)   ?? true,
        sellEnabled:   (m['sellEnabled']   as bool?)   ?? true,
        marketOpen:    (m['marketOpen']    as String?) ?? '09:15',
        marketClose:   (m['marketClose']   as String?) ?? '15:30',
        maxLeverage:   ((m['maxLeverage']  as num?)    ?? 20).toDouble(),
        marginPercent: ((m['marginPercent'] as num?)   ?? 5).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'enabled':       enabled,
        'buyEnabled':    buyEnabled,
        'sellEnabled':   sellEnabled,
        'marketOpen':    marketOpen,
        'marketClose':   marketClose,
        'maxLeverage':   maxLeverage,
        'marginPercent': marginPercent,
      };

  SegmentSettings copyWith({
    bool? enabled,
    bool? buyEnabled,
    bool? sellEnabled,
    String? marketOpen,
    String? marketClose,
    double? maxLeverage,
    double? marginPercent,
  }) =>
      SegmentSettings(
        enabled:       enabled       ?? this.enabled,
        buyEnabled:    buyEnabled    ?? this.buyEnabled,
        sellEnabled:   sellEnabled   ?? this.sellEnabled,
        marketOpen:    marketOpen    ?? this.marketOpen,
        marketClose:   marketClose   ?? this.marketClose,
        maxLeverage:   maxLeverage   ?? this.maxLeverage,
        marginPercent: marginPercent ?? this.marginPercent,
      );
}

class MarketSettings {
  final SegmentSettings stocks;
  final SegmentSettings mcx;

  const MarketSettings({required this.stocks, required this.mcx});

  static const MarketSettings defaults = MarketSettings(
    stocks: SegmentSettings(
      enabled: true, buyEnabled: true, sellEnabled: true,
      marketOpen: '09:15', marketClose: '15:30',
      maxLeverage: 20.0, marginPercent: 5.0,
    ),
    mcx: SegmentSettings(
      enabled: true, buyEnabled: true, sellEnabled: true,
      marketOpen: '09:00', marketClose: '23:30',
      maxLeverage: 100.0, marginPercent: 1.0,
    ),
  );

  factory MarketSettings.fromMap(Map<String, dynamic> m) => MarketSettings(
        stocks: SegmentSettings.fromMap(
            (m['stocks'] as Map<String, dynamic>?) ?? {}),
        mcx: SegmentSettings.fromMap(
            (m['mcx'] as Map<String, dynamic>?) ?? {}),
      );

  Map<String, dynamic> toMap() => {
        'stocks': stocks.toMap(),
        'mcx':    mcx.toMap(),
      };

  /// Returns the segment settings for a given exchange string.
  /// MCX → mcx, everything else → stocks.
  SegmentSettings forExchange(String exchange) =>
      exchange.toUpperCase() == 'MCX' ? mcx : stocks;

  /// Check if a buy/sell action is allowed for a given exchange.
  /// Returns null if allowed, or a human-readable reason string if blocked.
  String? checkAction(String exchange, {required bool isBuy}) {
    final seg = forExchange(exchange);
    final label = exchange.toUpperCase() == 'MCX' ? 'MCX' : 'Stock';

    if (!seg.enabled) return '$label market is disabled';
    if (isBuy  && !seg.buyEnabled)  return '$label buying is disabled';
    if (!isBuy && !seg.sellEnabled) return '$label selling is disabled';

    // Check IST time
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final nowMin = now.hour * 60 + now.minute;
    final openMin  = _parseTime(seg.marketOpen);
    final closeMin = _parseTime(seg.marketClose);

    if (nowMin < openMin || nowMin >= closeMin) {
      final h = now.hour.toString().padLeft(2, '0');
      final m = now.minute.toString().padLeft(2, '0');
      return '$label market closed (${seg.marketOpen}–${seg.marketClose} IST, now $h:$m)';
    }

    return null; // allowed
  }

  static int _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }
}
