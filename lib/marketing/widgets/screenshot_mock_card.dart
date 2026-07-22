import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Stylized "browser window" frame used to showcase a mocked-up preview of
/// an in-app screen (dashboard, portfolio, charts, orders...) without
/// requiring real screenshot image assets.
class ScreenshotMockCard extends StatelessWidget {
  final String title;
  final String description;
  final Widget mock;
  final bool comingSoon;

  const ScreenshotMockCard({
    super.key,
    required this.title,
    required this.description,
    required this.mock,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.heroRadius),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: const Color(0xFFF0F1F3),
            child: Row(
              children: const [
                _Dot(Color(0xFFFF5F57)),
                SizedBox(width: 6),
                _Dot(Color(0xFFFEBC2E)),
                SizedBox(width: 6),
                _Dot(Color(0xFF28C840)),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            width: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(child: Container(color: const Color(0xFFFAFBFC), child: mock)),
                if (comingSoon)
                  Positioned.fill(
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.72),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'COMING SOON',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.warning,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.5,
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

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Mini candlestick chart mock for the Dashboard/Charts preview.
class CandlestickMock extends StatelessWidget {
  const CandlestickMock({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: CustomPaint(painter: _CandlestickPainter(), size: Size.infinite),
    );
  }
}

class _CandlestickPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    const barCount = 22;
    final barWidth = size.width / (barCount * 1.6);
    double y = size.height * 0.55;

    for (int i = 0; i < barCount; i++) {
      final open = y;
      final delta = (rnd.nextDouble() - 0.45) * size.height * 0.22;
      final close = (open + delta).clamp(size.height * 0.1, size.height * 0.9);
      final high = math.min(open, close) - rnd.nextDouble() * size.height * 0.08;
      final low = math.max(open, close) + rnd.nextDouble() * size.height * 0.08;
      final isUp = close < open;
      final color = isUp ? AppColors.success : AppColors.danger;
      final x = i * barWidth * 1.6 + barWidth;

      final wickPaint = Paint()..color = color.withValues(alpha: 0.7)..strokeWidth = 1.4;
      canvas.drawLine(Offset(x, high), Offset(x, low), wickPaint);

      final bodyPaint = Paint()..color = color;
      final top = math.min(open, close);
      final bottom = math.max(open, close);
      canvas.drawRect(
        Rect.fromLTRB(x - barWidth / 2, top, x + barWidth / 2, math.max(bottom, top + 2)),
        bodyPaint,
      );
      y = close;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Mini portfolio holdings-list mock.
class PortfolioMock extends StatelessWidget {
  const PortfolioMock({super.key});

  static const _rows = [
    ('RELIANCE', '+2.4%', true),
    ('HDFCBANK', '-0.8%', false),
    ('TCS', '+1.1%', true),
    ('INFY', '+0.3%', true),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: _rows
            .map(
              (r) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.$1,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      r.$2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: r.$3 ? AppColors.success : AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

/// Mini order-book mock.
class OrderBookMock extends StatelessWidget {
  const OrderBookMock({super.key});

  static const _rows = [
    ('NIFTY 24800 CE', 'BUY', 'EXECUTED'),
    ('BANKNIFTY FUT', 'SELL', 'PENDING'),
    ('SBIN', 'BUY', 'EXECUTED'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: _rows
            .map(
              (r) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (r.$2 == 'BUY' ? AppColors.success : AppColors.danger)
                            .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        r.$2,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: r.$2 == 'BUY' ? AppColors.success : AppColors.danger,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(r.$1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    Text(
                      r.$3,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

/// Mini learning-progress mock.
class LearningMock extends StatelessWidget {
  const LearningMock({super.key});

  static const _rows = [
    ('Basics of the Stock Market', 1.0),
    ('Technical Analysis 101', 0.6),
    ('Options Trading Fundamentals', 0.25),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _rows
            .map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.$1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: r.$2,
                        minHeight: 6,
                        backgroundColor: AppColors.border,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

/// Mini leaderboard mock (feature not yet live — shown with COMING SOON overlay).
class LeaderboardMock extends StatelessWidget {
  const LeaderboardMock({super.key});

  static const _rows = [
    ('1', 'Trader_Amit', '+18.4%'),
    ('2', 'Priya.Trades', '+15.1%'),
    ('3', 'RahulK', '+12.7%'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: _rows
            .map(
              (r) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Text('#${r.$1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(r.$2, style: const TextStyle(fontSize: 12))),
                    Text(r.$3, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
