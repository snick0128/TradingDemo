import 'package:flutter/foundation.dart';

/// Phase 1 — Full lifecycle record for a single CRUDEOIL tick.
///
/// All *Ts fields are epoch-milliseconds (wall-clock). 0 means the timestamp
/// was not available at that pipeline stage.
class TickRecord {
  const TickRecord({
    required this.tickId,
    required this.symbol,
    required this.ltp,
    required this.seq,
    required this.exchangeTs,
    required this.brokerTs,
    required this.backendReceiveTs,
    required this.hubEntryTs,
    required this.hubExitTs,
    required this.broadcastTs,
    required this.clientReceiveTs,
    required this.storeEntryTs,
    required this.storeExitTs,
    required this.paintTs,
    required this.connectionId,
    required this.source,
    required this.wasRejected,
    required this.rejectionReason,
    required this.isReplayed,
    required this.seqAdvancedBeforeRejection,
  });

  final int tickId;
  final String symbol;
  final double ltp;
  final int seq;

  // ── Pipeline timestamps ────────────────────────────────────────────────────
  /// From Angel One: tick.exchange_timestamp (or last_traded_timestamp).
  final int exchangeTs;

  /// Proxy for broker-receive ts — same as broadcastTs since we have no
  /// separate broker-receive timestamp in the current stack.
  final int brokerTs;

  /// When the backend Node.js process received the raw Angel One tick.
  final int backendReceiveTs;

  /// When liveDataHub.updateTick() was entered (marketData.js).
  final int hubEntryTs;

  /// When liveDataHub.updateTick() returned.
  final int hubExitTs;

  /// broadcastEntryTs from clientWsServer.broadcastTick (the outer `ts` field).
  final int broadcastTs;

  /// First line of LiveMarketService._onWsMessage.
  final int clientReceiveTs;

  /// Just before _latestMap[symbol] = stock.
  final int storeEntryTs;

  /// Just after _latestMap[symbol] = stock.
  final int storeExitTs;

  /// Just after _emitTickImmediate() / snapshot _emitStocks().
  final int paintTs;

  // ── Routing metadata ──────────────────────────────────────────────────────
  /// 'gen_N' where N is the wsGeneration counter in LiveMarketService.
  final String connectionId;

  /// 'live' | 'replay' | 'snapshot'
  final String source;

  // ── Phase 2 corruption flags ───────────────────────────────────────────────
  final bool wasRejected;

  /// '' | 'seq' | 'ts' | 'exchangeTs_mono' | 'stale_flag' | 'resume_gate'
  final String rejectionReason;

  /// True when the server tagged this tick with replayed=true.
  final bool isReplayed;

  /// True when _lastSeqBySymbol was advanced for this tick but the timestamp
  /// guard subsequently rejected it — the seq-before-ts-guard bug.
  final bool seqAdvancedBeforeRejection;

  Map<String, dynamic> toMap() => {
    'tickId':                     tickId,
    'symbol':                     symbol,
    'ltp':                        ltp,
    'seq':                        seq,
    'exchangeTs':                 exchangeTs,
    'brokerTs':                   brokerTs,
    'backendReceiveTs':           backendReceiveTs,
    'hubEntryTs':                 hubEntryTs,
    'hubExitTs':                  hubExitTs,
    'broadcastTs':                broadcastTs,
    'clientReceiveTs':            clientReceiveTs,
    'storeEntryTs':               storeEntryTs,
    'storeExitTs':                storeExitTs,
    'paintTs':                    paintTs,
    'connectionId':               connectionId,
    'source':                     source,
    'wasRejected':                wasRejected,
    'rejectionReason':            rejectionReason,
    'isReplayed':                 isReplayed,
    'seqAdvancedBeforeRejection': seqAdvancedBeforeRejection,
  };
}

/// Phase 1-5 tracer for the CRUDEOIL tick pipeline.
///
/// Singleton — Dart single-threaded event loop makes this safe.
/// 10,000-entry ring buffer; oldest entry overwritten when full.
class CrudeoilTickTracer {
  static final CrudeoilTickTracer instance = CrudeoilTickTracer._();
  CrudeoilTickTracer._();

  static const String _target   = 'CRUDEOIL';
  static const int    _capacity = 10000;

  final List<TickRecord?> _ring = List.filled(_capacity, null);
  int _head = 0;
  int _size = 0;
  int _nextId = 0;

  // ── Phase 2: corruption-detection state ───────────────────────────────────
  int    _lastAcceptedSeq        = 0;
  double _lastAcceptedLtp        = 0.0;
  int    _lastAcceptedExchangeTs = 0;

  // ── Phase 5: per-symbol monotonic exchangeTs tracking ─────────────────────
  final Map<String, int> _monoExchangeTs = {};

  // ──────────────────────────────────────────────────────────────────────────

  int get nextId => _nextId++;

  void record(TickRecord r) {
    _ring[_head] = r;
    _head = (_head + 1) % _capacity;
    if (_size < _capacity) _size++;
  }

