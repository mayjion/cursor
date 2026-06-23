import 'dart:math';

import '../models/stock_bar.dart';

class TechnicalIndicators {
  static double? sma(List<StockBar> bars, int period) {
    if (bars.length < period) return null;
    final slice = bars.sublist(bars.length - period);
    final closes = slice.map((b) => b.effectiveClose).whereType<double>();
    if (closes.length < period) return null;
    return closes.reduce((a, b) => a + b) / period;
  }

  static double? smaAt(List<StockBar> bars, int endIndex, int period) {
    if (endIndex < period - 1 || endIndex >= bars.length) return null;
    final slice = bars.sublist(endIndex - period + 1, endIndex + 1);
    final closes = slice.map((b) => b.effectiveClose).whereType<double>();
    if (closes.length < period) return null;
    return closes.reduce((a, b) => a + b) / period;
  }

  static double? maSlope(List<StockBar> bars, int period, {int lookback = 5}) {
    if (bars.length < period + lookback) return null;
    final end = bars.length - 1;
    final start = end - lookback;
    final maEnd = smaAt(bars, end, period);
    final maStart = smaAt(bars, start, period);
    if (maEnd == null || maStart == null || maStart == 0) return null;
    return (maEnd - maStart) / maStart * 100;
  }

  static double avgVolume(List<StockBar> bars, int period) {
    if (bars.isEmpty) return 0;
    final slice = bars.length >= period
        ? bars.sublist(bars.length - period)
        : bars;
    final vols = slice.map((b) => b.volume).whereType<double>();
    if (vols.isEmpty) return 0;
    return vols.reduce((a, b) => a + b) / vols.length;
  }

  static double? retracePercent(List<StockBar> window, double current) {
    final highs =
        window.map((b) => b.effectiveHigh).whereType<double>().toList();
    if (highs.isEmpty || current <= 0) return null;
    final high30 = highs.reduce(max);
    if (high30 <= current) return 0;
    return (high30 - current) / high30 * 100;
  }

  static double? rsi(List<StockBar> bars, {int period = 14}) {
    if (bars.length < period + 1) return null;
    var gains = 0.0;
    var losses = 0.0;
    for (var i = bars.length - period; i < bars.length; i++) {
      final prev = bars[i - 1].effectiveClose;
      final cur = bars[i].effectiveClose;
      if (prev == null || cur == null) continue;
      final diff = cur - prev;
      if (diff >= 0) {
        gains += diff;
      } else {
        losses -= diff;
      }
    }
    if (losses == 0) return 100;
    final rs = gains / losses;
    return 100 - 100 / (1 + rs);
  }

  static List<double> rsiSeries(List<StockBar> bars, {int period = 14}) {
    final series = <double>[];
    for (var i = period; i < bars.length; i++) {
      final slice = bars.sublist(0, i + 1);
      final v = rsi(slice, period: period);
      if (v != null) series.add(v);
    }
    return series;
  }

  static double? rsiSlope(List<StockBar> bars, {int days = 3}) {
    final series = rsiSeries(bars);
    if (series.length < days) return null;
    return series.last - series[series.length - days];
  }

  static double? atr(List<StockBar> bars, {int period = 14}) {
    if (bars.length < period + 1) return null;
    final trs = <double>[];
    for (var i = bars.length - period; i < bars.length; i++) {
      final high = bars[i].effectiveHigh;
      final low = bars[i].effectiveLow;
      final prevClose = bars[i - 1].effectiveClose;
      if (high == null || low == null || prevClose == null) continue;
      trs.add(max(high - low, max((high - prevClose).abs(), (low - prevClose).abs())));
    }
    if (trs.isEmpty) return null;
    return trs.reduce((a, b) => a + b) / trs.length;
  }

  static ({double? dif, double? dea, double? macd}) macd(
    List<StockBar> bars, {
    int fast = 12,
    int slow = 26,
    int signal = 9,
  }) {
    final closes = bars.map((b) => b.effectiveClose).whereType<double>().toList();
    if (closes.length < slow + signal) {
      return (dif: null, dea: null, macd: null);
    }

    double ema(List<double> data, int period) {
      final k = 2.0 / (period + 1);
      var emaVal = data.take(period).reduce((a, b) => a + b) / period;
      for (var i = period; i < data.length; i++) {
        emaVal = data[i] * k + emaVal * (1 - k);
      }
      return emaVal;
    }

    final difList = <double>[];
    for (var i = slow; i <= closes.length; i++) {
      final slice = closes.sublist(0, i);
      final fastEma = ema(slice, fast);
      final slowEma = ema(slice, slow);
      difList.add(fastEma - slowEma);
    }
    if (difList.length < signal) {
      return (dif: null, dea: null, macd: null);
    }
    final dea = ema(difList, signal);
    final dif = difList.last;
    return (dif: dif, dea: dea, macd: (dif - dea) * 2);
  }

  static bool macdDeathCross(List<StockBar> bars) {
    if (bars.length < 40) return false;
    final prev = macd(bars.sublist(0, bars.length - 1));
    final cur = macd(bars);
    if (prev.dif == null ||
        prev.dea == null ||
        cur.dif == null ||
        cur.dea == null) {
      return false;
    }
    return prev.dif! >= prev.dea! && cur.dif! < cur.dea!;
  }

