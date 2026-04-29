/// Property 1: Authentication outcome matches credential validity
/// Validates: Requirements 1.2, 1.3

import 'package:flutter_test/flutter_test.dart';
import 'package:box_trading_web/state/security_store.dart';

void main() {
  // ─── Property 1: Valid credentials return success=true ────────────────────

  group('Valid credentials authenticate successfully', () {
    test('demo/password returns true', () {
      final store = SecurityStore();
      expect(store.authenticate('demo', 'password'), isTrue);
      expect(store.isAuthenticated, isTrue);
    });

    test('admin/admin123 returns true', () {
      final store = SecurityStore();
      expect(store.authenticate('admin', 'admin123'), isTrue);
      expect(store.isAuthenticated, isTrue);
    });
  });

  // ─── Property 1: Invalid credentials return success=false ─────────────────

  group('Invalid credentials are rejected', () {
    final invalidCombinations = [
      ('demo', 'wrongpassword'),
      ('admin', 'password'),
      ('unknown', 'password'),
      ('', ''),
      ('demo', ''),
      ('', 'password'),
      ('DEMO', 'password'),
      ('demo', 'Password'),
    ];

    for (final (clientId, password) in invalidCombinations) {
      test('clientId="$clientId", password="$password" returns false', () {
        final store = SecurityStore();
        expect(store.authenticate(clientId, password), isFalse);
        expect(store.isAuthenticated, isFalse);
      });
    }
  });

  // ─── Property 1: Session log updated on successful auth ───────────────────

  test('Session log records each successful authentication', () {
    final store = SecurityStore();
    expect(store.sessionLog, isEmpty);

    store.authenticate('demo', 'password');
    expect(store.sessionLog.length, equals(1));

    // Re-authenticate (new store instance to simulate fresh login)
    final store2 = SecurityStore();
    store2.authenticate('admin', 'admin123');
    store2.authenticate('demo', 'password');
    expect(store2.sessionLog.length, equals(2));
  });

  // ─── Property 1: Failed auth does not update session log ──────────────────

  test('Failed authentication does not add to session log', () {
    final store = SecurityStore();
    store.authenticate('wrong', 'creds');
    expect(store.sessionLog, isEmpty);
  });

  // ─── Property 1: currentUser is set on success, null on failure ───────────

  test('currentUser is populated after successful auth', () {
    final store = SecurityStore();
    expect(store.currentUser, isNull);
    store.authenticate('demo', 'password');
    expect(store.currentUser, isNotNull);
    expect(store.currentUser!.clientId, equals('demo'));
  });

  test('currentUser remains null after failed auth', () {
    final store = SecurityStore();
    store.authenticate('bad', 'creds');
    expect(store.currentUser, isNull);
  });
}
