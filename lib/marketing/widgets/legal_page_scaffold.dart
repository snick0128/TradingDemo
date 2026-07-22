import 'package:flutter/material.dart';

import '../../theme.dart';
import '../content/legal_content.dart';
import 'section.dart';

/// Generic renderer for all 8 legal documents — avoids near-duplicate page
/// files by driving layout entirely from LegalDoc data.
class LegalPageScaffold extends StatelessWidget {
  final LegalDoc doc;
  const LegalPageScaffold({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    return Section(
      maxWidth: 820,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            doc.title,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Last updated: ${doc.lastUpdated}',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 32),
          for (final section in doc.sections) ...[
            Text(
              section.heading,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              section.body,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.7,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
          ],
        ],
      ),
    );
  }
}
