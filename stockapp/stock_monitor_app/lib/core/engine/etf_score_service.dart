import '../api/eastmoney_client.dart';
import '../engine/etf_add_feature_miner.dart';
import '../engine/etf_flow_model.dart';
import '../engine/etf_flow_signal_analyzer.dart';
import '../models/etf_models.dart';
import '../models/stock_bar.dart';
import '../models/watch_stock.dart';
import '../storage/etf_add_rule_pack_storage.dart';
import '../storage/etf_score_storage.dart';
import '../storage/etf_share_cache_storage.dart';
import '../storage/watchlist_storage.dart';
import '../background/foreground_scan.dart';

class EtfSyncRunResult {
  const EtfSyncRunResult({
    required this.total,
    required this.fetched,
    required this.skippedFresh,
    required this.failed,
    this.rulePack,
  });

  final int total;
  final int fetched;
  final int skippedFresh;
  final int failed;
  final AddRulePack? rulePack;
}

/// 无 Riverpod 依赖的 ETF 评分计算与批量同步（可供 UI / Workmanager 共用）。
class EtfScoreService {
  static Future<EtfBuyScore> computeAndSave(
    EastmoneyClient client,
    String code, {
    bool forceNetwork = false,
    bool alignPrices = false,
    bool fetchBars = false,
    AddRulePack? rulePack,
  }) async {
    final loaded = await _loadSharesAndBars(
      client,
      code,
      forceNetwork: forceNetwork,
      alignPrices: alignPrices,
      fetchBars: fetchBars,
    );
    final pack = rulePack ??
        await EtfAddRulePackStorage.load() ??
        AddRulePack.empty;
    final score = _buildScore(
      code: code,
      shares: loaded.shares,
      bars: loaded.bars,
      rulePack: pack,
    );
    await EtfScoreStorage.save(score);
    return score;
  }

  static Future<({List<EtfSharePoint> shares, List<StockBar> bars})>
      _loadSharesAndBars(
    EastmoneyClient client,
    String code, {
    required bool forceNetwork,
    required bool alignPrices,
    required bool fetchBars,
  }) async {
    List<EtfSharePoint>? shares;
    if (!forceNetwork) {
      final entry = await EtfShareCacheStorage.loadEntry(code);
      if (entry != null && entry.isFreshToday && entry.points.isNotEmpty) {
        shares = entry.points;
      }
    }

    if (shares == null) {
      shares = await client.fetchEtfShareHistory(
        code,
        limit: 800,
        alignPrices: alignPrices,
      );
      if (shares.isNotEmpty) {
        await EtfShareCacheStorage.save(code, shares);
      }
    }

    List<StockBar> bars = const [];
    try {
      if (fetchBars) {
        bars = await client.fetchDailyBars(code, limit: 400);
      } else {
        bars = await client.fetchWeeklyBars(code, limit: 160);
      }
    } catch (_) {}

    return (shares: shares, bars: bars);
  }

  static EtfBuyScore _buildScore({
    required String code,
    required List<EtfSharePoint> shares,
    required List<StockBar> bars,
    required AddRulePack rulePack,
  }) {
    final features = EtfFlowModel.buildFeatures(shares, bars: bars);
    var score = EtfFlowModel.score(code, features);
    final result = EtfFlowSignalAnalyzer.analyze(
      code: code,
      shares: shares,
      bars: bars,
      rulePack: rulePack,
    );
    return _applySignals(score, result, rulePack);
  }

  static EtfBuyScore _applySignals(
    EtfBuyScore score,
    EtfFlowSignalResult result,
    AddRulePack rulePack,
  ) {
    final signals = result.signals;
    final winLine = rulePack.winSamples > 0
        ? '全池加仓规则胜率${((rulePack.winRate ?? 0) * 100).toStringAsFixed(0)}%'
            '（${rulePack.winHits}/${rulePack.winSamples}，'
            '${rulePack.validated ? '已达标>80%' : '未达标暂不预测'}）'
        : '全池历史样本不足，加仓规则暂未生效';

    final reasons = <String>[
      winLine,
      '加仓适配度 ${result.addFitness.toStringAsFixed(0)}',
      ...signals.where((s) => s.isActionable).map((s) => s.reason),
      ...signals.where((s) => !s.isActionable).take(2).map((s) => s.reason),
      ...score.reasons,
    ];
    final deduped = <String>[];
    for (final r in reasons) {
      if (!deduped.contains(r)) deduped.add(r);
    }

    var buy = score.buyIndex;
    // 用适配度主导买入指数，便于与列表排序一致
    if (result.addFitness >= 70) {
      buy = result.addFitness;
    } else if (result.addFitness >= 35) {
      buy = (40 + result.addFitness * 0.3).clamp(0, 100);
    }

    final actionableRisk =
        signals.where((s) => s.type == EtfFlowSignalType.risk && s.isActionable);
    final actionableAdd =
        signals.where((s) => s.type == EtfFlowSignalType.add && s.isActionable);

    if (actionableRisk.isNotEmpty) {
      buy = (buy - 15).clamp(0, 100);
    }

    String label = score.label;
    if (actionableRisk.isNotEmpty) {
      label = '风险';
    } else if (actionableAdd.isNotEmpty) {
      label = '加仓';
    } else if (buy >= 75) {
      label = '偏强';
    } else if (buy >= 55) {
      label = '关注';
    } else if (buy >= 40) {
      label = '中性';
    } else {
      label = '偏弱';
    }

    return score.copyWith(
      buyIndex: double.parse(buy.toStringAsFixed(1)),
      label: label,
      reasons: deduped.take(6).toList(),
      signals: signals,
      signalWinRate: rulePack.winRate,
      signalWinHits: rulePack.winHits,
      signalWinSamples: rulePack.winSamples,
      historySupportsAdd: rulePack.validated,
      addFitness: result.addFitness,
      ruleLines: rulePack.ruleLinesZh,
      replaceSignalMeta: true,
    );
  }

