class EtfInfo {
  const EtfInfo({
    required this.code,
    required this.name,
    this.indexCode = '',
    this.indexName = '',
    this.totalShare,
    /// 东财 RPT_FUND_ETFLIST 的 DEC_NAV，实际为基金规模（亿元）。
    this.scaleYi,
    this.change1w,
    this.change1m,
    this.change3m,
    this.changeYtd,
    this.category = '',
  });

  final String code;
  final String name;
  final String indexCode;
  final String indexName;
  final double? totalShare;
  /// 基金规模，单位：亿元。
  final double? scaleYi;
  final double? change1w;
  final double? change1m;
  final double? change3m;
  final double? changeYtd;
  final String category;
}

class EtfSharePoint {
  const EtfSharePoint({
    required this.date,
    required this.totalShare,
    this.applyShare,
    this.redeemShare,
    this.shareChangeQ,
    this.netShareChange,
    this.closePrice,
    this.netAmount,
  });

  final String date;
  final double totalShare;
  /// 期间申购（季报口径，多数交易日为空）
  final double? applyShare;
  /// 期间赎回（季报口径，多数交易日为空）
  final double? redeemShare;
  /// 东财 SHARE_CHANGE_Q：季初至今累计份额变动（日频也会更新）
  final double? shareChangeQ;
  /// 日净申购代理（当日总份额 − 前一日）；季报行则为期间申购−赎回
  final double? netShareChange;
  final double? closePrice;
  /// 净申购金额代理 = netShareChange × closePrice
  final double? netAmount;

  /// 是否为季报披露行（有期间申购/赎回）。
  bool get isQuarterReport =>
      applyShare != null || redeemShare != null;

  /// 季报净申购：优先 申购−赎回，其次 SHARE_CHANGE_Q / netShareChange。
  double? get quarterNetShare {
    if (applyShare != null || redeemShare != null) {
      return (applyShare ?? 0) - (redeemShare ?? 0);
    }
    return shareChangeQ ?? netShareChange;
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'totalShare': totalShare,
        'applyShare': applyShare,
        'redeemShare': redeemShare,
        'shareChangeQ': shareChangeQ,
        'netShareChange': netShareChange,
        'closePrice': closePrice,
        'netAmount': netAmount,
      };

  factory EtfSharePoint.fromJson(Map<String, dynamic> json) {
    return EtfSharePoint(
      date: json['date'] as String? ?? '',
      totalShare: (json['totalShare'] as num?)?.toDouble() ?? 0,
      applyShare: (json['applyShare'] as num?)?.toDouble(),
      redeemShare: (json['redeemShare'] as num?)?.toDouble(),
      shareChangeQ: (json['shareChangeQ'] as num?)?.toDouble(),
      netShareChange: (json['netShareChange'] as num?)?.toDouble(),
      closePrice: (json['closePrice'] as num?)?.toDouble(),
      netAmount: (json['netAmount'] as num?)?.toDouble(),
    );
  }
}

/// 模型特征：以季报期间申购/赎回为主。
class EtfFlowFeatures {
  const EtfFlowFeatures({
    this.burstRatio = 1,
    this.persistRatio = 0.5,
    this.cumIntensity = 0,
    this.latestQuarterNet,
    this.last4QuartersNet,
    this.last8QuartersNet,
    this.inQuarterNetToDate,
    this.quarterCount = 0,
    this.usedDailyFallback = false,
    this.priceMomentum20d,
    // 兼容旧缓存字段名
    this.net20d,
    this.net60d,
    this.net120d,
  });

  /// 最近一季净申购 / 此前若干季平均净申购绝对值
  final double burstRatio;
  /// 近 N 季净申购为正的季度占比
  final double persistRatio;
  /// 近 4 季累计净申购 / 期初份额
  final double cumIntensity;
  final double? latestQuarterNet;
  final double? last4QuartersNet;
  final double? last8QuartersNet;
  /// 本季至今（日频 SHARE_CHANGE_Q），辅助
  final double? inQuarterNetToDate;
  final int quarterCount;
  final bool usedDailyFallback;
  final double? priceMomentum20d;
  final double? net20d;
  final double? net60d;
  final double? net120d;
}

