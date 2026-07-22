import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme.dart';
import '../../utils/responsive.dart';
import '../content/pricing_content.dart';
import '../widgets/faq_accordion.dart';
import '../widgets/marketing_scaffold.dart';
import '../widgets/pricing_card.dart';
import '../widgets/section.dart';

typedef _ComparisonRow = (String feature, String free, String premium);

const _comparison = <_ComparisonRow>[
  ('Paper trading simulator (Equity, F&O, MCX)', 'Included', 'Included'),
  ('Virtual starting capital', '₹10,00,000', '₹10,00,000'),
  ('Portfolio resets', '1 / month', 'Unlimited'),
  ('Watchlists & order book', 'Included', 'Included'),
  ('Starter guides & videos', 'Included', 'Included'),
  ('Full course library', '—', 'Included'),
  ('Brokerage & tax-style reports', '—', 'Included'),
  ('Priority feature access', '—', 'Included'),
  ('Progress tracking', '—', 'Coming Soon'),
  ('Certificates', '—', 'Coming Soon'),
];

const _pricingFaqs = [
  FaqItemData(
    'Is this real subscription pricing?',
    'Pricing shown here is illustrative — Trade Kosh is a paper trading and '
        'education platform, not a brokerage, so these plans reflect access '
        'to simulation limits and learning content rather than trading '
        'fees or commissions.',
  ),
  FaqItemData(
    'Can I switch between Free and Premium anytime?',
    'Yes. You can upgrade to Premium whenever you like, and cancel anytime '
        '— you\'ll keep Premium access until the end of your current '
        'billing cycle.',
  ),
  FaqItemData(
    'Do you offer refunds?',
    'Yes — full refunds are available within 7 days of your initial '
        'purchase under the conditions in our Refund Policy.',
  ),
  FaqItemData(
    'Does Premium give me real trading advantages?',
    'No. Premium only unlocks more educational content, simulation limits, '
        'and analytics depth — it does not affect real-world trading in '
        'any way, since Trade Kosh does not execute real trades.',
  ),
];

class PricingPage extends StatelessWidget {
  const PricingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = layoutForWidth(width) == AppLayoutBreakpoint.mobile;

    return MarketingScaffold(
      path: '/pricing',
      seoTitle: 'Pricing — Free & Premium Plans | Trade Kosh',
      seoDescription:
          'Trade Kosh pricing: start free with full access to the paper '
          'trading simulator, or upgrade to Premium for the full course '
          'library, unlimited resets, and advanced analytics.',
      child: Column(
        children: [
          Section(
            child: Column(
              children: [
                const SectionHeading(
                  eyebrow: 'Pricing',
                  title: 'Simple, transparent pricing',
                  subtitle:
                      'Start completely free. Upgrade only if you want '
                      'deeper courses and analytics. Illustrative pricing — '
                      'Trade Kosh is an education platform, not a brokerage.',
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
              ],
            ),
          ),
          Section(
            background: AppColors.surface,
            child: Column(
              children: [
                const SectionHeading(
                  eyebrow: 'Compare Plans',
                  title: 'What\'s included in each plan',
                ),
                const SizedBox(height: 40),
                _ComparisonTable(isMobile: isMobile),
              ],
            ),
          ),
          Section(
            maxWidth: 800,
            child: Column(
              children: [
                const SectionHeading(eyebrow: 'Pricing FAQ', title: 'Billing questions, answered'),
                const SizedBox(height: 40),
                const FaqAccordion(items: _pricingFaqs),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  final bool isMobile;
  const _ComparisonTable({required this.isMobile});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: AppColors.surfaceAlt,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Expanded(flex: 3, child: SizedBox()),
                const Expanded(
                  flex: 2,
                  child: Text('Free', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Premium',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < _comparison.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.divider, width: i == 0 ? 0 : 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      _comparison[i].$1,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(flex: 2, child: _cell(_comparison[i].$2)),
                  Expanded(flex: 2, child: _cell(_comparison[i].$3)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(String value) {
    if (value == '—') {
      return const Center(child: Icon(LucideIcons.minus, size: 16, color: AppColors.textSecondary));
    }
    return Center(
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}
