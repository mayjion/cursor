import '../api/eastmoney_client.dart';
import '../models/capital_flow_day.dart';
import '../models/prediction_analysis.dart';
import '../models/prediction_direction.dart';
import '../models/prediction_record.dart';
import '../settings/app_settings.dart';
import '../storage/flow_cache_storage.dart';
import '../storage/prediction_storage.dart';
import 'prediction_analyzer.dart';
import 'prediction_verify.dart';

class PredictionStats {
  const PredictionStats({
    required this.totalPredictions,
    required this.scoredPredictions,
    required this.hits,
    required this.accuracyPercent,
    required this.byCode,
  });

  final int totalPredictions;
  final int scoredPredictions;
  final int hits;
  final double accuracyPercent;
  final Map<String, CodeStats> byCode;
}

class CodeStats {
  const CodeStats({
    required this.code,
    required this.scored,
    required this.hits,
    required this.accuracyPercent,
  });

  final String code;
  final int scored;
  final int hits;
  final double accuracyPercent;
}

class PredictionEngine {
  PredictionEngine({
    EastmoneyClient? client,
    PredictionThresholds? thresholds,
    PredictionAnalyzer? analyzer,
  })  : _client = client ?? EastmoneyClient(),
        _thresholds = thresholds ?? const PredictionThresholds(),
        _analyzer = analyzer ?? PredictionAnalyzer(thresholds: thresholds ?? const PredictionThresholds());

  final EastmoneyClient _client;
  final PredictionThresholds _thresholds;
  final PredictionAnalyzer _analyzer;

  PredictionAnalysis analyzeHistory(List<CapitalFlowDay> history) {
    return PredictionAnalyzer(thresholds: _thresholds).analyze(history);
  }

  PredictionDirection predictFromFlow(CapitalFlowDay flow) {
    return analyzeHistory([flow]).direction;
  }

  ActualDirection actualFromChange(double changePercent) {
    if (changePercent >= _thresholds.upChangePercent) {
      return ActualDirection.up;
    }
    if (changePercent <= _thresholds.downChangePercent) {
      return ActualDirection.down;
    }
    return ActualDirection.flat;
  }

  Future<PredictionRecord?> generatePrediction(
    String code,
    List<CapitalFlowDay> history, {
    bool force = false,
  }) async {
    if (history.isEmpty) return null;
    final signalDate = PredictionVerifyHelper.resolveSignalTradeDate(history);
    final latest = history.lastWhere(
      (d) => d.tradeDate == signalDate,
      orElse: () => history.last,
    );
    final existing = await PredictionStorage.getForDate(code, signalDate);
    if (existing != null && !force) return existing;

    final analysis = _analyzer.analyze(history);
    final record = PredictionRecord(
      id: '${code}_$signalDate',
      code: code,
      tradeDate: signalDate,
      direction: analysis.direction,
      mainNetInflow: latest.mainNetInflow,
      mainNetRatio: latest.mainNetRatio,
      createdAt: DateTime.now(),
      analysisSummary: analysis.summaryText,
      confidenceScore: analysis.confidence,
      compositeScore: analysis.score,
      actual: existing?.actual ?? ActualDirection.pending,
      actualChangePercent: existing?.actualChangePercent,
      verifiedAt: existing?.verifiedAt,
    );
    await PredictionStorage.save(record);
    return record;
  }

