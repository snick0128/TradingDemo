/// SearchIndex — Prefix-trie search engine for trading instruments.
///
/// Architecture:
///   - Static seed catalog (popular instruments — instant offline results)
///   - Prefix trie (Map<String, Set<int>>) for O(1) prefix lookup on any catalog size
///   - Scoring: exact > prefix > alias > name > fuzzy
///   - Context boosts: watchlist, holdings, positions, recent searches
///   - Dynamic loading: remote results are ingested via [ingestRemoteResults()]
///     so the same search() call covers both local + backend instruments after
///     the first remote response.

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

// ── Instrument model ──────────────────────────────────────────────────────────

enum InstrumentSegment { eq, fut, ce, pe, comm, curr, etf, idx, mf, bond }

class Instrument {
  final String symbol;      // e.g. RELIANCE, CRUDEOIL, NIFTY 50
  final String displayName; // cleaned display symbol
  final String name;        // full company/instrument name
  final String exchange;    // NSE, BSE, MCX, NFO, CDS
  final InstrumentSegment segment;
  final List<String> aliases;
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
      case InstrumentSegment.eq:   return 'EQ';
      case InstrumentSegment.fut:  return 'FUT';
      case InstrumentSegment.ce:   return 'CE';
      case InstrumentSegment.pe:   return 'PE';
      case InstrumentSegment.comm: return 'COMM';
      case InstrumentSegment.curr: return 'CURR';
      case InstrumentSegment.etf:  return 'ETF';
      case InstrumentSegment.idx:  return 'INDEX';
      case InstrumentSegment.mf:   return 'MF';
      case InstrumentSegment.bond: return 'BOND';
    }
  }
}

// ── Static seed catalog ───────────────────────────────────────────────────────

