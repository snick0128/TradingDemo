import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme.dart';
import '../widgets/shared_widgets.dart';

class MarketOverviewScreen extends StatelessWidget {
  const MarketOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Market Overview'),
        leading: const BackButton(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(context, 'Indian Indices'),
            const SizedBox(height: 12),
            _IndianIndicesGrid(),
            const SizedBox(height: 24),
            _sectionTitle(context, 'Global Indices'),
            const SizedBox(height: 12),
            _GlobalIndicesGrid(),
            const SizedBox(height: 24),
            _sectionTitle(context, 'Sector Performance'),
            const SizedBox(height: 12),
            _SectorPerformanceTable(),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(title, style: Theme.of(context).textTheme.titleLarge);
  }
}

// ─── Indian Indices ───────────────────────────────────────────────────────────

const _indianIndices = [
  ('NIFTY 50', '22,814.65', 192.15, 0.84),
  ('SENSEX', '75,091.11', 440.23, 0.59),
  ('NIFTY BANK', '48,115.30', -215.10, -0.45),
  ('NIFTY IT', '36,420.80', 85.40, 0.24),
  ('NIFTY MIDCAP 100', '44,230.55', 310.20, 0.71),
  ('NIFTY SMALLCAP 100', '14,820.40', -95.30, -0.64),
  ('NIFTY FMCG', '55,640.10', 220.80, 0.40),
  ('NIFTY AUTO', '22,180.75', 145.60, 0.66),
];

class _IndianIndicesGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 600
            ? 3
            : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.2,
          ),
          itemCount: _indianIndices.length,
          itemBuilder: (context, i) {
            final (name, price, change, pct) = _indianIndices[i];
            final isPos = pct >= 0;
            return CustomCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    price,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        isPos
                            ? LucideIcons.trendingUp
                            : LucideIcons.trendingDown,
                        size: 12,
                        color: isPos ? AppColors.success : AppColors.danger,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${isPos ? '+' : ''}${change.toStringAsFixed(2)} (${pct.toStringAsFixed(2)}%)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isPos ? AppColors.success : AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Global Indices ───────────────────────────────────────────────────────────

const _globalIndices = [
  ('Dow Jones', '38,654.42', 125.69, 0.33),
  ('S&P 500', '5,204.34', 18.78, 0.36),
  ('NASDAQ', '16,384.47', -42.15, -0.26),
  ('Nikkei 225', '38,460.08', 210.30, 0.55),
  ('FTSE 100', '8,145.20', -30.40, -0.37),
  ('DAX', '18,210.55', 95.80, 0.53),
];

class _GlobalIndicesGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 600
            ? 2
            : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 3.0,
          ),
          itemCount: _globalIndices.length,
          itemBuilder: (context, i) {
            final (name, price, change, pct) = _globalIndices[i];
            final isPos = pct >= 0;
            return CustomCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      StatusBadge(label: 'GLOBAL', color: AppColors.primary),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        price,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '${isPos ? '+' : ''}${pct.toStringAsFixed(2)}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isPos ? AppColors.success : AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Sector Performance Table ─────────────────────────────────────────────────

const _sectorData = [
  ('IT', 0.24, 'INFY'),
  ('Finance', -0.45, 'HDFC'),
  ('Energy', 1.12, 'RELIANCE'),
  ('FMCG', 0.40, 'HUL'),
  ('Auto', 0.66, 'MARUTI'),
  ('Pharma', -0.18, 'SUNPHARMA'),
  ('Telecom', 0.85, 'BHARTIARTL'),
];

class _SectorPerformanceTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Sector',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Change%',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Top Mover',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ..._sectorData.asMap().entries.map((entry) {
            final i = entry.key;
            final (sector, pct, topMover) = entry.value;
            final isPos = pct >= 0;
            return Column(
              children: [
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          sector,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (isPos ? AppColors.success : AppColors.danger)
                                      .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${isPos ? '+' : ''}${pct.toStringAsFixed(2)}%',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isPos
                                    ? AppColors.success
                                    : AppColors.danger,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          topMover,
                          textAlign: TextAlign.right,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
