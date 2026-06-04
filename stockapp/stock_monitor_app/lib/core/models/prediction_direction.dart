enum PredictionDirection {
  up,
  down,
  neutral;

  String get key => name;

  static PredictionDirection fromKey(String? key) {
    return PredictionDirection.values.firstWhere(
      (e) => e.key == key,
      orElse: () => PredictionDirection.neutral,
    );
  }
}

enum ActualDirection {
  up,
  down,
  flat,
  pending;

  String get key => name;

  static ActualDirection fromKey(String? key) {
    if (key == null || key.isEmpty) return ActualDirection.pending;
    return ActualDirection.values.firstWhere(
      (e) => e.key == key,
      orElse: () => ActualDirection.pending,
    );
  }
}
