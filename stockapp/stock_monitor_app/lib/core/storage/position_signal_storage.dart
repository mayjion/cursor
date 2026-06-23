import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/position_signal.dart';
import '../models/position_signal_record.dart';

const String _boxName = 'position_signals';

class PositionSignalStorage {
  static Box<String>? _box;

  static Future<void> ensureOpen() async {
    _box ??= await Hive.openBox<String>(_boxName);
  }

  static Future<void> save(PositionSignalRecord record) async {
    await ensureOpen();
    await _box!.put(record.id, jsonEncode(record.toJson()));
  }

  static Future<List<PositionSignalRecord>> list() async {
    await ensureOpen();
    final list = <PositionSignalRecord>[];
    for (final v in _box!.values) {
      try {
        list.add(PositionSignalRecord.fromJson(
            Map<String, dynamic>.from(jsonDecode(v) as Map)));
      } catch (_) {}
    }
    list.sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
    return list;
  }

  static Future<List<PositionSignalRecord>> listForCode(String code) async {
    final all = await list();
    return all.where((r) => r.code == code).toList();
  }

  static Future<PositionSignalRecord?> getForDate(
    String code,
    String date,
  ) async {
    final all = await listForCode(code);
    for (final r in all) {
      if (r.tradeDate == date) return r;
    }
    return null;
  }

  static Future<PositionSignalRecord?> getLatestForCode(String code) async {
    final all = await listForCode(code);
    return all.isNotEmpty ? all.first : null;
  }

  static Future<void> updateNotificationState(
    String id, {
    ReversalSeverity? lastNotifiedSeverity,
  }) async {
    await ensureOpen();
    final raw = _box!.get(id);
    if (raw == null) return;
    final record = PositionSignalRecord.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
    await _box!.put(
      id,
      jsonEncode(
        record.copyWith(lastNotifiedSeverity: lastNotifiedSeverity).toJson(),
      ),
    );
  }
}
