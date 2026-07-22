import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme.dart';
import '../../utils/responsive.dart';
import '../content/faq_content.dart';
import '../content/pricing_content.dart';
import '../content/testimonials_content.dart';
import '../widgets/faq_accordion.dart';
import '../widgets/feature_card.dart';
import '../widgets/gradient_hero_background.dart';
import '../widgets/marketing_scaffold.dart';
import '../widgets/pricing_card.dart';
import '../widgets/screenshot_mock_card.dart';
import '../widgets/section.dart';
import '../widgets/stat_tile.dart';
import '../widgets/step_card.dart';
import '../widgets/testimonial_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return MarketingScaffold(
      path: '/',
      seoTitle:
          'Trade Kosh — Paper Trading & Stock Market Education Platform',
      seoDescription:
          'Practice stock, F&O, and MCX trading risk-free with virtual '
          'money on Trade Kosh\'s realistic market simulator, and learn the '
          'markets through structured courses and guides. No real money, '
          'no brokerage — 100% educational.',
      child: Column(
        children: [
          _Hero(),
          _TrustedStats(),
          _FeaturesPreview(),
          _HowItWorks(),
          _ScreenshotsShowcase(),
          _WhyChoose(),
          _Testimonials(),
          _PricingPreview(),
          _FaqPreview(),
          _FinalCta(),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = layoutForWidth(width) == AppLayoutBreakpoint.desktop;

    return GradientHeroBackground(
      child: Section(
        verticalPadding: EdgeInsets.symmetric(vertical: isDesktop ? 96 : 56),
        child: isDesktop
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _heroCopy(context, isDesktop)),
                  const SizedBox(width: 48),
                  const Expanded(child: _HeroVisual()),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heroCopy(context, isDesktop),
                  const SizedBox(height: 40),
                  const _HeroVisual(),
                ],
              ),
      ),
    );
  }

  Widget _heroCopy(BuildContext context, bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.shieldCheck, size: 14, color: AppColors.success),
                  SizedBox(width: 6),
                  Text(
                    '100% Risk-Free Paper Trading',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            )
            .animate()
            .fadeIn(duration: 400.ms)
            .slideY(begin: 0.2, end: 0),
        const SizedBox(height: 24),
        Text(
          'Master the markets\nwithout risking a rupee.',
          style: TextStyle(
            fontSize: isDesktop ? 48 : 32,
            fontWeight: FontWeight.w800,
            height: 1.15,
            color: AppColors.textPrimary,
          ),
        ).animate().fadeIn(delay: 100.ms, duration: 500.ms).slideY(begin: 0.15, end: 0),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
                'Trade Kosh is a paper trading and stock market education '
                'platform. Practice Equity, F&O, and MCX trading with '
                'virtual money on a realistic live market simulator, and '
                'learn the skills that matter through structured courses.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              )
              .animate()
              .fadeIn(delay: 200.ms, duration: 500.ms)
              .slideY(begin: 0.15, end: 0),
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            ElevatedButton(
              onPressed: () => context.push('/app/register'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Start Paper Trading', style: TextStyle(fontSize: 15)),
                  SizedBox(width: 8),
                  Icon(LucideIcons.arrowRight, size: 17),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: () => context.go('/courses'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
                foregroundColor: AppColors.textPrimary,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.playCircle, size: 17),
                  SizedBox(width: 8),
                  Text('Watch Courses', style: TextStyle(fontSize: 15)),
                ],
              ),
            ),
          ],
        ).animate().fadeIn(delay: 300.ms, duration: 500.ms),
        const SizedBox(height: 20),
        const Text(
          'No credit card required · Free forever plan',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _HeroVisual extends StatelessWidget {
  const _HeroVisual();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Reserve margin around the card (instead of negative overlap) so the
        // floating stat pills below have empty space to sit in without
        // covering the card's own title/description text.
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 30, 0, 70),
          child: ScreenshotMockCard(
            title: 'Live Market Simulation',
            description: 'Real-time-linked candlestick charts across NSE, BSE & MCX',
            mock: const CandlestickMock(),
          ).animate().fadeIn(delay: 250.ms, duration: 600.ms).scale(
            begin: const Offset(0.95, 0.95),
            end: const Offset(1, 1),
          ),
        ),
        Positioned(
          left: 0,
          bottom: 0,
          child: _FloatingStatCard(
            icon: LucideIcons.wallet,
            label: 'Portfolio Value',
            value: '₹12,45,320',
            delta: '+3.2%',
            positive: true,
          ).animate().fadeIn(delay: 550.ms, duration: 500.ms).slideX(begin: -0.1, end: 0),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: _FloatingStatCard(
            icon: LucideIcons.trendingUp,
            label: "Today's P&L",
            value: '+₹8,240',
            delta: '+1.8%',
            positive: true,
          ).animate().fadeIn(delay: 650.ms, duration: 500.ms).slideX(begin: 0.1, end: 0),
        ),
      ],
    );
  }
}

