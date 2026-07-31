import '../api/eastmoney_client.dart';

import '../models/market_space_context.dart';

import '../models/recommendation.dart';

import '../models/stock_snapshot.dart';

import '../storage/recommendation_cache_storage.dart';

import 'valuation_scorer.dart';



typedef ScanProgressCallback = void Function(int progress, String message);



class LocalScanEngine {

  LocalScanEngine({EastmoneyClient? client})

      : _client = client ?? EastmoneyClient();



  final EastmoneyClient _client;

  static bool cancelRequested = false;



  static void requestCancel() => cancelRequested = true;



  Future<TodayRecommendations> run({

    required int topN,

    bool excludeStarMarket = true,

    String marketCapFilter = 'all',

    int enrichTopN = 50,

    ScanProgressCallback? onProgress,

  }) async {

    cancelRequested = false;

    final started = DateTime.now();

    await RecommendationCacheStorage.saveScanMeta(

      ScanMeta(status: ScanStatus.running, progress: 0, progressMessage: '开始扫描'),

    );

    onProgress?.call(0, '开始扫描');



    try {

      onProgress?.call(5, '拉取全市场数据...');

      var snapshots = await _client.fetchAShareUniverse();

      _checkCancelled();



      onProgress?.call(12, '拉取行业板块...');

      final industries = await _client.fetchIndustryBoards(limit: 50);

      final spaceContext = MarketSpaceContext.fromIndustryBoards(industries);



      onProgress?.call(15, '映射行业分类...');

      await _client.enrichSnapshotsWithIndustry(snapshots);

      _checkCancelled();



      onProgress?.call(20, '计算 GARP 综合评分...');

      var scored = scoreUniverseInitial(

        snapshots,

        excludeStarMarket: excludeStarMarket,

        marketCapFilter: marketCapFilter,

        spaceContext: spaceContext,

      );

      final top = scored.take(enrichTopN).toList();

      final industryReportCache = <String, double>{};



      for (var i = 0; i < top.length; i++) {

        _checkCancelled();

        final item = top[i];

        final pct = 25 + ((i + 1) / top.length * 50).round();

        onProgress?.call(pct, '深度分析 ${i + 1}/${top.length} ${item.snapshot.name}');



        final research = await _client.fetchResearchSummary(item.snapshot.code);

        if (research.indvInduCode.isNotEmpty &&

            !industryReportCache.containsKey(research.indvInduCode)) {

          industryReportCache[research.indvInduCode] =

              await _client.fetchIndustryReportScore(research.indvInduCode);

        }



        final growth = scoreGrowth(item.snapshot, research: research);

        item.growthScore = growth.score;

        item.reasons.addAll(growth.reasons);



        final institution =

            await _client.fetchInstitutionalHoldChange(item.snapshot.code);

        final instScore = scoreInstitution(institution);

        item.institutionScore = instScore.score;

        item.reasons.addAll(instScore.reasons);



        item.capitalScore =

            await _client.fetchCapitalFlowScore(item.snapshot.code);

        item.technicalScore =

            await _client.fetchTechnicalScore(item.snapshot.code);

        recalculateComposite(item);

      }



      if (industryReportCache.isNotEmpty) {

        final enrichedContext = MarketSpaceContext(

          industryBoards: spaceContext.industryBoards,

          industryReportScores: industryReportCache,

          hotKeywords: spaceContext.hotKeywords,

        );

        for (final item in top) {

          final space = scoreMarketSpace(item.snapshot, enrichedContext);

          item.spaceScore = space.score;

          item.reasons.addAll(space.reasons);

          recalculateComposite(item);

        }

      }



      top.sort((a, b) => b.compositeScore.compareTo(a.compositeScore));

      final tradeDate = _formatDate(DateTime.now());

      final items = top.take(topN).toList().asMap().entries.map((e) {

        final rank = e.key + 1;

        final s = e.value;

        final uniqueReasons = s.reasons.toSet().take(6).toList();

        return RecommendationItem(

          code: s.snapshot.code,

          name: s.snapshot.name,

          industry: s.snapshot.industry,

          rank: rank,

          compositeScore: double.parse(s.compositeScore.toStringAsFixed(2)),

          valuationScore: double.parse(s.valuationScore.toStringAsFixed(2)),

          growthScore: double.parse(s.growthScore.toStringAsFixed(2)),

          spaceScore: double.parse(s.spaceScore.toStringAsFixed(2)),

          institutionScore: double.parse(s.institutionScore.toStringAsFixed(2)),

          capitalScore: double.parse(s.capitalScore.toStringAsFixed(2)),

          technicalScore: double.parse(s.technicalScore.toStringAsFixed(2)),

          peTtm: s.snapshot.peTtm,

          pb: s.snapshot.pb,

          roe: s.snapshot.roe,

          dividendYield: s.snapshot.dividendYield,

          reasons: uniqueReasons,

        );

      }).toList();



      onProgress?.call(80, '保存推荐结果...');

      final today = TodayRecommendations(tradeDate: tradeDate, items: items);

      await RecommendationCacheStorage.saveToday(today);

      await RecommendationCacheStorage.appendHistory(today);



      onProgress?.call(85, '拉取行业与新闻...');

      await RecommendationCacheStorage.saveIndustries(industries);



      final allNews = <NewsArticleItem>[];

      final marketNews = await _client.fetchMarketNews(limit: 15);

      allNews.addAll(marketNews);

      for (final item in items.take(10)) {

        _checkCancelled();

        final news = await _client.fetchStockNews(item.code, limit: 3);

        allNews.addAll(news);

      }

      await RecommendationCacheStorage.saveNews(allNews);



      final digest = _buildDigest(tradeDate, items, industries);

      await RecommendationCacheStorage.saveDigest(digest);



      final duration = DateTime.now().difference(started).inMilliseconds;

      await RecommendationCacheStorage.saveScanMeta(

        ScanMeta(

          status: ScanStatus.done,

          lastScanAt: DateTime.now(),

          lastDurationMs: duration,

          progress: 100,

          progressMessage: '扫描完成',

        ),

      );

      onProgress?.call(100, '扫描完成');

      return today;

    } catch (e) {

      final status =

          cancelRequested ? ScanStatus.cancelled : ScanStatus.failed;

      await RecommendationCacheStorage.saveScanMeta(

        ScanMeta(

          status: status,

          lastScanAt: DateTime.now(),

          progress: 0,

          progressMessage: status == ScanStatus.cancelled ? '已取消' : '扫描失败',

          errorMessage: e.toString(),

        ),

      );

      rethrow;

    } finally {

      cancelRequested = false;

    }

  }



