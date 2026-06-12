// ignore_for_file: deprecated_member_use
import 'dart:ui';

import 'package:flutter/material.dart';
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
///
/// Usage:
///   1. Hold an instance in the root shell state.
///   2. Pass it down (or expose via InheritedWidget / Provider).
///   3. Call [jumpTo] from any descendant to change the active tab.
///
/// Example:
///   final _navCtrl = TradingNavController();
///   // In a child widget:
///   TradingNavController.of(context).jumpTo(2);
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

/// Premium floating pill-shaped bottom navigation bar for Trade Kosh.
///
/// Layout contract
/// ───────────────
/// • Floats [kBottomMargin] above the SafeArea bottom edge.
/// • Has [kSideMargin] horizontal margin from each screen edge.
/// • The pill container is exactly [kHeight] tall.
///
/// Animation model
/// ───────────────
/// The [LayoutBuilder] divides the pill into 9 equal "units" of width.
/// The selected item occupies 3 units; each inactive item occupies 1.5 units
/// (3 + 4 × 1.5 = 9 — always fills the container exactly).
///
/// An [AnimatedContainer] on each slot interpolates its allocated width when
/// [selectedIndex] changes, so the active capsule expands while all others
/// contract simultaneously in a single smooth motion.  No [TickerProvider],
/// no [AnimationController], no extra state needed — purely declarative.
///
/// Glassmorphism
/// ─────────────
/// The pill is a [BackdropFilter] blur (sigmaX/Y = 18) with a semi-transparent
/// surface background so the screen content scrolls through behind it.
/// Outside the pill the background is fully transparent — content is visible.
///
/// Theme awareness
/// ───────────────
/// All colours are read from [Theme.of(context)]:
///   • Surface  → [ColorScheme.surface] at 72 % opacity (light) / 82 % (dark)
///   • Active   → [ColorScheme.primary]
///   • Inactive → [AppColors.navInactive]   (9E9E9E — identical in light/dark)
///   • Border   → white highlight at 55 % opacity (light) / 10 % (dark)
class TradingBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<TradingNavItem> items;

  /// Visible pill height in logical pixels.
  static const double kHeight = 56.0;

  /// Gap between pill bottom edge and SafeArea bottom edge.
  static const double kBottomMargin = 14.0;

  /// Horizontal margin from each screen edge.
  static const double kSideMargin = 18.0;

  /// Total bottom space to reserve in the Scaffold
  /// (pill height + bottom margin; safe area is handled separately by SafeArea).
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
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(
          left: kSideMargin,
          right: kSideMargin,
          bottom: kBottomMargin,
        ),
        // Glass pill: ClipRRect shapes the blur, BackdropFilter frosts the
        // content behind it, Container provides the semi-transparent fill.
        // Outside the pill the widget tree is transparent — no background.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kHeight / 2),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: kHeight,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withOpacity(
                  theme.brightness == Brightness.light ? 0.72 : 0.82,
                ),
                borderRadius: BorderRadius.circular(kHeight / 2),
                border: Border.all(
                  color: theme.brightness == Brightness.light
                      ? Colors.white.withOpacity(0.55)
                      : Colors.white.withOpacity(0.10),
                  width: 1.0,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(kHeight / 2 - 0.5),
                child: LayoutBuilder(builder: (context, constraints) {
                  // Slot width model:
                  //   selected  = 3 units
                  //   inactive  = 1.5 units each
                  //   total     = 3 + 4 × 1.5 = 9 units
                  //
                  // Because the growing item gains exactly what the shrinking item
                  // loses, the sum is always constraints.maxWidth — no gaps, no
                  // overflow, no layout jank during animation.
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
      ),
    );
  }
}

// ─── Item slot ────────────────────────────────────────────────────────────────

/// Renders one navigation item inside its animated width slot.
///
/// Stateless — the only input driving appearance is [isSelected].
/// All animations are purely declarative (no AnimationController).
class _NavItemSlot extends StatelessWidget {
  final TradingNavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItemSlot({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary  = Theme.of(context).colorScheme.primary;
    // navInactive is intentionally hardcoded here — it is the same token
    // (#9E9E9E) in both the light and dark Trade Kosh themes.
    const inactive = AppColors.navInactive;

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
            // The capsule container: animates padding & background colour.
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: isSelected ? 12.0 : 4.0,
                vertical: 8.0,
              ),
              decoration: BoxDecoration(
                // Light tint of primary (#2962FF at 10% opacity) — matches
                // the existing chip/badge pattern used in Trade Kosh
                // (e.g., exchange chip: E3F2FD, selected pill: E8F5E9).
                color: isSelected
                    ? primary.withOpacity(0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Icon ──────────────────────────────────────────────
                  // AnimatedSwitcher creates a scale+fade "pop" when the
                  // active state changes, giving tactile feedback.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: Tween<double>(begin: 0.72, end: 1.0)
                          .animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Icon(
                      item.icon,
                      // Unique key per state so AnimatedSwitcher fires on toggle.
                      key: ValueKey('${item.label}_$isSelected'),
                      size: 20.0,
                      color: isSelected ? primary : inactive,
                    ),
                  ),

                  // ── Label (slides + fades in when selected) ───────────
                  // AnimatedSize collapses the width smoothly; the label
                  // widget itself is only present when selected so the
                  // content is never clipped in an odd half-visible state.
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
                              style: TextStyle(
                                fontSize: 12.0,
                                fontWeight: FontWeight.w600,
                                color: primary,
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
