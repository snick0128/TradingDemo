import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme.dart';
import '../utils/responsive.dart';

// ─── Data ─────────────────────────────────────────────────────────────────────

/// Immutable configuration for one tab in [TradingBottomNavBar].
@immutable
class TradingNavItem {
  final String label;
  final IconData icon;

  const TradingNavItem({required this.label, required this.icon});
}

/// The canonical 5-tab definition for Trade Kosh.
/// Declared as a top-level const so it is compiled into the app once.
const List<TradingNavItem> kTradingNavItems = [
  TradingNavItem(label: 'Home',      icon: LucideIcons.home),
  TradingNavItem(label: 'Markets',   icon: LucideIcons.trendingUp),
  TradingNavItem(label: 'Orders',    icon: LucideIcons.listTodo),
  TradingNavItem(label: 'Portfolio', icon: LucideIcons.pieChart),
  TradingNavItem(label: 'Profile',   icon: LucideIcons.user),
];

// ─── Controller ───────────────────────────────────────────────────────────────

/// Lightweight controller for programmatic tab switches from deep in the tree.
class TradingNavController extends ChangeNotifier {
  int _index = 0;

  int get index => _index;

  void jumpTo(int i) {
    if (i == _index) return;
    _index = i;
    notifyListeners();
  }
}

/// InheritedWidget wrapper so any descendant can read/write the controller
/// without explicit passing.
class TradingNavControllerScope extends InheritedNotifier<TradingNavController> {
  const TradingNavControllerScope({
    super.key,
    required TradingNavController controller,
    required super.child,
  }) : super(notifier: controller);

  static TradingNavController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<TradingNavControllerScope>()
        ?.notifier;
  }
}

// ─── Bar ──────────────────────────────────────────────────────────────────────

/// Floating pill-shaped bottom navigation bar for Trade Kosh.
///
/// Design system
/// ─────────────
/// • Flat surface container (AppColors.surface / surfaceDark), 1px border
/// • 28px corner radius, single subtle floating shadow (AppColors.floatingShadow)
/// • Selected tab uses a tinted primary pill (AppColors.primary at 10%)
/// • Selected icon/label use AppColors.navActive; inactive use AppColors.navInactive
///
/// Layout contract
/// ───────────────
/// • Floats [kBottomMargin] above the SafeArea bottom edge.
/// • Has [kSideMargin] horizontal margin from each screen edge.
/// • The pill container is exactly [kHeight] tall.
class TradingBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<TradingNavItem> items;

  /// Visible pill height in logical pixels.
  static const double kHeight = 56.0;

  /// Gap between pill bottom edge and SafeArea bottom edge.
  static const double kBottomMargin = 8.0;

  /// Horizontal margin from each screen edge.
  static const double kSideMargin = 18.0;

  /// Outer corner radius for the glass container.
  static const double kRadius = 28.0;

  /// Total bottom space scrollable content must reserve (height + margin).
  /// Safe-area bottom is NOT included here — [bottomInset] adds it.
  static const double kReservedHeight = kHeight + kBottomMargin;

  /// Bottom padding scrollable content must add to avoid being hidden behind
  /// the floating navigation pill. Returns 0 on desktop (NavigationRail instead).
  static double bottomInset(BuildContext context) {
    if (layoutForWidth(MediaQuery.sizeOf(context).width) ==
        AppLayoutBreakpoint.desktop) {
      return 0.0;
    }
    return kReservedHeight + MediaQuery.viewPaddingOf(context).bottom;
  }

  const TradingBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    this.items = kTradingNavItems,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(
          left: kSideMargin,
          right: kSideMargin,
          bottom: kBottomMargin,
        ),
        // Shadow lives outside ClipRRect so it is never clipped.
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kRadius),
            boxShadow: AppColors.floatingShadow,
          ),
          child: Container(
            height: kHeight,
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surface,
              borderRadius: BorderRadius.circular(kRadius),
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.border,
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kRadius - 1),
              child: LayoutBuilder(builder: (context, constraints) {
                // Slot width model:
                //   selected  = 3 units
                //   inactive  = 1.5 units each
                //   total     = 3 + 4 × 1.5 = 9 units — always fills exactly
                final unit = constraints.maxWidth / 9.0;

                return Row(
                  children: List.generate(items.length, (i) {
                    final isSelected = i == selectedIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      width: isSelected ? unit * 3.0 : unit * 1.5,
                      height: kHeight,
                      child: _NavItemSlot(
                        item: items[i],
                        isSelected: isSelected,
                        isDark: isDark,
                        onTap: () => onTap(i),
                      ),
                    );
                  }),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Item slot ────────────────────────────────────────────────────────────────

class _NavItemSlot extends StatelessWidget {
  final TradingNavItem item;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _NavItemSlot({
    required this.item,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedColor =
        isDark ? AppColors.navActiveDark : AppColors.navActive;
    final inactiveColor =
        isDark ? AppColors.navInactiveDark : AppColors.navInactive;
    final pillBg = (isDark ? AppColors.primaryOnDark : AppColors.primary)
        .withOpacity(0.10);
    final iconColor = isSelected ? selectedColor : inactiveColor;
    final labelColor = isSelected ? selectedColor : inactiveColor;

    return Semantics(
      label: item.label,
      selected: isSelected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: TradingBottomNavBar.kHeight,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: isSelected ? 12.0 : 4.0,
                vertical: 8.0,
              ),
              decoration: BoxDecoration(
                color: isSelected ? pillBg : Colors.transparent,
                borderRadius: BorderRadius.circular(20.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Icon ────────────────────────────────────────────────
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: Tween<double>(begin: 0.72, end: 1.0).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Icon(
                      item.icon,
                      key: ValueKey('${item.label}_$isSelected'),
                      size: 20.0,
                      color: iconColor,
                    ),
                  ),

                  // ── Label (slides in when selected) ─────────────────────
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.centerLeft,
                    child: isSelected
                        ? Padding(
                            padding: const EdgeInsets.only(left: 6.0),
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: GoogleFonts.inter(
                                fontSize: 12.0,
                                fontWeight: FontWeight.w600,
                                color: labelColor,
                                letterSpacing: -0.2,
                                height: 1.0,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