  /// 用本地缓存重挖全池规则并回写每只评分（不强制拉网）。
  static Future<AddRulePack> rebuildRulePackAndRescore({
    EastmoneyClient? client,
    void Function(EtfBuyScore score)? onScore,
  }) async {
    final c = client ?? EastmoneyClient();
    final ownsClient = client == null;
    try {
      final etfs = (await WatchlistStorage.list())
          .where((e) => e.assetType == AssetType.etf)
          .toList();
      final allSamples = <EtfAddSample>[];
      final loaded =
          <String, ({List<EtfSharePoint> shares, List<StockBar> bars})>{};

      for (final etf in etfs) {
        final shares = await EtfShareCacheStorage.loadPoints(etf.code) ?? [];
        if (shares.isEmpty) continue;
        List<StockBar> bars = const [];
        try {
          bars = await c.fetchWeeklyBars(etf.code, limit: 160);
        } catch (_) {}
        loaded[etf.code] = (shares: shares, bars: bars);
        allSamples.addAll(
          EtfAddSampleBuilder.build(
            code: etf.code,
            shares: shares,
            bars: bars,
          ),
        );
      }

      final settled = allSamples.where((s) => s.settled).toList();
      final pack = EtfAddFeatureMiner.mine(settled);
      await EtfAddRulePackStorage.save(pack);

      for (final entry in loaded.entries) {
        final score = _buildScore(
          code: entry.key,
          shares: entry.value.shares,
          bars: entry.value.bars,
          rulePack: pack,
        );
        await EtfScoreStorage.save(score);
        onScore?.call(score);
      }
      return pack;
    } finally {
      if (ownsClient) c.close();
    }
  }

  /// 批量同步自选 ETF：拉数 → 挖全池规则 → 按规则打分排序依据。
  static Future<EtfSyncRunResult> syncWatchlist({
    EastmoneyClient? client,
    bool force = false,
    bool useForeground = false,
    bool Function()? shouldContinue,
    void Function(int current, int total, String? code)? onProgress,
    void Function(EtfBuyScore score)? onScore,
  }) async {
    final c = client ?? EastmoneyClient();
    final ownsClient = client == null;
    final etfs = (await WatchlistStorage.list())
        .where((e) => e.assetType == AssetType.etf)
        .toList();
    if (etfs.isEmpty) {
      return const EtfSyncRunResult(
        total: 0,
        fetched: 0,
        skippedFresh: 0,
        failed: 0,
      );
    }

    if (useForeground) {
      await ForegroundScanNotifier.start('正在更新 ETF 0/${etfs.length}');
    }

    var fetched = 0;
    var skipped = 0;
    var failed = 0;
    final allSamples = <EtfAddSample>[];
    final loaded =
        <String, ({List<EtfSharePoint> shares, List<StockBar> bars})>{};

    try {
      await EastmoneyClient.withRequestGap(
        const Duration(milliseconds: 80),
        () async {
          for (var i = 0; i < etfs.length; i++) {
            if (shouldContinue != null && !shouldContinue()) break;
            final code = etfs[i].code;
            onProgress?.call(i, etfs.length, code);
            if (useForeground) {
              await ForegroundScanNotifier.update(
                '正在更新 ETF ${i + 1}/${etfs.length} $code',
              );
            }

            try {
              final fresh = !force &&
                  await EtfShareCacheStorage.isFreshToday(code);

              final data = await _loadSharesAndBars(
                c,
                code,
                forceNetwork: force || !fresh,
                alignPrices: false,
                fetchBars: false,
              );
              if (fresh && data.shares.isNotEmpty) {
                skipped++;
              } else {
                fetched++;
              }
              loaded[code] = data;
              allSamples.addAll(
                EtfAddSampleBuilder.build(
                  code: code,
                  shares: data.shares,
                  bars: data.bars,
                ),
              );
            } catch (_) {
              failed++;
            }

            onProgress?.call(i + 1, etfs.length, code);
          }
        },
      );

      if (useForeground) {
        await ForegroundScanNotifier.update('正在提炼全池加仓规则…');
      }

      final settled = allSamples.where((s) => s.settled).toList();
      final pack = EtfAddFeatureMiner.mine(settled);
      await EtfAddRulePackStorage.save(pack);

      for (final entry in loaded.entries) {
        final score = _buildScore(
          code: entry.key,
          shares: entry.value.shares,
          bars: entry.value.bars,
          rulePack: pack,
        );
        await EtfScoreStorage.save(score);
        onScore?.call(score);
      }

      return EtfSyncRunResult(
        total: etfs.length,
        fetched: fetched,
        skippedFresh: skipped,
        failed: failed,
        rulePack: pack,
      );
    } finally {
      if (useForeground) {
        await ForegroundScanNotifier.stop();
      }
      if (ownsClient) {
        c.close();
      }
    }
  }
}
