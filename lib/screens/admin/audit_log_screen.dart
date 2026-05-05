import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../state/admin_scope.dart';
import '../../models/trading_models.dart';
import '../../theme.dart';
import '../../widgets/shared_widgets.dart';
import 'admin_ui.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});
  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  String _actionFilter = 'All';
  DateTimeRange? _dateRange;

  @override
  Widget build(BuildContext context) {
    final admin = AdminScope.of(context);
    final actionTypes = <String>{
      'All',
      ...admin.auditLogs.map((l) => l.action),
    }.toList();
    final logs = admin.auditLogs.where((l) {
      if (_actionFilter != 'All' && l.action != _actionFilter) return false;
      if (_dateRange != null) {
        if (l.timestamp.isBefore(_dateRange!.start) ||
            l.timestamp.isAfter(_dateRange!.end.add(const Duration(days: 1))))
          return false;
      }
      return true;
    }).toList();

    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Audit Log',
            subtitle: '${logs.length} entries',
            trailing: OutlinedButton.icon(
              onPressed: () => _exportCsv(logs),
              icon: const Icon(LucideIcons.download, size: 16),
              label: const Text('Export CSV'),
            ),
          ),
          const SizedBox(height: 12),

          // Filters
          AdminPanel(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _actionFilter,
                    decoration: const InputDecoration(
                      labelText: 'Action',
                      isDense: true,
                    ),
                    items: actionTypes
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              t,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _actionFilter = v!),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                      initialDateRange: _dateRange,
                    );
                    if (range != null) setState(() => _dateRange = range);
                  },
                  icon: const Icon(LucideIcons.calendar, size: 14),
                  label: Text(
                    _dateRange == null
                        ? 'Date Range'
                        : '${DateFormat('dd MMM').format(_dateRange!.start)} – ${DateFormat('dd MMM').format(_dateRange!.end)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (_dateRange != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 14),
                    onPressed: () => setState(() => _dateRange = null),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: logs.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.fileSearch,
                          size: 48,
                          color: AppColors.border,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'No audit logs found.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                : AdminPanel(
                    child: ListView.separated(
                      itemCount: logs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) => _logRow(logs[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _logRow(AuditLogEntry log) {
    final fmt = DateFormat('dd MMM HH:mm:ss');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              LucideIcons.shield,
              size: 14,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.action,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Target: ${log.targetId}  •  Admin: ${log.adminId}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            fmt.format(log.timestamp),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _exportCsv(List<AuditLogEntry> logs) {
    final csv = StringBuffer('ID,Admin,Action,Target,Timestamp\n');
    for (final l in logs) {
      csv.writeln(
        '${l.id},${l.adminId},${l.action},${l.targetId},${l.timestamp.toIso8601String()}',
      );
    }
    Clipboard.setData(ClipboardData(text: csv.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CSV copied to clipboard.'),
        backgroundColor: AppColors.success,
      ),
    );
  }
}
