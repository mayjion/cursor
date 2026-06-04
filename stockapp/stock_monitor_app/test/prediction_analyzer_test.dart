import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor_app/core/models/capital_flow_day.dart';
import 'package:stock_monitor_app/core/models/prediction_direction.dart';
import 'package:stock_monitor_app/core/prediction/prediction_analyzer.dart';

void main() {
  CapitalFlowDay day(
    String date, {
    double main = 0,
    double small = 0,
    double ratio = 0,
    double? close,
    double? change,
  }) {
    return CapitalFlowDay(
      code: '600519',
      tradeDate: date,
      mainNetInflow: main,
      mainNetRatio: ratio,
      smallNetInflow: small,
      closePrice: close,
      changePercent: change,
    );
  }

  test('bullish when main in retail out with history', () {
    final history = <CapitalFlowDay>[
      for (var i = 0; i < 30; i++)
        day(
          '2025-01-${(i + 1).toString().padLeft(2, '0')}',
          main: 1e8,
          small: -5e7,
          ratio: 5,
          close: 100 + i.toDouble(),
          change: 0.5,
        ),
    ];
    final analysis = const PredictionAnalyzer().analyze(history);
    expect(analysis.direction, PredictionDirection.up);
    expect(analysis.score, greaterThan(0));
    expect(analysis.reasons, isNotEmpty);
  });

  test('bearish when main out retail in', () {
    final latest = day('2025-03-01', main: -2e8, small: 1e8, ratio: -5);
    final history = [
      ...List.generate(
        25,
        (i) => day('2025-01-${(i + 1).toString().padLeft(2, '0')}', close: 90.0 - i),
      ),
      latest,
    ];
    final analysis = const PredictionAnalyzer().analyze(history);
    expect(analysis.direction, PredictionDirection.down);
  });
}
