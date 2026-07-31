class RecommendationItem {
  const RecommendationItem({
    required this.code,
    required this.name,
    required this.industry,
    required this.rank,
    required this.compositeScore,
    required this.valuationScore,
    required this.growthScore,
    required this.spaceScore,
    required this.institutionScore,
    required this.capitalScore,
    required this.technicalScore,
    this.peTtm,
    this.pb,
    this.roe,
    this.dividendYield,
    this.reasons = const [],
  });

  final String code;
  final String name;
  final String industry;
  final int rank;
  final double compositeScore;
  final double valuationScore;
  final double growthScore;
  final double spaceScore;
  final double institutionScore;
  final double capitalScore;
  final double technicalScore;
  final double? peTtm;
  final double? pb;
  final double? roe;
  final double? dividendYield;
  final List<String> reasons;

  double get momentumScore => (capitalScore + technicalScore) / 2;

  /// 兼容旧缓存
  double get qualityScore => growthScore;

  factory RecommendationItem.fromJson(Map<String, dynamic> json) {
    final growth = (json['growth_score'] as num?)?.toDouble() ??
        (json['quality_score'] as num?)?.toDouble() ??
        50.0;
    return RecommendationItem(
      code: json['code'] as String,
      name: json['name'] as String,
      industry: json['industry'] as String? ?? '',
      rank: json['rank'] as int,
      compositeScore: (json['composite_score'] as num).toDouble(),
      valuationScore: (json['valuation_score'] as num).toDouble(),
      growthScore: growth,
      spaceScore: (json['space_score'] as num?)?.toDouble() ?? 50,
      institutionScore: (json['institution_score'] as num?)?.toDouble() ?? 50,
      capitalScore: (json['capital_score'] as num).toDouble(),
      technicalScore: (json['technical_score'] as num).toDouble(),
      peTtm: (json['pe_ttm'] as num?)?.toDouble(),
      pb: (json['pb'] as num?)?.toDouble(),
      roe: (json['roe'] as num?)?.toDouble(),
      dividendYield: (json['dividend_yield'] as num?)?.toDouble(),
      reasons: (json['reasons'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'industry': industry,
        'rank': rank,
        'composite_score': compositeScore,
        'valuation_score': valuationScore,
        'growth_score': growthScore,
        'quality_score': growthScore,
        'space_score': spaceScore,
        'institution_score': institutionScore,
        'capital_score': capitalScore,
        'technical_score': technicalScore,
        'pe_ttm': peTtm,
        'pb': pb,
        'roe': roe,
        'dividend_yield': dividendYield,
        'reasons': reasons,
      };
}

class TodayRecommendations {
  const TodayRecommendations({
    required this.tradeDate,
    required this.items,
  });

  final String tradeDate;
  final List<RecommendationItem> items;

  factory TodayRecommendations.fromJson(Map<String, dynamic> json) {
    return TodayRecommendations(
      tradeDate: json['trade_date'] as String,
      items: (json['items'] as List<dynamic>)
          .map((e) => RecommendationItem.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

class StockProfile {
  const StockProfile({
    required this.code,
    required this.name,
    this.industry = '',
    this.peTtm,
    this.pb,
    this.roe,
    this.dividendYield,
    this.revenueGrowth,
    this.debtRatio,
    this.marketCap,
    this.pePercentile,
    this.pbPercentile,
    this.compositeScore,
    this.valuationLabel = '',
    this.concepts = const [],
    this.companySummary = '',
  });

  final String code;
  final String name;
  final String industry;
  final double? peTtm;
  final double? pb;
  final double? roe;
  final double? dividendYield;
  final double? revenueGrowth;
  final double? debtRatio;
  final double? marketCap;
  final double? pePercentile;
  final double? pbPercentile;
  final double? compositeScore;
  final String valuationLabel;
  final List<String> concepts;
  final String companySummary;

  StockProfile copyWith({
    String? code,
    String? name,
    String? industry,
    double? peTtm,
    double? pb,
    double? roe,
    double? dividendYield,
    double? revenueGrowth,
    double? debtRatio,
    double? marketCap,
    double? pePercentile,
    double? pbPercentile,
    double? compositeScore,
    String? valuationLabel,
    List<String>? concepts,
    String? companySummary,
  }) {
    return StockProfile(
      code: code ?? this.code,
      name: name ?? this.name,
      industry: industry ?? this.industry,
      peTtm: peTtm ?? this.peTtm,
      pb: pb ?? this.pb,
      roe: roe ?? this.roe,
      dividendYield: dividendYield ?? this.dividendYield,
      revenueGrowth: revenueGrowth ?? this.revenueGrowth,
      debtRatio: debtRatio ?? this.debtRatio,
      marketCap: marketCap ?? this.marketCap,
      pePercentile: pePercentile ?? this.pePercentile,
      pbPercentile: pbPercentile ?? this.pbPercentile,
      compositeScore: compositeScore ?? this.compositeScore,
      valuationLabel: valuationLabel ?? this.valuationLabel,
      concepts: concepts ?? this.concepts,
      companySummary: companySummary ?? this.companySummary,
    );
  }

  factory StockProfile.fromJson(Map<String, dynamic> json) {
    return StockProfile(
      code: json['code'] as String,
      name: json['name'] as String,
      industry: json['industry'] as String? ?? '',
      peTtm: (json['pe_ttm'] as num?)?.toDouble(),
      pb: (json['pb'] as num?)?.toDouble(),
      roe: (json['roe'] as num?)?.toDouble(),
      dividendYield: (json['dividend_yield'] as num?)?.toDouble(),
      revenueGrowth: (json['revenue_growth'] as num?)?.toDouble(),
      debtRatio: (json['debt_ratio'] as num?)?.toDouble(),
      marketCap: (json['market_cap'] as num?)?.toDouble(),
      pePercentile: (json['pe_percentile'] as num?)?.toDouble(),
      pbPercentile: (json['pb_percentile'] as num?)?.toDouble(),
      compositeScore: (json['composite_score'] as num?)?.toDouble(),
      valuationLabel: json['valuation_label'] as String? ?? '',
      concepts: (json['concepts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      companySummary: json['company_summary'] as String? ?? '',
    );
  }
}

class NewsArticleItem {
  const NewsArticleItem({
    required this.id,
    required this.title,
    this.source = '',
    this.url = '',
    this.summary = '',
    this.stockCode,
    this.industry,
    this.publishedAt,
  });

  final int id;
  final String title;
  final String source;
  final String url;
  final String summary;
  final String? stockCode;
  final String? industry;
  final String? publishedAt;

  factory NewsArticleItem.fromJson(Map<String, dynamic> json) {
    return NewsArticleItem(
      id: json['id'] as int,
      title: json['title'] as String,
      source: json['source'] as String? ?? '',
      url: json['url'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      stockCode: json['stock_code'] as String?,
      industry: json['industry'] as String?,
      publishedAt: json['published_at'] as String?,
    );
  }
}

class IndustryItem {
  const IndustryItem({
    required this.industry,
    this.changePercent,
    this.mainNetInflow,
    this.stockCount = 0,
  });

  final String industry;
  final double? changePercent;
  final double? mainNetInflow;
  final int stockCount;

  factory IndustryItem.fromJson(Map<String, dynamic> json) {
    return IndustryItem(
      industry: json['industry'] as String,
      changePercent: (json['change_percent'] as num?)?.toDouble(),
      mainNetInflow: (json['main_net_inflow'] as num?)?.toDouble(),
      stockCount: json['stock_count'] as int? ?? 0,
    );
  }
}

class DailyDigest {
  const DailyDigest({
    required this.tradeDate,
    required this.marketSummary,
    this.topIndustries = const [],
    this.keyEvents = const [],
  });

  final String tradeDate;
  final String marketSummary;
  final List<Map<String, dynamic>> topIndustries;
  final List<String> keyEvents;

  factory DailyDigest.fromJson(Map<String, dynamic> json) {
    return DailyDigest(
      tradeDate: json['trade_date'] as String,
      marketSummary: json['market_summary'] as String? ?? '',
      topIndustries: (json['top_industries'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      keyEvents: (json['key_events'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

class HistoryRecommendationItem {
  const HistoryRecommendationItem({
    required this.tradeDate,
    required this.code,
    required this.name,
    required this.compositeScore,
    this.return5d,
    this.return20d,
    this.return60d,
  });

  final String tradeDate;
  final String code;
  final String name;
  final double compositeScore;
  final double? return5d;
  final double? return20d;
  final double? return60d;

  factory HistoryRecommendationItem.fromJson(Map<String, dynamic> json) {
    return HistoryRecommendationItem(
      tradeDate: json['trade_date'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      compositeScore: (json['composite_score'] as num).toDouble(),
      return5d: (json['return_5d'] as num?)?.toDouble(),
      return20d: (json['return_20d'] as num?)?.toDouble(),
      return60d: (json['return_60d'] as num?)?.toDouble(),
    );
  }
}
