import 'dart:math';

import '../models/position_signal.dart';
import '../models/stock_bar.dart';
import 'technical_indicators.dart';

class DowntrendDetectionResult {
  const DowntrendDetectionResult({
    required this.blockedByFilter,
    required this.triggeredSignals,
    required this.severity,
    required this.trendPhase,
    required this.resonanceScore,
    required this.reasons,
    this.suggestedAction,
  });

  final bool blockedByFilter;
  final List<String> triggeredSignals;
  final ReversalSeverity? severity;
  final TrendPhase trendPhase;
  final int resonanceScore;
  final List<String> reasons;
  final String? suggestedAction;
}

class DowntrendDetector {
  const DowntrendDetector();

  DowntrendDetectionResult detect({
    required List<StockBar> dailyBars,
    required List<StockBar> weeklyBars,
  }) {
    if (dailyBars.length < 30) {
      return const DowntrendDetectionResult(
        blockedByFilter: false,
        triggeredSignals: [],
        severity: null,
        trendPhase: TrendPhase.neutral,
        resonanceScore: 0,
        reasons: ['数据不足30日'],
      );
    }

    final window30 = dailyBars.sublist(dailyBars.length - 30);
    final current = window30.last.effectiveClose ?? 0;
    final ma5 = TechnicalIndicators.sma(dailyBars, 5);
    final ma10 = TechnicalIndicators.sma(dailyBars, 10);
    final ma20 = TechnicalIndicators.sma(dailyBars, 20);
    final ma30 = TechnicalIndicators.sma(dailyBars, 30);
    final ma60 = TechnicalIndicators.sma(dailyBars, 60);
    final avgVol30 = TechnicalIndicators.avgVolume(window30, 30);
    final recent10 = window30.sublist(window30.length - 10);
    final recent5 = window30.sublist(window30.length - 5);
    final avgVolRecent10 = TechnicalIndicators.avgVolume(recent10, 10);
    final avgVolRecent5 = TechnicalIndicators.avgVolume(recent5, 5);
    final rsi = TechnicalIndicators.rsi(dailyBars);
    final rsiSlope = TechnicalIndicators.rsiSlope(dailyBars);
    final adx = TechnicalIndicators.adx(dailyBars);
    final macd = TechnicalIndicators.macd(dailyBars);
    final low30 = window30
        .map((b) => b.effectiveLow)
        .whereType<double>()
        .reduce((a, b) => a < b ? a : b);
    final high30 = window30
        .map((b) => b.effectiveHigh)
        .whereType<double>()
        .reduce((a, b) => a > b ? a : b);

    final triggered = <String>[];
    final reasons = <String>[];

    // --- Price signals ---
    final lowerHighsLows =
        TechnicalIndicators.lowerHighsLowerLows(window30);
    if (lowerHighsLows) {
      triggered.add('lowerHighsLows');
      reasons.add('30日内出现更低高点与更低低点');
    }

    final breakSupport = current > 0 &&
        ma30 != null &&
        (current < low30 * 0.97 || current < ma30) &&
        avgVolRecent5 > avgVol30 * 1.1;
    if (breakSupport) {
      triggered.add('breakSupport');
      reasons.add('有效跌破30日支撑/MA30且近5日放量');
    }

    final maDeathCross = ma5 != null &&
        ma10 != null &&
        ma20 != null &&
        ma30 != null &&
        (ma5 < ma10 && ma10 < ma20 && ma20 < ma30);
    if (maDeathCross) {
      triggered.add('maDeathCross');
      reasons.add('均线空头排列（MA5<MA10<MA20<MA30）');
    }

    var belowMa30Days = 0;
    for (var i = dailyBars.length - 1; i >= dailyBars.length - 5 && i >= 0; i--) {
      final c = dailyBars[i].effectiveClose;
      final m30 = TechnicalIndicators.smaAt(dailyBars, i, 30);
      if (c != null && m30 != null && c < m30) belowMa30Days++;
    }
    final belowMa30Sustained = belowMa30Days >= 3;
    if (belowMa30Sustained) {
      triggered.add('belowMa30Sustained');
      reasons.add('连续3日收盘在MA30下方');
    }

    // --- Volume signals ---
    var downVolDays = 0;
    for (final b in recent10) {
      final vol = b.volume ?? 0;
      if (b.isBearish && vol > avgVol30 * 1.1) downVolDays++;
    }
    final downOnVolume = downVolDays >= 2;
    if (downOnVolume) {
      triggered.add('downOnVolume');
      reasons.add('近10日下跌放量（抛压加重）');
    }

    final upOnLowVolume = avgVolRecent5 < avgVol30 * 0.9 &&
        current > window30[window30.length - 6].effectiveClose!;
    if (upOnLowVolume) {
      triggered.add('upOnLowVolume');
      reasons.add('小反弹但量能不足');
    }

    final prior10 = window30.sublist(0, 10);
    final prior10Vol = TechnicalIndicators.avgVolume(prior10, 10);
    final bearishDivergence = current <= low30 * 1.02 &&
        avgVolRecent10 < prior10Vol * 0.85;
    if (bearishDivergence) {
      triggered.add('bearishDivergence');
      reasons.add('价格走弱且量能萎缩（趋势仍弱）');
    }

    // --- Indicator signals ---
    final rsiWeak = rsi != null && rsi < 40 && (rsiSlope ?? 0) < 0;
    if (rsiWeak) {
      triggered.add('rsiWeak');
      reasons.add('RSI<40且持续走弱');
    }

    final rsiBearishDiv = _rsiBearishDivergence(window30);
    if (rsiBearishDiv) {
      triggered.add('rsiBearishDiv');
      reasons.add('RSI负背离（上涨衰竭）');
    }

    final adxWeak = adx != null && adx < 20;
    if (adxWeak) {
      triggered.add('adxWeak');
    }

    final macdBearish = TechnicalIndicators.macdDeathCross(dailyBars) ||
        ((macd.dif ?? 0) < 0 && (macd.dea ?? 0) < 0);
    if (macdBearish) {
      triggered.add('macdBearish');
      reasons.add('MACD死叉或在零轴下方');
    }

    final bearishCandles =
        TechnicalIndicators.consecutiveBearish(window30, count: 3) ||
            TechnicalIndicators.bearishEngulfing(window30);
    if (bearishCandles) {
      triggered.add('bearishCandles');
      reasons.add('连续大阴或吞没形态');
    }

    // --- Weekly signals ---
    final weeklyBreak = _weeklyBreak(weeklyBars);
    if (weeklyBreak) {
      triggered.add('weeklyBreak');
      reasons.add('周线趋势转弱或破位');
    }

    final invalidRebounds = _invalidRebounds(window30, high30, avgVol30);
    if (invalidRebounds) {
      triggered.add('invalidRebounds');
      reasons.add('多次反弹未放量创新高');
    }

    // --- Pseudo-signal filters ---
    if (_flashCrashRecovery(dailyBars, ma30)) {
      return DowntrendDetectionResult(
        blockedByFilter: true,
        triggeredSignals: triggered,
        severity: null,
        trendPhase: TrendPhase.neutral,
        resonanceScore: triggered.length,
        reasons: ['闪崩后快速收复，暂不判逆转'],
      );
    }

    if (TechnicalIndicators.maTangled(dailyBars) && adxWeak) {
      return DowntrendDetectionResult(
        blockedByFilter: true,
        triggeredSignals: triggered,
        severity: null,
        trendPhase: TrendPhase.neutral,
        resonanceScore: triggered.length,
        reasons: ['MA纠缠震荡，ADX<20，暂停行动'],
      );
    }

    if (_falseBreakRecovery(dailyBars, low30, avgVol30)) {
      return DowntrendDetectionResult(
        blockedByFilter: true,
        triggeredSignals: triggered,
        severity: null,
        trendPhase: TrendPhase.neutral,
        resonanceScore: triggered.length,
        reasons: ['假突破已收回，暂不判逆转'],
      );
    }

    final priceSignals = triggered.where((s) => {
          'lowerHighsLows',
          'breakSupport',
          'maDeathCross',
          'belowMa30Sustained',
        }.contains(s));
    final volumeSignals = triggered.where((s) => {
          'downOnVolume',
          'upOnLowVolume',
          'bearishDivergence',
        }.contains(s));
    final indicatorSignals = triggered.where((s) => {
          'rsiWeak',
          'rsiBearishDiv',
          'macdBearish',
          'bearishCandles',
        }.contains(s));

    final hasPriceBreak =
        triggered.contains('breakSupport') || triggered.contains('maDeathCross');
    final hasVolumeBad =
        triggered.contains('downOnVolume') || triggered.contains('upOnLowVolume');
    final hasIndicator =
        indicatorSignals.isNotEmpty;

    ReversalSeverity? severity;
    String? suggestedAction;
    TrendPhase trendPhase = TrendPhase.neutral;

    final volBearStreak =
        TechnicalIndicators.consecutiveVolumeBearish(window30, avgVol30);
    final belowMa60 = ma60 != null && current < ma60;

    // Confirmed reversal
    if (hasPriceBreak && hasVolumeBad && hasIndicator) {
      severity = ReversalSeverity.confirmed;
      trendPhase = TrendPhase.leftSideDowntrend;
      suggestedAction = '清空可变仓，底仓观察并设ATR止损';
    } else if (hasPriceBreak &&
        (hasVolumeBad || hasIndicator) &&
        priceSignals.length + volumeSignals.length + indicatorSignals.length >= 3) {
      severity = ReversalSeverity.confirmed;
      trendPhase = TrendPhase.leftSideDowntrend;
      suggestedAction = '清空可变仓，底仓观察并设ATR止损';
    }

    // Deep drop
    if (severity == ReversalSeverity.confirmed &&
        (belowMa60 || weeklyBreak || volBearStreak >= 3)) {
      severity = ReversalSeverity.deepDrop;
      suggestedAction = '整体减仓或清仓，切换防御';
    }

    // Early warning
    if (severity == null &&
        lowerHighsLows &&
        (upOnLowVolume || rsiWeak) &&
        triggered.length >= 2) {
      severity = ReversalSeverity.earlyWarning;
      trendPhase = TrendPhase.leftSideDowntrend;
      suggestedAction = '减可变仓30-50%，暂停加仓，观察';
    }

    if (severity != null && trendPhase == TrendPhase.neutral) {
      trendPhase = TrendPhase.leftSideDowntrend;
    }

    return DowntrendDetectionResult(
      blockedByFilter: false,
      triggeredSignals: triggered,
      severity: severity,
      trendPhase: trendPhase,
      resonanceScore: triggered.length,
      reasons: reasons,
      suggestedAction: suggestedAction,
    );
  }