final _kSeedCatalog = <Instrument>[
  // NSE Equities
  Instrument(symbol: 'RELIANCE',   displayName: 'RELIANCE',   name: 'Reliance Industries Ltd',      exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['ril', 'reliance'],            popularityRank: 1),
  Instrument(symbol: 'TCS',        displayName: 'TCS',        name: 'Tata Consultancy Services',    exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['tata consultancy'],           popularityRank: 2),
  Instrument(symbol: 'INFY',       displayName: 'INFY',       name: 'Infosys Ltd',                  exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['infosys'],                   popularityRank: 3),
  Instrument(symbol: 'HDFCBANK',   displayName: 'HDFCBANK',   name: 'HDFC Bank Ltd',                exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['hdfc bank', 'hdfc'],         popularityRank: 4),
  Instrument(symbol: 'ICICIBANK',  displayName: 'ICICIBANK',  name: 'ICICI Bank Ltd',               exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['icici bank', 'icici'],       popularityRank: 5),
  Instrument(symbol: 'SBIN',       displayName: 'SBIN',       name: 'State Bank of India',          exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['sbi', 'state bank'],         popularityRank: 6),
  Instrument(symbol: 'WIPRO',      displayName: 'WIPRO',      name: 'Wipro Ltd',                    exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['wipro'],                     popularityRank: 7),
  Instrument(symbol: 'AXISBANK',   displayName: 'AXISBANK',   name: 'Axis Bank Ltd',                exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['axis bank', 'axis'],         popularityRank: 8),
  Instrument(symbol: 'BAJFINANCE', displayName: 'BAJFINANCE', name: 'Bajaj Finance Ltd',            exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['bajaj finance', 'bajaj fin'],popularityRank: 9),
  Instrument(symbol: 'HINDUNILVR', displayName: 'HINDUNILVR', name: 'Hindustan Unilever Ltd',       exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['hul', 'hindustan unilever'], popularityRank: 10),
  Instrument(symbol: 'KOTAKBANK',  displayName: 'KOTAKBANK',  name: 'Kotak Mahindra Bank',          exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['kotak bank', 'kotak'],       popularityRank: 11),
  Instrument(symbol: 'BHARTIARTL', displayName: 'BHARTIARTL', name: 'Bharti Airtel Ltd',            exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['airtel', 'bharti airtel'],   popularityRank: 12),
  // Tata Motors demerged into TMPV (passenger vehicles) and TMCV (commercial
  // vehicles, continuing "Tata Motors Limited" entity) in 2024 — TATAMOTORS
  // no longer exists as a symbol.
  Instrument(symbol: 'TMCV',       displayName: 'TMCV',       name: 'Tata Motors Ltd',              exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['tata motors'],               popularityRank: 13),
  Instrument(symbol: 'SUNPHARMA',  displayName: 'SUNPHARMA',  name: 'Sun Pharmaceutical',           exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['sun pharma'],                popularityRank: 14),
  Instrument(symbol: 'MARUTI',     displayName: 'MARUTI',     name: 'Maruti Suzuki India Ltd',      exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['maruti suzuki'],             popularityRank: 15),
  Instrument(symbol: 'NTPC',       displayName: 'NTPC',       name: 'NTPC Ltd',                     exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['ntpc'],                      popularityRank: 16),
  Instrument(symbol: 'ONGC',       displayName: 'ONGC',       name: 'Oil and Natural Gas Corp',     exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['ongc'],                      popularityRank: 17),
  Instrument(symbol: 'ITC',        displayName: 'ITC',        name: 'ITC Ltd',                      exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['itc'],                       popularityRank: 18),
  Instrument(symbol: 'HCLTECH',    displayName: 'HCLTECH',    name: 'HCL Technologies Ltd',         exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['hcl tech', 'hcl'],           popularityRank: 19),
  Instrument(symbol: 'TITAN',      displayName: 'TITAN',      name: 'Titan Company Ltd',            exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['titan'],                     popularityRank: 20),
  Instrument(symbol: 'ADANIENT',   displayName: 'ADANIENT',   name: 'Adani Enterprises Ltd',        exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['adani enterprises', 'adani'],popularityRank: 21),
  Instrument(symbol: 'ADANIPORTS', displayName: 'ADANIPORTS', name: 'Adani Ports & SEZ',            exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['adani ports'],               popularityRank: 22),
  Instrument(symbol: 'LT',         displayName: 'LT',         name: 'Larsen & Toubro',              exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['larsen toubro', 'l&t'],      popularityRank: 23),
  Instrument(symbol: 'BAJAJFINSV', displayName: 'BAJAJFINSV', name: 'Bajaj Finserv Ltd',            exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['bajaj finserv'],             popularityRank: 24),
  Instrument(symbol: 'ULTRACEMCO', displayName: 'ULTRACEMCO', name: 'UltraTech Cement Ltd',         exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['ultratech cement', 'ultratech'], popularityRank: 25),
  // Symbol is the real listed ticker (ETERNAL — Zomato's legal/exchange name
  // since the 2024 rename) so quote/order resolution stays correct, but the
  // display name intentionally stays "ZOMATO" since that's the recognized
  // brand users search for.
  Instrument(symbol: 'ETERNAL',    displayName: 'ZOMATO',     name: 'Zomato Ltd',                   exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['zomato', 'eternal'],         popularityRank: 26),
  Instrument(symbol: 'HAL',        displayName: 'HAL',        name: 'Hindustan Aeronautics Ltd',    exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['hal', 'hindustan aeronautics'], popularityRank: 27),
  Instrument(symbol: 'BEL',        displayName: 'BEL',        name: 'Bharat Electronics Ltd',       exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['bel', 'bharat electronics'], popularityRank: 28),
  Instrument(symbol: 'TRENT',      displayName: 'TRENT',      name: 'Trent Ltd',                    exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['trent'],                     popularityRank: 29),
  Instrument(symbol: 'DRREDDY',    displayName: 'DRREDDY',    name: "Dr. Reddy's Laboratories",     exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['dr reddy', 'dr reddys'],     popularityRank: 30),
  // Recent IPOs
  Instrument(symbol: 'OLAELECTRIC',displayName: 'OLAELECTRIC',name: 'Ola Electric Mobility Ltd',   exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['ola electric', 'ola ev', 'ola'], popularityRank: 31),
  Instrument(symbol: 'SWIGGY',     displayName: 'SWIGGY',     name: 'Swiggy Ltd',                   exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['swiggy'],                    popularityRank: 32),
  Instrument(symbol: 'HYUNDAI',    displayName: 'HYUNDAI',    name: 'Hyundai Motor India Ltd',      exchange: 'NSE', segment: InstrumentSegment.eq,   aliases: ['hyundai india', 'hmil'],     popularityRank: 33),
  // Indices
  Instrument(symbol: 'NIFTY 50',   displayName: 'NIFTY 50',   name: 'Nifty 50 Index',               exchange: 'NSE', segment: InstrumentSegment.idx,  aliases: ['nifty', 'nifty50', 'nf'],     popularityRank: 1),
  Instrument(symbol: 'BANKNIFTY',  displayName: 'BANKNIFTY',  name: 'Bank Nifty Index',             exchange: 'NSE', segment: InstrumentSegment.idx,  aliases: ['bnf', 'bank nifty', 'banknf'], popularityRank: 2),
  Instrument(symbol: 'SENSEX',     displayName: 'SENSEX',     name: 'BSE Sensex',                   exchange: 'BSE', segment: InstrumentSegment.idx,  aliases: ['bse sensex', 'sensex30'],     popularityRank: 3),
  Instrument(symbol: 'FINNIFTY',   displayName: 'FINNIFTY',   name: 'Nifty Financial Services',     exchange: 'NSE', segment: InstrumentSegment.idx,  aliases: ['fin nifty', 'finnf'],         popularityRank: 4),
  Instrument(symbol: 'MIDCPNIFTY', displayName: 'MIDCPNIFTY', name: 'Nifty Midcap Select',          exchange: 'NSE', segment: InstrumentSegment.idx,  aliases: ['midcap nifty', 'midcp'],      popularityRank: 5),
  Instrument(symbol: 'INDIA VIX',  displayName: 'INDIA VIX',  name: 'India Volatility Index',       exchange: 'NSE', segment: InstrumentSegment.idx,  aliases: ['vix', 'india vix', 'volatility index'], popularityRank: 6),
  // MCX Commodities
  Instrument(symbol: 'GOLD',        displayName: 'GOLD',        name: 'Gold MCX Futures',            exchange: 'MCX', segment: InstrumentSegment.comm, aliases: ['gold mcx', 'sona'],           popularityRank: 1),
  Instrument(symbol: 'SILVER',      displayName: 'SILVER',      name: 'Silver MCX Futures',          exchange: 'MCX', segment: InstrumentSegment.comm, aliases: ['silver mcx', 'chandi'],       popularityRank: 2),
  Instrument(symbol: 'CRUDEOIL',    displayName: 'CRUDEOIL',    name: 'Crude Oil MCX Futures',       exchange: 'MCX', segment: InstrumentSegment.comm, aliases: ['crude', 'crude oil', 'wti'],  popularityRank: 3),
  Instrument(symbol: 'NATURALGAS',  displayName: 'NATURALGAS',  name: 'Natural Gas MCX Futures',     exchange: 'MCX', segment: InstrumentSegment.comm, aliases: ['nat gas', 'natural gas', 'ng'], popularityRank: 4),
  Instrument(symbol: 'COPPER',      displayName: 'COPPER',      name: 'Copper MCX Futures',          exchange: 'MCX', segment: InstrumentSegment.comm, aliases: ['copper mcx'],                 popularityRank: 5),
  Instrument(symbol: 'ZINC',        displayName: 'ZINC',        name: 'Zinc MCX Futures',            exchange: 'MCX', segment: InstrumentSegment.comm, aliases: ['zinc mcx'],                   popularityRank: 6),
  Instrument(symbol: 'LEAD',        displayName: 'LEAD',        name: 'Lead MCX Futures',            exchange: 'MCX', segment: InstrumentSegment.comm, aliases: ['lead mcx'],                   popularityRank: 7),
  Instrument(symbol: 'ALUMINIUM',   displayName: 'ALUMINIUM',   name: 'Aluminium MCX Futures',       exchange: 'MCX', segment: InstrumentSegment.comm, aliases: ['alum', 'aluminium mcx'],      popularityRank: 8),
  Instrument(symbol: 'NICKEL',      displayName: 'NICKEL',      name: 'Nickel MCX Futures',          exchange: 'MCX', segment: InstrumentSegment.comm, aliases: ['nickel mcx'],                 popularityRank: 9),
  Instrument(symbol: 'COTTON',      displayName: 'COTTON',      name: 'Cotton MCX Futures',          exchange: 'MCX', segment: InstrumentSegment.comm, aliases: ['cotton mcx', 'kapas'],        popularityRank: 10),
  // NFO Futures
  Instrument(symbol: 'NIFTY FUT',      displayName: 'NIFTY FUT',      name: 'Nifty 50 Futures (Near)',     exchange: 'NFO', segment: InstrumentSegment.fut, aliases: ['nifty futures', 'nf fut'],   popularityRank: 1),
  Instrument(symbol: 'BANKNIFTY FUT',  displayName: 'BANKNIFTY FUT',  name: 'Bank Nifty Futures (Near)',   exchange: 'NFO', segment: InstrumentSegment.fut, aliases: ['bnf fut', 'bank nifty fut'], popularityRank: 2),
  Instrument(symbol: 'RELIANCE FUT',   displayName: 'RELIANCE FUT',   name: 'Reliance Futures (Near)',     exchange: 'NFO', segment: InstrumentSegment.fut, aliases: ['ril fut'],                   popularityRank: 3),
  // Currency
  Instrument(symbol: 'USDINR', displayName: 'USDINR', name: 'US Dollar / Indian Rupee', exchange: 'CDS', segment: InstrumentSegment.curr, aliases: ['usd inr', 'dollar rupee'], popularityRank: 1),
  Instrument(symbol: 'EURINR', displayName: 'EURINR', name: 'Euro / Indian Rupee',       exchange: 'CDS', segment: InstrumentSegment.curr, aliases: ['eur inr', 'euro rupee'],   popularityRank: 2),
  Instrument(symbol: 'GBPINR', displayName: 'GBPINR', name: 'British Pound / INR',       exchange: 'CDS', segment: InstrumentSegment.curr, aliases: ['gbp inr', 'pound rupee'],  popularityRank: 3),
  // ETFs
  Instrument(symbol: 'GOLDBEES',  displayName: 'GOLDBEES',  name: 'Nippon India Gold ETF',        exchange: 'NSE', segment: InstrumentSegment.etf, aliases: ['gold etf', 'gold bees'],  popularityRank: 1),
  Instrument(symbol: 'NIFTYBEES', displayName: 'NIFTYBEES', name: 'Nippon India ETF Nifty 50',    exchange: 'NSE', segment: InstrumentSegment.etf, aliases: ['nifty etf', 'nifty bees'],popularityRank: 2),
  Instrument(symbol: 'BANKBEES',  displayName: 'BANKBEES',  name: 'Nippon India ETF Bank Nifty',  exchange: 'NSE', segment: InstrumentSegment.etf, aliases: ['bank etf', 'bank bees'],  popularityRank: 3),
];

