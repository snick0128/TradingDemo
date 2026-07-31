import 'dart:async';

import 'package:flutter/material.dart';

import '../state/trading_scope.dart';
import '../theme.dart';

/// Debug screen: 5-stage tick pipeline trace for a single symbol.
///
/// Usage (navigate from any screen for debugging):
///   Navigator.push(context, MaterialPageRoute(builder: (_) => const TickTraceScreen()));
///
/// Default symbol: CRUDEOIL.  Change via the top text-field.
class TickTraceScreen extends StatefulWidget {
  const TickTraceScreen({super.key, this.symbol = 'CRUDEOIL'});
  final String symbol;

  @override
  State<TickTraceScreen> createState() => _TickTraceScreenState();
}

class _TickTraceScreenState extends State<TickTraceScreen> {
  late final TextEditingController _symCtrl;
  Timer? _autoRefresh;
  Map<String, dynamic>? _trace;
  bool _loading = false;
  String? _error;
  static const _windowMs = 60000;

  @override
  void initState() {
    super.initState();
    _symCtrl = TextEditingController(text: widget.symbol);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    _symCtrl.dispose();
    super.dispose();
  }

  // ── Data refresh ────────────────────────────────────────────────────────────

  Future<void> _refresh() async {
    final store  = TradingScope.of(context);
    final lms    = store.liveMarketService;
    final symbol = _symCtrl.text.trim().toUpperCase();
    if (symbol.isEmpty || lms == null) return;

    setState(() { _loading = true; _error = null; });
    try {
      // POST Flutter trace + GET merged backend timeline in one call.
      final result = await lms.fetchTrace(symbol, windowMs: _windowMs);
      if (mounted) setState(() { _trace = result; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _startAutoRefresh() {
    _autoRefresh?.cancel();
    _autoRefresh = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    _refresh();
  }

  void _stopAutoRefresh() {
    _autoRefresh?.cancel();
    _autoRefresh = null;
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Tick Trace'),
        actions: [
          if (_autoRefresh != null)
            IconButton(
              icon: const Icon(Icons.pause_circle_outline),
              tooltip: 'Stop auto-refresh',
              onPressed: () => setState(_stopAutoRefresh),
            )
          else
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: 'Auto-refresh every 5s',
              onPressed: () => setState(_startAutoRefresh),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh now',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSymbolBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger)))
                    : _trace == null
                        ? const Center(child: Text('No data yet — press refresh'))
                        : _buildBody(_trace!),
          ),
        ],
      ),
    );
  }

  Widget _buildSymbolBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _symCtrl,
              decoration: const InputDecoration(
                labelText: 'Symbol',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (_) => _refresh(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _refresh, child: const Text('Trace')),
        ],
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> trace) {
    if (trace['error'] != null) {
      return Center(child: Text('${trace['error']}\n${trace['hint'] ?? ''}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.danger)));
    }

    final summary    = trace['summary'] as Map<String, dynamic>?;
    final timeline   = trace['timeline'] as List<dynamic>? ?? [];
    final firstDrop  = trace['firstDrop'] as Map<String, dynamic>?;
    final iCheck     = trace['instrumentCheck'] as Map<String, dynamic>?;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummaryCard(summary, trace),
        const SizedBox(height: 12),
        if (firstDrop != null) _buildFirstDropCard(firstDrop),
        if (firstDrop != null) const SizedBox(height: 12),
        if (iCheck != null) _buildInstrumentCard(iCheck),
        if (iCheck != null) const SizedBox(height: 12),
        _buildTimelineCard(timeline),
      ],
    );
  }

  // ── Summary card ─────────────────────────────────────────────────────────────

