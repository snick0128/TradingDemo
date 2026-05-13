/// SearchIndex — In-memory ranked search engine for trading instruments.
///
/// Architecture:
///   - Local instrument catalog (all known symbols + aliases)
///   - Trie-based prefix lookup for instant results
///   - Levenshtein fuzzy matching for typo tolerance
///   - Weighted scoring: exact > prefix > alias > name > fuzzy
///   - Context boosting: watchlist, holdings, positions, recent searches
///
/// This runs entirely on the client — no network call needed for the
/// local catalog. The backend API enriches results with live LTP.

import 'dart:math' as math;

// ── Instrument model ──────────────────────────────────────────────────────────

enum InstrumentSegment { eq, fut, ce, pe, comm, curr, etf, idx, mf, bond }

class Instrument {
  final String symbol; // e.g. RELIANCE, CRUDEOIL, NIFTY 50
  final String displayName; // cleaned display symbol
  final String name; // full company/instrument name
  final String exchange; // NSE, BSE, MCX, NFO, CDS
  final InstrumentSegment segment;
  final List<String> aliases; // shorthand: ril, bnf, nifty50
  final int popularityRank; // lower = more popular
  double? ltp;
  double? changePercent;

  Instrument({
    required this.symbol,
    required this.displayName,
    required this.name,
    required this.exchange,
    required this.segment,
    this.aliases = const [],
    this.popularityRank = 999,
    this.ltp,
    this.changePercent,
  });

  String get segmentLabel {
    switch (segment) {
      case InstrumentSegment.eq:
        return 'EQ';
      case InstrumentSegment.fut:
        return 'FUT';
      case InstrumentSegment.ce:
        return 'CE';
      case InstrumentSegment.pe:
        return 'PE';
      case InstrumentSegment.comm:
        return 'COMM';
      case InstrumentSegment.curr:
        return 'CURR';
      case InstrumentSegment.etf:
        return 'ETF';
      case InstrumentSegment.idx:
        return 'INDEX';
      case InstrumentSegment.mf:
        return 'MF';
      case InstrumentSegment.bond:
        return 'BOND';
    }
  }
}

// ── Catalog — all known instruments ──────────────────────────────────────────

