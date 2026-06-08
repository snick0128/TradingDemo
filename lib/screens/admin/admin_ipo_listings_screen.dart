import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../config/backend_config.dart';
import '../../data/services/backend_api_service.dart';
import '../../theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/shared_widgets.dart';

class AdminIpoListingsScreen extends StatefulWidget {
  const AdminIpoListingsScreen({super.key});

  @override
  State<AdminIpoListingsScreen> createState() => _AdminIpoListingsScreenState();
}

class _AdminIpoListingsScreenState extends State<AdminIpoListingsScreen> {
  final _api = BackendApiService(baseUrl: BackendConfig.backendBaseUrl);
  List<Map<String, dynamic>> _ipos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await _api.getIPOs();
      setState(() { _ipos = list; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _syncFromAngelOne(BuildContext context) async {
    final sm = ScaffoldMessenger.of(context);
    sm.showSnackBar(const SnackBar(
      content: Text('Syncing IPO data from Angel One…'),
      duration: Duration(seconds: 15),
      backgroundColor: Color(0xFF1565C0),
    ));
    try {
      final res = await _api.syncIPOsFromAngelOne();
      if (!mounted) return;
      sm.clearSnackBars();
      final count = res['synced'] ?? 0;
      if (count > 0) {
        AppToast.success(context, 'Synced $count IPO${count == 1 ? '' : 's'} from Angel One.');
        _load();
      } else {
        AppToast.error(context, res['message'] as String? ?? 'No IPO data returned from Angel One.');
      }
    } catch (e) {
      if (!mounted) return;
      sm.clearSnackBars();
      AppToast.error(context, e.toString().replaceAll('BackendException: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IPO Listings'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(LucideIcons.download),
            onPressed: () => _syncFromAngelOne(context),
            tooltip: 'Sync from Angel One',
          ),
          IconButton(
            icon: const Icon(LucideIcons.plusCircle),
            onPressed: () => _showForm(context),
            tooltip: 'Add IPO',
          ),
        ],
      ),
      body: _buildBody(context),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(context),
        icon: const Icon(LucideIcons.plus),
        label: const Text('Add IPO'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return ShimmerWrapper(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 5,
          itemBuilder: (_, __) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: ShimmerCard(height: 90),
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.wifiOff, size: 40, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_ipos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.inbox, size: 48, color: AppColors.border),
            const SizedBox(height: 16),
            const Text('No IPO listings yet.',
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            const Text(
              'Tap "+ Add IPO" to create the first listing.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _ipos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _IpoTile(
        ipo: _ipos[i],
        onEdit: () => _showForm(context, existing: _ipos[i]),
        onDelete: () => _confirmDelete(context, _ipos[i]),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, Map<String, dynamic> ipo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete IPO?'),
        content:
            Text('Remove "${ipo['companyName']}" from the listings? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _api.deleteIPO(ipo['id'] as String);
      if (!mounted) return;
      AppToast.success(context, '${ipo['companyName']} deleted.');
      _load();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.toString().replaceAll('BackendException: ', ''));
    }
  }

  void _showForm(BuildContext context, {Map<String, dynamic>? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _IpoForm(
        api: _api,
        existing: existing,
        onSaved: _load,
      ),
    );
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────

class _IpoTile extends StatelessWidget {
  final Map<String, dynamic> ipo;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _IpoTile(
      {required this.ipo, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final status = (ipo['status'] as String? ?? '').toLowerCase();
    final statusColor = status == 'ongoing'
        ? AppColors.success
        : status == 'upcoming'
            ? AppColors.warning
            : AppColors.textSecondary;
    final priceMin = (ipo['priceMin'] as num?)?.toDouble() ?? 0;
    final priceMax = (ipo['priceMax'] as num?)?.toDouble() ?? 0;
    final lotSize  = (ipo['lotSize'] as num?)?.toInt() ?? 0;
    final gain     = (ipo['listingGain'] as num?)?.toDouble();

    return CustomCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(ipo['companyName'] as String? ?? '—',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge(
                    label: status.toUpperCase(),
                    color: statusColor,
                  ),
                  if (gain != null) ...[
                    const SizedBox(width: 6),
                    StatusBadge(
                      label: '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}%',
                      color: gain >= 0 ? AppColors.success : AppColors.danger,
                    ),
                  ],
                ]),
                const SizedBox(height: 4),
                Text(
                  '₹${priceMin.toStringAsFixed(0)} – ₹${priceMax.toStringAsFixed(0)}'
                  '  ·  Lot: $lotSize'
                  '  ·  ${ipo['exchange'] ?? 'NSE'}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                if (ipo['openDate'] != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Open: ${_fmtDate(ipo['openDate'])}  Close: ${_fmtDate(ipo['closeDate'])}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.pencil,
                size: 16, color: AppColors.primary),
            onPressed: onEdit,
            tooltip: 'Edit',
          ),
          IconButton(
            icon: const Icon(LucideIcons.trash2,
                size: 16, color: AppColors.danger),
            onPressed: onDelete,
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return '—';
    try {
      return DateFormat('dd MMM yy').format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString().substring(0, 10);
    }
  }
}

// ── Form (create / edit) ──────────────────────────────────────────────────────

class _IpoForm extends StatefulWidget {
  final BackendApiService api;
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;

  const _IpoForm(
      {required this.api, required this.existing, required this.onSaved});

  @override
  State<_IpoForm> createState() => _IpoFormState();
}

class _IpoFormState extends State<_IpoForm> {
  final _nameCtrl      = TextEditingController();
  final _priceMinCtrl  = TextEditingController();
  final _priceMaxCtrl  = TextEditingController();
  final _lotCtrl       = TextEditingController();
  final _openCtrl      = TextEditingController();
  final _closeCtrl     = TextEditingController();
  final _listingCtrl   = TextEditingController();
  final _listPriceCtrl = TextEditingController();
  final _listGainCtrl  = TextEditingController();
  final _subTimesCtrl  = TextEditingController();
  final _descCtrl      = TextEditingController();

  String _status   = 'upcoming';
  String _exchange = 'NSE';
  bool   _saving   = false;

  static const _statuses  = ['upcoming', 'ongoing', 'closed', 'listed'];
  static const _exchanges = ['NSE', 'BSE', 'NSE+BSE'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text      = e['companyName']     as String? ?? '';
      _priceMinCtrl.text  = (e['priceMin']  as num?)?.toString()  ?? '';
      _priceMaxCtrl.text  = (e['priceMax']  as num?)?.toString()  ?? '';
      _lotCtrl.text       = (e['lotSize']   as num?)?.toString()  ?? '';
      _openCtrl.text      = _toDateStr(e['openDate']);
      _closeCtrl.text     = _toDateStr(e['closeDate']);
      _listingCtrl.text   = _toDateStr(e['listingDate']);
      _listPriceCtrl.text = (e['listingPrice']      as num?)?.toString() ?? '';
      _listGainCtrl.text  = (e['listingGain']       as num?)?.toString() ?? '';
      _subTimesCtrl.text  = (e['subscriptionTimes'] as num?)?.toString() ?? '';
      _descCtrl.text      = e['description'] as String? ?? '';
      _status   = e['status']   as String? ?? 'upcoming';
      _exchange = e['exchange'] as String? ?? 'NSE';
    }
  }

  String _toDateStr(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _priceMinCtrl, _priceMaxCtrl, _lotCtrl,
      _openCtrl, _closeCtrl, _listingCtrl, _listPriceCtrl,
      _listGainCtrl, _subTimesCtrl, _descCtrl,
    ]) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final bot = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bot + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(isEdit ? 'Edit IPO' : 'Add IPO',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                IconButton(
                    icon: const Icon(LucideIcons.x),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 14),
            _field('Company Name *', _nameCtrl, hint: 'e.g. ABC Technologies Ltd'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field('Price Min (₹) *', _priceMinCtrl, isNum: true)),
              const SizedBox(width: 10),
              Expanded(child: _field('Price Max (₹) *', _priceMaxCtrl, isNum: true)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field('Lot Size *', _lotCtrl, isNum: true, hint: '10')),
              const SizedBox(width: 10),
              Expanded(child: _dropField('Exchange', _exchange, _exchanges,
                  (v) => setState(() => _exchange = v!))),
            ]),
            const SizedBox(height: 10),
            _dropField('Status *', _status, _statuses,
                (v) => setState(() => _status = v!)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field('Open Date *', _openCtrl, hint: 'YYYY-MM-DD')),
              const SizedBox(width: 10),
              Expanded(child: _field('Close Date *', _closeCtrl, hint: 'YYYY-MM-DD')),
            ]),
            const SizedBox(height: 10),
            _field('Listing Date', _listingCtrl, hint: 'YYYY-MM-DD (optional)'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field('Listing Price (₹)', _listPriceCtrl, isNum: true)),
              const SizedBox(width: 10),
              Expanded(child: _field('Listing Gain (%)', _listGainCtrl, isNum: true, signed: true)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field('Subscription Times', _subTimesCtrl, isNum: true, hint: 'e.g. 67.5')),
            ]),
            const SizedBox(height: 10),
            _field('Description', _descCtrl, hint: 'Brief company description (optional)', maxLines: 2),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(isEdit ? 'Update IPO' : 'Create IPO'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? hint, bool isNum = false, bool signed = false, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: isNum
              ? TextInputType.numberWithOptions(decimal: true, signed: signed)
              : TextInputType.text,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }

  Widget _dropField(String label, String value, List<String> options,
      ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: value,
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: onChanged,
          decoration: const InputDecoration(),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final name     = _nameCtrl.text.trim();
    final priceMax = double.tryParse(_priceMaxCtrl.text.trim());
    final lotSize  = int.tryParse(_lotCtrl.text.trim());
    final openDate = _openCtrl.text.trim();
    final closeDate = _closeCtrl.text.trim();

    if (name.isEmpty || priceMax == null || lotSize == null ||
        openDate.isEmpty || closeDate.isEmpty) {
      AppToast.error(context,
          'Please fill: Company Name, Price Max, Lot Size, Open Date, Close Date.');
      return;
    }

    final body = <String, dynamic>{
      'companyName': name,
      'priceMin':    double.tryParse(_priceMinCtrl.text.trim()) ?? priceMax,
      'priceMax':    priceMax,
      'lotSize':     lotSize,
      'openDate':    openDate,
      'closeDate':   closeDate,
      'status':      _status,
      'exchange':    _exchange,
      if (_listingCtrl.text.trim().isNotEmpty)
        'listingDate': _listingCtrl.text.trim(),
      if (double.tryParse(_listPriceCtrl.text.trim()) != null)
        'listingPrice': double.parse(_listPriceCtrl.text.trim()),
      if (double.tryParse(_listGainCtrl.text.trim()) != null)
        'listingGain': double.parse(_listGainCtrl.text.trim()),
      if (double.tryParse(_subTimesCtrl.text.trim()) != null)
        'subscriptionTimes': double.parse(_subTimesCtrl.text.trim()),
      if (_descCtrl.text.trim().isNotEmpty)
        'description': _descCtrl.text.trim(),
    };

    setState(() => _saving = true);
    try {
      final isEdit = widget.existing != null;
      if (isEdit) {
        await widget.api.updateIPO(widget.existing!['id'] as String, body);
      } else {
        await widget.api.createIPO(body);
      }
      if (!mounted) return;
      Navigator.pop(context);
      AppToast.success(context,
          isEdit ? 'IPO updated.' : 'IPO listing created.');
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(context,
          e.toString().replaceAll('BackendException: ', ''));
    }
  }
}
