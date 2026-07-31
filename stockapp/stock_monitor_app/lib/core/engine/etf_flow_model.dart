import '../models/etf_models.dart';
import '../models/stock_bar.dart';

/// ETF 净申购特征与购买倾向评分。
///
/// 主口径：季报「期间申购 / 期间赎回」；
/// 无足够季报时降级为日频总份额差分。
class EtfFlowModel {
  /// 从份额序列中抽出季报披露点（有期间申购或期间赎回）。
  static List<EtfSharePoint> extractQuarterReports(List<EtfSharePoint> shares) {
    final qs = shares.where((p) => p.isQuarterReport).toList();
    qs.sort((a, b) => a.date.compareTo(b.date));
    return qs;
  }

  /// 由份额序列 + 可选日K 构建特征（季报优先）。
  static EtfFlowFeatures buildFeatures(
    List<EtfSharePoint> shares, {
    List<StockBar> bars = const [],
  }) {
    if (shares.isEmpty) return const EtfFlowFeatures();

    final quarters = extractQuarterReports(shares);
    final mom20 = _priceMomentum(bars, 20);
    final inQuarter = shares.isNotEmpty ? shares.last.shareChangeQ : null;

    if (quarters.length >= 2) {
      return _featuresFromQuarters(
        quarters,
        allShares: shares,
        inQuarterNetToDate: inQuarter,
        priceMomentum20d: mom20,
      );
    }

    // 降级：日频总份额差分
    return _featuresFromDaily(
      shares,
      inQuarterNetToDate: inQuarter,
      priceMomentum20d: mom20,
    );
  }

  static EtfFlowFeatures _featuresFromQuarters(
    List<EtfSharePoint> quarters, {
    required List<EtfSharePoint> allShares,
    double? inQuarterNetToDate,
    double? priceMomentum20d,
  }) {
    final nets = quarters
        .map((q) => q.quarterNetShare ?? 0)
        .toList(growable: false);
    if (nets.isEmpty) return const EtfFlowFeatures(usedDailyFallback: true);

    final latest = nets.last;
    final prior = nets.length > 1 ? nets.sublist(0, nets.length - 1) : <double>[];
    final priorTake = prior.length > 4 ? prior.sublist(prior.length - 4) : prior;
    final priorAbsAvg = priorTake.isEmpty
        ? 0.0
        : priorTake.map((e) => e.abs()).fold<double>(0, (a, b) => a + b) /
            priorTake.length;
    final burst = priorAbsAvg < 1e-9
        ? (latest > 0 ? 2.0 : (latest < 0 ? -1.0 : 1.0))
        : (latest / priorAbsAvg).clamp(-5.0, 5.0);

    final last8 = nets.length > 8 ? nets.sublist(nets.length - 8) : nets;
    final positive = last8.where((e) => e > 0).length;
    final persist = last8.isEmpty ? 0.5 : positive / last8.length;

    final last4 = nets.length > 4 ? nets.sublist(nets.length - 4) : nets;
    final cum4 = last4.fold<double>(0, (a, b) => a + b);
    final last8Sum = last8.fold<double>(0, (a, b) => a + b);

    // 期初份额：近 4 季窗口起点的总份额
    final baseIdx = quarters.length >= 4
        ? quarters.length - 4
        : 0;
    final baseShare = quarters[baseIdx].totalShare;
    // 更稳妥：用窗口前一个点的份额；若无则用当前点
    double base = baseShare;
    if (baseIdx > 0) {
      base = quarters[baseIdx - 1].totalShare;
    } else if (allShares.isNotEmpty) {
      // 找季报点之前最近的日频份额
      final qDate = quarters[baseIdx].date;
      for (var i = allShares.length - 1; i >= 0; i--) {
        if (allShares[i].date.compareTo(qDate) < 0) {
          base = allShares[i].totalShare;
          break;
        }
      }
    }
    final intensity = base.abs() < 1e-9 ? 0.0 : cum4 / base;

    return EtfFlowFeatures(
      burstRatio: burst.toDouble(),
      persistRatio: persist,
      cumIntensity: intensity,
      latestQuarterNet: latest,
      last4QuartersNet: cum4,
      last8QuartersNet: last8Sum,
      inQuarterNetToDate: inQuarterNetToDate,
      quarterCount: quarters.length,
      usedDailyFallback: false,
      priceMomentum20d: priceMomentum20d,
      net20d: latest,
      net60d: cum4,
      net120d: last8Sum,
    );
  }