  Future<void> verifyPendingRecords() async {
    final pending = await PredictionStorage.pendingVerification();
    if (pending.isEmpty) return;

    final codes = pending.map((r) => r.code).toSet();
    final calendarByCode = <String, ({List<CapitalFlowDay> cached, Map<String, double> kline})>{};

    for (final code in codes) {
      final cached = await FlowCacheStorage.listForCode(code);
      final hasChangeInCache =
          cached.any((d) => d.changePercent != null);
      Map<String, double> kline = {};
      if (!hasChangeInCache) {
        kline = await _client.fetchKlineChangeMap(code, limit: 126);
      }
      calendarByCode[code] = (cached: cached, kline: kline);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    for (final record in pending) {
      final cal = calendarByCode[record.code];
      if (cal == null) continue;

      final dates = PredictionVerifyHelper.mergeTradingDates(
        cal.cached,
        cal.kline,
      );
      final nextDate =
          PredictionVerifyHelper.nextTradingDate(record.tradeDate, dates);

      if (PredictionVerifyHelper.shouldRemainPending(record.tradeDate, nextDate)) {
        continue;
      }

      if (nextDate == null) {
        if (PredictionVerifyHelper.shouldCloseAsUnavailable(
          record.tradeDate,
          null,
        )) {
          await _closeUnavailable(record);
        }
        continue;
      }

      var change = PredictionVerifyHelper.changeOnDate(
        nextDate,
        cal.cached,
        cal.kline,
      );
      change ??= await _client.fetchChangePercentOnDate(record.code, nextDate);

      if (change == null) {
        if (PredictionVerifyHelper.shouldCloseAsUnavailable(
          record.tradeDate,
          nextDate,
        )) {
          await _closeUnavailable(record);
        }
        continue;
      }

      final actual = actualFromChange(change);
      await PredictionStorage.save(
        record.copyWith(
          actual: actual,
          actualChangePercent: change,
          verifiedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _closeUnavailable(PredictionRecord record) async {
    await PredictionStorage.save(
      PredictionRecord(
        id: record.id,
        code: record.code,
        tradeDate: record.tradeDate,
        direction: record.direction,
        mainNetInflow: record.mainNetInflow,
        mainNetRatio: record.mainNetRatio,
        createdAt: record.createdAt,
        actual: ActualDirection.flat,
        verifiedAt: DateTime.now(),
        analysisSummary: _appendNote(
          record.analysisSummary,
          'T+1行情缺失，已自动结案',
        ),
        confidenceScore: record.confidenceScore,
        compositeScore: record.compositeScore,
      ),
    );
  }

  String? _appendNote(String? existing, String note) {
    if (existing == null || existing.isEmpty) return note;
    if (existing.contains(note)) return existing;
    return '$existing；$note';
  }

  Future<PredictionStats> computeStats() async {
    final all = await PredictionStorage.list();
    final scored = all.where((r) => r.countsForAccuracy).toList();
    final hits = scored.where((r) => r.isHit).length;
    final accuracy = scored.isEmpty
        ? 0.0
        : (hits / scored.length) * 100;

    final byCodeMap = <String, List<PredictionRecord>>{};
    for (final r in scored) {
      byCodeMap.putIfAbsent(r.code, () => []).add(r);
    }
    final byCode = <String, CodeStats>{};
    for (final entry in byCodeMap.entries) {
      final codeHits = entry.value.where((r) => r.isHit).length;
      final n = entry.value.length;
      byCode[entry.key] = CodeStats(
        code: entry.key,
        scored: n,
        hits: codeHits,
        accuracyPercent: n == 0 ? 0 : (codeHits / n) * 100,
      );
    }

    return PredictionStats(
      totalPredictions: all.length,
      scoredPredictions: scored.length,
      hits: hits,
      accuracyPercent: accuracy,
      byCode: byCode,
    );
  }

  /// 拉取近6月数据并缓存，基于完整历史做综合推测。
  Future<List<CapitalFlowDay>> refreshStockFlows(
    String code, {
    bool shouldPredict = true,
    bool forcePrediction = false,
  }) async {
    List<CapitalFlowDay> history;
    try {
      history = await _client.fetchSixMonthHistory(code);
    } catch (e) {
      history = await _client.fetchFlowHistory(code, limit: 126);
    }
    try {
      final today = await _client.fetchTodayCapitalFlow(code);
      if (today != null) {
        history = _mergeTodayFlow(history, today);
      }
    } catch (_) {}
    await FlowCacheStorage.saveAll(history);

    if (history.isEmpty) return history;
    if (shouldPredict) {
      await generatePrediction(code, history, force: forcePrediction);
    }
    return history;
  }

  List<CapitalFlowDay> _mergeTodayFlow(
    List<CapitalFlowDay> history,
    CapitalFlowDay today,
  ) {
    if (history.isEmpty) return [today];
    final idx = history.indexWhere((d) => d.tradeDate == today.tradeDate);
    if (idx >= 0) {
      final copy = List<CapitalFlowDay>.from(history);
      copy[idx] = today;
      return copy;
    }
    return [...history, today];
  }

  Future<PredictionRecord?> generatePredictionForCode(
    String code,
    List<CapitalFlowDay> history, {
    bool force = true,
  }) =>
      generatePrediction(code, history, force: force);
}
