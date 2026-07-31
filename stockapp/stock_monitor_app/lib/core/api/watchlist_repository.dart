import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/stockserver_client.dart';
import '../models/watch_stock.dart';
import '../providers/server_providers.dart';

class WatchlistServerException implements Exception {
  WatchlistServerException(this.message);
  final String message;
  @override
  String toString() => message;
}

StockServerClient requireStockServerClient(Ref ref) {
  final conn = ref.read(serverConnectionProvider);
  final client = ref.read(stockServerClientProvider);
  if (client == null || !conn.connected) {
    throw WatchlistServerException('请先在设置中连接 stockserver，自选数据保存在服务端');
  }
  return client;
}

StockServerClient requireStockServerClientFromWidget(WidgetRef ref) {
  final conn = ref.read(serverConnectionProvider);
  final client = ref.read(stockServerClientProvider);
  if (client == null || !conn.connected) {
    throw WatchlistServerException('请先在设置中连接 stockserver，自选数据保存在服务端');
  }
  return client;
}

/// 服务端自选读写（不再使用手机本地 Hive 持久化）。
class WatchlistRepository {
  static Future<WatchlistPayload> fetch(Ref ref, {bool refresh = true}) async {
    final client = requireStockServerClient(ref);
    final raw = await client.watchlist(refresh: refresh);
    return WatchlistPayload.fromJson(raw);
  }

  static Future<WatchlistPayload> fetchWidget(
    WidgetRef ref, {
    bool refresh = true,
  }) async {
    final client = requireStockServerClientFromWidget(ref);
    final raw = await client.watchlist(refresh: refresh);
    return WatchlistPayload.fromJson(raw);
  }

  static Future<List<WatchStock>> list(Ref ref) async {
    return (await fetch(ref)).items;
  }

  static Future<WatchStock?> getByCode(Ref ref, String code) async {
    final c = code.padLeft(6, '0');
    final items = await list(ref);
    for (final s in items) {
      if (s.code == c) return s;
    }
    return null;
  }

  static Future<WatchStock?> getByCodeWidget(WidgetRef ref, String code) async {
    final c = code.padLeft(6, '0');
    final payload = await fetchWidget(ref);
    for (final s in payload.items) {
      if (s.code == c) return s;
    }
    return null;
  }

  static Future<WatchStock> save(
    WidgetRef ref, {
    required String code,
    required String name,
    required String market,
    AssetType assetType = AssetType.stock,
    String indexName = '',
  }) async {
    final client = requireStockServerClientFromWidget(ref);
    final raw = await client.addWatchlist(
      code: code,
      name: name,
      market: market,
      assetType: assetType.name,
      indexName: indexName,
    );
    final item = raw['item'];
    if (item is Map) {
      return WatchStock.fromJson(Map<String, dynamic>.from(item));
    }
    return WatchStock(
      id: code.padLeft(6, '0'),
      code: code.padLeft(6, '0'),
      name: name,
      market: market,
      addedAt: DateTime.now(),
      assetType: assetType,
      indexName: indexName,
    );
  }

  static Future<int> saveMany(
    WidgetRef ref,
    Iterable<WatchStock> stocks,
  ) async {
    final client = requireStockServerClientFromWidget(ref);
    final items = [
      for (final s in stocks)
        {
          'code': s.code,
          'name': s.name,
          'market': s.market,
          'asset_type': s.assetType.name,
          'index_name': s.indexName,
        },
    ];
    final raw = await client.addWatchlistBatch(items);
    return (raw['created'] as num?)?.toInt() ?? 0;
  }

  static Future<void> delete(WidgetRef ref, String codeOrId) async {
    final client = requireStockServerClientFromWidget(ref);
    await client.removeWatchlist(codeOrId);
  }

  static Future<void> deleteMany(WidgetRef ref, Iterable<String> codes) async {
    final client = requireStockServerClientFromWidget(ref);
    await client.removeWatchlistBatch(codes.toList());
  }
}
