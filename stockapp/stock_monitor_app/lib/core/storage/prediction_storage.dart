import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/prediction_record.dart';

const String _boxName = 'predictions';

class PredictionStorage {
  static Box<String>? _box;

  static Future<void> ensureOpen() async {
    _box ??= await Hive.openBox<String>(_boxName);
  }

  static Future<void> save(PredictionRecord record) async {
    await ensureOpen();
    await _box!.put(record.id, jsonEncode(record.toJson()));
  }

  static Future<List<PredictionRecord>> list() async {
    await ensureOpen();
    final list = <PredictionRecord>[];
    for (final v in _box!.values) {
      try {
        list.add(PredictionRecord.fromJson(
            Map<String, dynamic>.from(jsonDecode(v) as Map)));
      } catch (_) {}
    }
    list.sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
    return list;
  }

  static Future<List<PredictionRecord>> listForCode(String code) async {
    final all = await list();
    return all.where((r) => r.code == code).toList();
  }

  static Future<PredictionRecord?> getForDate(String code, String date) async {
    final all = await listForCode(code);
    for (final r in all) {
      if (r.tradeDate == date) return r;
    }
    return null;
  }

  static Future<List<PredictionRecord>> pendingVerification() async {
    final all = await list();
    return all.where((r) => !r.isVerified).toList();
  }
}