// ── Prefix Trie ───────────────────────────────────────────────────────────────
// Maps every prefix (1…8 chars) of every searchable term to the set of catalog
// indices that contain that prefix. Built once at startup and on ingestion.
// Lookup is O(1): single Map.[] call, no linear scan.

class _PrefixIndex {
  // prefix → Set of catalog indices
  final Map<String, Set<int>> _map = {};
  final List<Instrument> _catalog;

  _PrefixIndex(this._catalog) {
    _rebuildAll();
  }

  void _rebuildAll() {
    _map.clear();
    for (var i = 0; i < _catalog.length; i++) {
      _indexInstrument(i, _catalog[i]);
    }
  }

  void addInstrument(int index, Instrument inst) {
    _indexInstrument(index, inst);
  }

  Set<int> lookup(String prefix) => _map[prefix] ?? const {};

  void _indexInstrument(int idx, Instrument inst) {
    _addPrefixes(idx, inst.symbol.toLowerCase());
    _addPrefixes(idx, inst.displayName.toLowerCase());
    _addPrefixes(idx, inst.name.toLowerCase());
    for (final alias in inst.aliases) {
      _addPrefixes(idx, alias.toLowerCase());
    }
  }

  void _addPrefixes(int idx, String term) {
    if (term.isEmpty) return;
    // Index prefixes of length 1 through min(term.length, 8)
    final limit = math.min(term.length, 8);
    for (var len = 1; len <= limit; len++) {
      (_map[term.substring(0, len)] ??= {}).add(idx);
    }
    // Also index the full term for long symbols
    if (term.length > 8) {
      (_map[term] ??= {}).add(idx);
    }
  }
}