  bool _rsiBearishDivergence(List<StockBar> window) {
    if (window.length < 14) return false;
    final recentHigh = window
        .sublist(window.length - 10)
        .map((b) => b.effectiveHigh)
        .whereType<double>()
        .fold<double>(0, (a, b) => a > b ? a : b);
    final priorHigh = window
        .sublist(0, 10)
        .map((b) => b.effectiveHigh)
        .whereType<double>()
        .fold<double>(0, (a, b) => a > b ? a : b);
    if (recentHigh <= priorHigh) return false;
    final rsiRecent = TechnicalIndicators.rsi(window);
    final rsiPrior = TechnicalIndicators.rsi(window.sublist(0, window.length - 5));
    if (rsiRecent == null || rsiPrior == null) return false;
    return rsiRecent < rsiPrior;
  }

  bool _weeklyBreak(List<StockBar> weekly) {
    if (weekly.length < 8) return false;
    final recent4 = weekly.sublist(weekly.length - 4);
    final prior4 = weekly.sublist(weekly.length - 8, weekly.length - 4);
    double maxOf(List<StockBar> bars) {
      return bars
          .map((b) => b.effectiveHigh)
          .whereType<double>()
          .fold<double>(0, (a, b) => a > b ? a : b);
    }

    double minOf(List<StockBar> bars) {
      return bars
          .map((b) => b.effectiveLow)
          .whereType<double>()
          .fold<double>(double.infinity, (a, b) => a < b ? a : b);
    }

    final lowerWeekly = maxOf(recent4) < maxOf(prior4) &&
        minOf(recent4) < minOf(prior4);
    final wMa30 = TechnicalIndicators.sma(weekly, 30);
    final wMa60 = TechnicalIndicators.sma(weekly, min(60, weekly.length));
    final lastClose = weekly.last.effectiveClose;
    final maBreak = lastClose != null &&
        wMa30 != null &&
        lastClose < wMa30 &&
        (wMa60 == null || lastClose < wMa60);
    return lowerWeekly || maBreak;
  }

