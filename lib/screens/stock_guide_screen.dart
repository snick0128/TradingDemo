// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

// ─── Hardcoded course content ─────────────────────────────────────────────────

class _Video {
  final String ytId;
  final String title;
  final String channel;
  final String duration;
  final String views;
  final String category;
  final String description;

  const _Video({
    required this.ytId,
    required this.title,
    required this.channel,
    required this.duration,
    required this.views,
    required this.category,
    required this.description,
  });

  String get thumbnail => 'https://img.youtube.com/vi/$ytId/mqdefault.jpg';
  String get url => 'https://www.youtube.com/watch?v=$ytId';
}

const _kVideos = [
  _Video(
    ytId: 'p7HKvqRI_Bo',
    title: 'Stock Market Basics — Complete Beginner Guide',
    channel: 'Zerodha Varsity',
    duration: '22:15',
    views: '4.1M views',
    category: 'Basics',
    description:
        'Understand how the stock market works, what stocks are, and how to start investing in NSE & BSE.',
  ),
  _Video(
    ytId: 'JDWQ_VyjZCM',
    title: 'Options Trading Explained — NSE F&O for Beginners',
    channel: 'CA Rachana Ranade',
    duration: '35:48',
    views: '6.7M views',
    category: 'Options',
    description:
        'A complete guide to Call & Put options, strike price, expiry, OI, and how to trade Nifty options.',
  ),
  _Video(
    ytId: 'yQqgVF0Wm7c',
    title: 'MCX Gold & Crude Oil Trading Strategy',
    channel: 'Trading Fuel',
    duration: '18:30',
    views: '1.2M views',
    category: 'MCX',
    description:
        'Learn how to trade GOLD, SILVER, and CRUDEOIL on MCX — lot sizes, margins, and entry strategies.',
  ),
  _Video(
    ytId: '0uoz6Yf5QEU',
    title: 'Candlestick Patterns — Master Technical Analysis',
    channel: 'Elearnmarkets',
    duration: '28:12',
    views: '3.8M views',
    category: 'Technical Analysis',
    description:
        'From Doji to Engulfing — learn the most powerful candlestick patterns used by professional traders.',
  ),
  _Video(
    ytId: 'gXBFGrOJMD4',
    title: 'Futures Trading — What are Futures Contracts?',
    channel: 'Zerodha Varsity',
    duration: '20:44',
    views: '2.3M views',
    category: 'Futures',
    description:
        'Understand futures contracts, lot sizes, margin requirements, rollover, and how to trade Bank Nifty futures.',
  ),
  _Video(
    ytId: 'KA7g8VbS5YA',
    title: 'Support & Resistance — Trading Strategy That Works',
    channel: 'Trading with Vivek',
    duration: '24:06',
    views: '1.9M views',
    category: 'Technical Analysis',
    description:
        'Learn how to identify key support and resistance zones and use them for high-probability trade setups.',
  ),
  _Video(
    ytId: 'Ypj6n4lsTrg',
    title: 'Risk Management — How to Never Blow Your Account',
    channel: 'Power of Stocks',
    duration: '16:55',
    views: '2.1M views',
    category: 'Risk',
    description:
        'Position sizing, stop-loss placement, risk-reward ratio, and the golden rules every trader must follow.',
  ),
  _Video(
    ytId: 'WqVoqFNEVnI',
    title: 'Intraday Trading Strategy — MIS Orders Explained',
    channel: 'Nitin Bhatia',
    duration: '30:22',
    views: '3.4M views',
    category: 'Basics',
    description:
        'Everything about intraday (MIS) trading — order types, leverage, squaring off, and common mistakes.',
  ),
  _Video(
    ytId: 'M3EhxFpJQag',
    title: 'Option Chain Analysis — Reading OI & PCR',
    channel: 'CA Rachana Ranade',
    duration: '19:18',
    views: '2.8M views',
    category: 'Options',
    description:
        'Learn to read an options chain — open interest, put-call ratio, max pain, and how the market makers think.',
  ),
  _Video(
    ytId: 'sFkB2ZCmgLQ',
    title: 'MCX Commodity Market — Silver & Natural Gas Trading',
    channel: 'Commodity Samachar',
    duration: '14:45',
    views: '890K views',
    category: 'MCX',
    description:
        'Trading SILVER and NATURALGAS on MCX — seasonality, global cues, technical levels, and lot sizes.',
  ),
  _Video(
    ytId: 'bX3sZ_rFSMY',
    title: 'Moving Averages — EMA & SMA Strategy',
    channel: 'Elearnmarkets',
    duration: '21:33',
    views: '1.6M views',
    category: 'Technical Analysis',
    description:
        'How to use 9 EMA, 20 EMA, and 200 SMA for trend following and crossover signals in any market.',
  ),
  _Video(
    ytId: 'FfQOSQYDjH0',
    title: 'Banknifty Weekly Options — Scalping Strategy',
    channel: 'Trading with Vivek',
    duration: '26:10',
    views: '1.1M views',
    category: 'Options',
    description:
        'A live strategy for trading weekly Banknifty options — premium decay, theta, and entry/exit timing.',
  ),
];

