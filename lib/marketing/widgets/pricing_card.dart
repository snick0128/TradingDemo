import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme.dart';

class PricingCard extends StatelessWidget {
  final String planName;
  final String price;
  final String period;
  final String description;
  final List<String> features;
  final bool highlighted;
  final String ctaLabel;

  const PricingCard({
    super.key,
    required this.planName,
    required this.price,
    required this.period,
    required this.description,
    required this.features,
    required this.ctaLabel,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.textPrimary : AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.heroRadius),
        border: Border.all(
          color: highlighted ? AppColors.textPrimary : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (highlighted)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'MOST POPULAR',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          Text(
            planName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: highlighted ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: highlighted ? const Color(0xFFB0B8C4) : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: highlighted ? Colors.white : AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  period,
                  style: TextStyle(
                    fontSize: 13,
                    color: highlighted ? const Color(0xFFB0B8C4) : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: highlighted
                ? ElevatedButton(
                    onPressed: () => context.push('/app/register'),
                    child: Text(ctaLabel),
                  )
                : OutlinedButton(
                    onPressed: () => context.push('/app/register'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                    ),
                    child: Text(ctaLabel),
                  ),
          ),
          const SizedBox(height: 24),
          ...features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.checkCircle2,
                    size: 17,
                    color: highlighted ? AppColors.success : AppColors.success,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      f,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: highlighted ? const Color(0xFFE0E4EA) : AppColors.textPrimary,
                      ),
                    ),
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
