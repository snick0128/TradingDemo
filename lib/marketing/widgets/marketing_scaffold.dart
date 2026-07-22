import 'package:flutter/material.dart';

import '../seo/seo_meta.dart';
import 'marketing_footer.dart';
import 'marketing_header.dart';

/// Shared page shell for every marketing route: sticky header, scrollable
/// body, footer, and per-route SEO tag injection (title/description/OG/
/// canonical + optional JSON-LD).
class MarketingScaffold extends StatefulWidget {
  final String path;
  final String seoTitle;
  final String seoDescription;
  final Widget child;
  final Map<String, dynamic>? jsonLd;

  const MarketingScaffold({
    super.key,
    required this.path,
    required this.seoTitle,
    required this.seoDescription,
    required this.child,
    this.jsonLd,
  });

  @override
  State<MarketingScaffold> createState() => _MarketingScaffoldState();
}

class _MarketingScaffoldState extends State<MarketingScaffold> {
  @override
  void initState() {
    super.initState();
    SeoMeta.set(
      title: widget.seoTitle,
      description: widget.seoDescription,
      path: widget.path,
    );
    if (widget.jsonLd != null) {
      SeoMeta.setJsonLd(widget.jsonLd);
    }
  }

  @override
  void dispose() {
    if (widget.jsonLd != null) {
      SeoMeta.setJsonLd(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: MarketingHeader(currentPath: widget.path),
      body: SingleChildScrollView(
        child: Column(
          children: [widget.child, const MarketingFooter()],
        ),
      ),
    );
  }
}
