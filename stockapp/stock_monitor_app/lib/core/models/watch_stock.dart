enum AssetType {
  stock,
  etf;

  static AssetType fromCode(String code) {
    if (code.length != 6) return AssetType.stock;
    if (code.startsWith('51') ||
        code.startsWith('56') ||
        code.startsWith('58') ||
        code.startsWith('15')) {
      return AssetType.etf;
    }
    return AssetType.stock;
  }

  static AssetType parse(String? raw) {
    if (raw == 'etf') return AssetType.etf;
    return AssetType.stock;
  }
}

class WatchStock {
  const WatchStock({
    required this.id,
    required this.code,
    required this.name,
    required this.market,
    required this.addedAt,
    this.assetType = AssetType.stock,
    this.indexName = '',
  });

  final String id;
  final String code;
  final String name;
  final String market;
  final DateTime addedAt;
  final AssetType assetType;
  final String indexName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'market': market,
        'addedAt': addedAt.toIso8601String(),
        'assetType': assetType.name,
        'indexName': indexName,
      };

  factory WatchStock.fromJson(Map<String, dynamic> json) {
    final code = json['code'] as String;
    return WatchStock(
      id: json['id'] as String,
      code: code,
      name: json['name'] as String? ?? '',
      market: json['market'] as String? ?? 'sh',
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.now(),
      assetType: json['assetType'] != null
          ? AssetType.parse(json['assetType'] as String?)
          : AssetType.fromCode(code),
      indexName: json['indexName'] as String? ?? '',
    );
  }

  WatchStock copyWith({String? name, String? indexName, AssetType? assetType}) {
    return WatchStock(
      id: id,
      code: code,
      name: name ?? this.name,
      market: market,
      addedAt: addedAt,
      assetType: assetType ?? this.assetType,
      indexName: indexName ?? this.indexName,
    );
  }
}