// ── SearchIndex ───────────────────────────────────────────────────────────────

class SearchIndex {
  SearchIndex._() {
    _catalog = List<Instrument>.from(_kSeedCatalog);
    _prefix  = _PrefixIndex(_catalog);
    _dedupKeys = {
      for (var i = 0; i < _catalog.length; i++)
        _dedupKey(_catalog[i]): i,
    };
  }

  static final SearchIndex instance = SearchIndex._();

  late List<Instrument> _catalog;
  late _PrefixIndex _prefix;
  // exchange_symbol → catalog index (prevents duplicates on ingest)
  late Map<String, int> _dedupKeys;

  // symbol (upper) → Angel One symbolToken — populated by ingestRemoteResults.
  // Used to pass a valid token when navigating from local catalog results so
  // the StockDetailScreen can call /derivatives/quote and always get a price.
  final Map<String, String> _tokenMap = {};

  // Context sets — updated from TradingStore
  final Set<String> _watchlistSymbols = {};
  final Set<String> _holdingSymbols   = {};
  final Set<String> _positionSymbols  = {};
  final List<String> _recentSearches  = [];

  static String _dedupKey(Instrument i) => '${i.exchange}_${i.symbol}';

  void updateContext({
    required Set<String> watchlist,
    required Set<String> holdings,
    required Set<String> positions,
    required List<String> recent,
  }) {
    _watchlistSymbols..clear()..addAll(watchlist.map((s) => s.toUpperCase()));
    _holdingSymbols  ..clear()..addAll(holdings .map((s) => s.toUpperCase()));
    _positionSymbols ..clear()..addAll(positions.map((s) => s.toUpperCase()));
    _recentSearches  ..clear()..addAll(recent   .map((s) => s.toUpperCase()));
  }