const _kCategories = [
  'All',
  'Basics',
  'Options',
  'Futures',
  'MCX',
  'Technical Analysis',
  'Risk',
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class StockGuideScreen extends StatefulWidget {
  const StockGuideScreen({super.key});

  @override
  State<StockGuideScreen> createState() => _StockGuideScreenState();
}

class _StockGuideScreenState extends State<StockGuideScreen> {
  String _selectedCategory = 'All';

  List<_Video> get _filtered => _selectedCategory == 'All'
      ? _kVideos
      : _kVideos.where((v) => v.category == _selectedCategory).toList();

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverToBoxAdapter(child: _buildHeroBanner()),
          SliverToBoxAdapter(child: _buildCategoryBar()),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: isWide ? _buildWideGrid() : _buildNarrowList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Color(0xFF0D0D0D)),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Courses',
        style: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF0D0D0D),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFFEEEEEE)),
      ),
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      height: 130,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF283593)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // Background decoration circles
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            right: 40,
            bottom: -30,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD600),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'FREE',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0D0D0D),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_kVideos.length} Expert Videos',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Learn to Trade\nLike a Pro',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Stocks · Options · Futures · MCX',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBar() {
    return SizedBox(
      height: 52,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: _kCategories.length,
        itemBuilder: (context, i) {
          final cat = _kCategories[i];
          final selected = cat == _selectedCategory;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF1565C0) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF1565C0)
                      : const Color(0xFFE0E0E0),
                ),
              ),
              child: Text(
                cat,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : const Color(0xFF555555),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWideGrid() {
    final videos = _filtered;
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (context, i) => _VideoCard(video: videos[i]),
        childCount: videos.length,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.55,
      ),
    );
  }

  Widget _buildNarrowList() {
    final videos = _filtered;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _VideoCard(video: videos[i]),
        ),
        childCount: videos.length,
      ),
    );
  }
}

// ─── Video Card ───────────────────────────────────────────────────────────────

class _VideoCard extends StatefulWidget {
  final _Video video;
  const _VideoCard({required this.video});

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => html.window.open(widget.video.url, '_blank'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: _hovered ? 0.10 : 0.05),
                blurRadius: _hovered ? 16 : 8,
                offset: Offset(0, _hovered ? 6 : 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                child: Stack(
                  children: [
                    Image.network(
                      widget.video.thumbnail,
                      width: double.infinity,
                      height: 130,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 130,
                        color: const Color(0xFF1A237E),
                        child: const Center(
                          child: Icon(LucideIcons.playCircle,
                              size: 40, color: Colors.white54),
                        ),
                      ),
                    ),
                    // Play overlay
                    Positioned.fill(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: _hovered ? 1.0 : 0.0,
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.35),
                          child: const Center(
                            child: Icon(
                              Icons.play_circle_fill,
                              size: 44,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Duration badge
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          widget.video.duration,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // Category badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _categoryColor(widget.video.category),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          widget.video.category,
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.video.title,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0D0D0D),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.video.description,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFF757575),
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(
                            LucideIcons.youtube,
                            size: 12,
                            color: Color(0xFFD50000),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              widget.video.channel,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF555555),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            widget.video.views,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: const Color(0xFF9E9E9E),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _categoryColor(String cat) {
  switch (cat) {
    case 'Options':
      return const Color(0xFF1565C0);
    case 'Futures':
      return const Color(0xFF6A1B9A);
    case 'MCX':
      return const Color(0xFFE65100);
    case 'Technical Analysis':
      return const Color(0xFF00695C);
    case 'Risk':
      return const Color(0xFFD50000);
    default:
      return const Color(0xFF37474F);
  }
}
