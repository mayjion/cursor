class StockSnapshot {

  const StockSnapshot({

    required this.code,

    required this.name,

    this.industry = '',

    this.peTtm,

    this.pb,

    this.roe,

    this.dividendYield,

    this.revenueGrowth,

    this.netProfitGrowth,

    this.netMargin,

    this.marketCap,

    this.avgAmount,

    this.changePercent,

    this.price,

    this.isSt = false,

    this.concepts = const [],

    this.industryClass = '',

  });



  final String code;

  final String name;

  final String industry;

  final double? peTtm;

  final double? pb;

  final double? roe;

  final double? dividendYield;

  final double? revenueGrowth;

  final double? netProfitGrowth;

  final double? netMargin;

  final double? marketCap;

  final double? avgAmount;

  final double? changePercent;

  final double? price;

  final bool isSt;

  final List<String> concepts;

  final String industryClass;



  StockSnapshot copyWith({

    String? industry,

    double? roe,

    double? dividendYield,

    double? revenueGrowth,

    double? netProfitGrowth,

    double? netMargin,

    List<String>? concepts,

    String? industryClass,

  }) {

    return StockSnapshot(

      code: code,

      name: name,

      industry: industry ?? this.industry,

      peTtm: peTtm,

      pb: pb,

      roe: roe ?? this.roe,

      dividendYield: dividendYield ?? this.dividendYield,

      revenueGrowth: revenueGrowth ?? this.revenueGrowth,

      netProfitGrowth: netProfitGrowth ?? this.netProfitGrowth,

      netMargin: netMargin ?? this.netMargin,

      marketCap: marketCap,

      avgAmount: avgAmount,

      changePercent: changePercent,

      price: price,

      isSt: isSt,

      concepts: concepts ?? this.concepts,

      industryClass: industryClass ?? this.industryClass,

    );

  }

}



class ScoredStock {

  ScoredStock({

    required this.snapshot,

    this.compositeScore = 0,

    this.valuationScore = 0,

    this.growthScore = 0,

    this.spaceScore = 0,

    this.institutionScore = 50,

    this.capitalScore = 0,

    this.technicalScore = 0,

    List<String>? reasons,

  }) : reasons = reasons ?? [];



  StockSnapshot snapshot;

  double compositeScore;

  double valuationScore;

  double growthScore;

  double spaceScore;

  double institutionScore;

  double capitalScore;

  double technicalScore;

  List<String> reasons;



  double get momentumScore => (capitalScore + technicalScore) / 2;



  /// 兼容旧字段名

  double get qualityScore => growthScore;

  set qualityScore(double v) => growthScore = v;

}



enum ScanStatus { idle, running, done, failed, cancelled }



class ScanMeta {

  const ScanMeta({

    this.status = ScanStatus.idle,

    this.lastScanAt,

    this.lastDurationMs,

    this.progress = 0,

    this.progressMessage = '',

    this.errorMessage,

  });



  final ScanStatus status;

  final DateTime? lastScanAt;

  final int? lastDurationMs;

  final int progress;

  final String progressMessage;

  final String? errorMessage;



  ScanMeta copyWith({

    ScanStatus? status,

    DateTime? lastScanAt,

    int? lastDurationMs,

    int? progress,

    String? progressMessage,

    String? errorMessage,

  }) {

    return ScanMeta(

      status: status ?? this.status,

      lastScanAt: lastScanAt ?? this.lastScanAt,

      lastDurationMs: lastDurationMs ?? this.lastDurationMs,

      progress: progress ?? this.progress,

      progressMessage: progressMessage ?? this.progressMessage,

      errorMessage: errorMessage,

    );

  }



  Map<String, dynamic> toJson() => {

        'status': status.name,

        'lastScanAt': lastScanAt?.toIso8601String(),

        'lastDurationMs': lastDurationMs,

        'progress': progress,

        'progressMessage': progressMessage,

        'errorMessage': errorMessage,

      };



  factory ScanMeta.fromJson(Map<String, dynamic> json) {

    return ScanMeta(

      status: ScanStatus.values.firstWhere(

        (e) => e.name == json['status'],

        orElse: () => ScanStatus.idle,

      ),

      lastScanAt: json['lastScanAt'] != null

          ? DateTime.tryParse(json['lastScanAt'] as String)

          : null,

      lastDurationMs: json['lastDurationMs'] as int?,

      progress: json['progress'] as int? ?? 0,

      progressMessage: json['progressMessage'] as String? ?? '',

      errorMessage: json['errorMessage'] as String?,

    );

  }

}


