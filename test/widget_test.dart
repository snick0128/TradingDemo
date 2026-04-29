import 'package:flutter_test/flutter_test.dart';

import 'package:box_trading_web/main.dart';

void main() {
  testWidgets('renders trading dashboard shell', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const BoxTradingApp());
      await tester.pump();
    });

    // The splash screen shows the app name
    expect(find.text('Trade Kosh'), findsOneWidget);
  });
}
