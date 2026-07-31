import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/eastmoney_client.dart';
import '../api/watchlist_repository.dart';
import '../engine/etf_flow_model.dart';
import '../engine/etf_score_service.dart';
import '../models/etf_models.dart';
import '../models/stock_bar.dart';
import '../models/watch_stock.dart';
import '../storage/etf_add_rule_pack_storage.dart';
import '../storage/etf_score_storage.dart';
import '../storage/etf_share_cache_storage.dart';
import '../storage/watchlist_storage.dart';
import 'investment_providers.dart';
import 'stock_providers.dart';

final etfWatchlistProvider = FutureProvider<List<WatchStock>>((ref) async {
  final all = await ref.watch(watchlistProvider.future);
  return all.where((e) => e.assetType == AssetType.etf).toList();
});

final stockWatchlistProvider = FutureProvider<List<WatchStock>>((ref) async {
  final all = await ref.watch(watchlistProvider.future);
  return all.where((e) => e.assetType == AssetType.stock).toList();
});

/// 本地缓存的 ETF 评分表；后台同步时逐只 upsert，UI 即时刷新。
class EtfScoreMapNotifier extends StateNotifier<Map<String, EtfBuyScore>> {
  EtfScoreMapNotifier() : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    state = await EtfScoreStorage.loadAll();
  }

  Future<void> reload() async {
    state = await EtfScoreStorage.loadAll();
  }

  void upsert(EtfBuyScore score) {
    state = {...state, score.code: score};
  }

  void removeCodes(Iterable<String> codes) {
    if (codes.isEmpty) return;
    final next = Map<String, EtfBuyScore>.from(state);
    for (final c in codes) {
      next.remove(c);
    }
    state = next;
  }

  Future<void> clear() async {
    await EtfScoreStorage.clear();
    state = const {};
  }
}

final etfScoreMapProvider =
    StateNotifierProvider<EtfScoreMapNotifier, Map<String, EtfBuyScore>>((ref) {
  return EtfScoreMapNotifier();
});

class EtfSyncProgress {
  const EtfSyncProgress({
    this.running = false,
    this.current = 0,
    this.total = 0,
    this.currentCode,
    this.skippedFresh = 0,
    this.fetched = 0,
  });

  final bool running;
  final int current;
  final int total;
  final String? currentCode;
  final int skippedFresh;
  final int fetched;

  double get fraction => total <= 0 ? 0 : current / total;

  EtfSyncProgress copyWith({
    bool? running,
    int? current,
    int? total,
    String? currentCode,
    int? skippedFresh,
    int? fetched,
    bool clearCode = false,
  }) {
    return EtfSyncProgress(
      running: running ?? this.running,
      current: current ?? this.current,
      total: total ?? this.total,
      currentCode: clearCode ? null : (currentCode ?? this.currentCode),
      skippedFresh: skippedFresh ?? this.skippedFresh,
      fetched: fetched ?? this.fetched,
    );
  }
}

/// 后台逐只同步；当日已缓存的跳过网络；可开前台服务锁屏继续。
class EtfSyncNotifier extends StateNotifier<EtfSyncProgress> {
  EtfSyncNotifier(this.ref) : super(const EtfSyncProgress());

  final Ref ref;
  bool _cancelled = false;

  Future<void> start({bool force = false}) async {
    if (state.running) return;
    _cancelled = false;

    final etfs = (await WatchlistStorage.list())
        .where((e) => e.assetType == AssetType.etf)
        .toList();
    if (etfs.isEmpty) {
      state = const EtfSyncProgress();
      return;
    }

    state = EtfSyncProgress(running: true, current: 0, total: etfs.length);

    final client = ref.read(eastmoneyClientProvider);
    final result = await EtfScoreService.syncWatchlist(
      client: client,
      force: force,
      useForeground: true,
      shouldContinue: () => !_cancelled && mounted,
      onProgress: (current, total, code) {
        if (!mounted || _cancelled) return;
        state = state.copyWith(
          running: true,
          current: current,
          total: total,
          currentCode: code,
        );
      },
      onScore: (score) {
        if (!mounted) return;
        ref.read(etfScoreMapProvider.notifier).upsert(score);
      },
    );

    if (!mounted) return;
    await ref.read(etfScoreMapProvider.notifier).reload();
    state = EtfSyncProgress(
      running: false,
      current: etfs.length,
      total: etfs.length,
      skippedFresh: result.skippedFresh,
      fetched: result.fetched,
    );
  }

