import 'capital_flow_day.dart';
import 'capital_flow_point.dart';

/// 详情页顶部展示：与当日分时曲线末点一致的资金流。
class TodayFlowDisplay {
  const TodayFlowDisplay({
    required this.tradeDate,
    required this.mainNetInflow,
    required this.retailNetInflow,
    required this.mainNetRatio,
    this.closePrice,
    this.changePercent,
  });

  final String tradeDate;
  final double mainNetInflow;
  final double retailNetInflow;
  final double mainNetRatio;
  final double? closePrice;
  final double? changePercent;

  static TodayFlowDisplay? from(
    List<CapitalFlowPoint> intraday,
    List<CapitalFlowDay> history,
  ) {
    if (intraday.isNotEmpty) {
      final last = intraday.last;
      final meta = history.isNotEmpty ? history.last : null;
      return TodayFlowDisplay(
        tradeDate: meta?.tradeDate ?? _todayString(),
        mainNetInflow: last.mainNetInflow,
        retailNetInflow: last.retailNetInflow,
        mainNetRatio: meta?.mainNetRatio ?? 0,
        closePrice: meta?.closePrice,
        changePercent: meta?.changePercent,
      );
    }
    if (history.isEmpty) return null;
    final d = history.last;
    return TodayFlowDisplay(
      tradeDate: d.tradeDate,
      mainNetInflow: d.mainNetInflow,
      retailNetInflow: d.smallNetInflow,
      mainNetRatio: d.mainNetRatio,
      closePrice: d.closePrice,
      changePercent: d.changePercent,
    );
  }

  static String _todayString() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }
}
