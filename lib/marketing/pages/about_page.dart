import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme.dart';
import '../../utils/responsive.dart';
import '../widgets/feature_card.dart';
import '../widgets/marketing_scaffold.dart';
import '../widgets/section.dart';
import '../widgets/stat_tile.dart';

const _values = [
  (LucideIcons.shieldCheck, 'Practice First', 'We believe you should be able to learn and make mistakes before any real money is on the line.'),
  (LucideIcons.eye, 'Transparency', 'We\'re upfront that this is a simulation — never a broker, advisor, or guarantee of returns.'),
  (LucideIcons.scale, 'Risk Awareness', 'Every lesson we teach is grounded in managing risk, not chasing unrealistic profits.'),
  (LucideIcons.users, 'Accessibility', 'Markets can feel intimidating. We want anyone, regardless of background, to be able to learn.'),
];

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = layoutForWidth(width) == AppLayoutBreakpoint.mobile ? 1 : 2;

    return MarketingScaffold(
      path: '/about',
      seoTitle: 'About Us — Trade Kosh',
      seoDescription:
          'Trade Kosh is a paper trading and stock market education '
          'platform built to help anyone learn the markets safely, through '
          'realistic simulation and structured courses.',
      child: Column(
        children: [
          Section(
            child: Column(
              children: [
                const SectionHeading(
                  eyebrow: 'About Us',
                  title: 'Learning the markets shouldn\'t\ncost you your savings',
                  subtitle:
                      'Trade Kosh was built on a simple idea: everyone '
                      'deserves a safe place to learn how markets actually '
                      'work — before they ever put real money at risk.',
                ),
              ],
            ),
          ),
          Section(
            background: AppColors.surface,
            maxWidth: 820,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Our Story', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                const Text(
                  'Most people\'s first experience with the stock market is '
                  'also their first time risking real money — usually '
                  'without a real understanding of order types, risk '
                  'management, or how volatile markets can be. We started '
                  'Trade Kosh to change that.\n\n'
                  'By pairing a realistic paper trading simulator — covering '
                  'Equity, Futures & Options, and MCX commodities — with '
                  'structured educational content, we give learners a place '
                  'to build real skill and confidence with virtual money, '
                  'long before they ever open a real trading account.\n\n'
                  'Trade Kosh is not a stockbroker, investment adviser, or '
                  'portfolio manager. We don\'t give stock tips or promise '
                  'returns. Our only goal is to make learning the markets '
                  'safer, more structured, and more accessible.',
                  style: TextStyle(fontSize: 14.5, height: 1.8, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Section(
            child: Column(
              children: [
                const SectionHeading(eyebrow: 'What We Believe', title: 'The values behind Trade Kosh'),
                const SizedBox(height: 48),
                GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: columns == 1 ? 1.7 : 1.4,
                  children: [
                    for (final v in _values)
                      FeatureCard(icon: v.$1, title: v.$2, description: v.$3),
                  ],
                ),
              ],
            ),
          ),
          Section(
            background: AppColors.surface,
            child: Row(
              children: const [
                Expanded(child: StatTile(value: '1,000+', label: 'Active Traders')),
                Expanded(child: StatTile(value: '500+', label: 'Educational Videos', index: 1)),
                Expanded(child: StatTile(value: '2026', label: 'Founded', index: 2)),
              ],
            ),
          ),
          Section(
            maxWidth: 820,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Careers', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'COMING SOON',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'We\'re not actively hiring yet, but we\'re growing. Check '
                  'back soon, or reach out via our Contact page if you\'d '
                  'like to be considered for future openings.',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.6),
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () => context.go('/contact'),
                  child: const Text('Get in Touch'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