class _FloatingStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String delta;
  final bool positive;

  const _FloatingStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.delta,
    required this.positive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                Text(
                  value,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                Text(
                  delta,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: positive ? AppColors.success : AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustedStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = layoutForWidth(width) == AppLayoutBreakpoint.mobile;

    const stats = [
      ('1,000+', 'Active Traders'),
      ('500+', 'Educational Videos'),
      ('Real-Time', 'Market Simulation'),
      ('NSE · BSE · MCX', 'Exchanges Supported'),
    ];

    return Section(
      background: AppColors.surface,
      verticalPadding: const EdgeInsets.symmetric(vertical: 40),
      child: isMobile
          ? Wrap(
              spacing: 24,
              runSpacing: 24,
              alignment: WrapAlignment.center,
              children: [
                for (int i = 0; i < stats.length; i++)
                  SizedBox(
                    width: 140,
                    child: StatTile(value: stats[i].$1, label: stats[i].$2, index: i),
                  ),
              ],
            )
          : Row(
              children: [
                for (int i = 0; i < stats.length; i++)
                  Expanded(child: StatTile(value: stats[i].$1, label: stats[i].$2, index: i)),
              ],
            ),
    );
  }
}

const _paperTradingFeatures = [
  (LucideIcons.candlestickChart, 'Realistic Order Execution', 'Live-linked prices, spreads, and margin modeling across intraday and delivery.'),
  (LucideIcons.layers, 'Futures & Options', 'Full options chain, OI build-up, and PCR analytics for F&O practice.'),
  (LucideIcons.pieChart, 'Portfolio Tracking', 'Track holdings, positions, and realised/unrealised P&L in one place.'),
  (LucideIcons.listChecks, 'Watchlists & Order Book', 'Build custom watchlists and review your full trade & order history.'),
];

const _learningFeatures = [
  (LucideIcons.graduationCap, 'Beginner to Advanced', 'Structured lessons covering technical analysis, price action, and options.'),
  (LucideIcons.brain, 'Risk Management & Psychology', 'Learn position sizing, discipline, and the mindset behind consistent trading.'),
  (LucideIcons.video, 'Video Lessons & Guides', 'Bite-sized video guides you can learn from at your own pace.'),
  (LucideIcons.award, 'Progress Tracking & Certificates', 'Track what you\'ve learned, with certificates on the way.'),
];