  /// Ingest remote search results (from backend) into the local index so that
  /// subsequent keystrokes return instant results without another API call.
  /// Deduplicates against existing catalog entries.
  void ingestRemoteResults(List<Map<String, dynamic>> results) {
    for (final r in results) {
      final sym  = ((r['symbol'] ?? r['tradingSymbol'] ?? '') as String).toUpperCase().trim();
      final ex   = ((r['exchange'] ?? '') as String).toUpperCase().trim();
      if (sym.isEmpty || ex.isEmpty) continue;

      // Always store the token — even for existing catalog entries.
      // This is the key fix: local results (seed catalog) have no token, but
      // once the remote search returns a token, we cache it here so that
      // _navigateToSymbol can pass it to StockDetailScreen.
      final token = (r['token'] ?? r['symbolToken'] ?? '').toString().trim();
      if (token.isNotEmpty) {
        _tokenMap[sym] = token;
        // Also store with exchange prefix for disambiguation (e.g. INFY NSE vs INFY BSE)
        _tokenMap['${ex}_$sym'] = token;
        // NSE stores equities/ETFs with a -EQ suffix (e.g. NIFTYBEES-EQ).
        // The local seed catalog uses the bare name (NIFTYBEES, exchange=NSE).
        // Store an extra qualified entry under the bare name so that
        // getToken('NIFTYBEES', exchange:'NSE') finds the NSE token, not BSE's.
        if (ex == 'NSE') {
          final bare = sym.replaceAll(RegExp(r'-(EQ|BE|BL|IQ|RL|AF|U\d+)$'), '');
          if (bare != sym) {
            _tokenMap['NSE_$bare'] = token;
            debugPrint('[SearchIndex] NSE suffix-stripped: $sym → $bare token=$token');
          }
        }
      }

      final key = '${ex}_$sym';
      if (_dedupKeys.containsKey(key)) {
        // Update LTP on existing entry
        final idx = _dedupKeys[key]!;
        final ltp = (r['ltp'] as num?)?.toDouble();
        if (ltp != null && ltp > 0) _catalog[idx].ltp = ltp;
        continue;
      }

      final seg = _segmentFromRemote(
        (r['type'] ?? r['instrumentType'] ?? '') as String,
        sym,
        ex,
      );

      final inst = Instrument(
        symbol:       sym,
        displayName:  sym.replaceAll(RegExp(r'-(EQ|BE|BL|IQ|RL|AF|U\d+)$'), ''),
        name:         (r['displayName'] ?? r['name'] ?? sym) as String,
        exchange:     ex,
        segment:      seg,
        aliases:      const [],
        popularityRank: 500,
        ltp:          (r['ltp'] as num?)?.toDouble(),
        changePercent:(r['percentChange'] as num?)?.toDouble(),
      );

      final idx = _catalog.length;
      _catalog.add(inst);
      _prefix.addInstrument(idx, inst);
      _dedupKeys[key] = idx;
    }
  }

