import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../models/etf_models.dart';

const String _boxName = 'etf_share_cache';

class EtfShareCacheEntry {
  const EtfShareCacheEntry({
    required this.code,
    required this.fetchedAt,
    required this.points,
  });

  final String code;
  final DateTime fetchedAt;
  final List<EtfSharePoint> points;

  String get fetchedDay => DateFormat('yyyy-MM-dd').format(fetchedAt);

  bool get isFreshToday {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return fetchedDay == today;
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'fetchedAt': fetchedAt.toIso8601String(),
        'points': points.map((e) => e.toJson()).toList(),
      };

  factory EtfShareCacheEntry.fromJson(Map<String, dynamic> json) {
    return EtfShareCacheEntry(
      code: json['code'] as String? ?? '',
      fetchedAt: DateTime.tryParse(json['fetchedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      points: (json['points'] as List<dynamic>? ?? [])
          .map((e) => EtfSharePoint.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(),
    );
  }
}

/// ETF 份额序列本地缓存：同一自然日整包只拉一次网络。
class EtfShareCacheStorage {
  static Box<String>? _box;

  static Future<void> ensureOpen() async {
    _box ??= await Hive.openBox<String>(_boxName);
  }

  static Future<void> save(String code, List<EtfSharePoint> points) async {
    await ensureOpen();
    final entry = EtfShareCacheEntry(
      code: code,
      fetchedAt: DateTime.now(),
      points: points,
    );
    await _box!.put(code, jsonEncode(entry.toJson()));
  }

  static Future<EtfShareCacheEntry?> loadEntry(String code) async {
    await ensureOpen();
    final raw = _box!.get(code);
    if (raw == null) return null;
    try {
      return EtfShareCacheEntry.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<EtfSharePoint>?> loadPoints(String code) async {
    final entry = await loadEntry(code);
    return entry?.points;
  }

  static Future<bool> isFreshToday(String code) async {
    final entry = await loadEntry(code);
    return entry?.isFreshToday ?? false;
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
