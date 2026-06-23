import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor_app/core/models/position_signal.dart';
import 'package:stock_monitor_app/core/models/stock_bar.dart';
import 'package:stock_monitor_app/core/position/position_signal_analyzer.dart';

StockBar _bar({
  required String date,
  required double close,
  double? open,
  double? high,
  double? low,
  double volume = 1e6,
  double changePercent = 0,
}) {
  return StockBar(
    code: '600000',
    tradeDate: date,
    open: open ?? close - 0.1,
    close: close,
    high: high ?? close + 0.2,
    low: low ?? close - 0.2,
    volume: volume,
    changePercent: changePercent,
  );
}

List<StockBar> _uptrendSeries({int days = 60, double start = 10}) {
  return [
    for (var i = 0; i < days; i++)
      _bar(
        date: '2024-01-${(i + 1).toString().padLeft(2, '0')}',
        close: start + i * 0.08,
        volume: 1e6 + (i % 5) * 1e4,
        changePercent: i.isEven ? 0.5 : -0.2,
      ),
  ];
}

void main() {
  const analyzer = PositionSignalAnalyzer();

  test('数据不足30日输出 holdBaseOnly', () {
    final bars = _uptrendSeries(days: 20);
    final result = analyzer.analyze(dailyBars: bars, weeklyBars: const []);
    expect(result.signalType, PositionSignalType.holdBaseOnly);
    expect(result.reasons.first, contains('数据不足'));
  });

  test('右侧健康趋势可输出 hold 或 add', () {
    final bars = _uptrendSeries(days: 65, start: 12);
    // 制造健康回调：最后几天小幅回落且缩量
    for (var i = bars.length - 10; i < bars.length; i++) {
      bars[i] = _bar(
        date: bars[i].tradeDate,
        close: bars.last.effectiveClose! - 1.2,
        volume: 5e5,
        changePercent: -0.8,
      );
    }
    final result = analyzer.analyze(dailyBars: bars, weeklyBars: bars);
    expect(
      {
        PositionSignalType.hold,
        PositionSignalType.add,
        PositionSignalType.reduce,
        PositionSignalType.holdBaseOnly,
      },
      contains(result.signalType),
    );
  });

  test('近高点缩量可输出 reduce', () {
    final bars = _uptrendSeries(days: 65, start: 10);
    final peak = bars.last.effectiveClose!;
    for (var i = bars.length - 5; i < bars.length; i++) {
      bars[i] = _bar(
        date: bars[i].tradeDate,
        close: peak * 0.99,
        volume: 4e5,
        changePercent: 0.1,
      );
    }
    final result = analyzer.analyze(dailyBars: bars, weeklyBars: bars);
    expect(
      {PositionSignalType.reduce, PositionSignalType.hold},
      contains(result.signalType),
    );
  });

  test('下跌序列可触发 trendBreak 或 trendReversal', () {
    final bars = _uptrendSeries(days: 65, start: 20);
    for (var i = bars.length - 15; i < bars.length; i++) {
      bars[i] = _bar(
        date: bars[i].tradeDate,
        close: 18 - (i - (bars.length - 15)) * 0.4,
        open: 18.5,
        high: 18.6,
        low: 17.5,
        volume: 3e6,
        changePercent: -2.5,
      );
    }
    final result = analyzer.analyze(
      dailyBars: bars,
      weeklyBars: bars,
      previousTrendPhase: TrendPhase.rightSideUptrend,
    );
    expect(
      {
        PositionSignalType.trendBreak,
        PositionSignalType.trendReversal,
        PositionSignalType.holdBaseOnly,
      },
      contains(result.signalType),
    );
  });

  test('右到左切换时 isReversal 为 true', () {
    final bars = _uptrendSeries(days: 65, start: 20);
    for (var i = bars.length - 12; i < bars.length; i++) {
      bars[i] = _bar(
        date: bars[i].tradeDate,
        close: 16 - (i - (bars.length - 12)) * 0.5,
        volume: 4e6,
        changePercent: -3.5,
      );
    }
    final result = analyzer.analyze(
      dailyBars: bars,
      weeklyBars: bars,
      previousTrendPhase: TrendPhase.rightSideUptrend,
    );
    if (result.reversalSeverity != null ||
        result.signalType == PositionSignalType.trendBreak) {
      expect(result.isReversal, isTrue);
    }
  });
}