  void cancel() {
    _cancelled = true;
  }
}

final etfSyncProvider =
    StateNotifierProvider<EtfSyncNotifier, EtfSyncProgress>((ref) {
  return EtfSyncNotifier(ref);
});

/// 触发后台同步（不阻塞调用方）。若已在跑则忽略。
void startEtfScoreSyncInBackground(WidgetRef ref, {bool force = false}) {
  unawaited(ref.read(etfSyncProvider.notifier).start(force: force));
}

final etfScoreProvider =
    FutureProvider.family<EtfBuyScore?, String>((ref, code) async {
  final cachedMap = ref.watch(etfScoreMapProvider);
  final fromMap = cachedMap[code];
  if (fromMap != null) return fromMap;
  final cached = await EtfScoreStorage.load(code);
  if (cached != null) return cached;
  final score = await EtfScoreService.computeAndSave(
    ref.read(eastmoneyClientProvider),
    code,
    forceNetwork: false,
    alignPrices: false,
    fetchBars: false,
  );
  ref.read(etfScoreMapProvider.notifier).upsert(score);
  return score;
});

/// 份额历史：优先本地缓存；无缓存再拉网并写入。
final etfShareHistoryProvider =
    FutureProvider.family<List<EtfSharePoint>, String>((ref, code) async {
  final cached = await EtfShareCacheStorage.loadPoints(code);
  if (cached != null && cached.isNotEmpty) return cached;
  final client = ref.read(eastmoneyClientProvider);
  final shares = await client.fetchEtfShareHistory(
    code,
    limit: 800,
    alignPrices: true,
  );
  if (shares.isNotEmpty) {
    await EtfShareCacheStorage.save(code, shares);
  }
  return shares;
});

/// ETF 周 K（详情页价格走势用）。
final etfWeeklyBarsProvider =
    FutureProvider.family<List<StockBar>, String>((ref, code) async {
  final client = ref.read(eastmoneyClientProvider);
  return client.fetchWeeklyBars(code, limit: 160);
});

Future<EtfBuyScore> refreshEtfScore(
  Ref ref,
  String code, {
  bool forceNetwork = true,
}) async {
  final score = await EtfScoreService.computeAndSave(
    ref.read(eastmoneyClientProvider),
    code,
    forceNetwork: forceNetwork,
    alignPrices: forceNetwork,
    fetchBars: forceNetwork,
  );
  ref.read(etfScoreMapProvider.notifier).upsert(score);
  return score;
}

Future<EtfBuyScore> refreshEtfScoreWithClient(
  EastmoneyClient client,
  String code, {
  bool forceNetwork = true,
}) {
  return EtfScoreService.computeAndSave(
    client,
    code,
    forceNetwork: forceNetwork,
    alignPrices: forceNetwork,
    fetchBars: forceNetwork,
  );
}

Future<void> refreshAllEtfScores(WidgetRef ref) async {
  startEtfScoreSyncInBackground(ref);
}

class BulkAddEtfResult {
  const BulkAddEtfResult({
    required this.matched,
    required this.added,
    required this.skipped,
  });

  final int matched;
  final int added;
  final int skipped;
}

/// 按规模（亿元）一键添加场内 ETF；已在自选中的会跳过。
Future<BulkAddEtfResult> bulkAddEtfsByScale(
  WidgetRef ref, {
  required double minScaleYi,
}) async {
  final client = ref.read(eastmoneyClientProvider);
  final universe = await client.fetchEtfUniverse(
    pageSize: 200,
    maxPages: 20,
    minScaleYi: minScaleYi,
  );
  final existing = await WatchlistStorage.list();
  final existingCodes = existing.map((e) => e.code).toSet();
  final now = DateTime.now();
  final toAdd = <WatchStock>[];
  for (final info in universe) {
    if (existingCodes.contains(info.code)) continue;
    if (!EastmoneyClient.isEtfCode(info.code)) continue;
    toAdd.add(
      WatchStock(
        id: info.code,
        code: info.code,
        name: info.name,
        market: EastmoneyClient.marketFromCode(info.code),
        addedAt: now,
        assetType: AssetType.etf,
        indexName: info.indexName,
      ),
    );
  }
  await WatchlistRepository.saveMany(ref, toAdd);
  ref.invalidate(watchlistPayloadProvider);
  ref.invalidate(watchlistProvider);
  ref.invalidate(watchlistItemsProvider);
  ref.invalidate(etfWatchlistProvider);
  if (toAdd.isNotEmpty) {
    startEtfScoreSyncInBackground(ref);
  }
  return BulkAddEtfResult(
    matched: universe.length,
    added: toAdd.length,
    skipped: universe.length - toAdd.length,
  );
}

