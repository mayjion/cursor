import '../models/institutional_hold_summary.dart';
import '../models/market_space_context.dart';
import '../models/recommendation.dart';
import '../models/research_summary.dart';
import '../models/stock_snapshot.dart';



const double minDailyAmount = 50_000_000;



double percentileRank(List<double> values, double target) {

  if (values.isEmpty) return 50;

  final below = values.where((v) => v < target).length;

  return below / values.length * 100;

}



double scoreFromPercentile(double percentile, {bool lowerIsBetter = true}) {

  if (lowerIsBetter) {

    return (100 - percentile).clamp(0, 100);

  }

  return percentile.clamp(0, 100);

}



Map<String, Map<String, List<double>>> computeIndustryPePb(

  List<StockSnapshot> snapshots,

) {

  final industryMap = <String, Map<String, List<double>>>{};

  for (final s in snapshots) {

    final ind = s.industry.isEmpty ? '其他' : s.industry;

    industryMap.putIfAbsent(ind, () => {'pe': [], 'pb': []});

    if (s.peTtm != null && s.peTtm! > 0) {

      industryMap[ind]!['pe']!.add(s.peTtm!);

    }

    if (s.pb != null && s.pb! > 0) {

      industryMap[ind]!['pb']!.add(s.pb!);

    }

  }

  return industryMap;

}



({double score, List<String> reasons}) scoreValuation(

  StockSnapshot snapshot,

  Map<String, Map<String, List<double>>> industryStats,

) {

  final reasons = <String>[];

  final scores = <double>[];

  final ind = snapshot.industry.isEmpty ? '其他' : snapshot.industry;

  final stats = industryStats[ind] ?? {'pe': <double>[], 'pb': <double>[]};



  if (snapshot.peTtm != null && snapshot.peTtm! > 0) {

    final pePct = percentileRank(stats['pe']!, snapshot.peTtm!);

    scores.add(scoreFromPercentile(pePct));

    if (pePct < 30) {

      reasons.add(

        'PE(${snapshot.peTtm!.toStringAsFixed(1)})处于行业低分位(${pePct.toStringAsFixed(0)}%)',

      );

    }

  }



  if (snapshot.pb != null && snapshot.pb! > 0) {

    final pbPct = percentileRank(stats['pb']!, snapshot.pb!);

    scores.add(scoreFromPercentile(pbPct));

    if (pbPct < 30) {

      reasons.add(

        'PB(${snapshot.pb!.toStringAsFixed(2)})处于行业低分位(${pbPct.toStringAsFixed(0)}%)',

      );

    }

  }



  if (scores.isEmpty) return (score: 50, reasons: reasons);

  return (

    score: scores.reduce((a, b) => a + b) / scores.length,

    reasons: reasons,

  );

}



double _scoreGrowthRate(double? rate) {

  if (rate == null) return 50;

  if (rate >= 30) return 95;

  if (rate >= 20) return 85;

  if (rate >= 10) return 70;

  if (rate >= 5) return 60;

  if (rate >= 0) return 45;

  if (rate >= -10) return 30;

  return 15;

}



({double score, List<String> reasons}) scoreHistoricalGrowth(

  StockSnapshot snapshot,

) {

  final reasons = <String>[];

  final scores = <double>[];



  if (snapshot.revenueGrowth != null) {

    final s = _scoreGrowthRate(snapshot.revenueGrowth);

    scores.add(s);

    if (snapshot.revenueGrowth! >= 10) {

      reasons.add('营收增速(${snapshot.revenueGrowth!.toStringAsFixed(1)}%)较快');

    } else if (snapshot.revenueGrowth! < 0) {

      reasons.add('营收同比下滑(${snapshot.revenueGrowth!.toStringAsFixed(1)}%)');

    }

  }



  if (snapshot.netProfitGrowth != null) {

    scores.add(_scoreGrowthRate(snapshot.netProfitGrowth));

    if (snapshot.netProfitGrowth! >= 15) {

      reasons.add('利润增速(${snapshot.netProfitGrowth!.toStringAsFixed(1)}%)良好');

    }

  }



  if (snapshot.roe != null) {

    if (snapshot.roe! >= 15) {

      scores.add(90);

      reasons.add('ROE(${snapshot.roe!.toStringAsFixed(1)}%)优秀');

    } else if (snapshot.roe! >= 10) {

      scores.add(75);

      reasons.add('ROE(${snapshot.roe!.toStringAsFixed(1)}%)良好');

    } else if (snapshot.roe! >= 5) {

      scores.add(55);

    } else {

      scores.add(30);

    }

  }



  if (snapshot.revenueGrowth != null &&

      snapshot.netProfitGrowth != null &&

      snapshot.revenueGrowth! > 5 &&

      snapshot.netProfitGrowth! < 0) {

    scores.add(35);

    reasons.add('增收不增利，成长质量偏弱');

  }



  if (scores.isEmpty) return (score: 50, reasons: reasons);

  return (

    score: scores.reduce((a, b) => a + b) / scores.length,

    reasons: reasons,

  );

}



