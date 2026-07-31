import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../background/foreground_scan.dart';
import '../engine/local_scan_engine.dart';
import '../models/institutional_hold_change_record.dart';
import '../models/recommendation.dart';
import '../models/stock_snapshot.dart';
import '../models/watch_stock.dart';
import '../notifications/notification_service.dart';
import '../settings/app_settings.dart';
import '../storage/recommendation_cache_storage.dart';
import '../storage/watchlist_storage.dart';
import 'stock_providers.dart';

final localScanEngineProvider = Provider<LocalScanEngine>((ref) {
  final engine = LocalScanEngine(client: ref.watch(eastmoneyClientProvider));
  ref.onDispose(engine.close);
  return engine;
});

class ScanProgressNotifier extends StateNotifier<ScanMeta> {
  ScanProgressNotifier() : super(const ScanMeta()) {
    _load();
  }

  Future<void> _load() async {
    state = await RecommendationCacheStorage.loadScanMeta();
  }

  Future<void> refresh() async {
    state = await RecommendationCacheStorage.loadScanMeta();
  }

  void update(int progress, String message) {
    state = state.copyWith(
      status: ScanStatus.running,
      progress: progress,
      progressMessage: message,
    );
  }
}

final scanProgressProvider =
    StateNotifierProvider<ScanProgressNotifier, ScanMeta>((ref) {
  return ScanProgressNotifier();
});

final scanMetaProvider = FutureProvider<ScanMeta>((ref) async {
  ref.watch(scanProgressProvider);
  return RecommendationCacheStorage.loadScanMeta();
});

final todayRecommendationsProvider =
    FutureProvider<TodayRecommendations>((ref) async {
  ref.watch(scanProgressProvider);
  final cached = await RecommendationCacheStorage.loadToday();
  if (cached != null) return cached;
  return TodayRecommendations(
    tradeDate: _todayString(),
    items: const [],
  );
});

final stockProfileProvider =
    FutureProvider.family<StockProfile, String>((ref, code) async {
  final client = ref.read(eastmoneyClientProvider);
  StockProfile profile;
  try {
    profile = await client.fetchStockProfile(code);
  } catch (_) {
    profile = StockProfile(code: code, name: code);
  }

  final today = await ref.watch(todayRecommendationsProvider.future);
  final cached = profileFromCode(code, today);
  return profile.copyWith(
    name: profile.name != code ? profile.name : cached.name,
    industry: profile.industry.isNotEmpty ? profile.industry : cached.industry,
    peTtm: profile.peTtm ?? cached.peTtm,
    pb: profile.pb ?? cached.pb,
    roe: profile.roe ?? cached.roe,
    dividendYield: profile.dividendYield ?? cached.dividendYield,
    compositeScore: cached.compositeScore ?? profile.compositeScore,
    valuationLabel: cached.valuationLabel.isNotEmpty
        ? cached.valuationLabel
        : profile.valuationLabel,
  );
});

final stockNewsProvider =
    FutureProvider.family<List<NewsArticleItem>, String>((ref, code) async {
  final client = ref.read(eastmoneyClientProvider);
  try {
    final live = await client.fetchStockNews(code, limit: 15);
    if (live.isNotEmpty) return live;
  } catch (_) {}
  return RecommendationCacheStorage.loadNewsForStock(code);
});

final institutionalHoldRecordsProvider = FutureProvider.family<
    List<InstitutionalHoldChangeRecord>, String>((ref, code) async {
  final client = ref.read(eastmoneyClientProvider);
  return client.fetchInstitutionalHoldRecords(code, limit: 40);
});

final marketNewsProvider = FutureProvider<List<NewsArticleItem>>((ref) async {
  final client = ref.read(eastmoneyClientProvider);
  try {
    final live = await client.fetchMarketNews(limit: 20);
    if (live.isNotEmpty) return live;
  } catch (_) {}
  return RecommendationCacheStorage.loadNews();
});

Future<void> refreshMarketNews(WidgetRef ref) async {
  ref.invalidate(marketNewsProvider);
  ref.invalidate(todayDigestProvider);
  ref.invalidate(industriesProvider);
}

final industriesProvider = FutureProvider<List<IndustryItem>>((ref) async {
  ref.watch(scanProgressProvider);
  final cached = await RecommendationCacheStorage.loadIndustries();
  if (cached.isNotEmpty) return cached;
  final client = ref.read(eastmoneyClientProvider);
  return client.fetchIndustryBoards();
});

final todayDigestProvider = FutureProvider<DailyDigest>((ref) async {
  ref.watch(scanProgressProvider);
  final cached = await RecommendationCacheStorage.loadDigest();
  if (cached != null) return cached;
  return DailyDigest(
    tradeDate: _todayString(),
    marketSummary: '',
  );
});

final recommendationHistoryProvider =
    FutureProvider<List<HistoryRecommendationItem>>((ref) async {
  return RecommendationCacheStorage.loadHistoryFlat();
});

Future<bool> addRecommendationToWatchlist(RecommendationItem item) async {
  final existing = await WatchlistStorage.getByCode(item.code);
  if (existing != null) return false;
  final market = item.code.startsWith('6') ? 'SH' : 'SZ';
  await WatchlistStorage.save(
    WatchStock(
      id: '${item.code}_${DateTime.now().millisecondsSinceEpoch}',
      code: item.code,
      name: item.name,
      market: market,
      addedAt: DateTime.now(),
    ),
  );
  return true;
}

Future<void> runLocalScan(WidgetRef ref, {bool notifyOnComplete = true}) async {
  final settings = ref.read(appSettingsProvider);
  final engine = ref.read(localScanEngineProvider);
  final progress = ref.read(scanProgressProvider.notifier);

  await ForegroundScanNotifier.start('正在扫描低估股票...');
  try {
    final result = await engine.run(
      topN: settings.recommendationLimit,
      excludeStarMarket: settings.excludeStarMarket,
      marketCapFilter: settings.marketCapFilter,
      onProgress: (p, msg) {
        progress.update(p, msg);
        ForegroundScanNotifier.update(msg);
      },
    );
    await progress.refresh();
    ref.invalidate(todayRecommendationsProvider);
    ref.invalidate(todayDigestProvider);
    ref.invalidate(marketNewsProvider);
    ref.invalidate(industriesProvider);
    ref.invalidate(recommendationHistoryProvider);
    if (notifyOnComplete && settings.recommendationNotifyEnabled) {
      await NotificationService.instance.showRecommendationUpdateAlert(
        count: result.items.length,
      );
    }
  } catch (_) {
    await progress.refresh();
    rethrow;
  } finally {
    await ForegroundScanNotifier.stop();
  }
}

Future<void> refreshRecommendations(WidgetRef ref) async {
  if (ref.read(scanProgressProvider).status == ScanStatus.running) return;
  await runLocalScan(ref);
}

String _todayString() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}
