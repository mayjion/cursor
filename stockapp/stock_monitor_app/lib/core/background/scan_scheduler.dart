import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../engine/etf_score_service.dart';
import '../engine/local_scan_engine.dart';
import '../models/stock_snapshot.dart';
import '../notifications/notification_service.dart';
import '../storage/recommendation_cache_storage.dart';

const String nightScanTaskName = 'nightScanTask';
const String nightScanUniqueName = 'com.cursor.stock.night_scan';

const String etfSyncTaskName = 'etfDailySyncTask';
const String etfSyncUniqueName = 'com.cursor.stock.etf_daily_sync';

class ScanScheduler {
  ScanScheduler._();

  static Future<void> syncFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('night_scan_enabled') ?? false;
    if (enabled) {
      await scheduleNext();
    } else {
      await cancel();
    }
    // ETF 日更默认开启（锁屏/杀进程后由系统唤醒）
    await EtfSyncScheduler.ensureScheduled();
  }

  static Future<void> scheduleNext() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt('scan_hour') ?? 2;
    final minute = prefs.getInt('scan_minute') ?? 0;
    final delay = _delayUntilNext(hour, minute);
    await Workmanager().registerOneOffTask(
      nightScanUniqueName,
      nightScanTaskName,
      initialDelay: delay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(nightScanUniqueName);
  }

  static Duration _delayUntilNext(int hour, int minute) {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    while (next.weekday == DateTime.saturday || next.weekday == DateTime.sunday) {
      next = next.add(const Duration(days: 1));
    }
    return next.difference(now);
  }
}

/// ETF 每日后台同步（Workmanager）。
class EtfSyncScheduler {
  EtfSyncScheduler._();

  static Future<void> ensureScheduled() async {
    await Workmanager().registerPeriodicTask(
      etfSyncUniqueName,
      etfSyncTaskName,
      frequency: const Duration(hours: 12),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
    );
  }

  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(etfSyncUniqueName);
  }
}

@pragma('vm:entry-point')
void scanCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      await Hive.initFlutter();
      await NotificationService.instance.initialize();

      if (taskName == etfSyncTaskName ||
          taskName == Workmanager.iOSBackgroundTask) {
        await EtfScoreService.syncWatchlist(
          force: false,
          useForeground: false,
        );
        return true;
      }

      if (taskName != nightScanTaskName) return false;

      final prefs = await SharedPreferences.getInstance();
      final topN = prefs.getInt('recommendation_limit') ?? 15;
      final excludeStar = prefs.getBool('exclude_star_market') ?? true;
      final capFilter = prefs.getString('market_cap_filter') ?? 'all';
      final notify = prefs.getBool('recommendation_notify_enabled') ?? true;

      final engine = LocalScanEngine();
      final result = await engine.run(
        topN: topN.clamp(5, 20),
        excludeStarMarket: excludeStar,
        marketCapFilter: capFilter,
        onProgress: (_, msg) {},
      );
      engine.close();

      if (notify) {
        await NotificationService.instance.showRecommendationUpdateAlert(
          count: result.items.length,
        );
      }

      // 夜间扫描顺带补跑 ETF（跳过当日已缓存）
      await EtfScoreService.syncWatchlist(force: false, useForeground: false);
      await ScanScheduler.scheduleNext();
      return true;
    } catch (_) {
      if (taskName == nightScanTaskName) {
        await RecommendationCacheStorage.saveScanMeta(
          (await RecommendationCacheStorage.loadScanMeta()).copyWith(
            status: ScanStatus.failed,
            errorMessage: '夜间扫描失败',
          ),
        );
        await ScanScheduler.scheduleNext();
      }
      return false;
    }
  });
}
