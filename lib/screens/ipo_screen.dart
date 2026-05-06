import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../data/services/backend_api_service.dart';
import '../models/trading_models.dart';
import '../theme.dart';
import '../widgets/app_dialog.dart';
import '../widgets/shared_widgets.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class IPOScreen extends StatefulWidget {
  final bool showAppBar;
  const IPOScreen({super.key, this.showAppBar = true});

  @override
  State<IPOScreen> createState() => _IPOScreenState();
}

class _IPOScreenState extends State<IPOScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = BackendApiService();

  List<IPO> _ipoFeed = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadIPOs();
  }

  Future<void> _loadIPOs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _api.getIPOs();
      setState(() {
        _ipoFeed = raw.map(_parseIPO).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  IPO _parseIPO(Map<String, dynamic> m) {
    IPOStatus parseStatus(String s) {
      switch (s) {
        case 'upcoming':
          return IPOStatus.upcoming;
        case 'ongoing':
          return IPOStatus.ongoing;
        case 'closed':
          return IPOStatus.closed;
        case 'listed':
        default:
          return IPOStatus.listed;
      }
    }

    return IPO(
      id: m['id'] as String,
      companyName: m['companyName'] as String,
      priceMin: (m['priceMin'] as num).toDouble(),
      priceMax: (m['priceMax'] as num).toDouble(),
      openDate: DateTime.parse(m['openDate'] as String),
      closeDate: DateTime.parse(m['closeDate'] as String),
      listingDate: m['listingDate'] != null
          ? DateTime.parse(m['listingDate'] as String)
          : null,
      status: parseStatus(m['status'] as String),
      lotSize: (m['lotSize'] as num).toInt(),
      listingPrice: m['listingPrice'] != null
          ? (m['listingPrice'] as num).toDouble()
          : null,
      listingGain: m['listingGain'] != null
          ? (m['listingGain'] as num).toDouble()
          : null,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.wifiOff, color: AppColors.textSecondary, size: 40),
            const SizedBox(height: 12),
            Text(
              'Failed to load IPOs',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadIPOs,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    } else {
      body = Column(
        children: [
          Container(
            color: AppColors.surface,
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Upcoming'),
                Tab(text: 'Ongoing'),
                Tab(text: 'Closed / Listed'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _IPOList(
                  ipos: _ipoFeed
                      .where((i) => i.status == IPOStatus.upcoming)
                      .toList(),
                  type: IPOStatus.upcoming,
                ),
                _IPOList(
                  ipos: _ipoFeed
                      .where((i) => i.status == IPOStatus.ongoing)
                      .toList(),
                  type: IPOStatus.ongoing,
                ),
                _IPOList(
                  ipos: _ipoFeed
                      .where(
                        (i) =>
                            i.status == IPOStatus.closed ||
                            i.status == IPOStatus.listed,
                      )
                      .toList(),
                  type: IPOStatus.listed,
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (!widget.showAppBar) {
      return Scaffold(body: body);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('IPO'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            tooltip: 'Refresh',
            onPressed: _loadIPOs,
          ),
        ],
      ),
      body: body,
    );
  }
}

// ─── IPO List ─────────────────────────────────────────────────────────────────

class _IPOList extends StatelessWidget {
  final List<IPO> ipos;
  final IPOStatus type;

  const _IPOList({required this.ipos, required this.type});

  @override
  Widget build(BuildContext context) {
    if (ipos.isEmpty) {
      return const Center(
        child: Text(
          'No IPOs available',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: ipos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _IPOCard(ipo: ipos[index], type: type),
    );
  }
}

// ─── IPO Card ─────────────────────────────────────────────────────────────────

class _IPOCard extends StatelessWidget {
  final IPO ipo;
  final IPOStatus type;

  const _IPOCard({required this.ipo, required this.type});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM yyyy');
    final isListed = type == IPOStatus.listed || type == IPOStatus.closed;
    final isOngoing = type == IPOStatus.ongoing;

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ipo.companyName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              StatusBadge(
                label: ipo.status.name,
                color: isListed
                    ? AppColors.textSecondary
                    : isOngoing
                    ? AppColors.success
                    : AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _info(
                'Price Band',
                '₹${ipo.priceMin.toStringAsFixed(0)} – ₹${ipo.priceMax.toStringAsFixed(0)}',
              ),
              _info('Open Date', fmt.format(ipo.openDate)),
              _info('Close Date', fmt.format(ipo.closeDate)),
              _info('Lot Size', '${ipo.lotSize} shares'),
              if (ipo.listingDate != null)
                _info('Listing Date', fmt.format(ipo.listingDate!)),
            ],
          ),
          if (isListed && ipo.listingPrice != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                _info(
                  'Listing Price',
                  '₹${ipo.listingPrice!.toStringAsFixed(2)}',
                ),
                const SizedBox(width: 24),
                if (ipo.listingGain != null) _gainBadge(ipo.listingGain!),
              ],
            ),
          ],
          if (isOngoing) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showApplyDialog(context, ipo),
                icon: const Icon(LucideIcons.checkCircle, size: 16),
                label: const Text('Apply'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _info(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _gainBadge(double gain) {
    final isPos = gain >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (isPos ? AppColors.success : AppColors.danger).withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${isPos ? '+' : ''}${gain.toStringAsFixed(2)}% gain',
        style: TextStyle(
          color: isPos ? AppColors.success : AppColors.danger,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  void _showApplyDialog(BuildContext context, IPO ipo) {
    final lotsController = TextEditingController(text: '1');
    final bidController = TextEditingController(
      text: ipo.priceMax.toStringAsFixed(0),
    );
    String selectedUpi = 'user@okaxis';

    AppDialog.confirm(
      context,
      title: 'Apply for ${ipo.companyName}',
      message: 'Price Band: ₹${ipo.priceMin.toStringAsFixed(0)} – ₹${ipo.priceMax.toStringAsFixed(0)}',
      body: StatefulBuilder(
        builder: (ctx, setDialogState) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: lotsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of Lots',
                hintText: '1',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bidController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Bid Price',
                hintText: ipo.priceMax.toStringAsFixed(0),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectedUpi,
              decoration: const InputDecoration(labelText: 'UPI ID'),
              items: const [
                DropdownMenuItem(value: 'user@okaxis', child: Text('user@okaxis')),
                DropdownMenuItem(value: 'user@ybl', child: Text('user@ybl')),
                DropdownMenuItem(value: 'user@paytm', child: Text('user@paytm')),
              ],
              onChanged: (v) => setDialogState(() => selectedUpi = v!),
            ),
          ],
        ),
      ),
      confirmLabel: 'Submit Application',
      onConfirm: () {
        AppToast.success(context, 'Applied for ${ipo.companyName} via $selectedUpi');
      },
    );
  }
}
