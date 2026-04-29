/// Property 2: PIN validation is strict
/// Validates: Requirements 1.6, 3.2

import 'package:flutter_test/flutter_test.dart';
import 'package:box_trading_web/state/security_store.dart';

void main() {
  // ─── Property 2: Valid 4-digit numeric PINs are accepted ──────────────────

  group('Valid 4-digit numeric PINs are accepted by changePin', () {
    final validPins = ['1234', '0000', '9999', '5678', '1111'];

    for (final pin in validPins) {
      test('PIN "$pin" is valid', () {
        // Start with default pin '1234', change to the target pin
        final store = SecurityStore();
        // First set a known pin via setPin, then verify changePin accepts valid pins
        store.setPin('0000');
        final result = store.changePin(currentPin: '0000', newPin: pin);
        expect(result, isTrue, reason: 'PIN "$pin" should be accepted');
      });
    }
  });

  // ─── Property 2: Non-4-digit PINs are rejected ────────────────────────────

  group('Non-4-digit or non-numeric PINs are rejected by changePin', () {
    final invalidPins = ['123', '12345', 'abcd', '', '12 4', '123a', '00000'];

    for (final pin in invalidPins) {
      test('PIN "$pin" is invalid', () {
        final store = SecurityStore();
        store.setPin('0000');
        final result = store.changePin(currentPin: '0000', newPin: pin);
        expect(result, isFalse, reason: 'PIN "$pin" should be rejected');
      });
    }
  });

  // ─── Property 2: unlock only succeeds with correct PIN ────────────────────

  test('unlock returns true only for the correct PIN', () {
    final store = SecurityStore();
    store.setPin('5678');
    store.lockNow();

    expect(store.unlock('1234'), isFalse);
    expect(store.unlock('0000'), isFalse);
    expect(store.unlock('5678'), isTrue);
    expect(store.isLocked, isFalse);
  });
}
