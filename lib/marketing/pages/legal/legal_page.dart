import 'package:flutter/material.dart';

import '../../content/legal_content.dart';
import '../../widgets/legal_page_scaffold.dart';
import '../../widgets/marketing_scaffold.dart';

/// Single dynamic page for all legal documents, routed as `/legal/:slug`.
class LegalPage extends StatelessWidget {
  final String slug;
  const LegalPage({super.key, required this.slug});

  @override
  Widget build(BuildContext context) {
    final doc = legalDocs[slug];
    if (doc == null) {
      return MarketingScaffold(
        path: '/legal/$slug',
        seoTitle: 'Page Not Found — Trade Kosh',
        seoDescription: 'The legal document you requested could not be found.',
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 120),
          child: Center(child: Text('Document not found')),
        ),
      );
    }

    return MarketingScaffold(
      path: '/legal/${doc.slug}',
      seoTitle: '${doc.title} — Trade Kosh',
      seoDescription:
          '${doc.title} for Trade Kosh, a paper trading and stock market '
          'education platform.',
      child: LegalPageScaffold(doc: doc),
    );
  }
}