final kInstrumentCatalog = <Instrument>[
  // ── NSE Equities ────────────────────────────────────────────────────────────
  Instrument(
    symbol: 'RELIANCE',
    displayName: 'RELIANCE',
    name: 'Reliance Industries Ltd',
    exchange: 'NSE',
    segment: InstrumentSegment.eq,
    aliases: ['ril', 'reliance'],
    popularityRank: 1,
  ),
  Instrument(
    symbol: 'TCS',
    displayName: 'TCS',
    name: 'Tata Consultancy Services',
    exchange: 'NSE',
    segment: InstrumentSegment.eq,
    aliases: ['tata consultancy'],
    popularityRank: 2,
  ),
  Instrument(
    symbol: 'INFY',
    displayName: 'INFY',
    name: 'Infosys Ltd',
    exchange: 'NSE',
    segment: InstrumentSegment.eq,
    aliases: ['infosys'],
    popularityRank: 3,
  ),
  Instrument(
    symbol: 'HDFCBANK',
    displayName: 'HDFCBANK',
    name: 'HDFC Bank Ltd',
    exchange: 'NSE',
    segment: InstrumentSegment.eq,
    aliases: ['hdfc bank', 'hdfc'],
    popularityRank: 4,
  ),
  Instrument(
    symbol: 'ICICIBANK',
    displayName: 'ICICIBANK',
    name: 'ICICI Bank Ltd',
    exchange: 'NSE',
    segment: InstrumentSegment.eq,
    aliases: ['icici bank', 'icici'],
    popularityRank: 5,
  ),
  Instrument(
    symbol: 'SBIN',
    displayName: 'SBIN',
    name: 'State Bank of India',
    exchange: 'NSE',
    segment: InstrumentSegment.eq,
    aliases: ['sbi', 'state bank'],
    popularityRank: 6,
  ),
  Instrument(
    symbol: 'WIPRO',
    displayName: 'WIPRO',
    name: 'Wipro Ltd',
    exchange: 'NSE',
    segment: InstrumentSegment.eq,
    aliases: ['wipro'],
    popularityRank: 7,
  ),
  Instrument(
    symbol: 'AXISBANK',
    displayName: 'AXISBANK',
    name: 'Axis Bank Ltd',
    exchange: 'NSE',
    segment: InstrumentSegment.eq,
    aliases: ['axis bank', 'axis'],
    popularityRank: 8,
  ),
  Instrument(
    symbol: 'BAJFINANCE',
    displayName: 'BAJFINANCE',
    name: 'Bajaj Finance Ltd',
    exchange: 'NSE',
    segment: InstrumentSegment.eq,
    aliases: ['bajaj finance', 'bajaj fin'],
    popularityRank: 9,
  ),
  Instrument(
    symbol: 'HINDUNILVR',
    displayName: 'HINDUNILVR',
    name: 'Hindustan Unilever Ltd',
    exchange: 'NSE',
    segment: InstrumentSegment.eq,
    aliases: ['hul', 'hindustan unilever'],
    popularityRank: 10,
  ),
  // BSE mirrors
  Instrument(
    symbol: 'RELIANCE',
    displayName: 'RELIANCE',
    name: 'Reliance Industries Ltd',
    exchange: 'BSE',
    segment: InstrumentSegment.eq,
    aliases: ['ril'],
    popularityRank: 11,
  ),
  Instrument(
    symbol: 'TCS',
    displayName: 'TCS',
    name: 'Tata Consultancy Services',
    exchange: 'BSE',
    segment: InstrumentSegment.eq,
    aliases: [],
    popularityRank: 12,
  ),
  Instrument(
    symbol: 'INFY',
    displayName: 'INFY',
    name: 'Infosys Ltd',
    exchange: 'BSE',
    segment: InstrumentSegment.eq,
    aliases: [],
    popularityRank: 13,
  ),
  Instrument(
    symbol: 'HDFCBANK',
    displayName: 'HDFCBANK',
    name: 'HDFC Bank Ltd',
    exchange: 'BSE',
    segment: InstrumentSegment.eq,
    aliases: [],
    popularityRank: 14,
  ),
  Instrument(
    symbol: 'ICICIBANK',
    displayName: 'ICICIBANK',
    name: 'ICICI Bank Ltd',
    exchange: 'BSE',
    segment: InstrumentSegment.eq,
    aliases: [],
    popularityRank: 15,
  ),
  Instrument(
    symbol: 'SBIN',
    displayName: 'SBIN',
    name: 'State Bank of India',
    exchange: 'BSE',
    segment: InstrumentSegment.eq,
    aliases: ['sbi'],
    popularityRank: 16,
  ),
  // ── Indices ──────────────────────────────────────────────────────────────────
  Instrument(
    symbol: 'NIFTY 50',
    displayName: 'NIFTY 50',
    name: 'Nifty 50 Index',
    exchange: 'NSE',
    segment: InstrumentSegment.idx,
    aliases: ['nifty', 'nifty50', 'nf'],
    popularityRank: 1,
  ),
  Instrument(
    symbol: 'BANKNIFTY',
    displayName: 'BANKNIFTY',
    name: 'Bank Nifty Index',
    exchange: 'NSE',
    segment: InstrumentSegment.idx,
    aliases: ['bnf', 'bank nifty', 'banknf'],
    popularityRank: 2,
  ),
  Instrument(
    symbol: 'SENSEX',
    displayName: 'SENSEX',
    name: 'BSE Sensex',
    exchange: 'BSE',
    segment: InstrumentSegment.idx,
    aliases: ['bse sensex', 'sensex30'],
    popularityRank: 3,
  ),
  Instrument(
    symbol: 'FINNIFTY',
    displayName: 'FINNIFTY',
    name: 'Nifty Financial Services',
    exchange: 'NSE',
    segment: InstrumentSegment.idx,
    aliases: ['fin nifty', 'finnf'],
    popularityRank: 4,
  ),
  Instrument(
    symbol: 'MIDCPNIFTY',
    displayName: 'MIDCPNIFTY',
    name: 'Nifty Midcap Select',
    exchange: 'NSE',
    segment: InstrumentSegment.idx,
    aliases: ['midcap nifty', 'midcp'],
    popularityRank: 5,
  ),
  // ── NSE F&O Futures ──────────────────────────────────────────────────────────
  Instrument(
    symbol: 'NIFTY FUT',
    displayName: 'NIFTY FUT',
    name: 'Nifty 50 Futures (Near)',
    exchange: 'NFO',
    segment: InstrumentSegment.fut,
    aliases: ['nifty futures', 'nf fut'],
    popularityRank: 1,
  ),
  Instrument(
    symbol: 'BANKNIFTY FUT',
    displayName: 'BANKNIFTY FUT',
    name: 'Bank Nifty Futures (Near)',
    exchange: 'NFO',
    segment: InstrumentSegment.fut,
    aliases: ['bnf fut', 'bank nifty fut'],
    popularityRank: 2,
  ),
  Instrument(
    symbol: 'RELIANCE FUT',
    displayName: 'RELIANCE FUT',
    name: 'Reliance Futures (Near)',
    exchange: 'NFO',
    segment: InstrumentSegment.fut,
    aliases: ['ril fut'],
    popularityRank: 3,
  ),
  Instrument(
    symbol: 'TCS FUT',
    displayName: 'TCS FUT',
    name: 'TCS Futures (Near)',
    exchange: 'NFO',
    segment: InstrumentSegment.fut,
    aliases: [],
    popularityRank: 4,
  ),
  Instrument(
    symbol: 'INFY FUT',
    displayName: 'INFY FUT',
    name: 'Infosys Futures (Near)',
    exchange: 'NFO',
    segment: InstrumentSegment.fut,
    aliases: ['infosys fut'],
    popularityRank: 5,
  ),
  // ── MCX Commodities ──────────────────────────────────────────────────────────
  Instrument(
    symbol: 'GOLD',
    displayName: 'GOLD',
    name: 'Gold 1kg MCX Futures',
    exchange: 'MCX',
    segment: InstrumentSegment.comm,
    aliases: ['gold mcx', 'sona'],
    popularityRank: 1,
  ),
  Instrument(
    symbol: 'SILVER',
    displayName: 'SILVER',
    name: 'Silver 30kg MCX Futures',
    exchange: 'MCX',
    segment: InstrumentSegment.comm,
    aliases: ['silver mcx', 'chandi'],
    popularityRank: 2,
  ),
  Instrument(
    symbol: 'CRUDEOIL',
    displayName: 'CRUDEOIL',
    name: 'Crude Oil 100bbl MCX Futures',
    exchange: 'MCX',
    segment: InstrumentSegment.comm,
    aliases: ['crude', 'crude oil', 'wti'],
    popularityRank: 3,
  ),
  Instrument(
    symbol: 'NATURALGAS',
    displayName: 'NATURALGAS',
    name: 'Natural Gas MCX Futures',
    exchange: 'MCX',
    segment: InstrumentSegment.comm,
    aliases: ['nat gas', 'natural gas', 'ng'],
    popularityRank: 4,
  ),
  Instrument(
    symbol: 'COPPER',
    displayName: 'COPPER',
    name: 'Copper 1MT MCX Futures',
    exchange: 'MCX',
    segment: InstrumentSegment.comm,
    aliases: ['copper mcx', 'tambe'],
    popularityRank: 5,
  ),
  Instrument(
    symbol: 'ZINC',
    displayName: 'ZINC',
    name: 'Zinc 5MT MCX Futures',
    exchange: 'MCX',
    segment: InstrumentSegment.comm,
    aliases: ['zinc mcx'],
    popularityRank: 6,
  ),
  Instrument(
    symbol: 'LEAD',
    displayName: 'LEAD',
    name: 'Lead 5MT MCX Futures',
    exchange: 'MCX',
    segment: InstrumentSegment.comm,
    aliases: ['lead mcx'],
    popularityRank: 7,
  ),
  Instrument(
    symbol: 'ALUMINIUM',
    displayName: 'ALUMINIUM',
    name: 'Aluminium 5MT MCX Futures',
    exchange: 'MCX',
    segment: InstrumentSegment.comm,
    aliases: ['alum', 'aluminium mcx'],
    popularityRank: 8,
  ),
  Instrument(
    symbol: 'NICKEL',
    displayName: 'NICKEL',
    name: 'Nickel 250kg MCX Futures',
    exchange: 'MCX',
    segment: InstrumentSegment.comm,
    aliases: ['nickel mcx'],
    popularityRank: 9,
  ),
  Instrument(
    symbol: 'COTTON',
    displayName: 'COTTON',
    name: 'Cotton 25 bales MCX Futures',
    exchange: 'MCX',
    segment: InstrumentSegment.comm,
    aliases: ['cotton mcx', 'kapas'],
    popularityRank: 10,
  ),
  // ── Currency ──────────────────────────────────────────────────────────────────
  Instrument(
    symbol: 'USDINR',
    displayName: 'USDINR',
    name: 'US Dollar / Indian Rupee',
    exchange: 'CDS',
    segment: InstrumentSegment.curr,
    aliases: ['usd inr', 'dollar rupee', 'inr usd'],
    popularityRank: 1,
  ),
  Instrument(
    symbol: 'EURINR',
    displayName: 'EURINR',
    name: 'Euro / Indian Rupee',
    exchange: 'CDS',
    segment: InstrumentSegment.curr,
    aliases: ['eur inr', 'euro rupee'],
    popularityRank: 2,
  ),
  Instrument(
    symbol: 'GBPINR',
    displayName: 'GBPINR',
    name: 'British Pound / Indian Rupee',
    exchange: 'CDS',
    segment: InstrumentSegment.curr,
    aliases: ['gbp inr', 'pound rupee'],
    popularityRank: 3,
  ),
  Instrument(
    symbol: 'JPYINR',
    displayName: 'JPYINR',
    name: 'Japanese Yen / Indian Rupee',
    exchange: 'CDS',
    segment: InstrumentSegment.curr,
    aliases: ['jpy inr', 'yen rupee'],
    popularityRank: 4,
  ),
  // ── ETFs ──────────────────────────────────────────────────────────────────────
  Instrument(
    symbol: 'GOLDBEES',
    displayName: 'GOLDBEES',
    name: 'Nippon India Gold ETF',
    exchange: 'NSE',
    segment: InstrumentSegment.etf,
    aliases: ['gold etf', 'gold bees'],
    popularityRank: 1,
  ),
  Instrument(
    symbol: 'NIFTYBEES',
    displayName: 'NIFTYBEES',
    name: 'Nippon India ETF Nifty 50',
    exchange: 'NSE',
    segment: InstrumentSegment.etf,
    aliases: ['nifty etf', 'nifty bees'],
    popularityRank: 2,
  ),
  Instrument(
    symbol: 'BANKBEES',
    displayName: 'BANKBEES',
    name: 'Nippon India ETF Bank Nifty',
    exchange: 'NSE',
    segment: InstrumentSegment.etf,
    aliases: ['bank etf', 'bank bees'],
    popularityRank: 3,
  ),
  Instrument(
    symbol: 'ICICIB22',
    displayName: 'ICICIB22',
    name: 'ICICI Prudential Bharat 22 ETF',
    exchange: 'NSE',
    segment: InstrumentSegment.etf,
    aliases: ['bharat 22', 'b22'],
    popularityRank: 4,
  ),
  // ── Sovereign Gold Bonds ──────────────────────────────────────────────────────
  Instrument(
    symbol: 'SGBFEB28',
    displayName: 'SGB FEB 28',
    name: 'Sovereign Gold Bond Feb 2028',
    exchange: 'NSE',
    segment: InstrumentSegment.bond,
    aliases: ['sgb', 'sovereign gold bond', 'gold bond'],
    popularityRank: 1,
  ),
];

