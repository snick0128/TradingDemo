import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Downloads and persists everything the Indian Listed Company Logos
/// integration needs locally (https://github.com/dharunashokkumar/indian-listed-company-logos):
///
///  - the ticker→file mapping (`logos.json`), refreshed at most once every
///    [_refreshInterval]
///  - individual SVG logo bytes, fetched once per ticker and kept forever
///    (company logos don't change often enough to warrant an expiry)
///
/// This project has no iOS/Android target (web-only — see `web/`), so
/// `dart:io` File-based caches (e.g. flutter_cache_manager's `getSingleFile`)
/// aren't usable here. SharedPreferences (backed by `localStorage` on web)
/// fills the same role Kingfisher/SDWebImage's disk cache would on iOS —
/// it's already this project's disk-persistence layer (see
/// `PersistenceService`), so this manager mirrors that pattern rather than
/// introducing a new storage mechanism.
class LogoCacheManager {
  LogoCacheManager._();

  static final instance = LogoCacheManager._();

  static const _mappingUrl =
      'https://dharunashokkumar.github.io/indian-listed-company-logos/data/logos.json';
  static const _mappingKey = 'logos.ticker_map_v1';
  static const _fetchedAtKey = 'logos.fetched_at_ms';
  static const _refreshInterval = Duration(days: 7);

  SharedPreferences? _prefs;
  Map<String, String>? _memoryMap;
  Future<Map<String, String>>? _loadFuture;

  /// Returns the ticker→file mapping ("NSE:RELIANCE" -> "nse/NSE_RELIANCE.svg"),
  /// loading it at most once per process. Safe to call from many widgets
  /// concurrently — they all await the same in-flight load.
  Future<Map<String, String>> loadMapping() {
    final cached = _memoryMap;
    if (cached != null) return Future.value(cached);
    return _loadFuture ??= _load();
  }

  Future<Map<String, String>> _load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final storedJson = _prefs!.getString(_mappingKey);
    final fetchedAtMs = _prefs!.getInt(_fetchedAtKey);
    final isStale = fetchedAtMs == null ||
        DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(fetchedAtMs),
            ) >
            _refreshInterval;

    if (storedJson != null && !isStale) {
      final map = _decode(storedJson);
      _memoryMap = map;
      return map;
    }

    try {
      final fresh = await _downloadAndSlim();
      await _persist(fresh);
      _memoryMap = fresh;
      return fresh;
    } catch (_) {
      // Network failed (or offline) — serve stale-but-usable data rather
      // than showing no logos at all. Only fall back to empty on first run.
      final map = storedJson != null ? _decode(storedJson) : <String, String>{};
      _memoryMap = map;
      return map;
    }
  }

  Future<Map<String, String>> _downloadAndSlim() async {
    final response =
        await http.get(Uri.parse(_mappingUrl)).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('logos.json fetch failed: HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final logos = decoded['logos'] as List<dynamic>? ?? const [];

    final map = <String, String>{};
    for (final raw in logos) {
      final entry = raw as Map<String, dynamic>;
      final exchange = (entry['exchange'] as String?)?.toUpperCase();
      final ticker = (entry['ticker'] as String?)?.toUpperCase();
      final file = entry['file'] as String?;
      if (exchange == null || ticker == null || file == null) continue;
      map['$exchange:$ticker'] = file;
    }
    return map;
  }

  Future<void> _persist(Map<String, String> map) async {
    await _prefs!.setString(_mappingKey, jsonEncode(map));
    await _prefs!.setInt(_fetchedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  Map<String, String> _decode(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  // ── Image bytes ──────────────────────────────────────────────────────────

  final Map<String, Uint8List> _imageMemCache = {};
  final Map<String, Future<Uint8List?>> _imageInFlight = {};

  String _imageKey(String url) => 'logos.img.${url.hashCode}';

  /// Returns the SVG bytes for [url] — from memory if already fetched this
  /// session, else from SharedPreferences, else downloads once. Concurrent
  /// calls for the same [url] (e.g. the same logo scrolling in and out of
  /// view repeatedly) share a single in-flight future, so it's never
  /// downloaded twice.
  Future<Uint8List?> loadImageBytes(String url) {
    final mem = _imageMemCache[url];
    if (mem != null) return Future.value(mem);
    return _imageInFlight.putIfAbsent(url, () => _fetchImageBytes(url));
  }

  Future<Uint8List?> _fetchImageBytes(String url) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final key = _imageKey(url);
      final cachedB64 = _prefs!.getString(key);
      if (cachedB64 != null) {
        final bytes = base64Decode(cachedB64);
        _imageMemCache[url] = bytes;
        return bytes;
      }

      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('logo image fetch failed: HTTP ${response.statusCode}');
      }
      final bytes = response.bodyBytes;
      _imageMemCache[url] = bytes;
      try {
        await _prefs!.setString(key, base64Encode(bytes));
      } catch (_) {
        // Storage quota exceeded or unavailable — logo still renders from
        // the in-memory cache for the rest of this session.
      }
      return bytes;
    } catch (_) {
      return null;
    } finally {
      _imageInFlight.remove(url);
    }
  }
}
