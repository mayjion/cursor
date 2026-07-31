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
    this.addPrice,
    this.price,
    this.changePct,
    this.returnPct,
    this.note = '',
  });

  final String id;
  final String code;
  final String name;
  final String market;
  final DateTime addedAt;
  final AssetType assetType;
  final String indexName;
  /// 加入自选时的基准价（服务端）
  final double? addPrice;
  /// 当前价
  final double? price;
  /// 当日涨跌幅（小数或百分数由服务端约定：百分数，如 1.5 表示 1.5%）
  final double? changePct;
  /// 相对加入价的收益率（小数，如 0.05 = +5%）
  final double? returnPct;
  final String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'market': market,
        'addedAt': addedAt.toIso8601String(),
        'assetType': assetType.name,
        'indexName': indexName,
        'add_price': addPrice,
        'price': price,
        'change_pct': changePct,
        'return_pct': returnPct,
        'note': note,
      };

  factory WatchStock.fromJson(Map<String, dynamic> json) {
    final code = '${json['code'] ?? ''}'.padLeft(6, '0');
    final addedRaw = json['added_at'] ?? json['addedAt'];
    return WatchStock(
      id: '${json['id'] ?? code}',
      code: code,
      name: '${json['name'] ?? ''}',
      market: '${json['market'] ?? 'sz'}',
      addedAt: DateTime.tryParse('$addedRaw') ?? DateTime.now(),
      assetType: json['asset_type'] != null || json['assetType'] != null
          ? AssetType.parse('${json['asset_type'] ?? json['assetType']}')
          : AssetType.fromCode(code),
      indexName: '${json['index_name'] ?? json['indexName'] ?? ''}',
      addPrice: (json['add_price'] as num?)?.toDouble() ??
          (json['addPrice'] as num?)?.toDouble(),
      price: (json['price'] as num?)?.toDouble(),
      changePct: (json['change_pct'] as num?)?.toDouble() ??
          (json['changePct'] as num?)?.toDouble(),
      returnPct: (json['return_pct'] as num?)?.toDouble() ??
          (json['returnPct'] as num?)?.toDouble(),
      note: '${json['note'] ?? ''}',
    );
  }

  WatchStock copyWith({
    String? name,
    String? indexName,
    AssetType? assetType,
    double? addPrice,
    double? price,
    double? changePct,
    double? returnPct,
    String? note,
  }) {
    return WatchStock(
      id: id,
      code: code,
      name: name ?? this.name,
      market: market,
      addedAt: addedAt,
      assetType: assetType ?? this.assetType,
      indexName: indexName ?? this.indexName,
      addPrice: addPrice ?? this.addPrice,
      price: price ?? this.price,
      changePct: changePct ?? this.changePct,
      returnPct: returnPct ?? this.returnPct,
      note: note ?? this.note,
    );
  }
}

class WatchlistStats {
  const WatchlistStats({
    this.count = 0,
    this.pricedCount = 0,
    this.avgReturnPct,
    this.medianReturnPct,
    this.winCount = 0,
    this.loseCount = 0,
    this.winRate,
    this.bestCode,
    this.bestName,
    this.bestReturnPct,
    this.worstCode,
    this.worstName,
    this.worstReturnPct,
  });

  final int count;
  final int pricedCount;
  final double? avgReturnPct;
  final double? medianReturnPct;
  final int winCount;
  final int loseCount;
  final double? winRate;
  final String? bestCode;
  final String? bestName;
  final double? bestReturnPct;
  final String? worstCode;
  final String? worstName;
  final double? worstReturnPct;

  factory WatchlistStats.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const WatchlistStats();
    final best = json['best'];
    final worst = json['worst'];
    return WatchlistStats(
      count: (json['count'] as num?)?.toInt() ?? 0,
      pricedCount: (json['priced_count'] as num?)?.toInt() ?? 0,
      avgReturnPct: (json['avg_return_pct'] as num?)?.toDouble(),
      medianReturnPct: (json['median_return_pct'] as num?)?.toDouble(),
      winCount: (json['win_count'] as num?)?.toInt() ?? 0,
      loseCount: (json['lose_count'] as num?)?.toInt() ?? 0,
      winRate: (json['win_rate'] as num?)?.toDouble(),
      bestCode: best is Map ? '${best['code'] ?? ''}' : null,
      bestName: best is Map ? '${best['name'] ?? ''}' : null,
      bestReturnPct:
          best is Map ? (best['return_pct'] as num?)?.toDouble() : null,
      worstCode: worst is Map ? '${worst['code'] ?? ''}' : null,
      worstName: worst is Map ? '${worst['name'] ?? ''}' : null,
      worstReturnPct:
          worst is Map ? (worst['return_pct'] as num?)?.toDouble() : null,
    );
  }
}

class WatchlistPayload {
  const WatchlistPayload({
    required this.items,
    required this.stats,
    this.updatedAt,
  });

  final List<WatchStock> items;
  final WatchlistStats stats;
  final String? updatedAt;

  factory WatchlistPayload.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = <WatchStock>[];
    if (raw is List) {
      for (final row in raw) {
        if (row is Map) {
          items.add(WatchStock.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }
    return WatchlistPayload(
      items: items,
      stats: WatchlistStats.fromJson(
        json['stats'] is Map
            ? Map<String, dynamic>.from(json['stats'] as Map)
            : null,
      ),
      updatedAt: json['updated_at']?.toString(),
    );
  }
}
