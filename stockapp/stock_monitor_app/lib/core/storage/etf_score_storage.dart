import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/etf_models.dart';

const String _boxName = 'etf_scores';

class EtfScoreStorage {
  static Box<String>? _box;

  static Future<void> ensureOpen() async {
    _box ??= await Hive.openBox<String>(_boxName);
  }

  static Future<void> save(EtfBuyScore score) async {
    await ensureOpen();
    await _box!.put(score.code, jsonEncode(score.toJson()));
  }

  static Future<EtfBuyScore?> load(String code) async {
    await ensureOpen();
    final raw = _box!.get(code);
    if (raw == null) return null;
    try {
      return EtfBuyScore.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, EtfBuyScore>> loadAll() async {
    await ensureOpen();
    final map = <String, EtfBuyScore>{};
    for (final key in _box!.keys) {
      final code = key.toString();
      final score = await load(code);
      if (score != null) map[code] = score;
    }
    return map;
  }

  static Future<void> deleteMany(Iterable<String> codes) async {
    await ensureOpen();
    final list = codes.toList();
    if (list.isNotEmpty) await _box!.deleteAll(list);
  }

  static Future<void> clear() async {
    await ensureOpen();
    await _box!.clear();
  }
}
