class CapitalFlowDay {
  const CapitalFlowDay({
    required this.code,
    required this.tradeDate,
    required this.mainNetInflow,
    required this.mainNetRatio,
    this.superNetInflow = 0,
    this.bigNetInflow = 0,
    this.midNetInflow = 0,
    this.smallNetInflow = 0,
    this.closePrice,
    this.changePercent,
    this.open,
    this.high,
    this.low,
    this.volume,
  });

  final String code;
  final String tradeDate;
  final double mainNetInflow;
  final double mainNetRatio;
  final double superNetInflow;
  final double bigNetInflow;
  final double midNetInflow;
  final double smallNetInflow;
  final double? closePrice;
  final double? changePercent;
  final double? open;
  final double? high;
  final double? low;
  final double? volume;

  String storageKey() => '$code|$tradeDate';

  Map<String, dynamic> toJson() => {
        'code': code,
        'tradeDate': tradeDate,
        'mainNetInflow': mainNetInflow,
        'mainNetRatio': mainNetRatio,
        'superNetInflow': superNetInflow,
        'bigNetInflow': bigNetInflow,
        'midNetInflow': midNetInflow,
        'smallNetInflow': smallNetInflow,
        'closePrice': closePrice,
        'changePercent': changePercent,
        'open': open,
        'high': high,
        'low': low,
        'volume': volume,
      };

  CapitalFlowDay copyWith({
    double? mainNetInflow,
    double? mainNetRatio,
    double? smallNetInflow,
    double? closePrice,
    double? changePercent,
    double? open,
    double? high,
    double? low,
    double? volume,
  }) {
    return CapitalFlowDay(
      code: code,
      tradeDate: tradeDate,
      mainNetInflow: mainNetInflow ?? this.mainNetInflow,
      mainNetRatio: mainNetRatio ?? this.mainNetRatio,
      superNetInflow: superNetInflow,
      bigNetInflow: bigNetInflow,
      midNetInflow: midNetInflow,
      smallNetInflow: smallNetInflow ?? this.smallNetInflow,
      closePrice: closePrice ?? this.closePrice,
      changePercent: changePercent ?? this.changePercent,
      open: open ?? this.open,
      high: high ?? this.high,
      low: low ?? this.low,
      volume: volume ?? this.volume,
    );
  }

  factory CapitalFlowDay.fromJson(Map<String, dynamic> json) {
    return CapitalFlowDay(
      code: json['code'] as String,
      tradeDate: json['tradeDate'] as String,
      mainNetInflow: (json['mainNetInflow'] as num?)?.toDouble() ?? 0,
      mainNetRatio: (json['mainNetRatio'] as num?)?.toDouble() ?? 0,
      superNetInflow: (json['superNetInflow'] as num?)?.toDouble() ?? 0,
      bigNetInflow: (json['bigNetInflow'] as num?)?.toDouble() ?? 0,
      midNetInflow: (json['midNetInflow'] as num?)?.toDouble() ?? 0,
      smallNetInflow: (json['smallNetInflow'] as num?)?.toDouble() ?? 0,
      closePrice: (json['closePrice'] as num?)?.toDouble(),
      changePercent: (json['changePercent'] as num?)?.toDouble(),
      open: (json['open'] as num?)?.toDouble(),
      high: (json['high'] as num?)?.toDouble(),
      low: (json['low'] as num?)?.toDouble(),
      volume: (json['volume'] as num?)?.toDouble(),
    );
  }
}
