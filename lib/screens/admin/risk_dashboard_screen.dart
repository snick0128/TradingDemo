import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/trade_ledger.dart';
import '../../state/admin_scope.dart';
import '../../state/admin_store.dart';
import '../../theme.dart';

class RiskDashboardScreen extends StatelessWidget {
  const RiskDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AdminScope.of(context);
    final width = MediaQuery.of(context).size.width;
    return _RiskBody(store: store, isWide: width >= 900);
  }
}

class _RiskBody extends StatelessWidget {
  final AdminStore store;
  final bool isWide;
  const _RiskBody({required this.store, required this.isWide});

  @override
  Widget build(BuildContext context) {
    final orders = store.masterOrderBook.toList();
    final risk = _RiskMetrics(orders, store);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isWide ? 20 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RiskHeader(risk: risk),
          SizedBox(height: isWide ? 20 : 14),

          // ── Top KPI cards ─────────────────────────────────────────
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: isWide ? 4 : 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: isWide ? 2.0 : 1.8,
            children: [
              _RiskKpi(
                icon: LucideIcons.trendingUp,
                label: 'Total Exposure',
                value: _fmtV(risk.totalExposure),
                color: AppColors.primary,
                sub: '${risk.openCount} open positions',
              ),
              _RiskKpi(
                icon: LucideIcons.alertTriangle,
                label: 'Risk Estimate',
                value: _fmtV(risk.riskEstimate),
                color: AppColors.warning,
                sub: '0.12% of exposure',
              ),
              _RiskKpi(
                icon: LucideIcons.shieldAlert,
                label: 'High-Risk Accounts',
                value: '${risk.highRiskCount}',
                color: AppColors.danger,
                sub: 'above 50% threshold',
              ),
              _RiskKpi(
                icon: LucideIcons.layers,
                label: 'Margin Utilisation',
                value: '${risk.marginUtilPct.toStringAsFixed(1)}%',
                color: _riskColor(risk.marginUtilPct / 100),
                sub: '${_fmtV(risk.totalMarginUsed)} used',
              ),
            ],
          ),
          SizedBox(height: isWide ? 20 : 14),

