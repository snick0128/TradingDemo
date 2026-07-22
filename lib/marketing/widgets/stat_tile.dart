import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme.dart';

class StatTile extends StatelessWidget {
  final String value;
  final String label;
  final int index;

  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ).animate().fadeIn(delay: (index * 120).ms, duration: 400.ms).slideY(
      begin: 0.2,
      end: 0,
    );
  }
}
