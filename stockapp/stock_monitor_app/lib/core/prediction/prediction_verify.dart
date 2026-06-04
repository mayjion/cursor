import '../models/capital_flow_day.dart';

/// 推测记录校验用的交易日历工具。
class PredictionVerifyHelper {
  static String todayTradeDate() {
    final n = DateTime.now();
    return _format(n);
  }

  static String _format(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  /// 推测所依据的交易日：历史中 <= 今天的最后一个交易日。
  static String resolveSignalTradeDate(List<CapitalFlowDay> history) {
    if (history.isEmpty) return todayTradeDate();
    final today = todayTradeDate();
    final sorted = List<CapitalFlowDay>.from(history)
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    for (var i = sorted.length - 1; i >= 0; i--) {
      if (sorted[i].tradeDate.compareTo(today) <= 0) {
        return sorted[i].tradeDate;
      }
    }
    return sorted.last.tradeDate;
  }

  /// 在有序交易日列表中取 tradeDate 的下一交易日。
  static String? nextTradingDate(String tradeDate, List<String> sortedDates) {
    for (final d in sortedDates) {
      if (d.compareTo(tradeDate) > 0) return d;
    }
    return null;
  }

  /// T+1 交易日是否尚未到来（仍为待验证）。
  static bool shouldRemainPending(String tradeDate, String? nextDate) {
    if (nextDate == null) return true;
    return nextDate.compareTo(todayTradeDate()) > 0;
  }

  /// 是否应尝试结案（推测日已过很久仍无法取到 T+1 数据）。
  static bool shouldCloseAsUnavailable(String tradeDate, String? nextDate) {
    final today = todayTradeDate();
    if (tradeDate.compareTo(today) >= 0) return false;
    if (nextDate != null && nextDate.compareTo(today) <= 0) {
      return false;
    }
    return _daysBetween(tradeDate, today) > 5;
  }

  static int _daysBetween(String from, String to) {
    try {
      final a = DateTime.parse(from);
      final b = DateTime.parse(to);
      return b.difference(a).inDays;
    } catch (_) {
      return 0;
    }
  }

  static List<String> mergeTradingDates(
    List<CapitalFlowDay> cached,
    Map<String, double> klineChanges,
  ) {
    final set = <String>{};
    for (final d in cached) {
      set.add(d.tradeDate);
    }
    set.addAll(klineChanges.keys);
    final list = set.toList()..sort();
    return list;
  }

  static double? changeOnDate(
    String date,
    List<CapitalFlowDay> cached,
    Map<String, double> klineChanges,
  ) {
    for (final d in cached) {
      if (d.tradeDate == date && d.changePercent != null) {
        return d.changePercent;
      }
    }
    if (klineChanges.containsKey(date)) {
      return klineChanges[date];
    }
    return null;
  }
}
