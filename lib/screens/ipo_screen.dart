import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../app/app_scope.dart';
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

  Future<void> _showApplyDialog(IPO ipo) async {
    final lotsController = TextEditingController(text: '1');
    final bidController = TextEditingController(
      text: ipo.priceMax.toStringAsFixed(0),
    );
    String selectedUpi = 'user@okaxis';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apply for ${ipo.companyName}'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Price Band: ₹${ipo.priceMin.toStringAsFixed(0)} – ₹${ipo.priceMax.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Bid Price',
                  hintText: ipo.priceMax.toStringAsFixed(0),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedUpi,
                decoration: const InputDecoration(labelText: 'UPI ID'),
                items: const [
                  DropdownMenuItem(
                    value: 'user@okaxis',
                    child: Text('user@okaxis'),
                  ),
                  DropdownMenuItem(value: 'user@ybl', child: Text('user@ybl')),
                  DropdownMenuItem(
                    value: 'user@paytm',
                    child: Text('user@paytm'),
                  ),
                ],
                onChanged: (v) => setDialogState(() => selectedUpi = v!),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final lots = int.tryParse(lotsController.text.trim()) ?? 0;
              final bid = double.tryParse(bidController.text.trim()) ?? 0;

              if (lots <= 0) {
                AppToast.error(context, 'Please enter valid lots.');
                return;
              }
              if (bid <= 0) {
                AppToast.error(context, 'Please enter valid bid price.');
                return;
              }

              try {
                await _applyForIpo(
                  ipo: ipo,
                  lots: lots,
                  bidPrice: bid,
                  upiId: selectedUpi,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (!mounted) return;
                AppToast.success(
                  context,
                  'IPO application submitted. 10% amount blocked.',
                );
              } catch (e) {
                if (!mounted) return;
                AppToast.error(
                  context,
                  e.toString().replaceAll('Exception: ', ''),
                );
              }
            },
            child: const Text('Submit Application'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyForIpo({
    required IPO ipo,
    required int lots,
    required double bidPrice,
    required String upiId,
  }) async {
    final app = AppScope.of(context);
    final sessionUser = app.notifier?.user;
    if (sessionUser == null) {
      throw Exception('Please login again.');
    }

    final db = app.firestoreService.raw;
    final userRef = db.collection('users').doc(sessionUser.uid);
    final orderRef = db.collection('ipo_orders').doc();

    final batchPrice = bidPrice * ipo.lotSize * lots;
    final blockedAmount = batchPrice * 0.10;

    await db.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        throw Exception('User account not found.');
      }
      final userData = userSnap.data()!;
      final balance =
          ((userData['balance'] as num?) ??
                  (userData['available_balance'] as num?) ??
                  0)
              .toDouble();
      if (balance < blockedAmount) {
        throw Exception(
          'Insufficient balance. Need ₹${blockedAmount.toStringAsFixed(2)} to apply.',
        );
      }
      final newBalance = balance - blockedAmount;

      tx.update(userRef, {
        'balance': newBalance,
        'available_balance': newBalance,
        'updatedAt': Timestamp.now(),
      });

      tx.set(orderRef, {
        'userId': sessionUser.uid,
        'userName': sessionUser.name,
        'ipoId': ipo.id,
        'companyName': ipo.companyName,
        'lots': lots,
        'lotSize': ipo.lotSize,
        'bidPrice': bidPrice,
        'batchPrice': batchPrice,
        'blockedAmount': blockedAmount,
        'cutAmount': 0.0,
        'refundAmount': 0.0,
        // Used by admin approval formula: profit on original batch value.
        'listingGainPercent': ipo.listingGain ?? 0.0,
        'upiId': upiId,
        'status': 'PENDING',
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });
    });
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
      body = ShimmerWrapper(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: 5,
          separatorBuilder: (_, __) => const SizedBox(height: 0),
          itemBuilder: (_, __) => const ShimmerCard(height: 130),
        ),
      );
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.wifiOff,
              color: AppColors.textSecondary,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              'Failed to load IPOs',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _error!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
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
                  onApply: _showApplyDialog,
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
  final Future<void> Function(IPO)? onApply;

  const _IPOList({required this.ipos, required this.type, this.onApply});

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
      itemBuilder: (context, index) =>
          _IPOCard(ipo: ipos[index], type: type, onApply: onApply),
    );
  }
}

// ─── IPO Card ─────────────────────────────────────────────────────────────────

class _IPOCard extends StatelessWidget {
  final IPO ipo;
  final IPOStatus type;
  final Future<void> Function(IPO)? onApply;

  const _IPOCard({required this.ipo, required this.type, this.onApply});

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
                onPressed: onApply == null ? null : () => onApply!(ipo),
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
}
