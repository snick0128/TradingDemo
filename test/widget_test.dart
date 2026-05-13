import 'package:flutter_test/flutter_test.dart';

import 'package:box_trading_web/main.dart';

void main() {
  testWidgets('renders trading dashboard shell', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const BoxTradingApp(firebaseReady: false));
      await tester.pump();
    });

    // In firebaseReady=false mode, app shows firebase-required fallback message.
    expect(
      find.textContaining('Firebase initialization failed'),
      findsOneWidget,
    );
  });
}
