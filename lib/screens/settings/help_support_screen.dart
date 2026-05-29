// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../state/trading_scope.dart';
import '../../theme.dart';
import '../../widgets/shared_widgets.dart';

class _FaqItem {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});
}

const _faqs = [
  _FaqItem(
    question: 'How do I place a market order?',
    answer:
        'Tap on any stock in your watchlist, then tap BUY or SELL. Select "Market" as the order variety and enter the quantity. Tap the submit button to place the order.',
  ),
  _FaqItem(
    question: 'What is the difference between CNC and Intraday?',
    answer:
        'CNC (Cash and Carry) is for delivery-based equity trades held overnight. Intraday trades are automatically squared off before market close if not exited manually.',
  ),
  _FaqItem(
    question: 'How do I add funds to my account?',
    answer:
        'Go to Wallet → Add Funds. You can add funds via UPI, Net Banking, or NEFT/RTGS. Funds are credited instantly for UPI and Net Banking.',
  ),
  _FaqItem(
    question: 'What is a GTT order?',
    answer:
        'GTT (Good Till Triggered) orders remain active until the trigger price is hit. They are useful for setting buy/sell targets without monitoring the market constantly.',
  ),
  _FaqItem(
    question: 'How do I set a price alert?',
    answer:
        'Go to the Price Alerts section and tap the + button. Enter the symbol, select the alert type (Price Above/Below, % Move, Volume Spike), and set your target.',
  ),
  _FaqItem(
    question: 'What is the brokerage for F&O trades?',
    answer:
        'F&O trades are charged at ₹20 per executed order, regardless of the trade size. Additional charges like STT, exchange fees, and GST apply.',
  ),
  _FaqItem(
    question: 'What happens to my Intraday positions at end of day?',
    answer:
        'All Intraday positions will be automatically squared off before market closing if not exited manually. Intraday leveraged positions may also be exited early if losses exceed your available margin.',
  ),
];

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});
  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final Set<int> _expanded = {};

  void _openUrl(String url) {
    html.window.open(url, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final store   = TradingScope.of(context);
    final support = store.supportConfig;

    final hasWhatsapp = support.whatsappNumber.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Help & Support'),
      ),
      floatingActionButton: hasWhatsapp
          ? _WhatsAppFab(
              number:  support.whatsappNumber,
              message: support.messageTemplate.isNotEmpty
                  ? support.messageTemplate
                  : 'Hello, I need help with my Trade Kosh account.',
              openUrl: _openUrl,
            )
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('FAQ', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            CustomCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: _faqs.asMap().entries.map((e) {
                  final isExpanded = _expanded.contains(e.key);
                  return Column(
                    children: [
                      InkWell(
                        onTap: () => setState(() {
                          if (isExpanded) _expanded.remove(e.key);
                          else            _expanded.add(e.key);
                        }),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.value.question,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                              ),
                              Icon(
                                isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isExpanded)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          color: AppColors.surfaceAlt.withOpacity(0.5),
                          child: Text(
                            e.value.answer,
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
                          ),
                        ),
                      if (e.key < _faqs.length - 1) const Divider(height: 1),
                    ],
                  );
                }).toList(),
              ),
            ),

            if (support.enabled) ...[
              const SizedBox(height: 24),
              Text('Contact Us', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              CustomCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (support.whatsappNumber.isNotEmpty)
                      _contactTile(
                        icon: LucideIcons.messageCircle,
                        title: 'WhatsApp Support',
                        subtitle: '+${support.whatsappNumber}',
                        onTap: () => _openUrl(
                          'https://wa.me/${support.whatsappNumber}'
                          '?text=${Uri.encodeComponent(support.messageTemplate)}',
                        ),
                      ),
                    if (support.whatsappNumber.isNotEmpty && support.phoneNumber.isNotEmpty)
                      const Divider(height: 1),
                    if (support.phoneNumber.isNotEmpty)
                      _contactTile(
                        icon: LucideIcons.phone,
                        title: 'Phone Support',
                        subtitle: support.phoneNumber,
                        onTap: () => _openUrl('tel:${support.phoneNumber}'),
                      ),
                    if (support.phoneNumber.isNotEmpty && support.email.isNotEmpty)
                      const Divider(height: 1),
                    if (support.email.isNotEmpty)
                      _contactTile(
                        icon: LucideIcons.mail,
                        title: 'Email Support',
                        subtitle: support.email,
                        onTap: () => _openUrl('mailto:${support.email}'),
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.25)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.info, size: 16, color: AppColors.warning),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Intraday leveraged positions may be automatically squared off if losses exceed available margin. '
                      'Positions using leverage are subject to RMS auto square-off on margin exhaustion.',
                      style: TextStyle(fontSize: 12, color: AppColors.warning, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 20),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
      onTap: onTap,
    );
  }
}

// ─── Floating WhatsApp Button ─────────────────────────────────────────────────

class _WhatsAppFab extends StatefulWidget {
  final String number;
  final String message;
  final void Function(String) openUrl;

  const _WhatsAppFab({
    required this.number,
    required this.message,
    required this.openUrl,
  });

  @override
  State<_WhatsAppFab> createState() => _WhatsAppFabState();
}

class _WhatsAppFabState extends State<_WhatsAppFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  static const _whatsappGreen = Color(0xFF25D366);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    // Delay the pop-in so it doesn't fight the page entrance animation.
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap() {
    final url =
        'https://wa.me/${widget.number}'
        '?text=${Uri.encodeComponent(widget.message)}';
    widget.openUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: FloatingActionButton.extended(
        onPressed: _onTap,
        backgroundColor: _whatsappGreen,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const _WhatsAppIcon(),
        label: const Text(
          'Chat on WhatsApp',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
  }
}

// Draws the WhatsApp speech-bubble logo using a CustomPainter so we don't need
// any image assets or third-party icon packages.
class _WhatsAppIcon extends StatelessWidget {
  const _WhatsAppIcon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(22, 22),
      painter: _WhatsAppIconPainter(),
    );
  }
}

class _WhatsAppIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width * 0.46;

    // Outer circle
    canvas.drawCircle(Offset(cx, cy), r, paint);

    // Speech-bubble tail (small triangle at bottom-left)
    final tailPath = Path()
      ..moveTo(cx - r * 0.55, cy + r * 0.70)
      ..lineTo(cx - r * 1.05, cy + r * 1.10)
      ..lineTo(cx - r * 0.15, cy + r * 0.85)
      ..close();
    canvas.drawPath(tailPath, paint);

    // Phone handset drawn in the WhatsApp green inside the white circle
    final phonePaint = Paint()
      ..color = const Color(0xFF25D366)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round;

    // A simplified phone icon path centred in the circle
    final phonePath = Path();
    final ps = size.width * 0.14; // scale unit
    final px = cx - ps * 0.6;
    final py = cy - ps * 1.0;
    phonePath
      ..moveTo(px,           py + ps * 0.4)
      ..quadraticBezierTo(px - ps * 0.3, py, px + ps * 0.5, py - ps * 0.1)
      ..lineTo(px + ps * 1.1, py + ps * 0.6)
      ..quadraticBezierTo(px + ps * 1.4, py + ps * 0.9, px + ps * 1.0, py + ps * 1.2)
      ..lineTo(px + ps * 0.8, py + ps * 1.5)
      ..quadraticBezierTo(px + ps * 0.4, py + ps * 2.0, px + ps * 0.0, py + ps * 1.8)
      ..lineTo(px - ps * 0.5, py + ps * 1.4);
    canvas.drawPath(phonePath, phonePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