  bool _invalidRebounds(List<StockBar> window, double high30, double avgVol) {
    if (avgVol <= 0) return false;
    var count = 0;
    for (var i = 5; i < window.length - 5; i += 5) {
      final slice = window.sublist(i, i + 5);
      final localHigh =
          slice.map((b) => b.effectiveHigh).whereType<double>().fold<double>(
                0,
                (a, b) => a > b ? a : b,
              );
      final localVol = TechnicalIndicators.avgVolume(slice, 5);
      if (localHigh < high30 * 0.95 && localVol < avgVol * 0.9) {
        count++;
      }
    }
    return count >= 2;
  }

  bool _flashCrashRecovery(List<StockBar> bars, double? ma30) {
    if (bars.length < 5 || ma30 == null) return false;
    for (var i = bars.length - 4; i < bars.length - 2; i++) {
      final change = bars[i].changePercent;
      if (change != null && change < -3) {
        final next = bars[i + 1].effectiveClose;
        final next2 = bars[i + 2].effectiveClose;
        if (next != null && next2 != null && next2 >= ma30) {
          return true;
        }
      }
    }
    return false;
  }

  bool _falseBreakRecovery(
    List<StockBar> bars,
    double low30,
    double avgVol,
  ) {
    if (bars.length < 5 || avgVol <= 0) return false;
    final recent = bars.sublist(bars.length - 5);
    var broke = false;
    for (final b in recent.take(3)) {
      final c = b.effectiveClose;
      if (c != null && c < low30 * 0.97) broke = true;
    }
    if (!broke) return false;
    final last = recent.last.effectiveClose ?? 0;
    final lastVol = recent.last.volume ?? 0;
    return last >= low30 && lastVol < avgVol * 0.85;
  }
}