class EtfBuyScore {
  const EtfBuyScore({
    required this.code,
    required this.buyIndex,
    this.label = '中性',
    this.reasons = const [],
    this.features = const EtfFlowFeatures(),
    this.signals = const [],
    this.signalWinRate,
    this.signalWinHits = 0,
    this.signalWinSamples = 0,
    this.historySupportsAdd = false,
    this.addFitness = 0,
    this.ruleLines = const [],
    this.updatedAt,
  });

  final String code;
  final double buyIndex;
  final String label;
  final List<String> reasons;
  final EtfFlowFeatures features;
  final List<EtfFlowSignal> signals;
  /// 全池统一规则回测胜率（非单只）
  final double? signalWinRate;
  final int signalWinHits;
  final int signalWinSamples;
  final bool historySupportsAdd;
  /// 当下加仓适配度 0~100，列表排序主依据
  final double addFitness;
  /// 当期规则说明行（含底条件/辅助/全池胜率）
  final List<String> ruleLines;
  final DateTime? updatedAt;

  EtfFlowSignal? get latestAdd {
    for (final s in signals) {
      if (s.type == EtfFlowSignalType.add && s.isActionable) return s;
    }
    return null;
  }

  EtfFlowSignal? get latestRisk {
    for (final s in signals) {
      if (s.type == EtfFlowSignalType.risk && s.isActionable) return s;
    }
    return null;
  }