({double score, List<String> reasons}) scoreResearchGrowth(

  ResearchSummary research,

  double? currentPe,

) {

  final reasons = <String>[];

  final scores = <double>[research.avgRatingScore];



  if (research.epsGrowthRate != null) {

    scores.add(_scoreGrowthRate(research.epsGrowthRate! * 100));

    if (research.epsGrowthRate! > 0.1) {

      reasons.add(

        '研报预期EPS增速${(research.epsGrowthRate! * 100).toStringAsFixed(0)}%',

      );

    }

  }



  if (research.avgPredictPe != null &&

      currentPe != null &&

      currentPe > 0 &&

      research.avgPredictPe! < currentPe) {

    scores.add(75);

    reasons.add('预期PE(${research.avgPredictPe!.toStringAsFixed(1)})低于当前');

  }



  if (research.topRating.isNotEmpty) {

    reasons.add('研报共识：${research.topRating}(${research.reportCount}篇)');

  }



  return (

    score: scores.reduce((a, b) => a + b) / scores.length,

    reasons: reasons,

  );

}



({double score, List<String> reasons}) scoreGrowth(

  StockSnapshot snapshot, {

  ResearchSummary? research,

}) {

  final historical = scoreHistoricalGrowth(snapshot);

  if (research == null || research.reportCount == 0) {

    return historical;

  }

  final fromResearch = scoreResearchGrowth(research, snapshot.peTtm);

  return (

    score: historical.score * 0.5 + fromResearch.score * 0.5,

    reasons: [...historical.reasons, ...fromResearch.reasons],

  );

}



IndustryItem? _matchIndustryBoard(

  StockSnapshot snapshot,

  List<IndustryItem> boards,

) {

  final names = [

    snapshot.industry,

    snapshot.industryClass,

  ].where((e) => e.isNotEmpty).toList();



  for (final board in boards) {

    for (final name in names) {

      if (board.industry.contains(name) || name.contains(board.industry)) {

        return board;

      }

    }

  }

  return null;

}



double _industryMomentumScore(IndustryItem? board, List<IndustryItem> boards) {

  if (board == null) return 50;

  var score = 50.0;

  final chg = board.changePercent ?? 0;

  if (chg >= 3) {

    score += 25;

  } else if (chg >= 1) {

    score += 15;

  } else if (chg >= 0) {

    score += 5;

  } else if (chg >= -2) {

    score -= 5;

  } else {

    score -= 20;

  }



  final sorted = [...boards]

    ..sort((a, b) =>

        (b.mainNetInflow ?? 0).compareTo(a.mainNetInflow ?? 0));

  final rank = sorted.indexWhere((b) => b.industry == board.industry);

  if (rank >= 0 && rank < 5) score += 15;

  if (rank >= 5 && rank < 15) score += 8;



  return score.clamp(0, 100);

}



({double score, List<String> reasons}) scoreMarketSpace(

  StockSnapshot snapshot,

  MarketSpaceContext context,

) {

  final reasons = <String>[];

  final board = _matchIndustryBoard(snapshot, context.industryBoards);

  final momentumScore = _industryMomentumScore(board, context.industryBoards);



  var reportScore = 50.0;

  for (final entry in context.industryReportScores.entries) {

    final key = entry.key;

    if (snapshot.industry.contains(key) ||

        key.contains(snapshot.industry) ||

        (snapshot.industryClass.isNotEmpty &&

            (snapshot.industryClass.contains(key) ||

                key.contains(snapshot.industryClass)))) {

      reportScore = entry.value;

      reasons.add('行业研报态度偏${entry.value >= 70 ? '积极' : '中性'}');

      break;

    }

  }



  var conceptScore = 50.0;

  if (snapshot.concepts.isNotEmpty && context.hotKeywords.isNotEmpty) {

    final hits = snapshot.concepts

        .where(

          (c) => context.hotKeywords.any(

            (h) => c.contains(h) || h.contains(c),

          ),

        )

        .length;

    if (hits >= 2) {

      conceptScore = 85;

      reasons.add('概念命中$hits个强势赛道');

    } else if (hits == 1) {

      conceptScore = 70;

      reasons.add('概念命中强势赛道');

    }

  }



  if (board != null && (board.changePercent ?? 0) >= 1) {

    reasons.add(

      '所属板块${board.industry}涨${board.changePercent!.toStringAsFixed(1)}%',

    );

  }



  final score =

      momentumScore * 0.40 + reportScore * 0.35 + conceptScore * 0.25;

  return (score: score.clamp(0, 100), reasons: reasons);

}



bool _isLargeInstitutionHolder(String name) {

  if (name.isEmpty) return false;

  const keywords = ['基金', '社保', '保险', 'QFII', '香港中央结算', '证金', '汇金'];

  for (final k in keywords) {

    if (name.contains(k)) return true;

  }

  return false;

}



