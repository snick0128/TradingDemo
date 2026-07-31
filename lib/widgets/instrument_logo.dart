import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/trading_models.dart';
import '../services/instrument_logo_service.dart';
import '../services/logo_cache_manager.dart';
import 'shared_widgets.dart' show SymbolAvatar;

/// Renders an instrument's icon — a bundled PNG for MCX commodity futures,
/// otherwise a company logo (SVG, from the Indian Listed Company Logos CDN)
/// — falling back to an initials avatar while loading, on error, or when
/// nothing is resolvable. Indices, currencies, and unlisted tickers all
/// resolve to null and never touch the network.
///
/// Drop-in replacement for [SymbolAvatar] (or any bespoke per-symbol avatar)
/// anywhere an instrument icon is shown: watchlist, search, holdings,
/// positions, order book, portfolio, instrument details.
class InstrumentLogo extends StatefulWidget {
  final String symbol;
  final String exchange;
  final InstrumentType? instrumentType;
  final double size;

  /// Overrides the default [SymbolAvatar] fallback — use this to keep a
  /// screen's existing bespoke placeholder (e.g. an exchange-colored square)
  /// instead of the generic circular initials avatar.
  final WidgetBuilder? fallbackBuilder;

  const InstrumentLogo({
    super.key,
    required this.symbol,
    this.exchange = 'NSE',
    this.instrumentType,
    this.size = 36,
    this.fallbackBuilder,
  });

  factory InstrumentLogo.forStock(
    Stock stock, {
    Key? key,
    double size = 36,
    WidgetBuilder? fallbackBuilder,
  }) {
    return InstrumentLogo(
      key: key,
      symbol: stock.symbol,
      exchange: stock.exchange,
      instrumentType: stock.instrumentType,
      size: size,
      fallbackBuilder: fallbackBuilder,
    );
  }

  @override
  State<InstrumentLogo> createState() => _InstrumentLogoState();
}

class _InstrumentLogoState extends State<InstrumentLogo> {
  final _service = InstrumentLogoService.instance;
  String? _assetPath;
  String? _url;

  @override
  void initState() {
    super.initState();
    _resolve();
    if (_assetPath == null && !_service.isLoaded) {
      _service.addListener(_onMappingLoaded);
      _service.ensureLoaded();
    }
  }

  @override
  void didUpdateWidget(covariant InstrumentLogo old) {
    super.didUpdateWidget(old);
    if (old.symbol != widget.symbol ||
        old.exchange != widget.exchange ||
        old.instrumentType != widget.instrumentType) {
      _resolve();
    }
  }

  void _onMappingLoaded() {
    _service.removeListener(_onMappingLoaded);
    if (mounted) setState(_resolve);
  }

  void _resolve() {
    // Bundled commodity assets are synchronous and take priority — no need
    // to wait on (or even trigger) the network logo mapping for MCX symbols.
    _assetPath = _service.localAssetForSymbol(widget.symbol);
    _url = _assetPath == null
        ? _service.logoUrlForSymbol(
            widget.symbol,
            exchange: widget.exchange,
            instrumentType: widget.instrumentType,
          )
        : null;
  }

  @override
  void dispose() {
    _service.removeListener(_onMappingLoaded);
    super.dispose();
  }

  Widget _fallback(BuildContext context) {
    final builder = widget.fallbackBuilder;
    if (builder != null) return builder(context);
    return SymbolAvatar(symbol: widget.symbol, size: widget.size);
  }

  @override
  Widget build(BuildContext context) {
    final assetPath = _assetPath;
    if (assetPath != null) {
      return Image.asset(
        assetPath,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _fallback(context),
      );
    }

    final url = _url;
    if (url == null) return _fallback(context);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: FutureBuilder<Uint8List?>(
        future: LogoCacheManager.instance.loadImageBytes(url),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _fallback(context);
          }
          final bytes = snapshot.data;
          if (bytes == null) return _fallback(context);
          return SvgPicture.memory(
            bytes,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            placeholderBuilder: (_) => _fallback(context),
            errorBuilder: (context, error, stackTrace) => _fallback(context),
          );
        },
      ),
    );
  }
}
