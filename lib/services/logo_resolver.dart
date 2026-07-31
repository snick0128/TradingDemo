/// Builds Indian Listed Company Logos CDN URLs from a ticker→file mapping.
/// Pure and dependency-free — takes the mapping as a parameter rather than
/// loading it itself, so it stays trivially unit-testable in isolation from
/// [LogoCacheManager]'s network/disk concerns.
class LogoResolver {
  LogoResolver._();

  static const baseUrl =
      'https://dharunashokkumar.github.io/indian-listed-company-logos/';

  /// Returns the full logo URL for [ticker], or null if it isn't in
  /// [mapping] (indices, currencies, commodities, and unlisted/unmatched
  /// tickers all fall through to null this way — no separate blocklist
  /// needed, since the mapping only ever contains real NSE/BSE listings).
  ///
  /// [exchange] is tried first (case-insensitively); Angel One's F&O/
  /// currency segments report exchange as NFO/MCX/CDS rather than the cash
  /// segment the underlying actually lists on, so NSE then BSE are tried as
  /// a fallback regardless of [exchange].
  static String? resolve({
    required String ticker,
    required String exchange,
    required Map<String, String> mapping,
  }) {
    if (ticker.isEmpty || mapping.isEmpty) return null;
    final upperTicker = ticker.toUpperCase();
    final upperExchange = exchange.toUpperCase();

    final file = mapping['$upperExchange:$upperTicker'] ??
        mapping['NSE:$upperTicker'] ??
        mapping['BSE:$upperTicker'];
    if (file == null) return null;
    return '$baseUrl$file';
  }
}