          // ── Content split ─────────────────────────────────────────
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    flex: 3,
                    child: _TopRiskAccounts(risk: risk, store: store)),
                const SizedBox(width: 16),
                Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        _MarginCallCandidates(risk: risk, store: store),
                        const SizedBox(height: 16),
                        _ExposureBySymbol(risk: risk),
                      ],
                    )),
              ],
            )
          else ...[
            _TopRiskAccounts(risk: risk, store: store),
            const SizedBox(height: 14),
            _MarginCallCandidates(risk: risk, store: store),
            const SizedBox(height: 14),
            _ExposureBySymbol(risk: risk),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _fmtV(double v) {
    if (v.abs() >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)}Cr';
    if (v.abs() >= 100000) return '₹${(v / 100000).toStringAsFixed(2)}L';
    if (v.abs() >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  static Color _riskColor(double ratio) {
    if (ratio > 0.7) return AppColors.danger;
    if (ratio > 0.4) return AppColors.warning;
    return AppColors.success;
  }
}

// ── Risk metrics ───────────────────────────────────────────────────────────────

class _RiskMetrics {
  final List<AdminOrderRecord> orders;
  final AdminStore store;
  late final LedgerSummary _ledger;

  _RiskMetrics(this.orders, this.store) {
    _ledger = LedgerSummary(orders);
  }

  // Open positions = FIFO-matched unmatched executed orders (not just pending)
  List<TradeLedgerEntry> get _openPositions => _ledger.open;

  int get openCount => _openPositions.length;
  double get totalExposure =>
      _openPositions.fold(0.0, (s, t) => s + t.entryValue);
  double get riskEstimate => totalExposure * 0.0012;
  // Sum the actual marginUsed stored in each open position's source order.
  // Falls back to 0 for pre-migration orders that lack the field.
  double get totalMarginUsed =>
      _openPositions.fold(0.0, (s, t) => s + t.marginUsed);

  // Per-user exposure
  Map<String, double> get exposureByUser {
    final m = <String, double>{};
    for (final t in _openPositions) {
      m[t.userId] = (m[t.userId] ?? 0) + t.entryValue;
    }
    return m;
  }

  Map<String, String> get labelByUser {
    final m = <String, String>{};
    for (final t in _openPositions) {
      if (t.userClientId.isNotEmpty) m[t.userId] = t.userClientId;
    }
    return m;
  }

  // Per-symbol exposure
  Map<String, double> get exposureBySymbol {
    final m = <String, double>{};
    for (final t in _openPositions) {
      m[t.symbol] = (m[t.symbol] ?? 0) + t.entryValue;
    }
    return m;
  }

  double get marginUtilPct {
    final users = store.users;
    final totalLimit =
        users.fold(0.0, (s, u) => s + u.marginLimit);
    if (totalLimit == 0) return 0;
    return (totalMarginUsed / totalLimit * 100).clamp(0, 100);
  }

  int get highRiskCount {
    if (exposureByUser.isEmpty) return 0;
    final maxExp = exposureByUser.values
        .reduce((a, b) => a > b ? a : b);
    return exposureByUser.values
        .where((v) => v / maxExp > 0.5)
        .length;
  }

  // Users sorted by exposure
  List<MapEntry<String, double>> get topRiskUsers {
    final sorted = exposureByUser.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(10).toList();
  }

  // Users where balance < exposure * 0.15 (margin call zone)
  List<MapEntry<String, double>> get marginCallCandidates {
    final users = {for (final u in store.users) u.id: u};
    return exposureByUser.entries.where((e) {
      final u = users[e.key];
      if (u == null) return false;
      return u.balance < e.value * 0.15;
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  // Top symbols by exposure
  List<MapEntry<String, double>> get topSymbols {
    final sorted = exposureBySymbol.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(8).toList();
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _RiskHeader extends StatelessWidget {
  final _RiskMetrics risk;
  const _RiskHeader({required this.risk});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(LucideIcons.shieldAlert,
            size: 18, color: AppColors.danger),
        const SizedBox(width: 8),
        Text('Risk Dashboard',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            )),
        const Spacer(),
        if (risk.highRiskCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.danger.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.alertTriangle,
                    size: 12, color: AppColors.danger),
                const SizedBox(width: 5),
                Text('${risk.highRiskCount} high-risk accounts',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger,
                    )),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Risk KPI card ──────────────────────────────────────────────────────────────

class _RiskKpi extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String sub;
  const _RiskKpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              Text(
                sub,
                style: GoogleFonts.inter(fontSize: 9, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Top risk accounts ──────────────────────────────────────────────────────────

class _TopRiskAccounts extends StatelessWidget {
  final _RiskMetrics risk;
  final AdminStore store;
  const _TopRiskAccounts({required this.risk, required this.store});

  static String _fmtV(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)}Cr';
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final top = risk.topRiskUsers;
    final maxExp = top.isEmpty ? 1.0 : top.first.value;
    final labels = risk.labelByUser;
    final users = {for (final u in store.users) u.id: u};

    return _Panel(
      title: 'Top Exposure Accounts',
      icon: LucideIcons.alertOctagon,
      iconColor: AppColors.danger,
      child: top.isEmpty
          ? _EmptySection('No open positions')
          : Column(
              children: top.map((e) {
                final pct = e.value / maxExp;
                final label = labels[e.key] ??
                    e.key.substring(0, e.key.length.clamp(0, 8));
                final user = users[e.key];
                final balance = user?.balance ?? 0;
                final riskRatio =
                    balance > 0 ? (e.value / balance).clamp(0.0, 10.0) : 10.0;
                final riskColor = riskRatio > 5
                    ? AppColors.danger
                    : riskRatio > 2
                        ? AppColors.warning
                        : AppColors.success;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: riskColor.withOpacity(0.12),
                        child: Text(
                          label.substring(0, label.length.clamp(0, 2)).toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: riskColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(label,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                      overflow: TextOverflow.ellipsis),
                                ),
                                Text(_fmtV(e.value),
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: riskColor,
                                    )),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: pct,
                                      backgroundColor: AppColors.border,
                                      valueColor: AlwaysStoppedAnimation(riskColor),
                                      minHeight: 4,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Bal: ${_fmtV(balance)}',
                                  style: GoogleFonts.inter(
                                      fontSize: 9,
                                      color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

// ── Margin call candidates ─────────────────────────────────────────────────────

class _MarginCallCandidates extends StatelessWidget {
  final _RiskMetrics risk;
  final AdminStore store;
  const _MarginCallCandidates({required this.risk, required this.store});

  static String _fmtV(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final candidates = risk.marginCallCandidates.take(6).toList();
    final labels = risk.labelByUser;
    final users = {for (final u in store.users) u.id: u};

    return _Panel(
      title: 'Margin Call Zone',
      icon: LucideIcons.alertCircle,
      iconColor: AppColors.warning,
      child: candidates.isEmpty
          ? _EmptySection('No margin call risk')
          : Column(
              children: candidates.map((e) {
                final label = labels[e.key] ??
                    e.key.substring(0, e.key.length.clamp(0, 8));
                final user = users[e.key];
                final balance = user?.balance ?? 0;
                final shortfall = (e.value * 0.15 - balance).clamp(0.0, double.infinity);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.alertTriangle,
                          size: 14, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                )),
                            Text(
                              'Bal: ${_fmtV(balance)} · Shortfall: ${_fmtV(shortfall)}',
                              style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: AppColors.warning),
                            ),
                          ],
                        ),
                      ),
                      Text(_fmtV(e.value),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.danger,
                          )),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

// ── Exposure by symbol ─────────────────────────────────────────────────────────

class _ExposureBySymbol extends StatelessWidget {
  final _RiskMetrics risk;
  const _ExposureBySymbol({required this.risk});

  static String _fmtV(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final top = risk.topSymbols;
    final maxV = top.isEmpty ? 1.0 : top.first.value;

    return _Panel(
      title: 'Exposure by Symbol',
      icon: LucideIcons.barChart2,
      iconColor: AppColors.primary,
      child: top.isEmpty
          ? _EmptySection('No open exposure')
          : Column(
              children: top.map((e) {
                final pct = e.value / maxV;
                final color = pct > 0.7
                    ? AppColors.danger
                    : pct > 0.4
                        ? AppColors.warning
                        : AppColors.primary;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(e.key,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                )),
                          ),
                          Text(_fmtV(e.value),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: color,
                              )),
                        ],
                      ),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct,
                          backgroundColor: AppColors.border,
                          valueColor: AlwaysStoppedAnimation(color),
                          minHeight: 5,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

// ── Panel wrapper ──────────────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;
  const _Panel({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: 7),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  final String message;
  const _EmptySection(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(message,
            style: GoogleFonts.inter(
                fontSize: 13, color: AppColors.textSecondary)),
      ),
    );
  }
}
