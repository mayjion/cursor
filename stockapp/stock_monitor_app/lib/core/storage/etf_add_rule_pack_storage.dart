import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/etf_models.dart';

const String _boxName = 'etf_add_rule_pack';
const String _key = 'current';

class EtfAddRulePackStorage {
  static Box<String>? _box;

  static Future<void> ensureOpen() async {
    _box ??= await Hive.openBox<String>(_boxName);
  }

  static Future<void> save(AddRulePack pack) async {
    await ensureOpen();
    await _box!.put(_key, jsonEncode(pack.toJson()));
  }

  static Future<AddRulePack?> load() async {
    await ensureOpen();
    final raw = _box!.get(_key);
    if (raw == null) return null;
    try {
      return AddRulePack.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    await ensureOpen();
    await _box!.delete(_key);
  }
}