  Widget _buildSummaryCard(Map<String, dynamic>? s, Map<String, dynamic> trace) {
    if (s == null) return const SizedBox.shrink();
    final symbol     = trace['sym'] ?? '';
    final since      = trace['tracedSince'] as int?;
    final sinceStr   = since != null
        ? 'since ${_hms(since)} UTC'
        : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('$symbol  ', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text('last 60s  $sinceStr',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            _stageRow('Angel One (exchange)',        s['angel'],         AppColors.primary),
            _stageRow('Backend received',           s['angel'],         AppColors.primary),
            _stageRow('Backend broadcast',          s['broadcast'],     AppColors.success),
            _dropRow('  └ LTP dedup dropped',       s['dropped_backend_ltp']),
            _dropRow('  └ No clients dropped',      s['dropped_backend_no_clients']),
            _stageRow('Flutter received',           s['clientRx'],      AppColors.warning),
            _dropRow('  └ Network dropped',         s['dropped_network']),
            _stageRow('Flutter rendered',           s['rendered'],      AppColors.success),
            _dropRow('  └ Flutter dedup dropped',   s['dropped_flutter_dedup']),
            const Divider(height: 16),
            Text(
              'Totals (all-time): Angel=${s['angelTotal']}  '
              'Broadcast=${s['broadcastTotal']}  '
              'ClientRx=${s['clientRxTotal']}  '
              'Rendered=${s['clientRenderedTotal']}',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stageRow(String label, dynamic count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('${count ?? 0}',
                style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _dropRow(String label, dynamic count) {
    final n = (count as num?)?.toInt() ?? 0;
    if (n == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label,
              style: const TextStyle(fontSize: 12, color: AppColors.danger))),
          Text('−$n',
              style: const TextStyle(fontSize: 12, color: AppColors.danger,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ── First divergence card ─────────────────────────────────────────────────────

  Widget _buildFirstDropCard(Map<String, dynamic> d) {
    return Card(
      color: AppColors.danger.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('⚠ First Divergence',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
            const SizedBox(height: 6),
            Text('Stage: ${d['stage']}',   style: const TextStyle(fontSize: 13)),
            Text('Reason: ${d['reason']}', style: const TextStyle(fontSize: 13)),
            Text('LTP: ₹${_ltp(d['ltp'])}',
                style: const TextStyle(fontSize: 13)),
            Text('At: ${_hms(d['at'] as int?)}',
                style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // ── Instrument consistency card ───────────────────────────────────────────────

  Widget _buildInstrumentCard(Map<String, dynamic> c) {
    if (c['ok'] == true) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '✓ Instrument: token=${c['token']}  exchange=${c['exchange']}  '
            'expiry=${c['expiry'] ?? 'none'}',
            style: const TextStyle(fontSize: 12, color: AppColors.success),
          ),
        ),
      );
    }
    return Card(
      color: AppColors.danger.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('⚠ Instrument mismatch across ticks!',
                style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
            Text('${c['mismatches']}', style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // ── Timeline card ─────────────────────────────────────────────────────────────

  Widget _buildTimelineCard(List<dynamic> timeline) {
    if (timeline.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No ticks in the last 60s',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    final rows = timeline.reversed.take(40).toList(); // newest first, max 40

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Timeline (newest first, last 40)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 32,
              dataRowMinHeight: 28,
              dataRowMaxHeight: 28,
              columnSpacing: 12,
              horizontalMargin: 12,
              headingTextStyle: AppTheme.mono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
              dataTextStyle: AppTheme.mono(
                fontSize: 10,
                color: AppColors.textPrimary,
              ),
              columns: const [
                DataColumn(label: Text('LTP')),
                DataColumn(label: Text('Exchange')),
                DataColumn(label: Text('Backend')),
                DataColumn(label: Text('Broadcast')),
                DataColumn(label: Text('Client Rx')),
                DataColumn(label: Text('Rendered')),
                DataColumn(label: Text('feedNet')),
                DataColumn(label: Text('proc')),
                DataColumn(label: Text('wsNet')),
                DataColumn(label: Text('render')),
              ],
              rows: rows.map((r) {
                final row = r as Map<String, dynamic>;
                final dropped = row['broadcastTs'] == null;
                final style   = dropped
                    ? AppTheme.mono(
                        fontSize: 10, color: AppColors.danger)
                    : AppTheme.mono(
                        fontSize: 10, color: AppColors.textPrimary);
                return DataRow(
                  color: WidgetStateProperty.resolveWith((_) =>
                      dropped ? AppColors.danger.withOpacity(0.06) : null),
                  cells: [
                    DataCell(Text('₹${_ltp(row['ltp'])}', style: style)),
                    DataCell(Text(_hms(row['exchangeMs'] as int?),   style: style)),
                    DataCell(Text(_hms(row['backendReceiveTs'] as int?), style: style)),
                    DataCell(Text(dropped ? '—DROPPED—' : _hms(row['broadcastTs'] as int?),
                        style: dropped
                            ? AppTheme.mono(fontSize: 10, color: AppColors.danger, fontWeight: FontWeight.w700)
                            : style)),
                    DataCell(Text(_hms(row['clientReceiveTs'] as int?),  style: style)),
                    DataCell(Text(_hms(row['clientRenderedTs'] as int?), style: style)),
                    DataCell(Text(_ms(row['feedNetMs']),  style: _latStyle(row['feedNetMs']))),
                    DataCell(Text(_ms(row['backendProcMs']), style: _latStyle(row['backendProcMs']))),
                    DataCell(Text(_ms(row['wsNetMs']),    style: _latStyle(row['wsNetMs']))),
                    DataCell(Text(_ms(row['renderMs']),   style: _latStyle(row['renderMs']))),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Formatters ────────────────────────────────────────────────────────────────

  String _hms(int? ms) {
    if (ms == null || ms == 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: false);
    final h  = dt.hour.toString().padLeft(2, '0');
    final m  = dt.minute.toString().padLeft(2, '0');
    final s  = dt.second.toString().padLeft(2, '0');
    final ms3 = dt.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms3';
  }

  String _ltp(dynamic v) {
    if (v == null) return '—';
    final d = (v as num).toDouble();
    return d.toStringAsFixed(2);
  }

  String _ms(dynamic v) {
    if (v == null) return '—';
    return '${(v as num).toInt()}ms';
  }

  TextStyle _latStyle(dynamic ms) {
    if (ms == null) return AppTheme.mono(fontSize: 10, color: AppColors.textSecondary);
    final n = (ms as num).toInt();
    final color = n > 500
        ? AppColors.danger
        : n > 200
            ? AppColors.warning
            : AppColors.success;
    return AppTheme.mono(fontSize: 10, color: color, fontWeight: FontWeight.w600);
  }
}
