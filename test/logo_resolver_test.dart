/// LogoResolver: builds Indian Listed Company Logos CDN URLs from a
/// ticker→file mapping. Pure — no network, no SharedPreferences.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:box_trading_web/services/logo_resolver.dart';

void main() {
  final mapping = {
    'NSE:RELIANCE': 'nse/NSE_RELIANCE.svg',
    'NSE:TCS': 'nse/NSE_TCS.svg',
    'BSE:7SEASL': 'bse/BSE_7SEASL.svg',
  };

  group('LogoResolver.resolve', () {
    test('resolves an NSE ticker to its CDN URL', () {
      final url = LogoResolver.resolve(
        ticker: 'RELIANCE',
        exchange: 'NSE',
        mapping: mapping,
      );
      expect(url, '${LogoResolver.baseUrl}nse/NSE_RELIANCE.svg');
    });

    test('resolves a BSE-only ticker even when exchange hint is NSE', () {
      final url = LogoResolver.resolve(
        ticker: '7SEASL',
        exchange: 'NSE',
        mapping: mapping,
      );
      expect(url, '${LogoResolver.baseUrl}bse/BSE_7SEASL.svg');
    });

    test('falls back across NSE/BSE for F&O exchange hints (NFO)', () {
      final url = LogoResolver.resolve(
        ticker: 'TCS',
        exchange: 'NFO',
        mapping: mapping,
      );
      expect(url, '${LogoResolver.baseUrl}nse/NSE_TCS.svg');
    });

    test('is case-insensitive on ticker and exchange', () {
      final url = LogoResolver.resolve(
        ticker: 'reliance',
        exchange: 'nse',
        mapping: mapping,
      );
      expect(url, '${LogoResolver.baseUrl}nse/NSE_RELIANCE.svg');
    });

    test('returns null for a ticker not present in the mapping', () {
      final url = LogoResolver.resolve(
        ticker: 'NIFTY',
        exchange: 'NSE',
        mapping: mapping,
      );
      expect(url, isNull);
    });

    test('returns null for an empty ticker', () {
      final url = LogoResolver.resolve(
        ticker: '',
        exchange: 'NSE',
        mapping: mapping,
      );
      expect(url, isNull);
    });

    test('returns null when the mapping itself is empty (not yet loaded)', () {
      final url = LogoResolver.resolve(
        ticker: 'RELIANCE',
        exchange: 'NSE',
        mapping: const {},
      );
      expect(url, isNull);
    });
  });
}
