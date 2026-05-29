import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme.dart';

/// Trade Kosh centralized logo widget.
///
/// This is the SINGLE SOURCE OF TRUTH for the Trade Kosh brand mark.
/// Every screen — splash, login, register, PIN setup, about, drawer,
/// header — uses this widget. To apply the final logo asset, update
/// only this file.
///
/// Usage:
///   TkLogo()              — icon on a blue gradient rounded-rect badge (72 px)
///   TkLogo(size: 48)      — same badge at any size
///   TkLogo.flat(size: 28) — bare white icon, no container (for use inside
///                           your own coloured Container)
///
/// Replacing the icon with the real PNG logo:
///   1. Save the logo as web/icons/tradekosh_logo.png
///   2. Add to pubspec.yaml assets: [web/icons/tradekosh_logo.png]
///   3. Swap the Icon() in _buildContent() for:
///        Image.asset('web/icons/tradekosh_logo.png',
///          width: iconSize, height: iconSize, fit: BoxFit.contain)
class TkLogo extends StatelessWidget {
  /// Total badge diameter. Icon is sized proportionally inside.
  final double size;

  /// When true, renders only the icon (white) with no surrounding container.
  /// Set this when the container is already coloured by the caller.
  final bool flat;

  const TkLogo({super.key, this.size = 72}) : flat = false;

  /// Bare white icon for embedding inside an already-coloured container.
  const TkLogo.flat({super.key, this.size = 28}) : flat = true;

  static const _brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A3A6B), Color(0xFF387ED1)],
  );

  /// Path to the Trade Kosh logo asset.
  /// Drop your PNG into assets/images/ and set this path.
  static const _logoAsset = 'assets/images/logo.png';

  Widget _buildIcon(double iconSize) {
    // Switch to Image.asset once assets/images/logo.png exists.
    // The AssetImage lookup is guarded — falls back to the icon if not found.
    return Image.asset(
      _logoAsset,
      width: iconSize,
      height: iconSize,
      fit: BoxFit.contain,
      color: flat ? Colors.white : null,       // tint white when on coloured bg
      colorBlendMode: flat ? BlendMode.srcIn : null,
      errorBuilder: (_, __, ___) => Icon(
        LucideIcons.candlestickChart,
        size: iconSize,
        color: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (flat) {
      return _buildIcon(size);
    }

    final radius = (size * 0.27).clamp(8.0, 24.0);
    final iconSize = size * 0.50;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: _brandGradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: size * 0.30,
            offset: Offset(0, size * 0.10),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: _buildIcon(iconSize),
    );
  }
}
