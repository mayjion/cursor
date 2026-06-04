import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings.dart';

class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;
  bool get isZh => locale.languageCode == 'zh';

  String get navWatchlist => isZh ? '自选' : 'Watchlist';
  String get navStats => isZh ? '统计' : 'Stats';
  String get navSettings => isZh ? '设置' : 'Settings';

  String get watchlistTitle => isZh ? '自选股' : 'Watchlist';
  String get addStock => isZh ? '添加自选' : 'Add stock';
  String get emptyWatchlist => isZh ? '还没有自选股' : 'No stocks yet';
  String get emptyWatchlistHint =>
      isZh ? '添加股票后，可监控资金流向并记录推测' : 'Add stocks to monitor capital flow';
  String get stockCode => isZh ? '股票代码' : 'Stock code';
  String get stockCodeHint => isZh ? '例如 600519' : 'e.g. 600519';
  String get pullToRefresh => isZh ? '下拉刷新数据' : 'Pull to refresh';
  String get refreshDone => isZh ? '刷新完成' : 'Refresh done';
  String get refreshFailed => isZh ? '刷新失败' : 'Refresh failed';

  String get mainNetInflow => isZh ? '主力净流入' : 'Main net inflow';
  String get mainNetRatio => isZh ? '主力净占比' : 'Main net ratio';
  String get predictUp => isZh ? '看涨' : 'Bullish';
  String get predictDown => isZh ? '看跌' : 'Bearish';
  String get predictNeutral => isZh ? '观望' : 'Neutral';
  String get generatePrediction => isZh ? '生成今日推测' : "Today's prediction";
  String get predictionHistory => isZh ? '推测历史' : 'Prediction history';
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
  String get latestPrice => isZh ? '现价' : 'Price';
  String get retailNetInflow => isZh ? '散户净流入' : 'Retail net inflow';
  String get analysisSection => isZh ? '综合推测分析' : 'Composite analysis';
  String get confidence => isZh ? '置信度' : 'Confidence';
  String get sixMonthTrend => isZh ? '近6月趋势' : '6-month trend';
  String get priceChange6m => isZh ? '6月涨跌幅' : '6M price change';
  String get mainFlow20d => isZh ? '近20日主力累计' : '20D main flow sum';
  String get patternWinRate => isZh ? '同模式历史上涨率' : 'Pattern win rate';
  String get compositeScore => isZh ? '综合评分' : 'Composite score';
  String get hit => isZh ? '命中' : 'Hit';
  String get miss => isZh ? '未中' : 'Miss';
  String get pending => isZh ? '待验证' : 'Pending';
  String get verifyUnavailable => isZh ? '数据缺失' : 'No data';

  String get statsTitle => isZh ? '推测统计' : 'Prediction stats';
  String get accuracy => isZh ? '命中率' : 'Accuracy';
  String get totalPredictions => isZh ? '推测总数' : 'Total predictions';
  String get scoredPredictions => isZh ? '计分推测' : 'Scored';
  String get hits => isZh ? '命中次数' : 'Hits';
  String get perStock => isZh ? '分股统计' : 'By stock';

  String get settingsTitle => isZh ? '设置' : 'Settings';
  String get themeSection => isZh ? '主题' : 'Theme';
  String get themeIndigo => isZh ? '靛蓝' : 'Indigo';
  String get themeTeal => isZh ? '青绿' : 'Teal';
  String get themeOrange => isZh ? '橙色' : 'Orange';
  String get languageSection => isZh ? '语言' : 'Language';
  String get thresholdSection => isZh ? '推测规则' : 'Prediction rules';
  String get bullRatio => isZh ? '看涨净占比阈值 (%)' : 'Bull ratio threshold (%)';
  String get bearRatio => isZh ? '看跌净占比阈值 (%)' : 'Bear ratio threshold (%)';
  String get notifySection => isZh ? '收盘提醒' : 'Close reminder';
  String get notifySubtitle =>
      isZh ? '交易日 15:05 提醒刷新并记录推测' : 'Weekday 15:05 reminder to refresh';
  String get disclaimer => isZh
      ? '数据来源于东方财富公开接口，推测结果仅供个人记录与统计，不构成任何投资建议。'
      : 'Data from East Money public APIs. Predictions are for personal records only, not investment advice.';

  String directionLabel(String key) {
    switch (key) {
      case 'up':
        return predictUp;
      case 'down':
        return predictDown;
      default:
        return predictNeutral;
    }
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
