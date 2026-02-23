import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'device_entity.dart';

const String _boxName = 'devices';

/// Device list storage: save/delete/list using Hive.
class DeviceStorage {
  static Box<String>? _box;

  static Future<void> ensureOpen() async {
    _box ??= await Hive.openBox<String>(_boxName);
  }

  static Future<void> save(DeviceEntity entity) async {
    await ensureOpen();
    await _box!.put(entity.id, jsonEncode(entity.toJson()));
  }

  static Future<void> delete(String id) async {
    await ensureOpen();
    await _box!.delete(id);
  }

  static Future<List<DeviceEntity>> list() async {
    await ensureOpen();
    final list = <DeviceEntity>[];
    for (final v in _box!.values) {
      try {
        list.add(DeviceEntity.fromJson(
            Map<String, dynamic>.from(jsonDecode(v) as Map)));
      } catch (_) {
        // skip malformed
      }
    }
    return list;
  }

  static Future<DeviceEntity?> get(String id) async {
    await ensureOpen();
    final v = _box!.get(id);
    if (v == null) return null;
    try {
      return DeviceEntity.fromJson(
          Map<String, dynamic>.from(jsonDecode(v) as Map));
    } catch (_) {
      return null;
    }
  }
}
