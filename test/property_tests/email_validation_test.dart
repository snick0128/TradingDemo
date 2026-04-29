/// Property 5: Email validation rejects malformed addresses
/// Validates: Requirements 2.3

import 'package:flutter_test/flutter_test.dart';

// The same regex used in RegisterScreen — tested in isolation here.
final _emailRegex = RegExp(
  r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
);

bool isValidEmail(String email) => _emailRegex.hasMatch(email.trim());

void main() {
  // ─── Property 5: Valid emails are accepted ────────────────────────────────

  group('Valid email addresses are accepted', () {
    final validEmails = [
      'user@example.com',
      'test.user@domain.co.in',
      'alice+tag@mail.org',
      'bob123@sub.domain.io',
      'USER@EXAMPLE.COM',
    ];

    for (final email in validEmails) {
      test('"$email" is valid', () {
        expect(
          isValidEmail(email),
          isTrue,
          reason: '"$email" should be a valid email',
        );
      });
    }
  });

  // ─── Property 5: Malformed emails are rejected ────────────────────────────

  group('Malformed email addresses are rejected', () {
    final invalidEmails = [
      'notanemail',
      '@nodomain',
      'missing@',
      'spaces in@email.com',
      'double@@domain.com',
      'nodot@domain',
      '',
      '@',
      'plainaddress',
    ];

    for (final email in invalidEmails) {
      test('"$email" is invalid', () {
        expect(
          isValidEmail(email),
          isFalse,
          reason: '"$email" should be rejected as invalid',
        );
      });
    }
  });
}