  void _checkCancelled() {

    if (cancelRequested) {

      throw Exception('扫描已取消');

    }

  }



  DailyDigest _buildDigest(

    String tradeDate,

    List<RecommendationItem> items,

    List<IndustryItem> industries,

  ) {

    final recIndustries =

        items.map((e) => e.industry).where((e) => e.isNotEmpty).toSet().take(3);

    final topNames = items.take(5).map((e) => e.name).join('、');

    final summary =

        '今日共推荐${items.length}只 GARP 候选股（估值+成长+空间+机构），重点关注：${recIndustries.join('、')}。Top5：$topNames。';

    final topInd = industries

        .where((i) => i.changePercent != null)

        .map((i) => {

              'industry': i.industry,

              'change': i.changePercent,

            })

        .take(5)

        .toList();

    final events = items

        .take(3)

        .map((r) =>

            '${r.name}(${r.code})：${r.reasons.isNotEmpty ? r.reasons.first : ''}')

        .toList();

    return DailyDigest(

      tradeDate: tradeDate,

      marketSummary: summary,

      topIndustries: topInd,

      keyEvents: events,

    );

  }



  String _formatDate(DateTime dt) {

    return '${dt.year.toString().padLeft(4, '0')}-'

        '${dt.month.toString().padLeft(2, '0')}-'

        '${dt.day.toString().padLeft(2, '0')}';

  }



  void close() => _client.close();

}



StockProfile profileFromRecommendation(RecommendationItem item) {

  var label = '合理';

  if (item.peTtm != null && item.peTtm! < 15) label = '低估';

  if (item.peTtm != null && item.peTtm! > 40) label = '高估';

  return StockProfile(

    code: item.code,

    name: item.name,

    industry: item.industry,

    peTtm: item.peTtm,

    pb: item.pb,

    roe: item.roe,

    dividendYield: item.dividendYield,

    compositeScore: item.compositeScore,

    valuationLabel: label,

    concepts: const [],

  );

}



StockProfile profileFromCode(String code, TodayRecommendations? today) {

  if (today != null) {

    for (final item in today.items) {

      if (item.code == code) return profileFromRecommendation(item);

    }

  }

  return StockProfile(code: code, name: code);

}


