/// SymbolParser: normalizing raw Angel One trading symbols and extracting
/// the underlying equity ticker from futures/options contract symbols.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:box_trading_web/services/symbol_parser.dart';

void main() {
  group('SymbolParser.normalize', () {
    test('strips -EQ suffix', () {
      expect(SymbolParser.normalize('RELIANCE-EQ'), 'RELIANCE');
    });

    test('strips -BE suffix', () {
      expect(SymbolParser.normalize('IDEA-BE'), 'IDEA');
    });

    test('strips .NS suffix', () {
      expect(SymbolParser.normalize('TCS.NS'), 'TCS');
    });

    test('strips .BO suffix', () {
      expect(SymbolParser.normalize('RELIANCE.BO'), 'RELIANCE');
    });

    test('leaves a bare symbol unchanged', () {
      expect(SymbolParser.normalize('INFY'), 'INFY');
    });

    test('trims whitespace and upper-cases', () {
      expect(SymbolParser.normalize('  infy  '), 'INFY');
    });
  });

  group('SymbolParser.underlyingOf — equities', () {
    test('RELIANCE-EQ -> RELIANCE', () {
      expect(SymbolParser.underlyingOf('RELIANCE-EQ'), 'RELIANCE');
    });

    test('TCS-EQ -> TCS', () {
      expect(SymbolParser.underlyingOf('TCS-EQ'), 'TCS');
    });

    test('INFY -> INFY', () {
      expect(SymbolParser.underlyingOf('INFY'), 'INFY');
    });
  });

  group('SymbolParser.underlyingOf — futures', () {
    test('real Angel One format: ADANIGREEN25AUG26FUT -> ADANIGREEN', () {
      expect(SymbolParser.underlyingOf('ADANIGREEN25AUG26FUT'), 'ADANIGREEN');
    });

    test('TCS31JULFUT (no year) -> TCS', () {
      expect(SymbolParser.underlyingOf('TCS31JULFUT'), 'TCS');
    });

    test('RELIANCE29AUGFUT -> RELIANCE', () {
      expect(SymbolParser.underlyingOf('RELIANCE29AUGFUT'), 'RELIANCE');
    });

    test('single-digit day: RELIANCE5AUG26FUT -> RELIANCE', () {
      expect(SymbolParser.underlyingOf('RELIANCE5AUG26FUT'), 'RELIANCE');
    });

    test('ticker with a leading digit: 3MINDIA25AUG26FUT -> 3MINDIA', () {
      expect(SymbolParser.underlyingOf('3MINDIA25AUG26FUT'), '3MINDIA');
    });
  });

  group('SymbolParser.underlyingOf — options', () {
    test('real Angel One format: DIXON28JUL2615250CE -> DIXON', () {
      expect(SymbolParser.underlyingOf('DIXON28JUL2615250CE'), 'DIXON');
    });

    test('real Angel One format PE: HINDUNILVR28JUL262480PE -> HINDUNILVR', () {
      expect(SymbolParser.underlyingOf('HINDUNILVR28JUL262480PE'), 'HINDUNILVR');
    });

    test('RELIANCE29AUG2600CE -> RELIANCE', () {
      expect(SymbolParser.underlyingOf('RELIANCE29AUG2600CE'), 'RELIANCE');
    });

    test('lower-case input still resolves: reliance29aug2600ce -> RELIANCE', () {
      expect(SymbolParser.underlyingOf('reliance29aug2600ce'), 'RELIANCE');
    });
  });

  group('SymbolParser.underlyingOf — indices, currencies, commodities', () {
    test('index symbol passes through unparsed: NIFTY -> NIFTY', () {
      expect(SymbolParser.underlyingOf('NIFTY'), 'NIFTY');
    });

    test('index symbol with space: NIFTY 50 -> NIFTY 50', () {
      expect(SymbolParser.underlyingOf('NIFTY 50'), 'NIFTY 50');
    });

    test('currency pair passes through unparsed: USDINR -> USDINR', () {
      expect(SymbolParser.underlyingOf('USDINR'), 'USDINR');
    });

    test('commodity root passes through unparsed: CRUDEOIL -> CRUDEOIL', () {
      expect(SymbolParser.underlyingOf('CRUDEOIL'), 'CRUDEOIL');
    });
  });
}
