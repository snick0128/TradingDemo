/// Property 6: Responsive layout matches screen width breakpoint
/// Validates: Requirements 4.8, 4.9, 4.10, 29.1, 29.2, 29.3
library;

import 'package:box_trading_web/utils/responsive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Property 6: Responsive breakpoint classification', () {
    test('all widths below 760 map to mobile', () {
      for (double width = 1; width < 760; width += 13) {
        expect(layoutForWidth(width), AppLayoutBreakpoint.mobile);
      }
    });

    test('all widths in [760, 1150) map to tablet', () {
      for (double width = 760; width < 1150; width += 17) {
        expect(layoutForWidth(width), AppLayoutBreakpoint.tablet);
      }
    });

    test('all widths >= 1150 map to desktop', () {
      for (double width = 1150; width <= 3000; width += 41) {
        expect(layoutForWidth(width), AppLayoutBreakpoint.desktop);
      }
    });

    test('boundary values are classified correctly', () {
      expect(layoutForWidth(759.99), AppLayoutBreakpoint.mobile);
      expect(layoutForWidth(760), AppLayoutBreakpoint.tablet);
      expect(layoutForWidth(1149.99), AppLayoutBreakpoint.tablet);
      expect(layoutForWidth(1150), AppLayoutBreakpoint.desktop);
    });
  });
}
