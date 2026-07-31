import '../models/watch_stock.dart';

/// 自选仅作内存缓存（真相源在 stockserver，不落手机盘）。
class WatchlistStorage {
  static List<WatchStock> _cache = [];

  static void setCache(List<WatchStock> items) {
    _cache = List<WatchStock>.from(items);
  }

  static void clearCache() => _cache = [];

  static Future<void> ensureOpen() async {}

  static Future<List<WatchStock>> list() async {
    final list = List<WatchStock>.from(_cache);
    list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list;
  }

  static Future<WatchStock?> getByCode(String code) async {
    final c = code.padLeft(6, '0');
    for (final s in _cache) {
      if (s.code == c) return s;
    }
    return null;
  }

  @Deprecated('Use WatchlistRepository.save')
  static Future<void> save(WatchStock stock) async {
    throw UnsupportedError('自选已改为服务端存储，请使用 WatchlistRepository');
  }

  @Deprecated('Use WatchlistRepository.saveMany')
  static Future<void> saveMany(Iterable<WatchStock> stocks) async {
    throw UnsupportedError('自选已改为服务端存储，请使用 WatchlistRepository');
  }

  @Deprecated('Use WatchlistRepository.delete')
  static Future<void> delete(String id) async {
    throw UnsupportedError('自选已改为服务端存储，请使用 WatchlistRepository');
  }

  @Deprecated('Use WatchlistRepository.deleteMany')
  static Future<void> deleteMany(Iterable<String> ids) async {
    throw UnsupportedError('自选已改为服务端存储，请使用 WatchlistRepository');
  }
}
