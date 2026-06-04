import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/capital_flow_day.dart';

const String _boxName = 'flow_cache';

class FlowCacheStorage {
  static Box<String>? _box;

  static Future<void> ensureOpen() async {
    _box ??= await Hive.openBox<String>(_boxName);
  }

  static Future<void> save(CapitalFlowDay day) async {
    await ensureOpen();
    await _box!.put(day.storageKey(), jsonEncode(day.toJson()));
  }

  static Future<void> saveAll(List<CapitalFlowDay> days) async {
    for (final d in days) {
      await save(d);
    }
  }

  static Future<CapitalFlowDay?> get(String code, String tradeDate) async {
    await ensureOpen();
    final v = _box!.get('$code|$tradeDate');
    if (v == null) return null;
    try {
      return CapitalFlowDay.fromJson(
          Map<String, dynamic>.from(jsonDecode(v) as Map));
    } catch (_) {
      return null;
    }
  }

  static Future<List<CapitalFlowDay>> listForCode(String code) async {
    await ensureOpen();
    final list = <CapitalFlowDay>[];
    for (final key in _box!.keys) {
      if (key is! String || !key.startsWith('$code|')) continue;
      final v = _box!.get(key);
      if (v == null) continue;
      try {
        list.add(CapitalFlowDay.fromJson(
            Map<String, dynamic>.from(jsonDecode(v) as Map)));
      } catch (_) {}
    }
    list.sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    return list;
  }
}
