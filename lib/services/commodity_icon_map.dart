/// Bundled-asset icons for MCX commodity futures — these aren't listed
/// equities, so they'll never appear in the Indian Listed Company Logos
/// mapping (see [LogoResolver]). Matches the 10 commodities this app tracks
/// (see paper_trading_backend/src/config/symbols.js MCX_DEFINITIONS and
/// lib/search/search_index.dart's MCX entries).
class CommodityIconMap {
  CommodityIconMap._();

  static const Map<String, String> _assetByTicker = {
    'GOLD': 'assets/images/gold.png',
    'SILVER': 'assets/images/silver.png',
    'CRUDEOIL': 'assets/images/crudeoil.png',
    'NATURALGAS': 'assets/images/naturalgas.png',
    'COPPER': 'assets/images/copper.png',
    'ZINC': 'assets/images/zinc.png',
    'LEAD': 'assets/images/lead.png',
    'ALUMINIUM': 'assets/images/aluminium.png',
    'NICKEL': 'assets/images/nickel.png',
    'COTTON': 'assets/images/cotton.png',
  };

  /// Returns the bundled asset path for [ticker] (e.g. "GOLD" ->
  /// "assets/images/gold.png"), or null if it isn't a tracked commodity.
  static String? assetFor(String ticker) => _assetByTicker[ticker.toUpperCase()];
}
