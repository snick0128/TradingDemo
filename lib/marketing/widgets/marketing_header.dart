import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import '../../utils/responsive.dart';
import '../../widgets/tk_logo.dart';

class _NavLink {
  final String label;
  final String path;
  const _NavLink(this.label, this.path);
}

const _navLinks = [
  _NavLink('Home', '/'),
  _NavLink('Features', '/features'),
  _NavLink('Courses', '/courses'),
  _NavLink('Pricing', '/pricing'),
  _NavLink('About', '/about'),
  _NavLink('FAQ', '/faq'),
  _NavLink('Contact', '/contact'),
];

/// Sticky marketing site navigation header. Reuses TkLogo (the app's single
/// source-of-truth brand mark) and AppColors so it's visually identical to
/// the in-app header/AppBar chrome.
class MarketingHeader extends StatelessWidget implements PreferredSizeWidget {
  final String currentPath;

  const MarketingHeader({super.key, required this.currentPath});

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = layoutForWidth(width) == AppLayoutBreakpoint.desktop;

    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 20),
          InkWell(
            onTap: () => context.go('/'),
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TkLogo(size: 36),
                  SizedBox(width: 10),
                  Text(
                    'Trade Kosh',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          if (isDesktop) ..._desktopNav(context) else _mobileMenuButton(context),
          const SizedBox(width: 20),
        ],
      ),
    );
  }

  List<Widget> _desktopNav(BuildContext context) {
    return [
      ..._navLinks.map((link) {
        final active = currentPath == link.path;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: InkWell(
            onTap: () => context.go(link.path),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(
                link.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        );
      }),
      const SizedBox(width: 12),
      TextButton(
        onPressed: () => context.push('/app/login'),
        child: const Text(
          'Login',
          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
      ),
      const SizedBox(width: 8),
      ElevatedButton(
        onPressed: () => context.push('/app/register'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        child: const Text('Start Free'),
      ),
    ];
  }

  Widget _mobileMenuButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
      onPressed: () => _openMobileMenu(context),
    );
  }

  void _openMobileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ..._navLinks.map(
                  (link) => ListTile(
                    title: Text(
                      link.label,
                      style: TextStyle(
                        fontWeight: currentPath == link.path
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: currentPath == link.path
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      context.go(link.path);
                    },
                  ),
                ),
                const Divider(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            context.push('/app/login');
                          },
                          child: const Text('Login'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            context.push('/app/register');
                          },
                          child: const Text('Start Free'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