/// 清空全部自选 ETF（含评分与份额缓存、加仓规则包）。
Future<int> clearAllEtfs(WidgetRef ref) async {
  ref.read(etfSyncProvider.notifier).cancel();
  final all = await WatchlistStorage.list();
  final etfs = all.where((e) => e.assetType == AssetType.etf).toList();
  if (etfs.isEmpty) return 0;
  final codes = etfs.map((e) => e.code).toList();
  await WatchlistRepository.deleteMany(ref, codes);
  await EtfScoreStorage.deleteMany(codes);
  await EtfShareCacheStorage.deleteMany(codes);
  await EtfAddRulePackStorage.clear();
  ref.read(etfScoreMapProvider.notifier).removeCodes(codes);
  ref.invalidate(watchlistPayloadProvider);
  ref.invalidate(watchlistProvider);
  ref.invalidate(watchlistItemsProvider);
  ref.invalidate(etfWatchlistProvider);
  return etfs.length;
}

/// 总览列表：本地评分即时刷新；行业/资讯异步加载后补全叙述。
final etfOverviewProvider = Provider<List<EtfOverviewItem>>((ref) {
  final etfs = ref.watch(etfWatchlistProvider).valueOrNull ?? [];
  if (etfs.isEmpty) return const [];

  final scores = ref.watch(etfScoreMapProvider);
  final industries = ref.watch(industriesProvider).valueOrNull ?? const [];
  final news = ref.watch(marketNewsProvider).valueOrNull ?? const [];

  final items = <EtfOverviewItem>[];
  for (final etf in etfs) {
    final score = scores[etf.code] ??
        EtfBuyScore(
          code: etf.code,
          buyIndex: 50,
          label: '待更新',
          reasons: const ['后台同步中，完成后自动更新'],
        );

    String? industryHint;
    final indexName = etf.indexName;
    if (indexName.isNotEmpty) {
      for (final ind in industries) {
        final name = ind.industry;
        if (name.isEmpty) continue;
        if (indexName.contains(name) || name.contains(indexName)) {
          final chgInd = ind.changePercent;
          if (chgInd != null) {
            industryHint =
                '相关行业「$name」近期${chgInd >= 0 ? '上涨' : '下跌'}${chgInd.abs().toStringAsFixed(1)}%';
          }
          break;
        }
      }
    }

    final newsTitles = <String>[];
    for (final n in news.take(10)) {
      final title = n.title;
      if (title.isEmpty) continue;
      final hitIndex = indexName.length >= 2 && title.contains(indexName);
      final hitName =
          etf.name.length >= 2 && title.contains(etf.name.substring(0, 2));
      if (hitIndex || hitName) newsTitles.add(title);
    }
    if (newsTitles.isEmpty) {
      newsTitles.addAll(
        news.take(2).map((e) => e.title).where((t) => t.isNotEmpty),
      );
    }

    items.add(
      EtfOverviewItem(
        code: etf.code,
        name: etf.name,
        score: score,
        indexName: indexName,
        narrative: EtfFlowModel.buildNarrative(
          name: etf.name,
          score: score,
          indexName: indexName,
          industryHint: industryHint,
          newsTitles: newsTitles,
        ),
      ),
    );
  }

  items.sort((a, b) {
    final fit = b.score.addFitness.compareTo(a.score.addFitness);
    if (fit != 0) return fit;
    final wr = (b.score.signalWinRate ?? 0)
        .compareTo(a.score.signalWinRate ?? 0);
    if (wr != 0) return wr;
    final buy = b.score.buyIndex.compareTo(a.score.buyIndex);
    if (buy != 0) return buy;
    return a.code.compareTo(b.code);
  });
  return items;
});
