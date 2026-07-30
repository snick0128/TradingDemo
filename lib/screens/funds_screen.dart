import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../app/app_scope.dart';
import '../models/trading_models.dart';
import '../state/trading_scope.dart';
import '../state/trading_store.dart';
import '../theme.dart';
import '../widgets/wallet_fund_widgets.dart';
import 'add_funds_screen.dart';
import 'deposit_history_screen.dart';
import 'withdraw_funds_screen.dart';
import 'withdrawal_history_screen.dart';

const _kMethodLabels = {
  'gpay': 'Google Pay',
  'phonepe': 'PhonePe',
  'paytm': 'Paytm',
  'upi': 'UPI',
  'bank_transfer': 'Bank Transfer',
};

// ── Indian currency formatter ─────────────────────────────────────────────────
String _fmt(double v) {
  final formatter = NumberFormat('#,##,##0.00', 'en_IN');
  return '₹${formatter.format(v)}';
}

// ── FundsScreen ───────────────────────────────────────────────────────────────
//
// Converted from StatelessWidget to StatefulWidget so it explicitly subscribes
// to TradingStore via addListener(). This guarantees live updates on every
// price tick and Firestore change regardless of TabBarView mount/unmount cycles.
// A StatelessWidget relying on InheritedWidget can silently lose its dependency
// subscription when the tab is scrolled out of the PageView cache range.

class FundsScreen extends StatefulWidget {
  final bool showAppBar;
  const FundsScreen({super.key, this.showAppBar = true});

  @override
  State<FundsScreen> createState() => _FundsScreenState();
}

class _FundsScreenState extends State<FundsScreen>
    with AutomaticKeepAliveClientMixin {
  TradingStore? _store;

  // Keep this tab alive inside TabBarView so the store subscription is
  // never dropped when the user switches to another tab.
  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = TradingScope.read(context);
    if (_store == store) return;
    _store?.removeListener(_onStoreUpdate);
    _store = store;
    store.addListener(_onStoreUpdate);
  }

  @override
  void dispose() {
    _store?.removeListener(_onStoreUpdate);
    super.dispose();
  }

  void _onStoreUpdate() {
    if (mounted) setState(() {});
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin

    final store = _store ?? TradingScope.read(context);

    // ── Live values (always from streaming store, never from stale cache) ──
    final balance         = store.balance;           // free cash after margin blocked
    final usedMargin      = store.usedMargin;        // sum of marginUsed on open positions
    final equity          = store.equity;            // walletBalance + runningPnL
    final runningPnl      = store.runningPnL;        // sum of unrealizedPnl on open positions
    final availableMargin = store.availableMargin;   // max(0, equity - usedMargin)
    final marginShortfall = store.marginShortfall;   // max(0, usedMargin - equity)
    final walletBalance   = balance + usedMargin;    // total deposited funds

    // Realized P&L: today's executed sell orders
    final now = DateTime.now();
    bool isSameDay(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;

    // Sum today's realized P&L across ALL closing orders (both SELL to close
    // longs, and BUY to close shorts). Opening orders have pnl = 0 so they
    // do not contribute.
    final realizedPnl = store.orders
        .where((o) =>
            o.status == OrderStatus.executed &&
            (o.pnl ?? 0.0) != 0.0 &&
            isSameDay(o.executedAt ?? o.dateTime))
        .fold(0.0, (sum, o) => sum + (o.pnl ?? 0.0));

    final body = Container(
      color: const Color(0xFFFAFAFA),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _HeroCard(
              walletBalance:   walletBalance,
              runningPnl:      runningPnl,
              equity:          equity,
              usedMargin:      usedMargin,
              availableMargin: availableMargin,
              marginShortfall: marginShortfall,
            ),
            const SizedBox(height: 16),
            _BreakdownSection(
              walletBalance:   walletBalance,
              runningPnl:      runningPnl,
              equity:          equity,
              usedMargin:      usedMargin,
              availableMargin: availableMargin,
              marginShortfall: marginShortfall,
            ),
            const SizedBox(height: 24),
            _PnlStrip(
              runningPnl:  runningPnl,
              realizedPnl: realizedPnl,
            ),
            const SizedBox(height: 24),
            _RequestsSection(
              collection: 'deposit_requests',
              pendingTitle: 'Pending Deposits',
              recentTitle: 'Recent Deposits',
              isCredit: true,
              historyScreen: const DepositHistoryScreen(),
              subtitleBuilder: (d) => _kMethodLabels[d['paymentMethod'] as String? ?? ''] ??
                  (d['paymentMethod'] as String? ?? 'UPI'),
            ),
            const SizedBox(height: 20),
            _RequestsSection(
              collection: 'withdrawal_requests',
              pendingTitle: 'Pending Withdrawals',
              recentTitle: 'Recent Withdrawals',
              isCredit: false,
              historyScreen: const WithdrawalHistoryScreen(),
              subtitleBuilder: (d) {
                final upi = d['upiId'] as String? ?? '';
                return upi.isNotEmpty ? 'UPI: $upi' : (d['bankAccount'] as String? ?? '');
              },
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );

    if (!widget.showAppBar) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Funds')),
      body: body,
    );
  }
}

