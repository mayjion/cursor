import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/recommendation.dart';
import '../models/stock_snapshot.dart';

const String _boxName = 'recommendation_cache';
const String _todayKey = 'today';
const String _digestKey = 'digest';
const String _newsKey = 'news';
const String _historyKey = 'history';
const String _scanMetaKey = 'scan_meta';
const String _industriesKey = 'industries';

class RecommendationCacheStorage {
  static Box<String>? _box;

  static Future<void> ensureOpen() async {
    _box ??= await Hive.openBox<String>(_boxName);
  }

  static Future<void> saveToday(TodayRecommendations data) async {
    await ensureOpen();
    await _box!.put(_todayKey, jsonEncode({
      'trade_date': data.tradeDate,
      'items': data.items.map((e) => e.toJson()).toList(),
    }));
  }

  static Future<TodayRecommendations?> loadToday() async {
    await ensureOpen();
    final raw = _box!.get(_todayKey);
    if (raw == null) return null;
    try {
      return TodayRecommendations.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> appendHistory(TodayRecommendations data) async {
    await ensureOpen();
    final existing = await loadHistory();
    existing.insert(0, data);
    final trimmed = existing.take(30).toList();
    await _box!.put(
      _historyKey,
      jsonEncode(trimmed
          .map((d) => {
                'trade_date': d.tradeDate,
                'items': d.items.map((e) => e.toJson()).toList(),
              })
          .toList()),
    );
  }

  static Future<List<TodayRecommendations>> loadHistory() async {
    await ensureOpen();
    final raw = _box!.get(_historyKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => TodayRecommendations.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<HistoryRecommendationItem>> loadHistoryFlat() async {
    final history = await loadHistory();
    final items = <HistoryRecommendationItem>[];
    for (final day in history) {
      for (final rec in day.items) {
        items.add(HistoryRecommendationItem(
          tradeDate: day.tradeDate,
          code: rec.code,
          name: rec.name,
          compositeScore: rec.compositeScore,
        ));
      }
    }
    return items;
  }

  static Future<void> saveScanMeta(ScanMeta meta) async {
    await ensureOpen();
    await _box!.put(_scanMetaKey, jsonEncode(meta.toJson()));
  }

  static Future<ScanMeta> loadScanMeta() async {
    await ensureOpen();
    final raw = _box!.get(_scanMetaKey);
    if (raw == null) return const ScanMeta();
    try {
      return ScanMeta.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return const ScanMeta();
    }
  }

  static Future<void> saveDigest(DailyDigest digest) async {
    await ensureOpen();
    await _box!.put(_digestKey, jsonEncode({
      'trade_date': digest.tradeDate,
      'market_summary': digest.marketSummary,
      'top_industries': digest.topIndustries,
      'key_events': digest.keyEvents,
    }));
  }

  static Future<DailyDigest?> loadDigest() async {
    await ensureOpen();
    final raw = _box!.get(_digestKey);
    if (raw == null) return null;
    try {
      return DailyDigest.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveIndustries(List<IndustryItem> items) async {
    await ensureOpen();
    await _box!.put(
      _industriesKey,
      jsonEncode(items
          .map((e) => {
                'industry': e.industry,
                'change_percent': e.changePercent,
                'main_net_inflow': e.mainNetInflow,
                'stock_count': e.stockCount,
              })
          .toList()),
    );
  }

  static Future<List<IndustryItem>> loadIndustries() async {
    await ensureOpen();
    final raw = _box!.get(_industriesKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => IndustryItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveNews(List<NewsArticleItem> items) async {
    await ensureOpen();
    await _box!.put(
      _newsKey,
      jsonEncode(items
          .map((e) => {
                'id': e.id,
                'title': e.title,
                'source': e.source,
                'url': e.url,
                'summary': e.summary,
                'stock_code': e.stockCode,
                'industry': e.industry,
                'published_at': e.publishedAt,
              })
          .toList()),
    );
  }

  static Future<List<NewsArticleItem>> loadNews() async {
    await ensureOpen();
    final raw = _box!.get(_newsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) =>
              NewsArticleItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<NewsArticleItem>> loadNewsForStock(String code) async {
    final all = await loadNews();
    return all.where((n) => n.stockCode == code).toList();
  }
}
