import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/watch_stock.dart';

const String _boxName = 'watchlist';

class WatchlistStorage {
  static Box<String>? _box;

  static Future<void> ensureOpen() async {
    _box ??= await Hive.openBox<String>(_boxName);
  }

  static Future<void> save(WatchStock stock) async {
    await ensureOpen();
    await _box!.put(stock.id, jsonEncode(stock.toJson()));
  }

  static Future<void> saveMany(Iterable<WatchStock> stocks) async {
    await ensureOpen();
    final map = <String, String>{
      for (final s in stocks) s.id: jsonEncode(s.toJson()),
    };
    if (map.isNotEmpty) await _box!.putAll(map);
  }

  static Future<void> deleteMany(Iterable<String> ids) async {
    await ensureOpen();
    final list = ids.toList();
    if (list.isNotEmpty) await _box!.deleteAll(list);
  }

  static Future<void> delete(String id) async {
    await ensureOpen();
    await _box!.delete(id);
  }

  static Future<List<WatchStock>> list() async {
    await ensureOpen();
    final list = <WatchStock>[];
    for (final v in _box!.values) {
      try {
        list.add(WatchStock.fromJson(
            Map<String, dynamic>.from(jsonDecode(v) as Map)));
      } catch (_) {}
    }
    list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list;
  }

  static Future<WatchStock?> getByCode(String code) async {
    final all = await list();
    for (final s in all) {
      if (s.code == code) return s;
    }
    return null;
  }
}
