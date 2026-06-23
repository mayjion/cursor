import 'capital_flow_day.dart';

/// 日/周 K 线 OHLCV，供技术指标计算。
class StockBar {
  const StockBar({
    required this.code,
    required this.tradeDate,
    this.open,
    this.close,
    this.high,
    this.low,
    this.volume,
    this.changePercent,
    this.mainNetInflow = 0,
    this.smallNetInflow = 0,
    this.mainNetRatio = 0,
  });

  final String code;
  final String tradeDate;
  final double? open;
  final double? close;
  final double? high;
  final double? low;
  final double? volume;
  final double? changePercent;
  final double mainNetInflow;
  final double smallNetInflow;
  final double mainNetRatio;

  double? get effectiveClose => close;
  double? get effectiveHigh => high ?? close;
  double? get effectiveLow => low ?? close;
  double? get effectiveOpen => open ?? close;

  bool get isBearish {
    final o = effectiveOpen;
    final c = effectiveClose;
    if (o == null || c == null) return false;
    return c < o;
  }

  StockBar copyWith({
    double? open,
    double? close,
    double? high,
    double? low,
    double? volume,
    double? changePercent,
    double? mainNetInflow,
    double? smallNetInflow,
    double? mainNetRatio,
  }) {
    return StockBar(
      code: code,
      tradeDate: tradeDate,
      open: open ?? this.open,
      close: close ?? this.close,
      high: high ?? this.high,
      low: low ?? this.low,
      volume: volume ?? this.volume,
      changePercent: changePercent ?? this.changePercent,
      mainNetInflow: mainNetInflow ?? this.mainNetInflow,
      smallNetInflow: smallNetInflow ?? this.smallNetInflow,
      mainNetRatio: mainNetRatio ?? this.mainNetRatio,
    );
  }

  factory StockBar.fromCapitalFlowDay(CapitalFlowDay day) {
    return StockBar(
      code: day.code,
      tradeDate: day.tradeDate,
      open: day.open,
      close: day.closePrice,
      high: day.high,
      low: day.low,
      volume: day.volume,
      changePercent: day.changePercent,
      mainNetInflow: day.mainNetInflow,
      smallNetInflow: day.smallNetInflow,
      mainNetRatio: day.mainNetRatio,
    );
  }

  factory StockBar.fromKline({
    required String code,
    required String tradeDate,
    required double? open,
    required double? close,
    required double? high,
    required double? low,
    required double? volume,
    required double? changePercent,
  }) {
    return StockBar(
      code: code,
      tradeDate: tradeDate,
      open: open,
      close: close,
      high: high,
      low: low,
      volume: volume,
      changePercent: changePercent,
    );
  }
}

List<StockBar> barsFromCapitalFlowDays(List<CapitalFlowDay> days) {
  final sorted = List<CapitalFlowDay>.from(days)
    ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
  return sorted.map(StockBar.fromCapitalFlowDay).toList();
}
