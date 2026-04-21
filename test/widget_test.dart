import 'package:flutter_test/flutter_test.dart';

import 'package:box_trading_web/main.dart';

void main() {
  testWidgets('renders trading dashboard shell', (WidgetTester tester) async {
    await tester.pumpWidget(const BoxTradingApp());
    await tester.pumpAndSettle();

    expect(find.text('Box Trading Pro'), findsOneWidget);
    expect(find.text('Market Watch'), findsOneWidget);
  });
}
