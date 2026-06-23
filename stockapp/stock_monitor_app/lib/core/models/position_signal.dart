enum PositionSignalType {
  holdBaseOnly,
  hold,
  add,
  reduce,
  trendBreak,
  trendReversal,
}

enum TrendPhase {
  rightSideUptrend,
  leftSideDowntrend,
  neutral,
}

enum ReversalSeverity {
  earlyWarning,
  confirmed,
  deepDrop,
}

extension PositionSignalTypeX on PositionSignalType {
  String get storageKey => name;

  static PositionSignalType fromKey(String key) {
    return PositionSignalType.values.firstWhere(
      (e) => e.name == key,
      orElse: () => PositionSignalType.holdBaseOnly,
    );
  }

  int get sortOrder {
    return switch (this) {
      PositionSignalType.trendReversal => 0,
      PositionSignalType.trendBreak => 1,
      PositionSignalType.reduce => 2,
      PositionSignalType.add => 3,
      PositionSignalType.hold => 4,
      PositionSignalType.holdBaseOnly => 5,
    };
  }
}

extension TrendPhaseX on TrendPhase {
  String get storageKey => name;

  static TrendPhase fromKey(String key) {
    return TrendPhase.values.firstWhere(
      (e) => e.name == key,
      orElse: () => TrendPhase.neutral,
    );
  }
}

extension ReversalSeverityX on ReversalSeverity {
  String get storageKey => name;

  static ReversalSeverity? fromKey(String? key) {
    if (key == null) return null;
    for (final e in ReversalSeverity.values) {
      if (e.name == key) return e;
    }
    return null;
  }

  int get level {
    return switch (this) {
      ReversalSeverity.earlyWarning => 1,
      ReversalSeverity.confirmed => 2,
      ReversalSeverity.deepDrop => 3,
    };
  }
}