class _FeaturesPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = layoutForWidth(width) == AppLayoutBreakpoint.mobile ? 1 : 2;

    return Section(
      child: Column(
        children: [
          const SectionHeading(
            eyebrow: 'Features',
            title: 'Everything you need to learn and practice',
            subtitle:
                'A realistic paper trading engine paired with a structured '
                'learning path — built to take you from your first trade to '
                'a disciplined strategy.',
          ),
          const SizedBox(height: 48),
          Text(
            'Paper Trading',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _grid(_paperTradingFeatures, columns),
          const SizedBox(height: 40),
          Text(
            'Learning Platform',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _grid(_learningFeatures, columns, comingSoonIndexes: const {3}),
          const SizedBox(height: 36),
          TextButton(
            onPressed: () => context.go('/features'),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('View all features', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(width: 6),
                Icon(LucideIcons.arrowRight, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(
    List<(IconData, String, String)> items,
    int columns, {
    Set<int> comingSoonIndexes = const {},
  }) {
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: columns == 1 ? 1.6 : 1.35,
      children: [
        for (int i = 0; i < items.length; i++)
          FeatureCard(
            icon: items[i].$1,
            title: items[i].$2,
            description: items[i].$3,
            comingSoon: comingSoonIndexes.contains(i),
          ),
      ],
    );
  }
}

const _steps = [
  (LucideIcons.userPlus, 'Create your account', 'Sign up free in under a minute — no Demat account or documents needed.'),
  (LucideIcons.bookOpen, 'Watch educational content', 'Learn market basics, technical analysis, and risk management at your pace.'),
  (LucideIcons.candlestickChart, 'Practice with paper trading', 'Apply what you learned in a realistic simulator using virtual money.'),
  (LucideIcons.barChart3, 'Track your performance', 'Review your P&L, win rate, and behaviour with detailed analytics.'),
  (LucideIcons.trophy, 'Become a better trader', 'Refine your strategy and discipline before ever risking real capital.'),
];

class _HowItWorks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Section(
      background: AppColors.surface,
      child: Column(
        children: [
          const SectionHeading(
            eyebrow: 'How it works',
            title: 'Five steps to trading with confidence',
          ),
          const SizedBox(height: 48),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                for (int i = 0; i < _steps.length; i++)
                  StepCard(
                    step: i + 1,
                    icon: _steps[i].$1,
                    title: _steps[i].$2,
                    description: _steps[i].$3,
                    isLast: i == _steps.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenshotsShowcase extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = switch (layoutForWidth(width)) {
      AppLayoutBreakpoint.mobile => 1,
      AppLayoutBreakpoint.tablet => 2,
      AppLayoutBreakpoint.desktop => 3,
    };

    final cards = [
      const ScreenshotMockCard(
        title: 'Dashboard',
        description: 'Your portfolio, market snapshot, and P&L at a glance.',
        mock: CandlestickMock(),
      ),
      const ScreenshotMockCard(
        title: 'Portfolio',
        description: 'Holdings and positions with live simulated P&L.',
        mock: PortfolioMock(),
      ),
      const ScreenshotMockCard(
        title: 'Advanced Charts',
        description: 'Technical charting to plan and review every trade.',
        mock: CandlestickMock(),
      ),
      const ScreenshotMockCard(
        title: 'Order Book',
        description: 'Track pending, executed, and cancelled orders.',
        mock: OrderBookMock(),
      ),
      const ScreenshotMockCard(
        title: 'Learning',
        description: 'Guided lessons with progress tracking.',
        mock: LearningMock(),
      ),
      const ScreenshotMockCard(
        title: 'Leaderboard',
        description: 'Compare simulated performance with the community.',
        mock: LeaderboardMock(),
        comingSoon: true,
      ),
    ];

    return Section(
      child: Column(
        children: [
          const SectionHeading(
            eyebrow: 'Platform',
            title: 'A closer look at Trade Kosh',
            subtitle: 'Illustrative previews of the Trade Kosh experience.',
          ),
          const SizedBox(height: 48),
          GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 20,
            crossAxisSpacing: 20,
            childAspectRatio: 0.92,
            children: cards,
          ),
        ],
      ),
    );
  }
}

const _whyChoose = [
  (LucideIcons.shieldCheck, 'Practice without financial risk', 'Make mistakes and learn from them without ever risking real capital.'),
  (LucideIcons.globe2, 'Real market environment', 'Live-linked data across NSE, BSE, and MCX for an authentic experience.'),
  (LucideIcons.bookMarked, 'Learn while trading', 'Education and practice live in one place, reinforcing each other.'),
  (LucideIcons.barChart4, 'Detailed analytics', 'Go beyond P&L with brokerage, tax, and behavioural insights.'),
  (LucideIcons.lineChart, 'Performance insights', 'Understand your strengths and blind spots as a trader over time.'),
  (LucideIcons.infinity, 'Practice as much as you want', 'Reset your virtual portfolio and try new strategies without limits.'),
];

class _WhyChoose extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = layoutForWidth(width) == AppLayoutBreakpoint.mobile ? 1 : (layoutForWidth(width) == AppLayoutBreakpoint.tablet ? 2 : 3);

    return Section(
      background: AppColors.surface,
      child: Column(
        children: [
          const SectionHeading(
            eyebrow: 'Why Trade Kosh',
            title: 'A better way to learn the markets',
            subtitle:
                'Traditional courses teach theory. Trade Kosh lets you '
                'apply it immediately in a realistic, risk-free environment.',
          ),
          const SizedBox(height: 48),
          GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.5,
            children: [
              for (final f in _whyChoose)
                FeatureCard(icon: f.$1, title: f.$2, description: f.$3),
            ],
          ),
        ],
      ),
    );
  }
}

class _Testimonials extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Section(
      child: Column(
        children: [
          const SectionHeading(
            eyebrow: 'Testimonials',
            title: 'Trusted by learners across India',
          ),
          const SizedBox(height: 40),
          SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: testimonials.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, i) {
                final t = testimonials[i];
                return TestimonialCard(
                  quote: t.quote,
                  name: t.name,
                  role: t.role,
                  initials: t.initials,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = layoutForWidth(width) == AppLayoutBreakpoint.mobile;

    return Section(
      background: AppColors.surface,
      child: Column(
        children: [
          const SectionHeading(
            eyebrow: 'Pricing',
            title: 'Simple, transparent pricing',
            subtitle: 'Start free. Upgrade only if you want more.',
          ),
          const SizedBox(height: 48),
          isMobile
              ? Column(
                  children: [
                    for (final p in pricingPlans) ...[
                      PricingCard(
                        planName: p.name,
                        price: p.price,
                        period: p.period,
                        description: p.description,
                        features: p.features,
                        ctaLabel: p.ctaLabel,
                        highlighted: p.highlighted,
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                )
              : IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final p in pricingPlans) ...[
                        Expanded(
                          child: PricingCard(
                            planName: p.name,
                            price: p.price,
                            period: p.period,
                            description: p.description,
                            features: p.features,
                            ctaLabel: p.ctaLabel,
                            highlighted: p.highlighted,
                          ),
                        ),
                        if (p != pricingPlans.last) const SizedBox(width: 24),
                      ],
                    ],
                  ),
                ),
          const SizedBox(height: 32),
          TextButton(
            onPressed: () => context.go('/pricing'),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('View full pricing details', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(width: 6),
                Icon(LucideIcons.arrowRight, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Section(
      maxWidth: 800,
      child: Column(
        children: [
          const SectionHeading(
            eyebrow: 'FAQ',
            title: 'Frequently asked questions',
          ),
          const SizedBox(height: 40),
          FaqAccordion(items: faqItems.take(5).toList()),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => context.go('/faq'),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('View all FAQs', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(width: 6),
                Icon(LucideIcons.arrowRight, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FinalCta extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A3A6B), Color(0xFF387ED1)],
        ),
      ),
      child: Section(
        background: Colors.transparent,
        child: Column(
          children: [
            const Text(
              'Join thousands of traders learning the smart way.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Create your free Trade Kosh account and start practicing '
              'today — no real money, no risk, no commitment.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Color(0xFFD6E2F5)),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => context.push('/app/register'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
              ),
              child: const Text('Start Paper Trading — It\'s Free', style: TextStyle(fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}
