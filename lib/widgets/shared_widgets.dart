import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../config/backend_config.dart';
import '../data/services/backend_api_service.dart';
import '../state/trading_store.dart';
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
          style: AppTheme.mono(
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
            style: AppTheme.mono(
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

// ─── LivePriceText ────────────────────────────────────────────────────────────

/// Price display that updates instantly on every WS tick via [ValueNotifier],
/// completely bypassing the store's 16ms debounce and any parent rebuild cycle.
///
/// Wraps [PriceFlashWidget] so the green/red flash animation still plays on
/// each price change. The [PriceFlashWidget] state is reused across rebuilds,
/// so the animation controller is never unnecessarily recreated.
///
/// Usage:
/// ```dart
/// LivePriceText(
///   symbol: stock.symbol,
///   store: TradingScope.of(context),
///   style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
/// )
/// ```
class LivePriceText extends StatelessWidget {
  final String symbol;
  final TradingStore store;
  final TextStyle? style;

  const LivePriceText({
    super.key,
    required this.symbol,
    required this.store,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: store.ltpNotifier(symbol),
      builder: (_, ltp, __) => PriceFlashWidget(
        price: ltp,
        child: Text(
          ltp > 0 ? '₹${ltp.toStringAsFixed(2)}' : '—',
          style: style,
        ),
      ),
    );
  }
}

// ─── Sparkline ──────────────────────────────────────────────────────────────
//
// Small trend-line chart driven by a live ValueListenable — samples a new
// point whenever the value changes, at most once per [minSampleGap], so a
// burst of ticks doesn't fill the buffer with near-duplicate points. No
// Timer is used: sampling is purely tick-driven, so there is nothing to leak
// if the widget is disposed mid-session.
class Sparkline extends StatefulWidget {
  final ValueListenable<double> valueListenable;
  final Color color;
  final bool filled;
  final int maxPoints;
  final Duration minSampleGap;
  final double strokeWidth;

  /// Fallback starting value (e.g. a cached/last-known price) used to seed
  /// the very first point when [valueListenable] hasn't ticked yet — without
  /// this, a fresh page load shows nothing until two live ticks arrive.
  final double? seedValue;

  /// When set, today's real intraday candles are fetched once and used to
  /// seed the line with an actual shape instead of the flat two-point
  /// placeholder — a flat line reads as broken once the user notices it
  /// never bends. [exchange]/[token] help the backend resolve non-standard
  /// instruments (MCX/NFO/CDS) the same way chart screens already do.
  final String? symbol;
  final String? exchange;
  final String? token;

  const Sparkline({
    super.key,
    required this.valueListenable,
    required this.color,
    this.filled = true,
    this.maxPoints = 24,
    this.minSampleGap = const Duration(seconds: 2),
    this.strokeWidth = 1.6,
    this.seedValue,
    this.symbol,
    this.exchange,
    this.token,
  });

  @override
  State<Sparkline> createState() => _SparklineState();
}

class _SparklineState extends State<Sparkline> {
  final List<double> _samples = [];
  DateTime? _lastSampleAt;
  bool _hasRealHistory = false;

  @override
  void initState() {
    super.initState();
    final v = widget.valueListenable.value > 0 ? widget.valueListenable.value : (widget.seedValue ?? 0);
    // Seed with two identical points so a flat line renders immediately
    // instead of nothing while the real history request (below) is in
    // flight, or as the permanent fallback if that request fails.
    if (v > 0) {
      _samples.add(v);
      _samples.add(v);
      _lastSampleAt = DateTime.now();
    }
    widget.valueListenable.addListener(_onTick);
    if (widget.symbol != null) _loadTodaysHistory();
  }

  Future<void> _loadTodaysHistory() async {
    try {
      final api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final rows = await api.getHistoricalData(
        widget.symbol!,
        interval: '5m',
        from: _fmtApiDate(startOfDay),
        to: _fmtApiDate(now),
        exchange: widget.exchange,
        token: widget.token,
      );
      if (!mounted || rows.length < 2) return;
      final closes = rows
          .map((r) => (r['close'] as num?)?.toDouble() ?? 0.0)
          .where((c) => c > 0)
          .toList();
      if (closes.length < 2) return;
      final liveValue = widget.valueListenable.value;
      setState(() {
        _hasRealHistory = true;
        _samples
          ..clear()
          ..addAll(closes);
        if (liveValue > 0 && _samples.last != liveValue) _samples.add(liveValue);
        _lastSampleAt = DateTime.now();
      });
    } catch (_) {
      // Keep whatever placeholder/live-tick samples already exist — a
      // failed history fetch shouldn't take down the whole card.
    }
  }

  String _fmtApiDate(DateTime local) {
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$m-$d $h:$min';
  }

  void _onTick() {
    final v = widget.valueListenable.value;
    if (v <= 0) return;
    final now = DateTime.now();
    if (_lastSampleAt != null && now.difference(_lastSampleAt!) < widget.minSampleGap) {
      return;
    }
    _lastSampleAt = now;
    setState(() {
      _samples.add(v);
      // Once seeded with real history, keep the full session shape instead
      // of sliding the window — only the live-tick-only fallback caps length.
      if (!_hasRealHistory && _samples.length > widget.maxPoints) {
        _samples.removeAt(0);
      }
    });
  }

  @override
  void didUpdateWidget(covariant Sparkline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.valueListenable != widget.valueListenable) {
      oldWidget.valueListenable.removeListener(_onTick);
      widget.valueListenable.addListener(_onTick);
    }
  }

  @override
  void dispose() {
    widget.valueListenable.removeListener(_onTick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_samples.length < 2) return const SizedBox.shrink();
    return CustomPaint(
      painter: _SparklinePainter(
        samples: _samples,
        color: widget.color,
        filled: widget.filled,
        strokeWidth: widget.strokeWidth,
      ),
      size: Size.infinite,
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  final bool filled;
  final double strokeWidth;

  _SparklinePainter({
    required this.samples,
    required this.color,
    required this.filled,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final minV = samples.reduce((a, b) => a < b ? a : b);
    final maxV = samples.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    final dx = samples.length > 1 ? size.width / (samples.length - 1) : 0.0;

    Offset pointAt(int i) {
      final normalized = (samples[i] - minV) / range;
      final y = size.height - normalized * size.height;
      return Offset(dx * i, y.clamp(0, size.height));
    }

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < samples.length; i++) {
      final p = pointAt(i);
      path.lineTo(p.dx, p.dy);
    }

    if (filled) {
      final fillPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      final paintFill = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.18), color.withOpacity(0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawPath(fillPath, paintFill);
    }

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final last = pointAt(samples.length - 1);
    // Soft glow halo behind the endpoint dot, then the solid dot on top.
    canvas.drawCircle(
      last,
      strokeWidth * 4,
      Paint()
        ..color = color.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(last, strokeWidth * 1.8, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.color != color ||
        oldDelegate.filled != filled;
  }
}

// ─── Tag Chip ─────────────────────────────────────────────────────────────
//
// Small rounded label badge — exchange/segment tags (NSE / EQ / MIS / CNC),
// or any other short categorical label next to a symbol or row.
class AppTagChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool neutral;

  const AppTagChip(this.label, {super.key, this.color, this.neutral = false});

  /// Gray/neutral variant — e.g. exchange tags like "NSE".
  const AppTagChip.neutral(this.label, {super.key})
      : color = null,
        neutral = true;

  @override
  Widget build(BuildContext context) {
    final fg = neutral ? AppColors.chipNeutralText : (color ?? AppColors.primary);
    final bg = neutral ? AppColors.chipNeutralBg : fg.withOpacity(0.10);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ─── Symbol Avatar ────────────────────────────────────────────────────────
//
// Circular initial-letter avatar for a stock/symbol row when no logo asset
// is available. Color is derived deterministically from the symbol so the
// same stock always gets the same avatar color.
class SymbolAvatar extends StatelessWidget {
  final String symbol;
  final double size;

  const SymbolAvatar({super.key, required this.symbol, this.size = 36});

  static const _palette = [
    Color(0xFF1B4FD8),
    Color(0xFF059669),
    Color(0xFFD97706),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFF0891B2),
  ];

  @override
  Widget build(BuildContext context) {
    final clean = symbol.trim();
    final letter = clean.isNotEmpty ? clean[0].toUpperCase() : '?';
    final color = _palette[clean.codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withOpacity(0.14), shape: BoxShape.circle),
      child: Text(
        letter,
        style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ─── Header Icon Action ───────────────────────────────────────────────────
//
// Circular icon button for screen headers (search/notifications/sort/add).
// [label] renders centered below the circle (matches the "icon + caption"
// header pattern); omit it for a bare icon button.
class AppHeaderAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final String? label;
  final double size;

  const AppHeaderAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.label,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final button = Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surfaceAlt,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.475, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
    if (label == null) return button;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(height: 4),
        Text(label!, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ─── Segmented Control ──────────────────────────────────────────────────────
//
// iOS/Robinhood-style pill switcher for a small, fixed set of options (e.g.
// "Order Book" / "Basket"). Each segment animates its own fill color on
// selection change — a lighter-weight approach than a measured sliding
// thumb, but still reads as one continuous, native-feeling transition.
class AppSegmentedControl extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final List<int>? badgeCounts;

  const AppSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.badgeCounts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppColors.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(labels.length, (i) {
          final selected = i == selectedIndex;
          final count = badgeCounts != null && i < badgeCounts!.length ? badgeCounts![i] : 0;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onChanged(i),
              borderRadius: BorderRadius.circular(AppColors.radiusPill),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppColors.radiusPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: selected ? Colors.white.withOpacity(0.25) : AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