  EtfBuyScore copyWith({
    double? buyIndex,
    String? label,
    List<String>? reasons,
    List<EtfFlowSignal>? signals,
    double? signalWinRate,
    int? signalWinHits,
    int? signalWinSamples,
    bool? historySupportsAdd,
    double? addFitness,
    List<String>? ruleLines,
    bool replaceSignalMeta = false,
  }) {
    return EtfBuyScore(
      code: code,
      buyIndex: buyIndex ?? this.buyIndex,
      label: label ?? this.label,
      reasons: reasons ?? this.reasons,
      features: features,
      signals: signals ?? this.signals,
      signalWinRate: replaceSignalMeta
          ? signalWinRate
          : (signalWinRate ?? this.signalWinRate),
      signalWinHits: signalWinHits ?? this.signalWinHits,
      signalWinSamples: signalWinSamples ?? this.signalWinSamples,
      historySupportsAdd: historySupportsAdd ?? this.historySupportsAdd,
      addFitness: addFitness ?? this.addFitness,
      ruleLines: ruleLines ?? this.ruleLines,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'buyIndex': buyIndex,
        'label': label,
        'reasons': reasons,
        'updatedAt': updatedAt?.toIso8601String(),
        'burstRatio': features.burstRatio,
        'persistRatio': features.persistRatio,
        'cumIntensity': features.cumIntensity,
        'latestQuarterNet': features.latestQuarterNet,
        'last4QuartersNet': features.last4QuartersNet,
        'last8QuartersNet': features.last8QuartersNet,
        'inQuarterNetToDate': features.inQuarterNetToDate,
        'quarterCount': features.quarterCount,
        'usedDailyFallback': features.usedDailyFallback,
        'net20d': features.net20d,
        'net60d': features.net60d,
        'net120d': features.net120d,
        'priceMomentum20d': features.priceMomentum20d,
        'signalWinRate': signalWinRate,
        'signalWinHits': signalWinHits,
        'signalWinSamples': signalWinSamples,
        'historySupportsAdd': historySupportsAdd,
        'addFitness': addFitness,
        'ruleLines': ruleLines,
        'signals': signals.map((e) => e.toJson()).toList(),
      };

  factory EtfBuyScore.fromJson(Map<String, dynamic> json) {
    return EtfBuyScore(
      code: json['code'] as String,
      buyIndex: (json['buyIndex'] as num?)?.toDouble() ?? 50,
      label: json['label'] as String? ?? '中性',
      reasons: (json['reasons'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
      features: EtfFlowFeatures(
        burstRatio: (json['burstRatio'] as num?)?.toDouble() ?? 1,
        persistRatio: (json['persistRatio'] as num?)?.toDouble() ?? 0.5,
        cumIntensity: (json['cumIntensity'] as num?)?.toDouble() ?? 0,
        latestQuarterNet: (json['latestQuarterNet'] as num?)?.toDouble(),
        last4QuartersNet: (json['last4QuartersNet'] as num?)?.toDouble(),
        last8QuartersNet: (json['last8QuartersNet'] as num?)?.toDouble(),
        inQuarterNetToDate: (json['inQuarterNetToDate'] as num?)?.toDouble(),
        quarterCount: (json['quarterCount'] as num?)?.toInt() ?? 0,
        usedDailyFallback: json['usedDailyFallback'] as bool? ?? false,
        net20d: (json['net20d'] as num?)?.toDouble(),
        net60d: (json['net60d'] as num?)?.toDouble(),
        net120d: (json['net120d'] as num?)?.toDouble(),
        priceMomentum20d: (json['priceMomentum20d'] as num?)?.toDouble(),
      ),
      signalWinRate: (json['signalWinRate'] as num?)?.toDouble(),
      signalWinHits: (json['signalWinHits'] as num?)?.toInt() ?? 0,
      signalWinSamples: (json['signalWinSamples'] as num?)?.toInt() ?? 0,
      historySupportsAdd: json['historySupportsAdd'] as bool? ?? false,
      addFitness: (json['addFitness'] as num?)?.toDouble() ?? 0,
      ruleLines: (json['ruleLines'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      signals: (json['signals'] as List<dynamic>?)
              ?.map((e) => EtfFlowSignal.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ))
              .toList() ??
          const [],
    );
  }
}

enum EtfFlowSignalType { add, risk }

enum AddAuxKind {
  prevNetMax,
  pricePercentileMax,
  mom20Min,
  mom20Max,
  mom60Max,
  qoqMultipleMin,
  qoqMultipleMax,
  noFollowOnRisk,
  persist4Max,
  netIntensityMin,
  burstVsPrior4Min,
}

/// 可解释辅助加仓条件（由全池胜/负样本挖掘）。
class AddAuxCondition {
  const AddAuxCondition({
    required this.kind,
    this.p1,
    this.p2,
  });

  final AddAuxKind kind;
  final double? p1;
  final double? p2;

  String get labelZh {
    switch (kind) {
      case AddAuxKind.prevNetMax:
        return '上一季净申购≤${_fmtNum(p1 ?? 0)}';
      case AddAuxKind.pricePercentileMax:
        return '价位分位≤${((p1 ?? 0.5) * 100).toStringAsFixed(0)}%（相对低位）';
      case AddAuxKind.mom20Min:
        return '前20日涨跌≥${_pct(p1 ?? 0)}';
      case AddAuxKind.mom20Max:
        return '前20日涨跌≤${_pct(p1 ?? 0.15)}（未过热）';
      case AddAuxKind.mom60Max:
        return '前60日涨跌≤${_pct(p1 ?? 0.25)}';
      case AddAuxKind.qoqMultipleMin:
        return '环比倍数≥${(p1 ?? 2.5).toStringAsFixed(1)}';
      case AddAuxKind.qoqMultipleMax:
        return '环比倍数≤${(p1 ?? 50).toStringAsFixed(0)}（排除失真巨倍）';
      case AddAuxKind.noFollowOnRisk:
        return '下一季未再≥2倍跟风放大';
      case AddAuxKind.persist4Max:
        return '前4季正净申购占比≤${((p1 ?? 0.5) * 100).toStringAsFixed(0)}%';
      case AddAuxKind.netIntensityMin:
        return '净申购占份额≥${_pct(p1 ?? 0.01)}';
      case AddAuxKind.burstVsPrior4Min:
        return '相对前4季均值突发≥${(p1 ?? 2).toStringAsFixed(1)}倍';
    }
  }

  static String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
  static String _fmtNum(double v) {
    if (v.abs() >= 1000) return v.toStringAsFixed(0);
    if (v.abs() >= 10) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }

  bool matchesSample({
    required double prevNet,
    required double qoqMultiple,
    required double persist4,
    required bool followOnRisk,
    double? mom20,
    double? mom60,
    double? pricePercentile,
    double? netIntensity,
    double? burstVsPrior4,
  }) {
    switch (kind) {
      case AddAuxKind.prevNetMax:
        return prevNet <= (p1 ?? 0);
      case AddAuxKind.pricePercentileMax:
        if (pricePercentile == null) return false;
        return pricePercentile <= (p1 ?? 0.5);
      case AddAuxKind.mom20Min:
        if (mom20 == null) return false;
        return mom20 >= (p1 ?? 0);
      case AddAuxKind.mom20Max:
        if (mom20 == null) return false;
        return mom20 <= (p1 ?? 0.15);
      case AddAuxKind.mom60Max:
        if (mom60 == null) return false;
        return mom60 <= (p1 ?? 0.25);
      case AddAuxKind.qoqMultipleMin:
        return qoqMultiple >= (p1 ?? 2.5);
      case AddAuxKind.qoqMultipleMax:
        return qoqMultiple <= (p1 ?? 50);
      case AddAuxKind.noFollowOnRisk:
        return !followOnRisk;
      case AddAuxKind.persist4Max:
        return persist4 <= (p1 ?? 0.5);
      case AddAuxKind.netIntensityMin:
        if (netIntensity == null) return false;
        return netIntensity >= (p1 ?? 0.01);
      case AddAuxKind.burstVsPrior4Min:
        if (burstVsPrior4 == null) return false;
        return burstVsPrior4 >= (p1 ?? 2);
    }
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'p1': p1,
        'p2': p2,
      };

  factory AddAuxCondition.fromJson(Map<String, dynamic> json) {
    final name = json['kind'] as String? ?? '';
    final kind = AddAuxKind.values.firstWhere(
      (e) => e.name == name,
      orElse: () => AddAuxKind.qoqMultipleMin,
    );
    return AddAuxCondition(
      kind: kind,
      p1: (json['p1'] as num?)?.toDouble(),
      p2: (json['p2'] as num?)?.toDouble(),
    );
  }
}

/// 全池统一加仓规则包（底条件固定 + 辅助条件 + 全池回测胜率）。
class AddRulePack {
  const AddRulePack({
    this.auxConditions = const [],
    this.winRate,
    this.winHits = 0,
    this.winSamples = 0,
    this.validated = false,
    this.updatedAt,
  });

  static const empty = AddRulePack();

  /// 底条件文案（固定）
  static const baseRuleZh =
      '当季净申购≥上一季的2倍（上季须为正），且净申购占份额≥0.3%';
  static const winDefZh =
      '预测点后约一季涨幅>15%计胜（全池实测>30%过稀，约7%，无法稳定形成>80%规则；'
      '15%仍处收益上沿）。完整规则须在全部自选ETF不同历史阶段回测胜率>80%才用于当下预测';

  final List<AddAuxCondition> auxConditions;
  final double? winRate;
  final int winHits;
  final int winSamples;
  final bool validated;
  final DateTime? updatedAt;

  List<String> get ruleLinesZh => [
        baseRuleZh,
        winDefZh,
        if (auxConditions.isEmpty)
          '辅助条件：暂无（仅底条件）'
        else
          ...auxConditions.map((c) => '辅助：${c.labelZh}'),
        if (winSamples > 0)
          '全池规则胜率 ${((winRate ?? 0) * 100).toStringAsFixed(0)}%'
              '（$winHits/$winSamples）${validated ? '，已达标' : '，未达标暂不预测加仓'}'
        else
          '全池规则胜率：样本不足',
      ];

  Map<String, dynamic> toJson() => {
        'auxConditions': auxConditions.map((e) => e.toJson()).toList(),
        'winRate': winRate,
        'winHits': winHits,
        'winSamples': winSamples,
        'validated': validated,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory AddRulePack.fromJson(Map<String, dynamic> json) {
    return AddRulePack(
      auxConditions: (json['auxConditions'] as List<dynamic>? ?? [])
          .map((e) => AddAuxCondition.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(),
      winRate: (json['winRate'] as num?)?.toDouble(),
      winHits: (json['winHits'] as num?)?.toInt() ?? 0,
      winSamples: (json['winSamples'] as num?)?.toInt() ?? 0,
      validated: json['validated'] as bool? ?? false,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }
}

/// 量价信号分析结果。
class EtfFlowSignalResult {
  const EtfFlowSignalResult({
    required this.signals,
    this.winRate,
    this.winHits = 0,
    this.winSamples = 0,
    this.historySupportsAdd = false,
    this.addFitness = 0,
    this.rulePackValidated = false,
  });

  static const empty = EtfFlowSignalResult(signals: []);

  final List<EtfFlowSignal> signals;
  /// 全池规则胜率（透传展示）
  final double? winRate;
  final int winHits;
  final int winSamples;
  final bool historySupportsAdd;
  final double addFitness;
  final bool rulePackValidated;
}

/// 量价信号（加仓点 / 风险点 / 历史规律）。
class EtfFlowSignal {
  const EtfFlowSignal({
    required this.type,
    required this.quarterEnd,
    required this.pointDate,
    required this.reason,
    this.netShare,
    this.multiple,
    this.relatedAddDate,
    this.isHistorical = false,
    this.isActionable = false,
    this.forwardReturn,
    this.isWin,
  });

  final EtfFlowSignalType type;
  final String quarterEnd;
  final String pointDate;
  final String reason;
  final double? netShare;
  final double? multiple;
  final String? relatedAddDate;
  final bool isHistorical;
  final bool isActionable;
  final double? forwardReturn;
  final bool? isWin;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'quarterEnd': quarterEnd,
        'pointDate': pointDate,
        'reason': reason,
        'netShare': netShare,
        'multiple': multiple,
        'relatedAddDate': relatedAddDate,
        'isHistorical': isHistorical,
        'isActionable': isActionable,
        'forwardReturn': forwardReturn,
        'isWin': isWin,
      };

  factory EtfFlowSignal.fromJson(Map<String, dynamic> json) {
    return EtfFlowSignal(
      type: json['type'] == 'risk'
          ? EtfFlowSignalType.risk
          : EtfFlowSignalType.add,
      quarterEnd: json['quarterEnd'] as String? ?? '',
      pointDate: json['pointDate'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      netShare: (json['netShare'] as num?)?.toDouble(),
      multiple: (json['multiple'] as num?)?.toDouble(),
      relatedAddDate: json['relatedAddDate'] as String?,
      isHistorical: json['isHistorical'] as bool? ?? false,
      isActionable: json['isActionable'] as bool? ?? false,
      forwardReturn: (json['forwardReturn'] as num?)?.toDouble(),
      isWin: json['isWin'] as bool?,
    );
  }
}

class EtfOverviewItem {
  const EtfOverviewItem({
    required this.code,
    required this.name,
    required this.score,
    this.indexName = '',
    this.price,
    this.changePercent,
    this.narrative = '',
  });

  final String code;
  final String name;
  final EtfBuyScore score;
  final String indexName;
  final double? price;
  final double? changePercent;
  final String narrative;
}
