import '../api/eastmoney_client.dart';
import '../models/capital_flow_day.dart';
import '../models/position_signal.dart';
import '../models/position_signal_analysis.dart';
import '../models/position_signal_record.dart';
import '../models/stock_bar.dart';
import '../notifications/notification_service.dart';
import '../storage/flow_cache_storage.dart';
import '../storage/position_signal_storage.dart';
import '../storage/watchlist_storage.dart';
import 'position_signal_analyzer.dart';

class PositionSignalSummary {
  const PositionSignalSummary({
    required this.totalSignals,
    required this.byType,
    required this.reversalCount,
    required this.recentChanges,
  });

  final int totalSignals;
  final Map<PositionSignalType, int> byType;
  final int reversalCount;
  final int recentChanges;
}

class PositionSignalEngine {
  PositionSignalEngine({
    EastmoneyClient? client,
    PositionSignalAnalyzer? analyzer,
    NotificationService? notifications,
  })  : _client = client ?? EastmoneyClient(),
        _analyzer = analyzer ?? const PositionSignalAnalyzer(),
        _notifications = notifications ?? NotificationService.instance;

  final EastmoneyClient _client;
  final PositionSignalAnalyzer _analyzer;
  final NotificationService _notifications;

  PositionSignalAnalysis analyzeHistory({
    required List<StockBar> dailyBars,
    required List<StockBar> weeklyBars,
    TrendPhase? previousTrendPhase,
    ReversalSeverity? previousSeverity,
  }) {
    return _analyzer.analyze(
      dailyBars: dailyBars,
      weeklyBars: weeklyBars,
      previousTrendPhase: previousTrendPhase,
      previousSeverity: previousSeverity,
    );
  }

  String resolveSignalTradeDate(List<CapitalFlowDay> history) {
    if (history.isEmpty) return '';
    final sorted = List<CapitalFlowDay>.from(history)
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    return sorted.last.tradeDate;
  }

  Future<PositionSignalRecord?> generateSignal(
    String code,
    List<CapitalFlowDay> history, {
    List<StockBar>? weeklyBars,
    bool force = false,
    bool notify = true,
    bool reversalNotifyEnabled = true,
  }) async {
    if (history.length < PositionSignalAnalyzer.windowDays) return null;

    final signalDate = resolveSignalTradeDate(history);
    final existing = await PositionSignalStorage.getForDate(code, signalDate);
    if (existing != null && !force) return existing;

    final dailyBars = barsFromCapitalFlowDays(history);
    final weekly = weeklyBars ?? await _client.fetchWeeklyBars(code, limit: 30);

    final previous = await _previousRecordBefore(code, signalDate);
    final analysis = _analyzer.analyze(
      dailyBars: dailyBars,
      weeklyBars: weekly,
      previousTrendPhase: previous?.trendPhase,
      previousSeverity: previous?.reversalSeverity,
    );

    final close = dailyBars.isNotEmpty ? dailyBars.last.effectiveClose : null;
    final record = PositionSignalRecord.fromAnalysis(
      code: code,
      tradeDate: signalDate,
      analysis: analysis,
      closePrice: close,
      lastNotifiedSeverity: existing?.lastNotifiedSeverity,
    );
    await PositionSignalStorage.save(record);

    if (notify) {
      await _maybeNotify(
        code,
        record,
        previous,
        reversalNotifyEnabled: reversalNotifyEnabled,
      );
    }
    return record;
  }

  Future<PositionSignalRecord?> _previousRecordBefore(
    String code,
    String date,
  ) async {
    final all = await PositionSignalStorage.listForCode(code);
    for (final r in all) {
      if (r.tradeDate.compareTo(date) < 0) return r;
    }
    return null;
  }

  Future<void> _maybeNotify(
    String code,
    PositionSignalRecord record,
    PositionSignalRecord? previous, {
    required bool reversalNotifyEnabled,
  }) async {
    final stock = await WatchlistStorage.getByCode(code);
    final name = stock?.name ?? code;

    if (record.isReversal && record.reversalSeverity != null) {
      if (!reversalNotifyEnabled) return;
      final prevLevel = record.lastNotifiedSeverity?.level ?? 0;
      final curLevel = record.reversalSeverity!.level;
      if (curLevel > prevLevel) {
        await _notifications.showReversalAlert(
          code: code,
          name: name,
          severity: record.reversalSeverity!,
          suggestedAction: record.suggestedAction,
        );
        await PositionSignalStorage.updateNotificationState(
          record.id,
          lastNotifiedSeverity: record.reversalSeverity,
        );
      }
      return;
    }

    if (previous == null) return;
    final prevType = previous.signalType;
    final curType = record.signalType;
    const watchTypes = {
      PositionSignalType.hold,
      PositionSignalType.holdBaseOnly,
    };
    const alertTypes = {
      PositionSignalType.add,
      PositionSignalType.reduce,
      PositionSignalType.trendBreak,
      PositionSignalType.trendReversal,
    };
    if (watchTypes.contains(prevType) && alertTypes.contains(curType)) {
      await _notifications.showSignalChangeAlert(
        code: code,
        name: name,
        signalType: curType,
        suggestedAction: record.suggestedAction,
      );
    }
  }

  Future<List<CapitalFlowDay>> refreshStockFlows(
    String code, {
    bool shouldSignal = true,
    bool forceSignal = false,
    bool notify = true,
    bool reversalNotifyEnabled = true,
  }) async {
    List<CapitalFlowDay> history;
    try {
      history = await _client.fetchSixMonthHistory(code);
    } catch (e) {
      history = await _client.fetchFlowHistory(code, limit: 126);
    }

    List<StockBar> weekly = [];
    try {
      weekly = await _client.fetchWeeklyBars(code, limit: 30);
    } catch (_) {}

    try {
      final today = await _client.fetchTodayCapitalFlow(code);
      if (today != null) {
        history = _mergeTodayFlow(history, today);
      }
    } catch (_) {}

    await FlowCacheStorage.saveAll(history);

    if (history.isNotEmpty && shouldSignal) {
      final signalDate = resolveSignalTradeDate(history);
      final existing = await PositionSignalStorage.getForDate(code, signalDate);
      final needsRefresh = existing != null && existing.reasons.isEmpty;
      await generateSignal(
        code,
        history,
        weeklyBars: weekly,
        force: forceSignal || needsRefresh,
        notify: notify,
        reversalNotifyEnabled: reversalNotifyEnabled,
      );
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

  Future<PositionSignalSummary> computeSummary() async {
    final all = await PositionSignalStorage.list();
    final byType = <PositionSignalType, int>{};
    var reversalCount = 0;
    var recentChanges = 0;
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final cutoffStr = _formatDate(cutoff);

    for (final r in all) {
      byType[r.signalType] = (byType[r.signalType] ?? 0) + 1;
      if (r.isReversal) reversalCount++;
      if (r.tradeDate.compareTo(cutoffStr) >= 0) recentChanges++;
    }

    return PositionSignalSummary(
      totalSignals: all.length,
      byType: byType,
      reversalCount: reversalCount,
      recentChanges: recentChanges,
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }
}
