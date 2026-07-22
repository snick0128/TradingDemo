import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme.dart';
import '../../utils/responsive.dart';
import '../../widgets/tk_logo.dart';
import 'section.dart';

class _FooterLink {
  final String label;
  final String path;
  const _FooterLink(this.label, this.path);
}

const _companyLinks = [
  _FooterLink('About Us', '/about'),
  _FooterLink('Careers (Coming Soon)', '/about'),
  _FooterLink('Contact Us', '/contact'),
];

const _supportLinks = [
  _FooterLink('FAQ', '/faq'),
  _FooterLink('Contact Support', '/contact'),
  _FooterLink('Pricing', '/pricing'),
];

const _legalLinks = [
  _FooterLink('Privacy Policy', '/legal/privacy-policy'),
  _FooterLink('Terms & Conditions', '/legal/terms-conditions'),
  _FooterLink('Refund Policy', '/legal/refund-policy'),
  _FooterLink('Cancellation Policy', '/legal/cancellation-policy'),
  _FooterLink('Shipping & Delivery Policy', '/legal/shipping-delivery'),
  _FooterLink('Disclaimer', '/legal/disclaimer'),
  _FooterLink('Risk Disclosure', '/legal/risk-disclosure'),
  _FooterLink('Cookie Policy', '/legal/cookie-policy'),
];

class MarketingFooter extends StatelessWidget {
  const MarketingFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = layoutForWidth(width) == AppLayoutBreakpoint.mobile;

    return Container(
      width: double.infinity,
      color: const Color(0xFF0D1526),
      child: Column(
        children: [
          Section(
            background: const Color(0xFF0D1526),
            verticalPadding: const EdgeInsets.symmetric(vertical: 56),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _brandBlock(),
                      const SizedBox(height: 36),
                      _linkColumn('Company', _companyLinks),
                      const SizedBox(height: 28),
                      _linkColumn('Support', _supportLinks),
                      const SizedBox(height: 28),
                      _linkColumn('Legal', _legalLinks),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: _brandBlock()),
                      Expanded(child: _linkColumn('Company', _companyLinks)),
                      Expanded(child: _linkColumn('Support', _supportLinks)),
                      Expanded(flex: 2, child: _linkColumn('Legal', _legalLinks)),
                    ],
                  ),
          ),
          const Divider(color: Color(0xFF1E2A42), height: 1),
          Section(
            background: const Color(0xFF0D1526),
            verticalPadding: const EdgeInsets.symmetric(vertical: 20),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _copyrightText(),
                      const SizedBox(height: 12),
                      _socialRow(),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [_copyrightText(), _socialRow()],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _brandBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            TkLogo(size: 32),
            SizedBox(width: 10),
            Text(
              'Trade Kosh',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Trade Kosh is a paper trading and stock market education platform. '
          'Practice trading with virtual money in a realistic market simulation '
          'and learn through structured courses — no real money, no brokerage, '
          'no investment advice.',
          style: TextStyle(color: Color(0xFF9AA7BD), fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'Simulated trading only — not a broker or investment advisor',
            style: TextStyle(
              color: Color(0xFF7FA8FF),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _linkColumn(String title, List<_FooterLink> links) {
    return Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 16),
          ...links.map(
            (link) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () => context.go(link.path),
                child: Text(
                  link.label,
                  style: const TextStyle(
                    color: Color(0xFF9AA7BD),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _copyrightText() {
    return const Text(
      '© 2026 Trade Kosh. All rights reserved.',
      style: TextStyle(color: Color(0xFF6B7A94), fontSize: 12),
    );
  }

  Widget _socialRow() {
    const icons = [
      LucideIcons.twitter,
      LucideIcons.instagram,
      LucideIcons.linkedin,
      LucideIcons.youtube,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: icons
          .map(
            (icon) => Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Icon(icon, size: 18, color: const Color(0xFF6B7A94)),
            ),
          )
          .toList(),
    );
  }
}
