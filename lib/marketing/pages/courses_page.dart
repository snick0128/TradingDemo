import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme.dart';
import '../../utils/responsive.dart';
import '../widgets/feature_card.dart';
import '../widgets/marketing_scaffold.dart';
import '../widgets/screenshot_mock_card.dart';
import '../widgets/section.dart';

class _Track {
  final String level;
  final String title;
  final String description;
  final List<String> topics;
  final IconData icon;
  const _Track(this.level, this.title, this.description, this.topics, this.icon);
}

const _tracks = [
  _Track(
    'Beginner',
    'Stock Market Foundations',
    'Start here if you\'re completely new to the markets.',
    ['What is a stock exchange', 'Reading a quote & order book', 'Placing your first paper trade', 'Understanding intraday vs delivery'],
    LucideIcons.sprout,
  ),
  _Track(
    'Intermediate',
    'Technical Analysis & Price Action',
    'Learn to read charts and market structure with confidence.',
    ['Candlestick patterns', 'Support, resistance & trends', 'Volume & momentum indicators', 'Price action without indicators'],
    LucideIcons.candlestickChart,
  ),
  _Track(
    'Advanced',
    'Options, Risk & Psychology',
    'Sharpen your edge with strategy, discipline, and risk control.',
    ['Options chain & strategies', 'Position sizing & stop-losses', 'Trading psychology & discipline', 'Building a trading plan'],
    LucideIcons.brain,
  ),
];

typedef _TopicItem = (IconData icon, String title, String description, bool comingSoon);

const _topics = <_TopicItem>[
  (LucideIcons.graduationCap, 'Beginner to Advanced', 'A learning path that grows with your skill level.', false),
  (LucideIcons.candlestickChart, 'Technical Analysis', 'Charts, indicators, and pattern recognition.', false),
  (LucideIcons.router, 'Price Action', 'Reading raw market structure and momentum.', false),
  (LucideIcons.layers, 'Options', 'Strategy fundamentals across calls, puts & spreads.', false),
  (LucideIcons.shieldAlert, 'Risk Management', 'Protecting capital before chasing returns.', false),
  (LucideIcons.brain, 'Trading Psychology', 'Discipline, bias, and emotional control.', false),
  (LucideIcons.radio, 'Live Sessions', 'Live walkthroughs of setups and simulator features.', true),
  (LucideIcons.video, 'Recorded Videos', 'A growing library of self-paced video lessons.', false),
];

class CoursesPage extends StatelessWidget {
  const CoursesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final layout = layoutForWidth(width);
    final trackColumns = layout == AppLayoutBreakpoint.mobile ? 1 : (layout == AppLayoutBreakpoint.tablet ? 2 : 3);
    final topicColumns = layout == AppLayoutBreakpoint.mobile ? 1 : (layout == AppLayoutBreakpoint.tablet ? 2 : 4);

    return MarketingScaffold(
      path: '/courses',
      seoTitle: 'Courses — Learn Stock Market Trading | Trade Kosh',
      seoDescription:
          'Learn stock market trading from beginner to advanced with '
          'Trade Kosh courses — technical analysis, price action, options, '
          'risk management, and trading psychology, through guided lessons '
          'and video content.',
      child: Column(
        children: [
          Section(
            child: Column(
              children: [
                const SectionHeading(
                  eyebrow: 'Courses',
                  title: 'Learn the markets, one track at a time',
                  subtitle:
                      'Structured lessons that pair directly with the paper '
                      'trading simulator, so you can apply every concept '
                      'immediately.',
                ),
                const SizedBox(height: 48),
                GridView.count(
                  crossAxisCount: trackColumns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  childAspectRatio: trackColumns == 1 ? 1.1 : 0.85,
                  children: _tracks.map((t) => _TrackCard(track: t)).toList(),
                ),
              ],
            ),
          ),
          Section(
            background: AppColors.surface,
            child: Column(
              children: [
                const SectionHeading(
                  eyebrow: 'What you\'ll learn',
                  title: 'Topics covered across every track',
                ),
                const SizedBox(height: 48),
                GridView.count(
                  crossAxisCount: topicColumns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: topicColumns == 1 ? 1.8 : 1.05,
                  children: [
                    for (final t in _topics)
                      FeatureCard(
                        icon: t.$1,
                        title: t.$2,
                        description: t.$3,
                        comingSoon: t.$4,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Section(
            child: Column(
              children: [
                const SectionHeading(
                  eyebrow: 'Learning Dashboard',
                  title: 'Track your learning journey',
                  subtitle:
                      'Follow your progress through each track — full '
                      'progress tracking and certificates are on our roadmap.',
                ),
                const SizedBox(height: 40),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: const ScreenshotMockCard(
                    title: 'Your Progress',
                    description: 'A snapshot of course completion across tracks.',
                    mock: LearningMock(),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: const Color(0xFF0D1526),
            child: Section(
              background: const Color(0xFF0D1526),
              verticalPadding: const EdgeInsets.symmetric(vertical: 64),
              child: Column(
                children: [
                  const Text(
                    'Start learning for free today',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Every Trade Kosh account includes starter courses and full access to the paper trading simulator.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF9AA7BD)),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: () => context.push('/app/register'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
                    child: const Text('Create Free Account'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  final _Track track;
  const _TrackCard({required this.track});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.heroRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(track.icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              track.level.toUpperCase(),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 0.4),
            ),
          ),
          const SizedBox(height: 10),
          Text(track.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(track.description, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
          const SizedBox(height: 14),
          ...track.topics.map(
            (topic) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.checkCircle2, size: 14, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(child: Text(topic, style: const TextStyle(fontSize: 12.5, height: 1.4))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
