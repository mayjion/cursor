import 'prediction_direction.dart';

/// 综合推测结果（含评分与依据）。
class PredictionAnalysis {
  const PredictionAnalysis({
    required this.direction,
    required this.score,
    required this.confidence,
    required this.reasons,
    required this.latestDate,
    required this.latestMainInflow,
    required this.latestRetailInflow,
    required this.latestMainRatio,
    required this.sixMonthPriceChangePercent,
    required this.sixMonthMainFlowSum,
    required this.recent20MainFlowSum,
    required this.historicalSamePatternRate,
  });

  final PredictionDirection direction;
  /// 综合评分，正值偏多、负值偏空。
  final double score;
  /// 0–1，历史样本与信号一致程度。
  final double confidence;
  final List<String> reasons;
  final String latestDate;
  final double latestMainInflow;
  final double latestRetailInflow;
  final double latestMainRatio;
  final double sixMonthPriceChangePercent;
  final double sixMonthMainFlowSum;
  final double recent20MainFlowSum;
  /// 近6月内「主力与散户同向模式」后次日上涨比例（%）。
  final double historicalSamePatternRate;

  String get summaryText => reasons.join('；');
}
