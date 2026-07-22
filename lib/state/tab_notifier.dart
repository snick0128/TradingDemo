import 'package:flutter/material.dart';

/// Broadcasts the active [IndexedStack] tab index (0–4) from [MainShell].
///
/// Tab screens subscribe to this notifier to gate [setState] calls behind a
/// visibility check, preventing hidden-tab rebuilds from market ticks.
///
///   0 = Dashboard   1 = MarketWatch   2 = Orders   3 = Portfolio   4 = Profile
final ValueNotifier<int> activeTabNotifier = ValueNotifier<int>(0);