  static double? adx(List<StockBar> bars, {int period = 14}) {
    if (bars.length < period * 2) return null;

    double? calcAdx(List<StockBar> data) {
      final plusDm = <double>[];
      final minusDm = <double>[];
      final trList = <double>[];

      for (var i = 1; i < data.length; i++) {
        final high = data[i].effectiveHigh;
        final low = data[i].effectiveLow;
        final prevHigh = data[i - 1].effectiveHigh;
        final prevLow = data[i - 1].effectiveLow;
        final prevClose = data[i - 1].effectiveClose;
        if (high == null ||
            low == null ||
            prevHigh == null ||
            prevLow == null ||
            prevClose == null) {
          continue;
        }
        final upMove = high - prevHigh;
        final downMove = prevLow - low;
        plusDm.add(upMove > downMove && upMove > 0 ? upMove : 0);
        minusDm.add(downMove > upMove && downMove > 0 ? downMove : 0);
        trList.add(max(
          high - low,
          max((high - prevClose).abs(), (low - prevClose).abs()),
        ));
      }

      if (trList.length < period) return null;

      var smoothedTr = trList.take(period).reduce((a, b) => a + b);
      var smoothedPlus = plusDm.take(period).reduce((a, b) => a + b);
      var smoothedMinus = minusDm.take(period).reduce((a, b) => a + b);

      final dxList = <double>[];
      for (var i = period; i < trList.length; i++) {
        smoothedTr = smoothedTr - smoothedTr / period + trList[i];
        smoothedPlus = smoothedPlus - smoothedPlus / period + plusDm[i];
        smoothedMinus = smoothedMinus - smoothedMinus / period + minusDm[i];
        if (smoothedTr == 0) continue;
        final plusDi = 100 * smoothedPlus / smoothedTr;
        final minusDi = 100 * smoothedMinus / smoothedTr;
        final sum = plusDi + minusDi;
        if (sum == 0) continue;
        dxList.add(100 * (plusDi - minusDi).abs() / sum);
      }
      if (dxList.isEmpty) return null;
      return dxList.reduce((a, b) => a + b) / dxList.length;
    }

    return calcAdx(bars);
  }

  static bool higherHighsHigherLows(List<StockBar> window) {
    if (window.length < 20) return false;
    final mid = window.length ~/ 2;
    final prior = window.sublist(0, mid);
    final recent = window.sublist(mid);
    double? maxOf(List<StockBar> bars) {
      final highs = bars.map((b) => b.effectiveHigh).whereType<double>();
      return highs.isEmpty ? null : highs.reduce(max);
    }

    double? minOf(List<StockBar> bars) {
      final lows = bars.map((b) => b.effectiveLow).whereType<double>();
      return lows.isEmpty ? null : lows.reduce(min);
    }

    final priorHigh = maxOf(prior);
    final recentHigh = maxOf(recent);
    final priorLow = minOf(prior);
    final recentLow = minOf(recent);
    if (priorHigh == null ||
        recentHigh == null ||
        priorLow == null ||
        recentLow == null) {
      return false;
    }
    return recentHigh > priorHigh && recentLow > priorLow;
  }

  static bool lowerHighsLowerLows(List<StockBar> window) {
    if (window.length < 20) return false;
    final mid = window.length ~/ 2;
    final prior = window.sublist(0, mid);
    final recent = window.sublist(mid);
    double? maxOf(List<StockBar> bars) {
      final highs = bars.map((b) => b.effectiveHigh).whereType<double>();
      return highs.isEmpty ? null : highs.reduce(max);
    }

    double? minOf(List<StockBar> bars) {
      final lows = bars.map((b) => b.effectiveLow).whereType<double>();
      return lows.isEmpty ? null : lows.reduce(min);
    }

    final priorHigh = maxOf(prior);
    final recentHigh = maxOf(recent);
    final priorLow = minOf(prior);
    final recentLow = minOf(recent);
    if (priorHigh == null ||
        recentHigh == null ||
        priorLow == null ||
        recentLow == null) {
      return false;
    }
    return recentHigh < priorHigh && recentLow < priorLow;
  }

  static bool maTangled(List<StockBar> bars) {
    final ma5 = sma(bars, 5);
    final ma10 = sma(bars, 10);
    final ma20 = sma(bars, 20);
    final ma30 = sma(bars, 30);
    if (ma5 == null || ma10 == null || ma20 == null || ma30 == null) {
      return false;
    }
    final values = [ma5, ma10, ma20, ma30];
    final maxV = values.reduce(max);
    final minV = values.reduce(min);
    if (minV == 0) return false;
    return (maxV - minV) / minV < 0.02;
  }

  static bool bearishEngulfing(List<StockBar> bars) {
    if (bars.length < 2) return false;
    final prev = bars[bars.length - 2];
    final cur = bars.last;
    final po = prev.effectiveOpen;
    final pc = prev.effectiveClose;
    final co = cur.effectiveOpen;
    final cc = cur.effectiveClose;
    if (po == null || pc == null || co == null || cc == null) return false;
    final prevBull = pc >= po;
    final curBear = cc < co;
    return prevBull && curBear && co >= pc && cc <= po;
  }

  static bool consecutiveBearish(List<StockBar> bars, {int count = 3}) {
    if (bars.length < count) return false;
    final slice = bars.sublist(bars.length - count);
    return slice.every((b) => b.isBearish);
  }

  static int consecutiveVolumeBearish(List<StockBar> bars, double avgVol) {
    if (avgVol <= 0) return 0;
    var streak = 0;
    for (var i = bars.length - 1; i >= 0; i--) {
      final b = bars[i];
      final vol = b.volume ?? 0;
      if (b.isBearish && vol > avgVol * 1.1) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }
}
