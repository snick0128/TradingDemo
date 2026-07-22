import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme.dart';
import '../../utils/responsive.dart';
import '../widgets/feature_card.dart';
import '../widgets/marketing_scaffold.dart';
import '../widgets/section.dart';

typedef _FeatureItem = (IconData icon, String title, String description, bool comingSoon);

const _paperTrading = <_FeatureItem>[
  (LucideIcons.wallet, 'Virtual Money', 'Start with substantial virtual capital — no real funds ever at risk.', false),
  (LucideIcons.activity, 'Live Market Simulation', 'Prices and charts linked to live/near-live market data.', false),
  (LucideIcons.gauge, 'Realistic Order Execution', 'Order matching modeled with spreads, slippage, and margin.', false),
  (LucideIcons.sunrise, 'Intraday Trading', 'Practice MIS-style intraday trades with square-off timing.', false),
  (LucideIcons.calendarClock, 'Delivery Trading', 'Hold simulated positions overnight like real equity delivery.', false),
  (LucideIcons.trendingUp, 'Futures', 'Practice index and stock futures with realistic margin & lot sizes.', false),
  (LucideIcons.layers, 'Options', 'Full options chain, strike selection, and premium pricing.', false),
  (LucideIcons.pieChart, 'Portfolio Tracking', 'Real-time simulated portfolio value, holdings, and positions.', false),
  (LucideIcons.star, 'Watchlists', 'Build and manage custom watchlists across every exchange.', false),
  (LucideIcons.listChecks, 'Order Book', 'Track pending, executed, cancelled, and rejected orders.', false),
  (LucideIcons.history, 'Trade History', 'Review every simulated trade you\'ve ever placed.', false),
  (LucideIcons.barChart3, 'P&L Analytics', 'Realised & unrealised P&L, brokerage and tax-style reports.', false),
];

const _learning = <_FeatureItem>[
  (LucideIcons.graduationCap, 'Beginner to Advanced Courses', 'A learning path that grows with you, from first-timer to advanced.', false),
  (LucideIcons.candlestickChart, 'Technical Analysis', 'Read charts, indicators, and patterns with confidence.', false),
  (LucideIcons.router, 'Price Action', 'Understand market structure without relying on lagging indicators.', false),
  (LucideIcons.layers, 'Options Strategies', 'Learn common options strategies and how risk/reward plays out.', false),
  (LucideIcons.shieldAlert, 'Risk Management', 'Position sizing, stop-losses, and capital protection fundamentals.', false),
  (LucideIcons.brain, 'Trading Psychology', 'Build the discipline and mindset consistent traders rely on.', false),
  (LucideIcons.radio, 'Live Sessions', 'Join live walkthroughs of market setups and simulator features.', true),
  (LucideIcons.video, 'Recorded Video Lessons', 'Learn at your own pace with our growing video library.', false),
  (LucideIcons.trendingUp, 'Progress Tracking', 'See what you\'ve completed and what to learn next.', true),
  (LucideIcons.award, 'Certificates', 'Earn a certificate of completion as you finish course tracks.', true),
];

class FeaturesPage extends StatelessWidget {
  const FeaturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MarketingScaffold(
      path: '/features',
      seoTitle: 'Features — Paper Trading & Learning Tools | Trade Kosh',
      seoDescription:
          'Explore Trade Kosh\'s paper trading features — Equity, F&O and '
          'MCX simulation, portfolio tracking, watchlists, P&L analytics — '
          'plus our structured learning platform covering technical '
          'analysis, options, risk management, and trading psychology.',
      child: Column(
        children: [
          const _FeaturesHero(),
          _FeatureSection(
            eyebrow: 'Paper Trading',
            title: 'A realistic simulator for every segment',
            subtitle:
                'Practice Equity, Futures, Options, and MCX trading with '
                'virtual money in an environment built to feel like the '
                'real market.',
            items: _paperTrading,
          ),
          _FeatureSection(
            eyebrow: 'Learning Platform',
            title: 'Structured education, not just theory',
            subtitle:
                'Go from market basics to advanced strategy with guided '
                'lessons designed to work hand-in-hand with the simulator.',
            items: _learning,
            background: AppColors.surface,
          ),
        ],
      ),
    );
  }
}

class _FeaturesHero extends StatelessWidget {
  const _FeaturesHero();

  @override
  Widget build(BuildContext context) {
    return const Section(
      child: SectionHeading(
        eyebrow: 'Features',
        title: 'Everything you need to learn and\npractice the markets',
        subtitle:
            'Trade Kosh combines a realistic paper trading engine with '
            'structured education — so you learn concepts and immediately '
            'put them into practice, risk-free.',
      ),
    );
  }
}

class _FeatureSection extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final List<_FeatureItem> items;
  final Color? background;

  const _FeatureSection({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.items,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = switch (layoutForWidth(width)) {
      AppLayoutBreakpoint.mobile => 1,
      AppLayoutBreakpoint.tablet => 2,
      AppLayoutBreakpoint.desktop => 3,
    };

    return Section(
      background: background,
      child: Column(
        children: [
          SectionHeading(eyebrow: eyebrow, title: title, subtitle: subtitle),
          const SizedBox(height: 48),
          GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: columns == 1 ? 1.7 : 1.3,
            children: [
              for (final item in items)
                FeatureCard(
                  icon: item.$1,
                  title: item.$2,
                  description: item.$3,
                  comingSoon: item.$4,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