// ── Scoring engine ────────────────────────────────────────────────────────────

class SearchResult {
  final Instrument instrument;
  final int score;
  SearchResult(this.instrument, this.score);
}

class SearchIndex {
  SearchIndex._();
  static final SearchIndex instance = SearchIndex._();

  // Context sets — updated from TradingStore
  final Set<String> _watchlistSymbols = {};
  final Set<String> _holdingSymbols = {};
  final Set<String> _positionSymbols = {};
  final List<String> _recentSearches = [];

  void updateContext({
    required Set<String> watchlist,
    required Set<String> holdings,
    required Set<String> positions,
    required List<String> recent,
  }) {
    _watchlistSymbols
      ..clear()
      ..addAll(watchlist.map((s) => s.toUpperCase()));
    _holdingSymbols
      ..clear()
      ..addAll(holdings.map((s) => s.toUpperCase()));
    _positionSymbols
      ..clear()
      ..addAll(positions.map((s) => s.toUpperCase()));
    _recentSearches
      ..clear()
      ..addAll(recent.map((s) => s.toUpperCase()));
  }

  /// Search the local catalog. Returns ranked results.
  List<Instrument> search(String rawQuery, {int limit = 30}) {
    if (rawQuery.trim().isEmpty) return [];
    final q = rawQuery.trim().toLowerCase();

    final scored = <SearchResult>[];

    for (final inst in kInstrumentCatalog) {
      final score = _score(inst, q);
      if (score > 0) scored.add(SearchResult(inst, score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((r) => r.instrument).toList();
  }

  int _score(Instrument inst, String q) {
    final sym = inst.symbol.toLowerCase();
    final display = inst.displayName.toLowerCase();
    final name = inst.name.toLowerCase();
    final symUp = inst.symbol.toUpperCase();

    int score = 0;

    // ── Exact symbol match ────────────────────────────────────────────────────
    if (sym == q || display == q)
      score += 1000;
    // ── Prefix match ──────────────────────────────────────────────────────────
    else if (sym.startsWith(q) || display.startsWith(q))
      score += 500;
    // ── Alias exact match ─────────────────────────────────────────────────────
    else if (inst.aliases.any((a) => a.toLowerCase() == q))
      score += 450;
    // ── Alias prefix match ────────────────────────────────────────────────────
    else if (inst.aliases.any((a) => a.toLowerCase().startsWith(q)))
      score += 300;
    // ── Symbol contains ───────────────────────────────────────────────────────
    else if (sym.contains(q) || display.contains(q))
      score += 200;
    // ── Name match ────────────────────────────────────────────────────────────
    else if (name.startsWith(q))
      score += 150;
    else if (name.contains(q))
      score += 80;
    // ── Alias contains ────────────────────────────────────────────────────────
    else if (inst.aliases.any((a) => a.toLowerCase().contains(q)))
      score += 120;
    // ── Fuzzy (Levenshtein ≤ 2 on first word of symbol) ──────────────────────
    else {
      final firstWord = sym.split(RegExp(r'[\s_\-]')).first;
      if (firstWord.length >= q.length - 2 &&
          firstWord.length <= q.length + 2) {
        final dist = _levenshtein(firstWord, q);
        if (dist == 1)
          score += 60;
        else if (dist == 2)
          score += 30;
      }
    }

    if (score == 0) return 0;

    // ── Context boosts ────────────────────────────────────────────────────────
    if (_positionSymbols.contains(symUp)) score += 400;
    if (_holdingSymbols.contains(symUp)) score += 300;
    if (_watchlistSymbols.contains(symUp)) score += 300;
    final recentIdx = _recentSearches.indexOf(symUp);
    if (recentIdx >= 0) score += math.max(0, 200 - recentIdx * 20);

    // ── Popularity boost ──────────────────────────────────────────────────────
    score += math.max(0, 50 - inst.popularityRank * 2);

    // ── Segment-aware query boosts ────────────────────────────────────────────
    // If query looks like a commodity → boost MCX
    const commodityHints = [
      'crude',
      'gold',
      'silver',
      'copper',
      'zinc',
      'nickel',
      'nat gas',
      'naturalgas',
      'aluminium',
      'lead',
      'cotton',
    ];
    if (commodityHints.any((h) => q.contains(h)) && inst.exchange == 'MCX') {
      score += 100;
    }
    // If query has currency pair pattern → boost CDS
    if ((q.contains('inr') ||
            q.contains('usd') ||
            q.contains('eur') ||
            q.contains('gbp')) &&
        inst.segment == InstrumentSegment.curr) {
      score += 100;
    }
    // If query has FUT/futures → boost futures
    if ((q.contains('fut') || q.contains('future')) &&
        inst.segment == InstrumentSegment.fut) {
      score += 80;
    }
    // If query has CE/PE → boost options
    if (q.endsWith('ce') && inst.segment == InstrumentSegment.ce) score += 80;
    if (q.endsWith('pe') && inst.segment == InstrumentSegment.pe) score += 80;

    return score;
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final dp = List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));
    for (var i = 0; i <= a.length; i++) dp[i][0] = i;
    for (var j = 0; j <= b.length; j++) dp[0][j] = j;
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        dp[i][j] = a[i - 1] == b[j - 1]
            ? dp[i - 1][j - 1]
            : 1 +
                  [
                    dp[i - 1][j],
                    dp[i][j - 1],
                    dp[i - 1][j - 1],
                  ].reduce(math.min);
      }
    }
    return dp[a.length][b.length];
  }
}
