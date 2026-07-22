import 'package:flutter/material.dart';

import '../../utils/responsive.dart';

/// Centered, max-width, responsively-padded section container used by
/// every marketing page for consistent horizontal rhythm.
class Section extends StatelessWidget {
  final Widget child;
  final Color? background;
  final double maxWidth;
  final EdgeInsets? verticalPadding;

  const Section({
    super.key,
    required this.child,
    this.background,
    this.maxWidth = 1160,
    this.verticalPadding,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final layout = layoutForWidth(width);
    final horizontal = switch (layout) {
      AppLayoutBreakpoint.mobile => 20.0,
      AppLayoutBreakpoint.tablet => 40.0,
      AppLayoutBreakpoint.desktop => 64.0,
    };
    final vertical =
        verticalPadding ??
        EdgeInsets.symmetric(
          vertical: layout == AppLayoutBreakpoint.mobile ? 48 : 88,
        );

    return Container(
      width: double.infinity,
      color: background,
      padding: EdgeInsets.symmetric(horizontal: horizontal).add(vertical),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// Small reusable "eyebrow" label shown above section headings, e.g. "FEATURES".
class SectionEyebrow extends StatelessWidget {
  final String text;
  const SectionEyebrow(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2962FF).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF2962FF).withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: Color(0xFF2962FF),
        ),
      ),
    );
  }
}

/// Standard "eyebrow + heading + subtitle" section header, centered.
class SectionHeading extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;
  final TextAlign align;

  const SectionHeading({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.align = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = layoutForWidth(width) == AppLayoutBreakpoint.mobile;

    return Column(
      crossAxisAlignment: align == TextAlign.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        SectionEyebrow(eyebrow),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: align,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: isMobile ? 26 : 34,
            height: 1.2,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              subtitle!,
              textAlign: align,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF666666),
                fontSize: 16,
                height: 1.5,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
