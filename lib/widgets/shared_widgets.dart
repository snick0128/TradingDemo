import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

// ─── Shimmer Loading Widget ───────────────────────────────────────────────────

class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = Tween<double>(
      begin: -2,
      end: 2,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value + 1, 0),
            colors: const [
              Color(0xFFEEEEEE),
              Color(0xFFF5F5F5),
              Color(0xFFEEEEEE),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shimmer row for list loading states
class ShimmerListTile extends StatelessWidget {
  const ShimmerListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const ShimmerBox(width: 40, height: 40, borderRadius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerBox(width: 120, height: 14),
                SizedBox(height: 6),
                ShimmerBox(width: 80, height: 11),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ShimmerBox(width: 70, height: 14),
              SizedBox(height: 6),
              ShimmerBox(width: 50, height: 11),
            ],
          ),
        ],
      ),
    );
  }
}

/// Synchronized shimmer wrapper — ONE controller for all children.
/// Wrap entire loading sections with this to keep all bones in sync.
class ShimmerWrapper extends StatefulWidget {
  final Widget child;
  const ShimmerWrapper({super.key, required this.child});

  @override
  State<ShimmerWrapper> createState() => _ShimmerWrapperState();
}

class _ShimmerWrapperState extends State<ShimmerWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ShimmerScope(
      controller: _ctrl,
      child: widget.child,
    );
  }
}

class _ShimmerScope extends InheritedWidget {
  final AnimationController controller;
  const _ShimmerScope({required this.controller, required super.child});
  static _ShimmerScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShimmerScope>();
  @override
  bool updateShouldNotify(_ShimmerScope old) => false;
}

/// Drop-in replacement for ShimmerBox that uses ShimmerWrapper's
/// shared controller when available, or falls back to its own.
class ShimmerRect extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerRect({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final scope = _ShimmerScope.of(context);
    if (scope != null) {
      return AnimatedBuilder(
        animation: scope.controller,
        builder: (_, __) => _shimmerContainer(
          scope.controller.value,
          width,
          height,
          borderRadius,
        ),
      );
    }
    // Standalone fallback
    return ShimmerBox(width: width, height: height, borderRadius: borderRadius);
  }

  static Widget _shimmerContainer(
      double t, double w, double h, double br) {
    final pos = t * 4 - 2;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(br),
        gradient: LinearGradient(
          begin: Alignment(pos - 1, 0),
          end: Alignment(pos + 1, 0),
          colors: const [
            Color(0xFFEEEEEE),
            Color(0xFFF5F5F5),
            Color(0xFFFFFFFF),
            Color(0xFFF5F5F5),
            Color(0xFFEEEEEE),
          ],
          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        ),
      ),
    );
  }
}

// ─── Screen-specific skeleton layouts ─────────────────────────────────────────

/// Skeleton for a single order row
class ShimmerOrderTile extends StatelessWidget {
  const ShimmerOrderTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              ShimmerBox(width: 90, height: 13),
              SizedBox(height: 5),
              ShimmerBox(width: 60, height: 11),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              ShimmerBox(width: 70, height: 13),
              SizedBox(height: 5),
              ShimmerBox(width: 50, height: 11),
            ],
          ),
          const SizedBox(width: 12),
          const ShimmerBox(width: 64, height: 28, borderRadius: 6),
        ],
      ),
    );
  }
}

/// Skeleton for a position row (with P&L column)
class ShimmerPositionTile extends StatelessWidget {
  const ShimmerPositionTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerBox(width: 100, height: 13),
                SizedBox(height: 5),
                ShimmerBox(width: 70, height: 11),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                ShimmerBox(width: 60, height: 13),
                SizedBox(height: 5),
                ShimmerBox(width: 44, height: 11),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                ShimmerBox(width: 60, height: 13),
                SizedBox(height: 5),
                ShimmerBox(width: 44, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for a holding row
class ShimmerHoldingTile extends StatelessWidget {
  const ShimmerHoldingTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerBox(width: 110, height: 13),
                SizedBox(height: 5),
                ShimmerBox(width: 80, height: 11),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                ShimmerBox(width: 70, height: 13),
                SizedBox(height: 5),
                ShimmerBox(width: 50, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Summary strip skeleton (3 stat tiles in a row)
class ShimmerSummaryStrip extends StatelessWidget {
  final int count;
  const ShimmerSummaryStrip({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: AppColors.surface,
      child: Row(
        children: List.generate(count, (i) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < count - 1 ? 20 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerBox(width: 50, height: 11),
                SizedBox(height: 6),
                ShimmerBox(width: 80, height: 16),
              ],
            ),
          ),
        )),
      ),
    );
  }
}

/// Card-style shimmer (for IPO cards, F&O cards, etc.)
class ShimmerCard extends StatelessWidget {
  final double height;
  const ShimmerCard({super.key, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              ShimmerBox(width: 36, height: 36, borderRadius: 18),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 140, height: 14),
                    SizedBox(height: 5),
                    ShimmerBox(width: 90, height: 11),
                  ],
                ),
              ),
              ShimmerBox(width: 60, height: 24, borderRadius: 6),
            ],
          ),
          const Spacer(),
          Row(
            children: const [
              ShimmerBox(width: 80, height: 11),
              SizedBox(width: 16),
              ShimmerBox(width: 80, height: 11),
              SizedBox(width: 16),
              ShimmerBox(width: 80, height: 11),
            ],
          ),
        ],
      ),
    );
  }
}

/// Options chain row skeleton
class ShimmerOptionRow extends StatelessWidget {
  const ShimmerOptionRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: const [
          Expanded(child: ShimmerBox(width: double.infinity, height: 13)),
          SizedBox(width: 8),
          Expanded(child: ShimmerBox(width: double.infinity, height: 13)),
          SizedBox(width: 8),
          ShimmerBox(width: 80, height: 20, borderRadius: 4),
          SizedBox(width: 8),
          Expanded(child: ShimmerBox(width: double.infinity, height: 13)),
          SizedBox(width: 8),
          Expanded(child: ShimmerBox(width: double.infinity, height: 13)),
        ],
      ),
    );
  }
}

/// Full dashboard loading skeleton
class ShimmerDashboard extends StatelessWidget {
  const ShimmerDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerWrapper(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Portfolio summary card
            Container(
              height: 130,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ShimmerRect(width: 100, height: 13),
                  const SizedBox(height: 10),
                  const ShimmerRect(width: 180, height: 28),
                  const Spacer(),
                  Row(
                    children: const [
                      ShimmerRect(width: 80, height: 11),
                      SizedBox(width: 16),
                      ShimmerRect(width: 60, height: 11),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Quick actions row
            Row(
              children: List.generate(4, (i) => Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 3 ? 10 : 0),
                  height: 70,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        ShimmerRect(width: 28, height: 28, borderRadius: 14),
                        SizedBox(height: 6),
                        ShimmerRect(width: 44, height: 10),
                      ],
                    ),
                  ),
                ),
              )),
            ),
            const SizedBox(height: 20),
            const ShimmerRect(width: 120, height: 16),
            const SizedBox(height: 12),
            ...List.generate(6, (_) => const Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: ShimmerListTile(),
            )),
          ],
        ),
      ),
    );
  }
}

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
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1),
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
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
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
