/// Property 3: Session locks after inactivity exceeding timeout
/// Validates: Requirements 1.8
///
/// Property 4: App backgrounding always locks the session
/// Validates: Requirements 1.9

import 'package:flutter_test/flutter_test.dart';
import 'package:box_trading_web/state/security_store.dart';

void main() {
  // ─── Property 3: lockNow() sets isLocked = true ───────────────────────────

  group('Property 3: Session lock behaviour', () {
    test('lockNow() sets isLocked to true', () {
      final store = SecurityStore();
      expect(store.isLocked, isFalse);
      store.lockNow();
      expect(store.isLocked, isTrue);
    });

    test('lockNow() is idempotent (calling twice stays locked)', () {
      final store = SecurityStore();
      store.lockNow();
      store.lockNow(); // should not throw
      expect(store.isLocked, isTrue);
    });

    test('unlock with correct PIN after lockNow() sets isLocked to false', () {
      final store = SecurityStore();
      store.setPin('1234');
      store.lockNow();
      expect(store.isLocked, isTrue);

      final result = store.unlock('1234');
      expect(result, isTrue);
      expect(store.isLocked, isFalse);
    });

    test('unlock with wrong PIN after lockNow() keeps isLocked = true', () {
      final store = SecurityStore();
      store.setPin('1234');
      store.lockNow();

      final result = store.unlock('9999');
      expect(result, isFalse);
      expect(store.isLocked, isTrue);
    });

    test('Session locks after idle timeout elapses', () async {
      // Use a very short timeout for testing
      final store = SecurityStore(
        lockTimeout: const Duration(milliseconds: 50),
      );
      store.startMonitoring();
      expect(store.isLocked, isFalse);

      // Wait longer than the timeout
      await Future.delayed(const Duration(milliseconds: 150));
      expect(store.isLocked, isTrue);

      store.disposeMonitoring();
    });
  });

  // ─── Property 4: App backgrounding locks session after timeout ────────────

  group('Property 4: App backgrounding locks session', () {
    test('onAppPaused + onAppResumed after timeout locks the session', () {
      // Use a zero-duration timeout so any pause exceeds it
      final store = SecurityStore(lockTimeout: Duration.zero);
      expect(store.isLocked, isFalse);

      store.onAppPaused();
      // Simulate time passing beyond timeout
      store.onAppResumed();

      expect(store.isLocked, isTrue);
    });

    test('onAppPaused + onAppResumed within timeout does NOT lock', () async {
      final store = SecurityStore(lockTimeout: const Duration(seconds: 60));
      store.startMonitoring();
      expect(store.isLocked, isFalse);

      store.onAppPaused();
      // Resume immediately — well within the 60s timeout
      await Future.delayed(const Duration(milliseconds: 10));
      store.onAppResumed();

      expect(store.isLocked, isFalse);
      store.disposeMonitoring();
    });

    test('onAppResumed without prior onAppPaused does not lock', () {
      final store = SecurityStore(lockTimeout: Duration.zero);
      store.onAppResumed(); // no prior pause
      expect(store.isLocked, isFalse);
    });
  });
}
