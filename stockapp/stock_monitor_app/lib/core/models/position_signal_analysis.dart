import 'position_signal.dart';

class PositionSignalAnalysis {
  const PositionSignalAnalysis({
    required this.signalType,
    required this.trendPhase,
    required this.confidence,
    required this.strength,
    required this.reasons,
    required this.latestDate,
    this.reversalSeverity,
    this.isReversal = false,
    this.resonanceScore = 0,
    this.triggeredSignals = const [],
    this.suggestedAction,
    this.retracePercent = 0,
    this.ma20,
    this.ma30,
    this.ma60,
    this.rsi,
    this.adx,
    this.macdDif,
    this.macdDea,
    this.atrStopLoss,
    this.volumeRatio,
  });

  final PositionSignalType signalType;
  final TrendPhase trendPhase;
  final ReversalSeverity? reversalSeverity;
  final bool isReversal;
  final int strength;
  final double confidence;
  final int resonanceScore;
  final List<String> triggeredSignals;
  final String? suggestedAction;
  final double retracePercent;
  final double? ma20;
  final double? ma30;
  final double? ma60;
  final double? rsi;
  final double? adx;
  final double? macdDif;
  final double? macdDea;
  final double? atrStopLoss;
  final double? volumeRatio;
  final List<String> reasons;
  final String latestDate;

  String get summaryText {
    final action = suggestedAction;
    if (action != null && action.isNotEmpty) {
      return '${reasons.isNotEmpty ? reasons.first : ''} · $action';
    }
    return reasons.isNotEmpty ? reasons.first : '';
  }
}