  /// Look up the Angel One symbolToken for a given trading symbol.
  ///
  /// Lookup order (stops at first hit):
  ///   1. Exchange-qualified exact:   NSE_NIFTYBEES-EQ
  ///   2. Exchange-qualified bare:    NSE_NIFTYBEES  (stripped by ingestRemoteResults)
  ///   3. Exchange-qualified +EQ:     NSE_NIFTYBEES-EQ  (for NSE, if bare miss)
  ///   4. Unqualified fallback:       NIFTYBEES
  ///
  /// Returns empty string if no token is known yet.
  String getToken(String symbol, {String exchange = ''}) {
    final sym = symbol.toUpperCase().trim();
    final ex  = exchange.toUpperCase().trim();
    if (ex.isNotEmpty) {
      // 1. Exact qualified key (e.g. NSE_NIFTYBEES-EQ or BSE_NIFTYBEES)
      final qualified = _tokenMap['${ex}_$sym'];
      if (qualified != null && qualified.isNotEmpty) return qualified;
      // 2. Bare-name qualified key stored by ingestRemoteResults for NSE -EQ symbols
      //    e.g. NSE_NIFTYBEES → covers seed-catalog instruments whose symbol has no suffix
      // (already covered by step 1 when sym has no suffix; this is a no-op duplicate-safe)

      // 3. For NSE: try with -EQ suffix in case only the suffixed form was ingested
      if (ex == 'NSE') {
        final withEq = _tokenMap['NSE_${sym}-EQ'];
        if (withEq != null && withEq.isNotEmpty) return withEq;
      }
    }
    // 4. Unqualified fallback — may be BSE token for dual-listed symbols;
    //    only reached when no exchange was provided or qualified lookup missed.
    return _tokenMap[sym] ?? '';
  }