({double score, List<String> reasons}) scoreInstitution(

  InstitutionalHoldSummary summary,

) {

  if (!summary.hasData) {

    return (score: 50, reasons: const []);

  }



  final reasons = [...summary.reasons];

  var aggregateScore = 50.0;

  final rate = summary.quarterChangeRate;

  if (summary.summaryAction.contains('增')) {

    aggregateScore = 70 + (rate ?? 0).clamp(0, 20);

    if (rate != null && rate > 5) {

      reasons.add('机构汇总季度增持${rate.toStringAsFixed(1)}%');

    }

  } else if (summary.summaryAction.contains('减')) {

    aggregateScore = 30 + (rate ?? 0).clamp(-20, 0);

    if (rate != null && rate < -5) {

      reasons.add('机构汇总季度减持${rate.abs().toStringAsFixed(1)}%');

    }

  }



  var typeScore = 50.0;

  if (summary.increasingTypes.isNotEmpty) {

    typeScore = (60 + summary.increasingTypes.length * 12).clamp(0, 95).toDouble();

    reasons.add('${summary.increasingTypes.join('、')}增仓');

  }



  var holderScore = 50.0;

  if (summary.newHolderCount >= 1) {

    holderScore += 20;

    reasons.add('${summary.newHolderCount}家大机构新进十大股东');

  }

  if (summary.increaseHolderCount >= 2) {

    holderScore += 15;

  }

  if (summary.decreaseHolderCount >= 2) {

    holderScore -= 20;

    reasons.add('多家大机构减持十大股东');

  }



  final score = aggregateScore * 0.45 +

      typeScore * 0.35 +

      holderScore.clamp(0, 100) * 0.20;

  return (score: score.clamp(0, 100), reasons: reasons);

}



bool passesHardFilter(StockSnapshot snapshot, {bool excludeStarMarket = true}) {

  if (snapshot.isSt) return false;

  if (excludeStarMarket &&

      (snapshot.code.startsWith('688') || snapshot.code.startsWith('8'))) {

    return false;

  }

  if (snapshot.avgAmount != null && snapshot.avgAmount! < minDailyAmount) {

    return false;

  }

  if (snapshot.peTtm != null && snapshot.peTtm! < 0) return false;

  if (snapshot.peTtm != null && snapshot.peTtm! > 200) return false;

  return true;

}



bool passesMarketCapFilter(StockSnapshot snapshot, String filter) {

  if (filter == 'all' || snapshot.marketCap == null) return true;

  final cap = snapshot.marketCap!;

  return switch (filter) {

    'large' => cap >= 500e8,

    'mid' => cap >= 100e8 && cap < 500e8,

    'small' => cap < 100e8,

    _ => true,

  };

}



double compositeScoreGarp({

  required double valuation,

  required double growth,

  required double space,

  required double institution,

  required double capital,

  required double technical,

}) {

  final momentum = (capital + technical) / 2;

  return valuation * 0.25 +

      growth * 0.25 +

      space * 0.20 +

      institution * 0.15 +

      momentum * 0.15;

}



/// 兼容旧调用

double compositeScore({

  required double valuation,

  required double quality,

  required double capital,

  required double technical,

}) {

  return compositeScoreGarp(

    valuation: valuation,

    growth: quality,

    space: 50,

    institution: 50,

    capital: capital,

    technical: technical,

  );

}



List<ScoredStock> scoreUniverseInitial(

  List<StockSnapshot> snapshots, {

  bool excludeStarMarket = true,

  String marketCapFilter = 'all',

  MarketSpaceContext? spaceContext,

}) {

  final industryStats = computeIndustryPePb(snapshots);

  final context = spaceContext ?? const MarketSpaceContext();

  final filtered = snapshots

      .where((s) => passesHardFilter(s, excludeStarMarket: excludeStarMarket))

      .where((s) => passesMarketCapFilter(s, marketCapFilter))

      .toList();



  final scored = <ScoredStock>[];

  for (final snapshot in filtered) {

    final val = scoreValuation(snapshot, industryStats);

    final growth = scoreGrowth(snapshot);

    final space = scoreMarketSpace(snapshot, context);

    const institutionScore = 50.0;

    const capScore = 50.0;

    const techScore = 50.0;

    final reasons = [

      ...val.reasons,

      ...growth.reasons,

      ...space.reasons,

    ];

    if (reasons.isEmpty) {

      reasons.add('综合估值与成长指标处于合理区间');

    }

    scored.add(

      ScoredStock(

        snapshot: snapshot,

        compositeScore: compositeScoreGarp(

          valuation: val.score,

          growth: growth.score,

          space: space.score,

          institution: institutionScore,

          capital: capScore,

          technical: techScore,

        ),

        valuationScore: val.score,

        growthScore: growth.score,

        spaceScore: space.score,

        institutionScore: institutionScore,

        capitalScore: capScore,

        technicalScore: techScore,

        reasons: reasons,

      ),

    );

  }

  scored.sort((a, b) => b.compositeScore.compareTo(a.compositeScore));

  return scored;

}



void recalculateComposite(ScoredStock item) {

  item.compositeScore = compositeScoreGarp(

    valuation: item.valuationScore,

    growth: item.growthScore,

    space: item.spaceScore,

    institution: item.institutionScore,

    capital: item.capitalScore,

    technical: item.technicalScore,

  );

}



bool isLargeInstitutionHolder(String name) => _isLargeInstitutionHolder(name);


