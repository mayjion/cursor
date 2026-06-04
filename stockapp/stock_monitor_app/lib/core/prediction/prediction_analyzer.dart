import '../models/capital_flow_day.dart';
import '../models/prediction_analysis.dart';
import '../models/prediction_direction.dart';
import '../settings/app_settings.dart';

/// 基于近6月行情+资金流与最新一日主力/散户流向的综合分析。
class PredictionAnalyzer {
  const PredictionAnalyzer({this.thresholds = const PredictionThresholds()});

  final PredictionThresholds thresholds;

  static const int sixMonthTradingDays = 126;
  static const int recentFlowWindow = 20;
  static const int patternLookback = 60;

  PredictionAnalysis analyze(List<CapitalFlowDay> history) {
    if (history.isEmpty) {
      return PredictionAnalysis(
        direction: PredictionDirection.neutral,
        score: 0,
        confidence: 0,
        reasons: const ['数据不足'],
        latestDate: '',
        latestMainInflow: 0,
        latestRetailInflow: 0,
        latestMainRatio: 0,
        sixMonthPriceChangePercent: 0,
        sixMonthMainFlowSum: 0,
        recent20MainFlowSum: 0,
        historicalSamePatternRate: 50,
      );
    }

    final sorted = List<CapitalFlowDay>.from(history)
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    final latest = sorted.last;
    final reasons = <String>[];
    var score = 0.0;

    // --- 1. 最新交易日：主力 vs 散户（权重 40）---
    final main = latest.mainNetInflow;
    final retail = latest.smallNetInflow;
    final ratio = latest.mainNetRatio;

    if (main > 0 && ratio >= thresholds.bullRatioPercent) {
      score += 18;
      reasons.add('最新日主力净流入且占比较高');
    } else if (main < 0 && ratio <= thresholds.bearRatioPercent) {
      score -= 18;
      reasons.add('最新日主力净流出且占比较高');
    }

    // 主力吸筹、散户流出
    if (main > 0 && retail < 0) {
      score += 14;
      reasons.add('主力流入而散户流出（吸筹特征）');
    } else if (main < 0 && retail > 0) {
      score -= 14;
      reasons.add('主力流出而散户流入（派发特征）');
    } else if (main > 0 && retail > 0) {
      score += 4;
      reasons.add('主力与散户同日净流入（跟风偏多）');
    } else if (main < 0 && retail < 0) {
      score -= 6;
      reasons.add('主力与散户同日净流出');
    }

    // --- 2. 近6月价格趋势（权重 25）---
    final priceChange6m = _sixMonthPriceChange(sorted);
    if (priceChange6m > 5) {
      score += 10;
      reasons.add('近6月收盘价涨幅 ${priceChange6m.toStringAsFixed(1)}%');
    } else if (priceChange6m < -5) {
      score -= 10;
      reasons.add('近6月收盘价跌幅 ${priceChange6m.abs().toStringAsFixed(1)}%');
    }

    final recentReturn = _recentReturn(sorted, 10);
    if (recentReturn > 2) {
      score += 8;
      reasons.add('近10日涨 ${recentReturn.toStringAsFixed(1)}%');
    } else if (recentReturn < -2) {
      score -= 8;
      reasons.add('近10日跌 ${recentReturn.abs().toStringAsFixed(1)}%');
    }

    // --- 3. 近6月资金流趋势（权重 25）---
    final sum6m = sorted.fold<double>(0, (s, d) => s + d.mainNetInflow);
    final recent20 = sorted.length <= recentFlowWindow
        ? sum6m
        : sorted
            .sublist(sorted.length - recentFlowWindow)
            .fold<double>(0, (s, d) => s + d.mainNetInflow);

    if (recent20 > 0) {
      score += 10;
      reasons.add('近20日主力净流入合计为正');
    } else if (recent20 < 0) {
      score -= 10;
      reasons.add('近20日主力净流入合计为负');
    }

    final flowMomentum = _flowMomentum(sorted);
    if (flowMomentum > 0) {
      score += 8;
      reasons.add('近5日主力流入强于前5日');
    } else if (flowMomentum < 0) {
      score -= 8;
      reasons.add('近5日主力流入弱于前5日');
    }

    // --- 4. 历史同模式次日涨跌统计（权重 10）---
    final patternRate = _historicalPatternWinRate(sorted, latest);
    if (patternRate >= 58) {
      score += 10;
      reasons.add('近$patternLookback日同模式后次日上涨概率 ${patternRate.toStringAsFixed(0)}%');
    } else if (patternRate <= 42) {
      score -= 10;
      reasons.add('近$patternLookback日同模式后次日下跌偏多 ${(100 - patternRate).toStringAsFixed(0)}%');
    }

    // 价量资金流共振
    if (priceChange6m > 0 && recent20 > 0 && main > 0) {
      score += 6;
      reasons.add('价格、中期资金与最新主力方向一致偏多');
    } else if (priceChange6m < 0 && recent20 < 0 && main < 0) {
      score -= 6;
      reasons.add('价格、中期资金与最新主力方向一致偏空');
    }

    final direction = _directionFromScore(score);
    final confidence = _confidence(score, patternRate, sorted.length);

    return PredictionAnalysis(
      direction: direction,
      score: score,
      confidence: confidence,
      reasons: reasons,
      latestDate: latest.tradeDate,
      latestMainInflow: main,
      latestRetailInflow: retail,
      latestMainRatio: ratio,
      sixMonthPriceChangePercent: priceChange6m,
      sixMonthMainFlowSum: sum6m,
      recent20MainFlowSum: recent20,
      historicalSamePatternRate: patternRate,
    );
  }