// ── Hero card ─────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final double walletBalance;
  final double runningPnl;
  final double equity;
  final double usedMargin;
  final double availableMargin;
  final double marginShortfall;

  const _HeroCard({
    required this.walletBalance,
    required this.runningPnl,
    required this.equity,
    required this.usedMargin,
    required this.availableMargin,
    required this.marginShortfall,
  });

  @override
  Widget build(BuildContext context) {
    final hasShortfall = marginShortfall > 0;
    final pnlColor = runningPnl >= 0
        ? const Color(0xFF00C853)
        : const Color(0xFFFF5252);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D2B6B), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Primary: Equity ────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Equity',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _fmt(equity),
                        style: GoogleFonts.inter(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── Primary CTA row: large Add Funds + Withdraw ────────────────
          Row(
            children: [
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddFundsScreen()),
                    ),
                    icon: const Icon(Icons.add_circle, size: 18),
                    label: Text('Add Funds', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0D2B6B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WithdrawFundsScreen()),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Withdraw', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                ),
              ),
            ],
          ),

          Container(
            margin: const EdgeInsets.symmetric(vertical: 16),
            height: 1,
            color: Colors.white.withOpacity(0.18),
          ),

          // ── Secondary: Wallet Balance | Running P&L | Available Margin ─
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  label: 'Wallet Balance',
                  value: walletBalance,
                  align: CrossAxisAlignment.start,
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Running P&L',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.65),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _fmt(runningPnl),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: pnlColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _HeroMetric(
                  label: 'Available Margin',
                  value: availableMargin,
                  align: CrossAxisAlignment.end,
                  valueColor: hasShortfall ? const Color(0xFFFF5252) : null,
                ),
              ),
            ],
          ),

          // ── Shortfall warning strip (only when in shortfall) ───────────
          if (hasShortfall) ...[
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFD50000).withOpacity(0.22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 13),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Margin Shortfall: ${_fmt(marginShortfall)} — add funds or reduce positions',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final String label;
  final double value;
  final CrossAxisAlignment align;
  final Color? valueColor;

  const _HeroMetric({
    required this.label,
    required this.value,
    required this.align,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: Colors.white.withOpacity(0.65),
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _fmt(value),
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Breakdown section ─────────────────────────────────────────────────────────

class _BreakdownSection extends StatelessWidget {
  final double walletBalance;
  final double runningPnl;
  final double equity;
  final double usedMargin;
  final double availableMargin;
  final double marginShortfall;

  const _BreakdownSection({
    required this.walletBalance,
    required this.runningPnl,
    required this.equity,
    required this.usedMargin,
    required this.availableMargin,
    required this.marginShortfall,
  });

  @override
  Widget build(BuildContext context) {
    final hasShortfall = marginShortfall > 0;
    final pnlColor = runningPnl >= 0 ? AppColors.success : AppColors.danger;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 20, bottom: 12),
          child: Text(
            'Margin breakdown',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF0D0D0D),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _Row('Wallet Balance', walletBalance),
              _Sep(),
              _Row('Running P&L',   runningPnl,  color: pnlColor),
              _Sep(),
              // Equity total row
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(color: Color(0xFFF8FBFF)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Equity',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0D0D0D),
                      ),
                    ),
                    Text(
                      _fmt(equity),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: const Color(0xFFE0E0E0)),
              _Row('Used Margin',      usedMargin,      color: usedMargin > 0 ? AppColors.danger : null),
              _Sep(),
              _Row('Available Margin', availableMargin, color: hasShortfall ? AppColors.danger : AppColors.success),
              if (hasShortfall) ...[
                _Sep(),
                _Row('Margin Shortfall', marginShortfall, color: AppColors.danger),
              ],
            ],
          ),
        ),

        // ── Shortfall warning card ─────────────────────────────────────
        if (hasShortfall) ...[
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.06),
              border: Border.all(color: AppColors.danger.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 15, color: AppColors.danger),
                    const SizedBox(width: 6),
                    Text(
                      'Margin Shortfall',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ShortfallRow('Required Margin', usedMargin),
                const SizedBox(height: 4),
                _ShortfallRow('Current Equity',  equity),
                const Divider(height: 16),
                _ShortfallRow('Shortfall', marginShortfall, bold: true, color: AppColors.danger),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ShortfallRow extends StatelessWidget {
  final String label;
  final double value;
  final bool bold;
  final Color? color;

  const _ShortfallRow(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: const Color(0xFF757575),
          ),
        ),
        Text(
          _fmt(value),
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: color ?? const Color(0xFF0D0D0D),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final double value;
  final Color? color;

  const _Row(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    final isZero = value == 0;
    final effectiveColor = isZero
        ? const Color(0xFF9E9E9E)
        : (color ?? const Color(0xFF0D0D0D));

    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF757575),
              ),
            ),
            Text(
              _fmt(value),
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: effectiveColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: const Color(0xFFF5F5F5));
}

