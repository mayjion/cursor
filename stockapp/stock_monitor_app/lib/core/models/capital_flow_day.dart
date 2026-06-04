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
      };

  CapitalFlowDay copyWith({
    double? mainNetInflow,
    double? mainNetRatio,
    double? smallNetInflow,
    double? closePrice,
    double? changePercent,
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
    );
  }
}
