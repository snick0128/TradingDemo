import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Subtle animated blurred-blob background used behind the hero section.
/// Flat/premium aesthetic: low-opacity brand-colored blobs that slowly
/// drift and pulse — no harsh shadows, consistent with AppColors.softShadow
/// being empty ("no shadows — flat premium style") elsewhere in the app.
class GradientHeroBackground extends StatelessWidget {
  final Widget child;
  const GradientHeroBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(color: const Color(0xFFFAFAFA)),
        ),
        Positioned(
          top: -120,
          right: -80,
          child: _blob(520, const Color(0xFF387ED1).withValues(alpha: 0.16))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(
                begin: 1.0,
                end: 1.12,
                duration: 6000.ms,
                curve: Curves.easeInOut,
              ),
        ),
        Positioned(
          top: 160,
          left: -140,
          child: _blob(420, const Color(0xFF1A3A6B).withValues(alpha: 0.10))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(
                begin: 1.0,
                end: 1.08,
                duration: 7000.ms,
                curve: Curves.easeInOut,
              ),
        ),
        Positioned(
          bottom: -160,
          right: 40,
          child: _blob(320, const Color(0xFF00C853).withValues(alpha: 0.08))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(
                begin: 1.0,
                end: 1.15,
                duration: 8000.ms,
                curve: Curves.easeInOut,
              ),
        ),
        child,
      ],
    );
  }

  Widget _blob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
