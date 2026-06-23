import 'position_signal.dart';
import 'position_signal_analysis.dart';

class PositionSignalRecord {
  const PositionSignalRecord({
    required this.id,
    required this.code,
    required this.tradeDate,
    required this.signalType,
    required this.trendPhase,
    required this.createdAt,
    this.reversalSeverity,
    this.isReversal = false,
    this.confidence = 0,
    this.strength = 1,
    this.resonanceScore = 0,
    this.triggeredSignals = const [],
    this.reasons = const [],
    this.suggestedAction,
    this.analysisSummary = '',
    this.retracePercent = 0,
    this.closePrice,
    this.lastNotifiedSeverity,
  });

  final String id;
  final String code;
  final String tradeDate;
  final PositionSignalType signalType;
  final TrendPhase trendPhase;
  final ReversalSeverity? reversalSeverity;
  final bool isReversal;
  final double confidence;
  final int strength;
  final int resonanceScore;
  final List<String> triggeredSignals;
  final List<String> reasons;
  final String? suggestedAction;
  final String analysisSummary;
  final double retracePercent;
  final double? closePrice;
  final ReversalSeverity? lastNotifiedSeverity;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'tradeDate': tradeDate,
        'signalType': signalType.storageKey,
        'trendPhase': trendPhase.storageKey,
        'reversalSeverity': reversalSeverity?.storageKey,
        'isReversal': isReversal,
        'confidence': confidence,
        'strength': strength,
        'resonanceScore': resonanceScore,
        'triggeredSignals': triggeredSignals,
        'reasons': reasons,
        'suggestedAction': suggestedAction,
        'analysisSummary': analysisSummary,
        'retracePercent': retracePercent,
        'closePrice': closePrice,
        'lastNotifiedSeverity': lastNotifiedSeverity?.storageKey,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PositionSignalRecord.fromJson(Map<String, dynamic> json) {
    return PositionSignalRecord(
      id: json['id'] as String,
      code: json['code'] as String,
      tradeDate: json['tradeDate'] as String,
      signalType: PositionSignalTypeX.fromKey(json['signalType'] as String),
      trendPhase: TrendPhaseX.fromKey(json['trendPhase'] as String),
      reversalSeverity:
          ReversalSeverityX.fromKey(json['reversalSeverity'] as String?),
      isReversal: json['isReversal'] as bool? ?? false,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      strength: json['strength'] as int? ?? 1,
      resonanceScore: json['resonanceScore'] as int? ?? 0,
      triggeredSignals: (json['triggeredSignals'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      reasons: (json['reasons'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      suggestedAction: json['suggestedAction'] as String?,
      analysisSummary: json['analysisSummary'] as String? ?? '',
      retracePercent: (json['retracePercent'] as num?)?.toDouble() ?? 0,
      closePrice: (json['closePrice'] as num?)?.toDouble(),
      lastNotifiedSeverity: ReversalSeverityX.fromKey(
        json['lastNotifiedSeverity'] as String?,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  PositionSignalRecord copyWith({
    ReversalSeverity? lastNotifiedSeverity,
  }) {
    return PositionSignalRecord(
      id: id,
      code: code,
      tradeDate: tradeDate,
      signalType: signalType,
      trendPhase: trendPhase,
      reversalSeverity: reversalSeverity,
      isReversal: isReversal,
      confidence: confidence,
      strength: strength,
      resonanceScore: resonanceScore,
      triggeredSignals: triggeredSignals,
      reasons: reasons,
      suggestedAction: suggestedAction,
      analysisSummary: analysisSummary,
      retracePercent: retracePercent,
      closePrice: closePrice,
      lastNotifiedSeverity: lastNotifiedSeverity ?? this.lastNotifiedSeverity,
      createdAt: createdAt,
    );
  }

  factory PositionSignalRecord.fromAnalysis({
    required String code,
    required String tradeDate,
    required PositionSignalAnalysis analysis,
    double? closePrice,
    ReversalSeverity? lastNotifiedSeverity,
  }) {
    return PositionSignalRecord(
      id: '${code}_$tradeDate',
      code: code,
      tradeDate: tradeDate,
      signalType: analysis.signalType,
      trendPhase: analysis.trendPhase,
      reversalSeverity: analysis.reversalSeverity,
      isReversal: analysis.isReversal,
      confidence: analysis.confidence,
      strength: analysis.strength,
      resonanceScore: analysis.resonanceScore,
      triggeredSignals: analysis.triggeredSignals,
      reasons: analysis.reasons,
      suggestedAction: analysis.suggestedAction,
      analysisSummary: analysis.summaryText,
      retracePercent: analysis.retracePercent,
      closePrice: closePrice,
      lastNotifiedSeverity: lastNotifiedSeverity,
      createdAt: DateTime.now(),
    );
  }
}