  /// Phase 2 — emit corruption-detection log lines for CRUDEOIL ticks.
  ///
  /// Call this at every decision point (before AND after guards).
  /// [accepted] — whether this tick will be committed to _latestMap.
  void checkCorruption({
    required String symbol,
    required double ltp,
    required int    exchangeTs,
    required int    seq,
    required int    clientReceiveTs,
    required bool   accepted,
    required bool   isReplayed,
    required bool   seqAdvancedBeforeRejection,
  }) {
    if (symbol != _target) return;

    // TICK_DUPLICATE: same seq seen twice
    if (seq > 0 && seq == _lastAcceptedSeq) {
      debugPrint(
        '[TICK_DUPLICATE] symbol=$symbol seq=$seq ltp=$ltp '
        'lastAcceptedLtp=$_lastAcceptedLtp clientRx=$clientReceiveTs',
      );
    }

    // TICK_MISSING: non-replay seq gap of ≥ 2
    if (!isReplayed && seq > 0 && _lastAcceptedSeq > 0 &&
        seq > _lastAcceptedSeq + 1) {
      debugPrint(
        '[TICK_MISSING] symbol=$symbol '
        'expectedSeq=${_lastAcceptedSeq + 1} actualSeq=$seq '
        'missing=${seq - _lastAcceptedSeq - 1} '
        'clientRx=$clientReceiveTs',
      );
    }

    // TICK_OUT_OF_ORDER: seq went backward (non-replay)
    if (!isReplayed && seq > 0 && _lastAcceptedSeq > 0 &&
        seq < _lastAcceptedSeq) {
      debugPrint(
        '[TICK_OUT_OF_ORDER] symbol=$symbol '
        'lastSeq=$_lastAcceptedSeq receivedSeq=$seq '
        'delta=${_lastAcceptedSeq - seq} clientRx=$clientReceiveTs',
      );
    }

    if (accepted) {
      // TICK_ROLLBACK: accepted an exchangeTs older than the last accepted one
      if (_lastAcceptedLtp > 0 &&
          exchangeTs > 0 &&
          exchangeTs < _lastAcceptedExchangeTs) {
        debugPrint(
          '[TICK_ROLLBACK] symbol=$symbol '
          'newLtp=$ltp lastLtp=$_lastAcceptedLtp '
          'newExchangeTs=$exchangeTs lastExchangeTs=$_lastAcceptedExchangeTs '
          'regressionMs=${_lastAcceptedExchangeTs - exchangeTs} '
          'clientRx=$clientReceiveTs',
        );
      }
      if (seq > 0 && seq > _lastAcceptedSeq) _lastAcceptedSeq = seq;
      _lastAcceptedLtp        = ltp;
      _lastAcceptedExchangeTs = exchangeTs;
    } else {
      // TICK_STALE_REJECTED: a guard blocked this tick
      debugPrint(
        '[TICK_STALE_REJECTED] symbol=$symbol seq=$seq ltp=$ltp '
        'exchangeTs=$exchangeTs '
        'seqAdvancedBeforeRejection=$seqAdvancedBeforeRejection '
        'isReplayed=$isReplayed clientRx=$clientReceiveTs',
      );
    }
  }

  /// Phase 5 — Monotonic exchangeTs guard.
  ///
  /// Returns false (and logs [TICK_TIMESTAMP_REGRESSION]) when [exchangeTs] is
  /// strictly less than the last recorded exchangeTs for [symbol].
  bool checkMonotonicExchangeTs(String symbol, int exchangeTs) {
    if (exchangeTs <= 0) return true;
    final last = _monoExchangeTs[symbol] ?? 0;
    if (last > 0 && exchangeTs < last) {
      debugPrint(
        '[TICK_TIMESTAMP_REGRESSION] symbol=$symbol '
        'exchangeTs=$exchangeTs lastExchangeTs=$last '
        'regressionMs=${last - exchangeTs}',
      );
      return false;
    }
    _monoExchangeTs[symbol] = exchangeTs;
    return true;
  }

  /// Returns up to [maxCount] most-recent records in chronological order
  /// (oldest first).
  List<TickRecord> snapshot([int maxCount = _capacity]) {
    final count  = _size < maxCount ? _size : maxCount;
    final result = <TickRecord>[];
    for (int i = count - 1; i >= 0; i--) {
      final idx = (_head - 1 - i + _capacity) % _capacity;
      final r = _ring[idx];
      if (r != null) result.add(r);
    }
    return result;
  }

  Map<String, dynamic> stats() {
    final recent      = snapshot(500);
    final rejected    = recent.where((r) => r.wasRejected).length;
    final seqBug      = recent.where((r) => r.seqAdvancedBeforeRejection).length;
    final replayCount = recent.where((r) => r.isReplayed).length;
    return {
      'totalBuffered':              _size,
      'recentSample':               recent.length,
      'rejected':                   rejected,
      'seqAdvancedBeforeRejection': seqBug,
      'replayTicks':                replayCount,
      'lastAcceptedSeq':            _lastAcceptedSeq,
      'lastAcceptedLtp':            _lastAcceptedLtp,
      'lastAcceptedExchangeTs':     _lastAcceptedExchangeTs,
    };
  }
}
