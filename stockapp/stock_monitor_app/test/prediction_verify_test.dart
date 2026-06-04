import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor_app/core/models/capital_flow_day.dart';
import 'package:stock_monitor_app/core/prediction/prediction_verify.dart';

void main() {
  test('nextTradingDate returns immediate next session', () {
    final dates = ['2025-11-27', '2025-11-28', '2025-11-29', '2025-12-02'];
    expect(
      PredictionVerifyHelper.nextTradingDate('2025-11-28', dates),
      '2025-11-29',
    );
  });

  test('shouldRemainPending when T+1 is in the future', () {
    final today = PredictionVerifyHelper.todayTradeDate();
    expect(
      PredictionVerifyHelper.shouldRemainPending(today, today),
      isFalse,
    );
  });

  test('resolveSignalTradeDate picks last day not after today', () {
    final today = PredictionVerifyHelper.todayTradeDate();
    final history = [
      CapitalFlowDay(
        code: '600584',
        tradeDate: '2099-01-01',
        mainNetInflow: 0,
        mainNetRatio: 0,
      ),
      CapitalFlowDay(
        code: '600584',
        tradeDate: today,
        mainNetInflow: 1,
        mainNetRatio: 1,
      ),
    ];
    expect(
      PredictionVerifyHelper.resolveSignalTradeDate(history),
      today,
    );
  });
}