  static EtfFlowFeatures _featuresFromDaily(
    List<EtfSharePoint> shares, {
    double? inQuarterNetToDate,
    double? priceMomentum20d,
  }) {
    if (shares.length < 30) {
      return EtfFlowFeatures(
        usedDailyFallback: true,
        inQuarterNetToDate: inQuarterNetToDate,
        priceMomentum20d: priceMomentum20d,
        quarterCount: 0,
      );
    }

    final nets = shares.map((p) => p.netShareChange ?? 0).toList();

    double sumLast(int n) {
      final start = nets.length > n ? nets.length - n : 0;
      return nets.sublist(start).fold<double>(0, (a, b) => a + b);
    }

    double avgLast(int n) {
      final take = nets.length > n ? n : nets.length;
      return sumLast(take) / take;
    }

    final avg5 = avgLast(5);
    final avg60 = avgLast(60);
    final burst = avg60.abs() < 1e-9
        ? (avg5 > 0 ? 2.0 : 1.0)
        : (avg5 / avg60.abs()).clamp(-5.0, 5.0);

    final last60 = nets.length >= 60 ? nets.sublist(nets.length - 60) : nets;
    final positiveDays = last60.where((e) => e > 0).length;
    final persist = last60.isEmpty ? 0.5 : positiveDays / last60.length;

    final baseShare = shares.length >= 120
        ? shares[shares.length - 120].totalShare
        : shares.first.totalShare;
    final cum120 = sumLast(120);
    final intensity = baseShare.abs() < 1e-9 ? 0.0 : cum120 / baseShare;

    return EtfFlowFeatures(
      burstRatio: burst.toDouble(),
      persistRatio: persist,
      cumIntensity: intensity,
      latestQuarterNet: sumLast(60),
      last4QuartersNet: cum120,
      last8QuartersNet: cum120,
      inQuarterNetToDate: inQuarterNetToDate,
      quarterCount: 0,
      usedDailyFallback: true,
      priceMomentum20d: priceMomentum20d,
      net20d: sumLast(20),
      net60d: sumLast(60),
      net120d: cum120,
    );
  }

  static double? _priceMomentum(List<StockBar> bars, int days) {
    if (bars.length < days + 1) return null;
    final a = bars[bars.length - days - 1].close;
    final b = bars.last.close;
    if (a == null || b == null || a <= 0) return null;
    return (b / a - 1) * 100;
  }

