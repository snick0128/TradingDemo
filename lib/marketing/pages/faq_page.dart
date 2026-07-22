import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import '../content/faq_content.dart';
import '../widgets/faq_accordion.dart';
import '../widgets/marketing_scaffold.dart';
import '../widgets/section.dart';

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MarketingScaffold(
      path: '/faq',
      seoTitle: 'Frequently Asked Questions — Trade Kosh',
      seoDescription:
          'Answers to common questions about Trade Kosh\'s paper trading '
          'simulator, courses, pricing, and how our education platform '
          'works.',
      jsonLd: {
        '@context': 'https://schema.org',
        '@type': 'FAQPage',
        'mainEntity': [
          for (final item in faqItems)
            {
              '@type': 'Question',
              'name': item.question,
              'acceptedAnswer': {'@type': 'Answer', 'text': item.answer},
            },
        ],
      },
      child: Column(
        children: [
          Section(
            maxWidth: 800,
            child: Column(
              children: [
                const SectionHeading(
                  eyebrow: 'FAQ',
                  title: 'Frequently asked questions',
                  subtitle:
                      'Can\'t find what you\'re looking for? Reach out on '
                      'our Contact page.',
                ),
                const SizedBox(height: 40),
                FaqAccordion(items: faqItems),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppColors.cardRadius),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Still have questions?',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Our support team is happy to help.',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => context.go('/contact'),
                        child: const Text('Contact Support'),
                      ),
                    ],
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
