enum AppLayoutBreakpoint { mobile, tablet, desktop }

AppLayoutBreakpoint layoutForWidth(double width) {
  if (width < 760) return AppLayoutBreakpoint.mobile;
  if (width < 1150) return AppLayoutBreakpoint.tablet;
  return AppLayoutBreakpoint.desktop;
}
