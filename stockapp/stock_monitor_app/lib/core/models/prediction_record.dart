import 'prediction_direction.dart';

class PredictionRecord {
  const PredictionRecord({
    required this.id,
    required this.code,
    required this.tradeDate,
    required this.direction,
    required this.mainNetInflow,
    required this.mainNetRatio,
    required this.createdAt,
    this.actual = ActualDirection.pending,
    this.actualChangePercent,
    this.verifiedAt,
    this.analysisSummary,
    this.confidenceScore,
    this.compositeScore,
  });

  final String id;
  final String code;
  final String tradeDate;
  final PredictionDirection direction;
  final double mainNetInflow;
  final double mainNetRatio;
  final DateTime createdAt;
  final ActualDirection actual;
  final double? actualChangePercent;
  final DateTime? verifiedAt;
  final String? analysisSummary;
  final double? confidenceScore;
  final double? compositeScore;

  bool get isVerified => actual != ActualDirection.pending;

  bool get isHit {
    if (!isVerified || direction == PredictionDirection.neutral) {
      return false;
    }
    if (direction == PredictionDirection.up) {
      return actual == ActualDirection.up;
    }
    if (direction == PredictionDirection.down) {
      return actual == ActualDirection.down;
    }
    return false;
  }

  bool get countsForAccuracy =>
      isVerified && direction != PredictionDirection.neutral;

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'tradeDate': tradeDate,
        'direction': direction.key,
        'mainNetInflow': mainNetInflow,
        'mainNetRatio': mainNetRatio,
        'createdAt': createdAt.toIso8601String(),
        'actual': actual.key,
        'actualChangePercent': actualChangePercent,
        'verifiedAt': verifiedAt?.toIso8601String(),
        'analysisSummary': analysisSummary,
        'confidenceScore': confidenceScore,
        'compositeScore': compositeScore,
      };

  factory PredictionRecord.fromJson(Map<String, dynamic> json) {
    return PredictionRecord(
      id: json['id'] as String,
      code: json['code'] as String,
      tradeDate: json['tradeDate'] as String,
      direction: PredictionDirection.fromKey(json['direction'] as String?),
      mainNetInflow: (json['mainNetInflow'] as num?)?.toDouble() ?? 0,
      mainNetRatio: (json['mainNetRatio'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      actual: ActualDirection.fromKey(json['actual'] as String?),
      actualChangePercent: (json['actualChangePercent'] as num?)?.toDouble(),
      verifiedAt: json['verifiedAt'] != null
          ? DateTime.tryParse(json['verifiedAt'] as String)
          : null,
      analysisSummary: json['analysisSummary'] as String?,
      confidenceScore: (json['confidenceScore'] as num?)?.toDouble(),
      compositeScore: (json['compositeScore'] as num?)?.toDouble(),
    );
  }

  PredictionRecord copyWith({
    ActualDirection? actual,
    double? actualChangePercent,
    DateTime? verifiedAt,
    PredictionDirection? direction,
    String? analysisSummary,
    double? confidenceScore,
    double? compositeScore,
  }) {
    return PredictionRecord(
      id: id,
      code: code,
      tradeDate: tradeDate,
      direction: direction ?? this.direction,
      mainNetInflow: mainNetInflow,
      mainNetRatio: mainNetRatio,
      createdAt: createdAt,
      actual: actual ?? this.actual,
      actualChangePercent: actualChangePercent ?? this.actualChangePercent,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      analysisSummary: analysisSummary ?? this.analysisSummary,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      compositeScore: compositeScore ?? this.compositeScore,
    );
  }
}