  /// 0-100 购买倾向指数。
  static EtfBuyScore score(String code, EtfFlowFeatures f) {
    final reasons = <String>[];
    final qMode = !f.usedDailyFallback && f.quarterCount >= 2;

    var burstScore = 50.0;
    if (f.burstRatio >= 2.0) {
      burstScore = 90;
      reasons.add(
        qMode
            ? '上一季净申购放量（约为此前四季均值的${f.burstRatio.toStringAsFixed(1)}倍）'
            : '近期净申购放量（日频降级口径）',
      );
    } else if (f.burstRatio >= 1.3) {
      burstScore = 75;
      reasons.add(qMode ? '上一季净申购偏强' : '近期净申购偏强（日频降级）');
    } else if (f.burstRatio <= 0.5 && f.burstRatio > 0) {
      burstScore = 40;
    } else if (f.burstRatio < 0) {
      burstScore = 25;
      reasons.add(qMode ? '上一季转为净赎回偏多' : '近期净赎回偏多（日频降级）');
    }

    var persistScore = (f.persistRatio * 100).clamp(0, 100).toDouble();
    if (f.persistRatio >= 0.6) {
      reasons.add(
        qMode
            ? '近${f.quarterCount.clamp(1, 8)}季中净申购季度占比${(f.persistRatio * 100).toStringAsFixed(0)}%，持续性较好'
            : '近期净申购日占比较高（日频降级）',
      );
    } else if (f.persistRatio <= 0.35) {
      reasons.add(
        qMode
            ? '近几季净申购季度偏少，资金流入不够持续'
            : '近期净申购日偏少（日频降级）',
      );
    }

    var cumScore = 50.0;
    if (f.cumIntensity >= 0.15) {
      cumScore = 90;
      reasons.add(
        qMode
            ? '近4季累计净申购占期初份额${(f.cumIntensity * 100).toStringAsFixed(1)}%'
            : '中期累计净申购较强（日频降级）',
      );
    } else if (f.cumIntensity >= 0.05) {
      cumScore = 72;
      reasons.add(qMode ? '近4季累计净申购为正' : '中期累计净申购为正（日频降级）');
    } else if (f.cumIntensity <= -0.1) {
      cumScore = 25;
      reasons.add(qMode ? '近4季累计净赎回较多' : '中期累计净赎回较多（日频降级）');
    } else if (f.cumIntensity < 0) {
      cumScore = 40;
    }

    if (qMode && f.latestQuarterNet != null) {
      final n = f.latestQuarterNet!;
      reasons.insert(
        0,
        '最近季报净申购${n >= 0 ? '+' : ''}${n.toStringAsFixed(0)}（期间申购−赎回）',
      );
    }

    var momAdj = 0.0;
    if (f.priceMomentum20d != null) {
      if (f.priceMomentum20d! > 8 && f.cumIntensity > 0) {
        momAdj = 5;
        reasons.add('价格与净申购同向偏强');
      } else if (f.priceMomentum20d! < -8 && f.cumIntensity > 0.05) {
        momAdj = 8;
        reasons.add('下跌中仍有净申购，关注资金吸筹');
      }
    }

    // 本季至今份额变动：仅作轻微辅助，不主导
    if (qMode &&
        f.inQuarterNetToDate != null &&
        f.latestQuarterNet != null &&
        f.latestQuarterNet! > 0 &&
        f.inQuarterNetToDate! > 0) {
      momAdj += 3;
      reasons.add('本季至今份额仍在扩张（日频辅助）');
    } else if (qMode &&
        f.inQuarterNetToDate != null &&
        f.latestQuarterNet != null &&
        f.latestQuarterNet! < 0 &&
        f.inQuarterNetToDate! < 0) {
      momAdj -= 3;
      reasons.add('本季至今份额继续收缩（日频辅助）');
    }

    if (f.usedDailyFallback) {
      reasons.add('缺少足够季报披露，已降级为日频份额变动');
    }

    final buyIndex = (burstScore * 0.35 +
            persistScore * 0.30 +
            cumScore * 0.30 +
            50 * 0.05 +
            momAdj)
        .clamp(0, 100)
        .toDouble();

    String label;
    if (buyIndex >= 75) {
      label = '偏强';
    } else if (buyIndex >= 55) {
      label = '关注';
    } else if (buyIndex >= 40) {
      label = '中性';
    } else {
      label = '偏弱';
    }

    if (reasons.isEmpty) {
      reasons.add('季报净申购特征处于历史中性区间');
    }

    // 去重并截断
    final deduped = <String>[];
    for (final r in reasons) {
      if (!deduped.contains(r)) deduped.add(r);
    }

    return EtfBuyScore(
      code: code,
      buyIndex: double.parse(buyIndex.toStringAsFixed(1)),
      label: label,
      reasons: deduped.take(5).toList(),
      features: f,
      updatedAt: DateTime.now(),
    );
  }

  /// 生成总览叙述（模板）。
  static String buildNarrative({
    required String name,
    required EtfBuyScore score,
    String indexName = '',
    String? industryHint,
    List<String> newsTitles = const [],
  }) {
    final buf = StringBuffer();
    buf.write('$name 模型评分 ${score.buyIndex.toStringAsFixed(0)}（${score.label}）。');
    if (score.reasons.isNotEmpty) {
      buf.write(score.reasons.first);
      buf.write('。');
    }
    if (indexName.isNotEmpty) {
      buf.write('跟踪「$indexName」。');
    }
    if (industryHint != null && industryHint.isNotEmpty) {
      buf.write(industryHint);
      buf.write('。');
    }
    if (newsTitles.isNotEmpty) {
      buf.write('相关热点：${newsTitles.take(2).join('；')}。');
    }
    buf.write('评分以季报期间申购/赎回为主，仅供参考。');
    return buf.toString();
  }
}