// ── P&L strip ─────────────────────────────────────────────────────────────────

class _PnlStrip extends StatelessWidget {
  final double runningPnl;
  final double realizedPnl;

  const _PnlStrip({required this.runningPnl, required this.realizedPnl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _PnlCell(label: 'Running P&L', value: runningPnl),
          ),
          Container(width: 1, height: 36, color: const Color(0xFFE0E0E0)),
          Expanded(
            child: _PnlCell(label: 'Realized (today)', value: realizedPnl),
          ),
        ],
      ),
    );
  }
}

class _PnlCell extends StatelessWidget {
  final String label;
  final double value;

  const _PnlCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isPos  = value > 0;
    final isZero = value == 0;
    final color  = isZero
        ? const Color(0xFF9E9E9E)
        : (isPos ? const Color(0xFF00C853) : const Color(0xFFD50000));
    final prefix = isZero ? '' : (isPos ? '+' : '-');

    return Column(
      children: [
        Text(
          '$prefix${_fmt(value.abs())}',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF9E9E9E)),
        ),
      ],
    );
  }
}

// ── Pending / Recent requests section (shared by deposits & withdrawals) ──────

class _RequestsSection extends StatelessWidget {
  final String collection;
  final String pendingTitle;
  final String recentTitle;
  final bool isCredit;
  final Widget historyScreen;
  final String Function(Map<String, dynamic> data) subtitleBuilder;

  const _RequestsSection({
    required this.collection,
    required this.pendingTitle,
    required this.recentTitle,
    required this.isCredit,
    required this.historyScreen,
    required this.subtitleBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final uid = AppScope.of(context).notifier?.user?.uid ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(collection)
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();

        final pending = docs.where((d) => (d.data()['status'] as String? ?? '') == 'PENDING').toList();
        final recent  = docs.where((d) => (d.data()['status'] as String? ?? '') != 'PENDING').take(3).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pending.isNotEmpty) ...[
              _SectionHeader(title: pendingTitle),
              const SizedBox(height: 10),
              ...pending.map((d) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _cardFor(d),
                  )),
              const SizedBox(height: 14),
            ],
            if (recent.isNotEmpty) ...[
              _SectionHeader(
                title: recentTitle,
                onViewAll: () => Navigator.push(context, MaterialPageRoute(builder: (_) => historyScreen)),
              ),
              const SizedBox(height: 10),
              ...recent.map((d) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _cardFor(d),
                  )),
            ],
          ],
        );
      },
    );
  }

  Widget _cardFor(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d      = doc.data();
    final amount = ((d['amount'] as num?) ?? 0).toDouble();
    final status = (d['status'] as String?) ?? 'PENDING';
    final ts     = d['createdAt'];
    final date   = ts is Timestamp ? ts.toDate() : DateTime.now();

    return WalletHistoryCard(
      amount: amount,
      status: status,
      date: date,
      subtitle: subtitleBuilder(d),
      rejectionReason: d['rejectionReason'] as String?,
      isCredit: isCredit,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onViewAll;

  const _SectionHeader({required this.title, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF0D0D0D))),
          if (onViewAll != null)
            InkWell(
              onTap: onViewAll,
              child: Text('View All',
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.primary)),
            ),
        ],
      ),
    );
  }
}
