import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position_signal.dart';
import 'app_settings.dart';

class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;
  bool get isZh => locale.languageCode == 'zh';

  String get navWatchlist => isZh ? '自选' : 'Watchlist';
  String get navStats => isZh ? '信号' : 'Signals';
  String get navSettings => isZh ? '设置' : 'Settings';

  String get watchlistTitle => isZh ? '自选股' : 'Watchlist';
  String get addStock => isZh ? '添加自选' : 'Add stock';
  String get emptyWatchlist => isZh ? '还没有自选股' : 'No stocks yet';
  String get emptyWatchlistHint =>
      isZh ? '添加股票后，可监控30日加减仓信号' : 'Add stocks to monitor position signals';
  String get stockCode => isZh ? '股票代码' : 'Stock code';
  String get stockCodeHint => isZh ? '例如 600519' : 'e.g. 600519';
  String get pullToRefresh => isZh ? '下拉刷新数据' : 'Pull to refresh';
  String get refreshDone => isZh ? '刷新完成' : 'Refresh done';
  String get refreshFailed => isZh ? '刷新失败' : 'Refresh failed';

  String get mainNetInflow => isZh ? '主力净流入' : 'Main net inflow';
  String get mainNetRatio => isZh ? '主力净占比' : 'Main net ratio';
  String get retailNetInflow => isZh ? '散户净流入' : 'Retail net inflow';
  String get latestPrice => isZh ? '现价' : 'Price';

  String get signalHoldBaseOnly => isZh ? '只持底仓' : 'Base only';
  String get signalHold => isZh ? '持有' : 'Hold';
  String get signalAdd => isZh ? '加仓' : 'Add';
  String get signalReduce => isZh ? '减仓' : 'Reduce';
  String get signalTrendBreak => isZh ? '下跌预警' : 'Break warning';
  String get signalTrendReversal => isZh ? '趋势逆转' : 'Reversal';

  String get analysisSection => isZh ? '30日加减仓分析' : '30-day position analysis';
  String get confidence => isZh ? '置信度' : 'Confidence';
  String get trendPhase => isZh ? '趋势相位' : 'Trend phase';
  String get phaseRightSide => isZh ? '右侧上涨' : 'Right-side up';
  String get phaseLeftSide => isZh ? '左侧下跌' : 'Left-side down';
  String get phaseNeutral => isZh ? '震荡未确认' : 'Neutral';
  String get retracePercent => isZh ? '回撤' : 'Retrace';
  String get volumeRatio => isZh ? '量比' : 'Vol ratio';
  String get atrStopLoss => isZh ? 'ATR止损参考' : 'ATR stop';
  String get resonanceSignals => isZh ? '共振信号' : 'Resonance signals';
  String get reversalBanner => isZh ? '趋势逆转警告' : 'Trend reversal warning';
  String get suggestedAction => isZh ? '建议动作' : 'Suggested action';

  String get flowChart => isZh ? '主力净流入走势' : 'Main inflow trend';
  String get historyFlowChart =>
      isZh ? '历史资金净流入' : 'Historical net inflow';
  String get intradayFlowChart =>
      isZh ? '当日资金净流入' : "Today's net inflow";
  String get chartUnitYi => isZh ? '单位：亿元' : 'Unit: 100M';
  String get chartNotEnough => isZh ? '历史数据不足' : 'Not enough history';
  String get intradayChartEmpty =>
      isZh ? '暂无当日分时数据（非交易时段或接口无数据）' : 'No intraday data';
  String get intradaySnapshotHint =>
      isZh ? '与下方当日曲线末点一致（累计净流入）' : 'Matches last point on intraday chart';
  String get signalHistory => isZh ? '信号历史' : 'Signal history';

  String get statsTitle => isZh ? '信号历史' : 'Signal history';
  String get totalSignals => isZh ? '信号总数' : 'Total signals';
  String get reversalCount => isZh ? '逆转提醒' : 'Reversals';
  String get recentChanges => isZh ? '近7日变更' : '7-day changes';
  String get perStock => isZh ? '各股最新信号' : 'Latest by stock';
  String get signalDistribution => isZh ? '信号分布' : 'Signal distribution';

  String get settingsTitle => isZh ? '设置' : 'Settings';
  String get themeSection => isZh ? '主题' : 'Theme';
  String get themeIndigo => isZh ? '靛蓝' : 'Indigo';
  String get themeTeal => isZh ? '青绿' : 'Teal';
  String get themeOrange => isZh ? '橙色' : 'Orange';
  String get languageSection => isZh ? '语言' : 'Language';
  String get notifySection => isZh ? '收盘提醒' : 'Close reminder';
  String get notifySubtitle =>
      isZh ? '交易日 15:05 提醒刷新并查看信号' : 'Weekday 15:05 reminder to refresh';
  String get reversalNotifySection => isZh ? '趋势逆转提醒' : 'Reversal alerts';
  String get reversalNotifySubtitle =>
      isZh ? '检测到左侧下跌趋势时高优先级推送' : 'High-priority alerts on downtrend reversal';
  String get disclaimer => isZh
      ? '数据来源于东方财富公开接口，加减仓信号仅供个人记录与参考，不构成任何投资建议。'
      : 'Data from East Money public APIs. Signals are for personal reference only, not investment advice.';

  String signalTypeLabel(PositionSignalType type) {
    return switch (type) {
      PositionSignalType.holdBaseOnly => signalHoldBaseOnly,
      PositionSignalType.hold => signalHold,
      PositionSignalType.add => signalAdd,
      PositionSignalType.reduce => signalReduce,
      PositionSignalType.trendBreak => signalTrendBreak,
      PositionSignalType.trendReversal => signalTrendReversal,
    };
  }

  String trendPhaseLabel(TrendPhase phase) {
    return switch (phase) {
      TrendPhase.rightSideUptrend => phaseRightSide,
      TrendPhase.leftSideDowntrend => phaseLeftSide,
      TrendPhase.neutral => phaseNeutral,
    };
  }

  String severityLabel(ReversalSeverity severity) {
    return switch (severity) {
      ReversalSeverity.earlyWarning => isZh ? '早期预警' : 'Early warning',
      ReversalSeverity.confirmed => isZh ? '确认反转' : 'Confirmed',
      ReversalSeverity.deepDrop => isZh ? '深跌保护' : 'Deep drop',
    };
  }

  String get triggerConditions => isZh ? '触发条件' : 'Triggers';
  String get executeAction => isZh ? '执行建议' : 'Action';

  String triggeredSignalLabel(String id) {
    const zh = {
      // 下跌逆转
      'lowerHighsLows': '更低高低点',
      'breakSupport': '破支撑放量',
      'maDeathCross': '均线死叉',
      'belowMa30Sustained': '持续MA30下',
      'downOnVolume': '下跌放量',
      'upOnLowVolume': '反弹缩量',
      'bearishDivergence': '量价背离',
      'rsiWeak': 'RSI走弱',
      'rsiBearishDiv': 'RSI负背离',
      'adxWeak': 'ADX转弱',
      'macdBearish': 'MACD偏空',
      'bearishCandles': '大阴/吞没',
      'weeklyBreak': '周线破位',
      'invalidRebounds': '无效反弹',
      // 右侧趋势 / 加仓
      'rightSideUptrend': '右侧趋势确认',
      'healthyRetrace': '健康回调5-20%',
      'volumeShrink': '缩量回调',
      'holdSupport': '未破30日支撑',
      'rsiOversold': 'RSI超卖',
      'bullishReversal': '阳线反转',
      // 减仓
      'nearHigh30': '近30日高点',
      'volumeStagnation': '缩量滞涨',
      'rsiOverbought': 'RSI超买',
      // 只持底仓
      'belowMa': '未站稳均线',
      'noHigherHL': '无更高高低点',
      'ma30Down': 'MA30向下',
      'weeklyWeak': '周线偏弱',
      'noActionYet': '暂无触发',
    };
    if (isZh) return zh[id] ?? id;
    return id;
  }

  String formatMoney(double v) {
    final abs = v.abs();
    final sign = v < 0 ? '-' : '';
    if (abs >= 1e8) {
      return '$sign${(abs / 1e8).toStringAsFixed(2)}亿';
    }
    if (abs >= 1e4) {
      return '$sign${(abs / 1e4).toStringAsFixed(2)}万';
    }
    return '$sign${abs.toStringAsFixed(0)}';
  }
}

final appStringsProvider = Provider<AppStrings>((ref) {
  final settings = ref.watch(appSettingsProvider);
  return AppStrings(settings.locale);
});
