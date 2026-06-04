class WatchStock {
  const WatchStock({
    required this.id,
    required this.code,
    required this.name,
    required this.market,
    required this.addedAt,
  });

  final String id;
  final String code;
  final String name;
  final String market;
  final DateTime addedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'market': market,
        'addedAt': addedAt.toIso8601String(),
      };

  factory WatchStock.fromJson(Map<String, dynamic> json) {
    return WatchStock(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String? ?? '',
      market: json['market'] as String? ?? 'sh',
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  WatchStock copyWith({String? name}) {
    return WatchStock(
      id: id,
      code: code,
      name: name ?? this.name,
      market: market,
      addedAt: addedAt,
    );
  }
}