  PredictionDirection _directionFromScore(double score) {
    if (score >= 22) return PredictionDirection.up;
    if (score <= -22) return PredictionDirection.down;
    return PredictionDirection.neutral;
  }

  double _confidence(double score, double patternRate, int sampleDays) {
    final absScore = score.abs().clamp(0, 50) / 50;
    final patternDev = (patternRate - 50).abs() / 50;
    final dataFactor = (sampleDays / sixMonthTradingDays).clamp(0.3, 1.0);
    return ((absScore * 0.5 + patternDev * 0.35) * dataFactor).clamp(0, 1);
  }

  double _sixMonthPriceChange(List<CapitalFlowDay> sorted) {
    final withPrice = sorted.where((d) => d.closePrice != null).toList();
    if (withPrice.length < 2) return 0;
    final first = withPrice.first.closePrice!;
    final last = withPrice.last.closePrice!;
    if (first == 0) return 0;
    return (last - first) / first * 100;
  }

  double _recentReturn(List<CapitalFlowDay> sorted, int days) {
    final withChange =
        sorted.where((d) => d.changePercent != null).toList();
    if (withChange.isEmpty) return 0;
    final slice = withChange.length <= days
        ? withChange
        : withChange.sublist(withChange.length - days);
    return slice.fold<double>(0, (s, d) => s + d.changePercent!);
  }

  double _flowMomentum(List<CapitalFlowDay> sorted) {
    if (sorted.length < 10) return 0;
    final last5 =
        sorted.sublist(sorted.length - 5).fold<double>(0, (s, d) => s + d.mainNetInflow);
    final prev5 = sorted
        .sublist(sorted.length - 10, sorted.length - 5)
        .fold<double>(0, (s, d) => s + d.mainNetInflow);
    return last5 - prev5;
  }

  /// 在历史中找与 latest 同向（主力/散户符号）的交易日，统计其次日收涨比例。
  double _historicalPatternWinRate(
    List<CapitalFlowDay> sorted,
    CapitalFlowDay latest,
  ) {
    final mainSign = latest.mainNetInflow >= 0 ? 1 : -1;
    final retailSign = latest.smallNetInflow >= 0 ? 1 : -1;

    var wins = 0;
    var total = 0;
    final start = sorted.length > patternLookback + 1
        ? sorted.length - patternLookback - 1
        : 0;

    for (var i = start; i < sorted.length - 1; i++) {
      final d = sorted[i];
      final dMainSign = d.mainNetInflow >= 0 ? 1 : -1;
      final dRetailSign = d.smallNetInflow >= 0 ? 1 : -1;
      if (dMainSign != mainSign || dRetailSign != retailSign) continue;
      final next = sorted[i + 1];
      if (next.changePercent == null) continue;
      total++;
      if (next.changePercent! > 0) wins++;
    }

    if (total < 5) return 50;
    return wins / total * 100;
  }
}
