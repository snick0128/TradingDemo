import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

class CustomCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const CustomCard({super.key, required this.child, this.padding, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1),
            boxShadow: AppColors.softShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

class PriceText extends StatelessWidget {
  final double price;
  final double? change;
  final bool? isChangePositive;
  final double? fontSize;

  const PriceText({
    super.key,
    required this.price,
    this.change,
    this.isChangePositive,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '₹${price.toStringAsFixed(2)}',
          style: GoogleFonts.jetBrainsMono(
            color: AppColors.textPrimary,
            fontSize: fontSize ?? 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        if (change != null)
          Text(
            '${isChangePositive! ? '+' : ''}${change!.toStringAsFixed(2)}%',
            style: TextStyle(
              color: isChangePositive! ? AppColors.success : AppColors.danger,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const StatusBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class PriceFlashWidget extends StatefulWidget {
  final double price;
  final Widget child;

  const PriceFlashWidget({super.key, required this.price, required this.child});

  @override
  State<PriceFlashWidget> createState() => _PriceFlashWidgetState();
}

class _PriceFlashWidgetState extends State<PriceFlashWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<Color?> _flashColor;
  double? _previousPrice;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _flashColor = ColorTween(
      begin: Colors.transparent,
      end: Colors.transparent,
    ).animate(_controller);
    _previousPrice = widget.price;
  }

  @override
  void didUpdateWidget(covariant PriceFlashWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _previousPrice ?? oldWidget.price;
    if (widget.price == previous) return;

    final isUp = widget.price > previous;
    _flashColor = ColorTween(
      begin: (isUp ? AppColors.success : AppColors.danger).withValues(
        alpha: 0.22,
      ),
      end: Colors.transparent,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward(from: 0);
    _previousPrice = widget.price;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _flashColor.value,
            borderRadius: BorderRadius.circular(6),
          ),
          child: child,
        );
      },
    );
  }
}