  /// Search the local catalog + any ingested instruments.
  /// O(1) prefix lookup via trie; scores only the candidate set.
  List<Instrument> search(String rawQuery, {int limit = 30}) {
    if (rawQuery.trim().isEmpty) return const [];
    final q = rawQuery.trim().toLowerCase();

    // Prefix lookup: get candidate indices — O(1)
    // If query is longer than the trie max prefix length (8), still try to
    // look up the full string to catch exact matches.
    Set<int> candidates = _prefix.lookup(q);
    if (candidates.isEmpty && q.length > 8) {
      candidates = _prefix.lookup(q.substring(0, 8));
    }
    // Fuzzy fallback: if no prefix hits, try a 1-char prefix for typo recovery
    if (candidates.isEmpty && q.isNotEmpty) {
      candidates = _prefix.lookup(q.substring(0, 1));
    }
    if (candidates.isEmpty) return const [];

    final scored = <_SearchResult>[];
    for (final i in candidates) {
      final score = _score(_catalog[i], q);
      if (score > 0) scored.add(_SearchResult(_catalog[i], score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((r) => r.instrument).toList();
  }

  int _score(Instrument inst, String q) {
    final sym     = inst.symbol.toLowerCase();
    final display = inst.displayName.toLowerCase();
    final name    = inst.name.toLowerCase();
    final symUp   = inst.symbol.toUpperCase();

    int score = 0;

    if (sym == q || display == q)                                      score += 1000;
    else if (sym.startsWith(q) || display.startsWith(q))              score += 500;
    else if (inst.aliases.any((a) => a.toLowerCase() == q))            score += 450;
    else if (inst.aliases.any((a) => a.toLowerCase().startsWith(q)))   score += 300;
    else if (sym.contains(q) || display.contains(q))                   score += 200;
    else if (name.startsWith(q))                                        score += 150;
    else if (name.contains(q))                                          score += 80;
    else if (inst.aliases.any((a) => a.toLowerCase().contains(q)))     score += 120;
    else {
      final firstWord = sym.split(RegExp(r'[\s_\-]')).first;
      if (firstWord.length >= q.length - 2 && firstWord.length <= q.length + 2) {
        final dist = _levenshtein(firstWord, q);
        if (dist == 1)      score += 60;
        else if (dist == 2) score += 30;
      }
    }

    if (score == 0) return 0;

    // Context boosts
    if (_positionSymbols.contains(symUp)) score += 400;
    if (_holdingSymbols .contains(symUp)) score += 300;
    if (_watchlistSymbols.contains(symUp))score += 300;
    final ri = _recentSearches.indexOf(symUp);
    if (ri >= 0) score += math.max(0, 200 - ri * 20);

    // Popularity
    score += math.max(0, 50 - inst.popularityRank * 2);

    // Segment-aware boosts
    const _commHints = ['crude','gold','silver','copper','zinc','nickel','nat gas','naturalgas','aluminium','lead','cotton'];
    if (_commHints.any((h) => q.contains(h)) && inst.exchange == 'MCX') score += 100;
    if ((q.contains('inr') || q.contains('usd') || q.contains('eur') || q.contains('gbp')) &&
        inst.segment == InstrumentSegment.curr) score += 100;
    if ((q.contains('fut') || q.contains('future')) && inst.segment == InstrumentSegment.fut) score += 80;
    if (q.endsWith('ce') && inst.segment == InstrumentSegment.ce) score += 80;
    if (q.endsWith('pe') && inst.segment == InstrumentSegment.pe) score += 80;

    return score;
  }

  static InstrumentSegment _segmentFromRemote(String type, String sym, String ex) {
    final t = type.toUpperCase();
    if (ex == 'MCX')                      return InstrumentSegment.comm;
    if (ex == 'CDS')                      return InstrumentSegment.curr;
    if (t == 'ETF' || t == 'ETFS')       return InstrumentSegment.etf;
    if (t == 'INDEX' || t == 'UNDIND')   return InstrumentSegment.idx;
    if (t == 'FUTSTK' || t == 'FUTIDX' || t == 'FUTCOM') return InstrumentSegment.fut;
    if (t == 'OPTSTK' || t == 'OPTIDX') {
      return sym.endsWith('PE') ? InstrumentSegment.pe : InstrumentSegment.ce;
    }
    if (sym.endsWith('FUT')) return InstrumentSegment.fut;
    if (sym.endsWith('CE'))  return InstrumentSegment.ce;
    if (sym.endsWith('PE'))  return InstrumentSegment.pe;
    return InstrumentSegment.eq;
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
            : 1 + [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]].reduce(math.min);
      }
    }
    return dp[a.length][b.length];
  }
}

class _SearchResult {
  final Instrument instrument;
  final int score;
  _SearchResult(this.instrument, this.score);
}
