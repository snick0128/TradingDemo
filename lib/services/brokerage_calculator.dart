import '../models/trading_models.dart';

/// Result of a brokerage calculation.
class BrokerageResult {
  final double tradeValue;
  final double brokerage;
  final double stt;
  final double gst;
  final double exchangeCharges;
  final double totalCharges;
  final double netPnl;

  const BrokerageResult({
    required this.tradeValue,
    required this.brokerage,
    required this.stt,
    required this.gst,
    required this.exchangeCharges,
    required this.totalCharges,
    required this.netPnl,
  });
}

/// Pure, stateless brokerage calculation function.
///
/// Rules:
/// - CNC: brokerage = min(₹20, 0.03% of tradeValue)
/// - MIS / NRML: brokerage = ₹20 flat
/// - STT: 0.1% of tradeValue
/// - GST: 18% of brokerage
/// - Exchange charges: 0.00325% of tradeValue
/// - Net P&L = tradeValue - totalCharges (simplified: gross value minus all charges)
class BrokerageCalculator {
  const BrokerageCalculator._();

  static BrokerageResult compute(double tradeValue, ProductType productType) {
    if (tradeValue <= 0) {
      return const BrokerageResult(
        tradeValue: 0,
        brokerage: 0,
        stt: 0,
        gst: 0,
        exchangeCharges: 0,
        totalCharges: 0,
        netPnl: 0,
      );
    }

    final double brokerage;
    if (productType == ProductType.nrml) {
      brokerage = (tradeValue * 0.0003).clamp(0, 20.0);
    } else {
      brokerage = 20.0;
    }

    final stt = tradeValue * 0.001;
    final gst = brokerage * 0.18;
    final exchangeCharges = tradeValue * 0.0000325;
    final totalCharges = brokerage + stt + gst + exchangeCharges;
    final netPnl = tradeValue - totalCharges;

    return BrokerageResult(
      tradeValue: tradeValue,
      brokerage: brokerage,
      stt: stt,
      gst: gst,
      exchangeCharges: exchangeCharges,
      totalCharges: totalCharges,
      netPnl: netPnl,
    );
  }
}
