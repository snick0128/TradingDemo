import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../state/admin_scope.dart';
import '../../theme.dart';
import '../../widgets/shared_widgets.dart';
import 'admin_ui.dart';

class AdminAnalyticsScreen extends StatelessWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    final stats = admin.stats;

    // Mock daily active users (last 7 days)
    final dauData = List.generate(
      7,
      (i) => _ChartPoint(
        DateTime.now().subtract(Duration(days: 6 - i)),
        (stats.activeUsers * (0.7 + i * 0.05)).round().toDouble(),
      ),
    );

    // Mock volume history
    final volData = stats.volumeHistory
        .asMap()
        .entries
        .map(
          (e) => _ChartPoint(
            DateTime.now().subtract(Duration(days: 6 - e.key)),
            e.value,
          ),
        )
        .toList();

    return AdminPage(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdminHeader(
              title: 'Platform Analytics',
              subtitle: 'Last 7 days performance overview.',
            ),
            const SizedBox(height: 20),

            // DAU Chart
            Text(
              'Daily Active Users',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            CustomCard(
              child: SizedBox(
                height: 220,
                child: SfCartesianChart(
                  plotAreaBorderWidth: 0,
                  primaryXAxis: DateTimeAxis(
                    majorGridLines: const MajorGridLines(width: 0),
                    labelStyle: Theme.of(context).textTheme.bodySmall,
                  ),
                  primaryYAxis: NumericAxis(
                    majorGridLines: MajorGridLines(
                      width: 0.5,
                      color: AppColors.border,
                    ),
                    labelStyle: Theme.of(context).textTheme.bodySmall,
                  ),
                  tooltipBehavior: TooltipBehavior(enable: true),
                  series: <CartesianSeries>[
                    AreaSeries<_ChartPoint, DateTime>(
                      name: 'Active Users',
                      dataSource: dauData,
                      xValueMapper: (p, _) => p.date,
                      yValueMapper: (p, _) => p.value,
                      color: AppColors.primary.withOpacity(0.15),
                      borderColor: AppColors.primary,
                      borderWidth: 2,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Volume Chart
            Text(
              'Trading Volume (₹ Cr)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            CustomCard(
              child: SizedBox(
                height: 220,
                child: SfCartesianChart(
                  plotAreaBorderWidth: 0,
                  primaryXAxis: DateTimeAxis(
                    majorGridLines: const MajorGridLines(width: 0),
                    labelStyle: Theme.of(context).textTheme.bodySmall,
                  ),
                  primaryYAxis: NumericAxis(
                    majorGridLines: MajorGridLines(
                      width: 0.5,
                      color: AppColors.border,
                    ),
                    labelStyle: Theme.of(context).textTheme.bodySmall,
                  ),
                  tooltipBehavior: TooltipBehavior(enable: true),
                  series: <CartesianSeries>[
                    ColumnSeries<_ChartPoint, DateTime>(
                      name: 'Volume (Cr)',
                      dataSource: volData,
                      xValueMapper: (p, _) => p.date,
                      yValueMapper: (p, _) => p.value,
                      color: AppColors.success.withOpacity(0.7),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Summary stats
            Text('Summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            CustomCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _statRow('Total Users', '${admin.users.length}'),
                  const Divider(height: 1),
                  _statRow('Active Users (Today)', '${stats.activeUsers}'),
                  const Divider(height: 1),
                  _statRow('Total Orders (Today)', '${stats.totalOrders}'),
                  const Divider(height: 1),
                  _statRow(
                    'Daily Volume',
                    '₹${(stats.dailyVolume / 10000000).toStringAsFixed(2)} Cr',
                  ),
                  const Divider(height: 1),
                  _statRow(
                    'Platform Revenue',
                    '₹${stats.platformRevenue.toStringAsFixed(0)}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPoint {
  final DateTime date;
  final double value;
  _ChartPoint(this.date, this.value);
}
