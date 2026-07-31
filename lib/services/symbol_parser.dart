/// Pure symbol-parsing helpers for resolving the underlying equity ticker
/// behind any Angel One trading symbol. No I/O, no Flutter dependency —
/// kept separate from [LogoResolver] so it stays trivially unit-testable.
class SymbolParser {
  SymbolParser._();

  static final RegExp _exchangeSuffix = RegExp(r'-(EQ|BE|BL|IQ|RL|AF|U\d+)$');
  static final RegExp _dotSuffix = RegExp(r'\.(NS|BO)$', caseSensitive: false);

  /// Matches the Angel One F&O date+strike tail: 1-2 digit day, 3-letter
  /// month, then any run of digits (2-digit year and/or strike price —
  /// deliberately not split out, since only the underlying prefix matters
  /// here), ending in FUT/CE/PE. e.g. "25AUG26FUT", "28JUL2615250CE".
  static final RegExp _derivativeSuffix =
      RegExp(r'^([A-Z0-9&]+?)\d{1,2}[A-Z]{3}\d*(?:FUT|CE|PE)$');

  /// Strips exchange suffixes ("-EQ", "-BE", ".NS", ".BO"), trims whitespace,
  /// and upper-cases. Safe to call on an already-normalized symbol.
  static String normalize(String rawSymbol) {
    var s = rawSymbol.trim().toUpperCase();
    s = s.replaceAll(_dotSuffix, '');
    s = s.replaceAll(_exchangeSuffix, '');
    return s;
  }

  /// Returns the underlying equity ticker for [rawSymbol].
  ///
  /// Handles plain equities ("RELIANCE-EQ" -> "RELIANCE"), futures
  /// ("RELIANCE29AUG26FUT" -> "RELIANCE"), and options
  /// ("RELIANCE29AUG2600CE" -> "RELIANCE"). Indices, currencies, and
  /// commodities are returned normalized but unparsed — callers should not
  /// assume the result is a listed-equity ticker without checking the logo
  /// mapping (see [LogoResolver]).
  static String underlyingOf(String rawSymbol) {
    final normalized = normalize(rawSymbol);
    final match = _derivativeSuffix.firstMatch(normalized);
    if (match != null) return match.group(1)!;
    return normalized;
  }
}
