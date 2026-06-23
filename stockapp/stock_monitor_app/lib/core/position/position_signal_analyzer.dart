import '../models/position_signal.dart';
import '../models/position_signal_analysis.dart';
import '../models/stock_bar.dart';
import 'downtrend_detector.dart';
import 'technical_indicators.dart';

class PositionSignalAnalyzer {
  const PositionSignalAnalyzer({
    DowntrendDetector? downtrendDetector,
  }) : _downtrendDetector = downtrendDetector ?? const DowntrendDetector();

  static const int windowDays = 30;

  final DowntrendDetector _downtrendDetector;

  PositionSignalAnalysis analyze({
    required List<StockBar> dailyBars,
    required List<StockBar> weeklyBars,
    TrendPhase? previousTrendPhase,
    ReversalSeverity? previousSeverity,
  }) {
    if (dailyBars.length < windowDays) {
      return PositionSignalAnalysis(
        signalType: PositionSignalType.holdBaseOnly,
        trendPhase: TrendPhase.neutral,
        confidence: 0,
        strength: 1,
        reasons: const ['数据不足30个交易日'],
        latestDate: dailyBars.isNotEmpty ? dailyBars.last.tradeDate : '',
      );
    }

    final window30 = dailyBars.sublist(dailyBars.length - windowDays);
    final current = window30.last.effectiveClose ?? 0;
    final ma20 = TechnicalIndicators.sma(dailyBars, 20);
    final ma30 = TechnicalIndicators.sma(dailyBars, 30);
    final ma60 = TechnicalIndicators.sma(dailyBars, 60);
    final rsi = TechnicalIndicators.rsi(dailyBars);
    final adx = TechnicalIndicators.adx(dailyBars);
    final macd = TechnicalIndicators.macd(dailyBars);
    final atr = TechnicalIndicators.atr(dailyBars);
    final avgVol30 = TechnicalIndicators.avgVolume(window30, 30);
    final avgVolRecent10 =
        TechnicalIndicators.avgVolume(window30.sublist(window30.length - 10), 10);
    final volumeRatio = avgVol30 > 0 ? avgVolRecent10 / avgVol30 : null;
    final retrace = TechnicalIndicators.retracePercent(window30, current) ?? 0;
    final atrStop = atr != null && current > 0 ? current - atr * 2.5 : null;

    final low30 = window30
        .map((b) => b.effectiveLow)
        .whereType<double>()
        .reduce((a, b) => a < b ? a : b);
    final high30 = window30
        .map((b) => b.effectiveHigh)
        .whereType<double>()
        .reduce((a, b) => a > b ? a : b);

    // --- Downtrend detection first (highest priority) ---
    final downtrend = _downtrendDetector.detect(
      dailyBars: dailyBars,
      weeklyBars: weeklyBars,
    );

    if (downtrend.blockedByFilter) {
      return PositionSignalAnalysis(
        signalType: PositionSignalType.holdBaseOnly,
        trendPhase: TrendPhase.neutral,
        confidence: 30,
        strength: 1,
        reasons: downtrend.reasons,
        latestDate: window30.last.tradeDate,
        retracePercent: retrace,
        ma20: ma20,
        ma30: ma30,
        ma60: ma60,
        rsi: rsi,
        adx: adx,
        macdDif: macd.dif,
        macdDea: macd.dea,
        atrStopLoss: atrStop,
        volumeRatio: volumeRatio,
        triggeredSignals: downtrend.triggeredSignals,
        resonanceScore: downtrend.resonanceScore,
      );
    }

    if (downtrend.severity != null) {
      final isReversal = _isReversal(
        previousTrendPhase: previousTrendPhase,
        previousSeverity: previousSeverity,
        currentPhase: downtrend.trendPhase,
        currentSeverity: downtrend.severity,
      );
      final signalType = downtrend.severity == ReversalSeverity.earlyWarning
          ? PositionSignalType.trendBreak
          : PositionSignalType.trendReversal;

      return PositionSignalAnalysis(
        signalType: signalType,
        trendPhase: downtrend.trendPhase,
        reversalSeverity: downtrend.severity,
        isReversal: isReversal,
        confidence: _severityConfidence(downtrend.severity!),
        strength: downtrend.severity!.level,
        reasons: downtrend.reasons.isNotEmpty
            ? downtrend.reasons
            : ['潜在下跌趋势，转为防御'],
        suggestedAction: downtrend.suggestedAction,
        latestDate: window30.last.tradeDate,
        retracePercent: retrace,
        ma20: ma20,
        ma30: ma30,
        ma60: ma60,
        rsi: rsi,
        adx: adx,
        macdDif: macd.dif,
        macdDea: macd.dea,
        atrStopLoss: atrStop,
        volumeRatio: volumeRatio,
        triggeredSignals: downtrend.triggeredSignals,
        resonanceScore: downtrend.resonanceScore,
      );
    }

    // --- Uptrend premise ---
    final higherHL = TechnicalIndicators.higherHighsHigherLows(window30);
    final ma30Slope = TechnicalIndicators.maSlope(dailyBars, 30) ?? 0;
    final weeklyUp = _weeklyUptrend(weeklyBars);
    final adxOk = adx != null && adx >= 20;
    final aboveMas = current > 0 &&
        ma20 != null &&
        ma30 != null &&
        ma60 != null &&
        current > ma20 &&
        current > ma30 &&
        current > ma60;

    final rightSide = aboveMas &&
        higherHL &&
        ma30Slope >= -0.5 &&
        weeklyUp &&
        adxOk;

    final trendPhase =
        rightSide ? TrendPhase.rightSideUptrend : TrendPhase.neutral;

    if (!rightSide) {
      final triggers = <String>[];
      if (!aboveMas) triggers.add('belowMa');
      if (!higherHL) triggers.add('noHigherHL');
      if (ma30Slope < -0.5) triggers.add('ma30Down');
      if (!weeklyUp) triggers.add('weeklyWeak');
      if (!adxOk) triggers.add('adxWeak');
      return PositionSignalAnalysis(
        signalType: PositionSignalType.holdBaseOnly,
        trendPhase: trendPhase,
        confidence: 40,
        strength: 1,
        reasons: _holdBaseReasons(
          aboveMas: aboveMas,
          higherHL: higherHL,
          ma30Slope: ma30Slope,
          weeklyUp: weeklyUp,
          adxOk: adxOk,
          current: current,
          ma20: ma20,
          ma30: ma30,
          ma60: ma60,
          adx: adx,
        ),
        suggestedAction: '暂停加减仓，仅持底仓',
        triggeredSignals: triggers,
        latestDate: window30.last.tradeDate,
        retracePercent: retrace,
        ma20: ma20,
        ma30: ma30,
        ma60: ma60,
        rsi: rsi,
        adx: adx,
        macdDif: macd.dif,
        macdDea: macd.dea,
        atrStopLoss: atrStop,
        volumeRatio: volumeRatio,
      );
    }

    // --- Add signal ---
    final volRatioPct =
        avgVol30 > 0 ? (avgVolRecent10 / avgVol30 * 100) : 100.0;
    final holdSupport = current > low30 * 0.97;
    final healthyRetrace = retrace > 5 && retrace < 20;
    final volumeShrink = avgVolRecent10 < avgVol30 * 0.8;
    final rsiOversold = rsi != null && rsi < 40;
    final bullishRev = _bullishReversal(window30);
    final addSignal = healthyRetrace &&
        holdSupport &&
        volumeShrink &&
        current > ma20 &&
        (rsiOversold || bullishRev);

    if (addSignal) {
      final addTriggers = <String>[
        'rightSideUptrend',
        'healthyRetrace',
        'volumeShrink',
        'holdSupport',
        if (rsiOversold) 'rsiOversold',
        if (bullishRev) 'bullishReversal',
      ];
      return PositionSignalAnalysis(
        signalType: PositionSignalType.add,
        trendPhase: trendPhase,
        confidence: 72,
        strength: retrace > 12 ? 2 : 1,
        reasons: [
          '右侧趋势确认：价在MA20/30/60上方，30日更高高低点',
          '健康回调${retrace.toStringAsFixed(1)}%（触发区间5-20%）',
          '近10日缩量至30均量${volRatioPct.toStringAsFixed(0)}%（<80%）',
          '未破30日低点${low30.toStringAsFixed(2)}支撑',
          if (rsiOversold) 'RSI=${rsi.toStringAsFixed(0)}超卖(<40)',
          if (bullishRev) '近2日阳线反转形态',
        ],
        suggestedAction: retrace > 12
            ? '分批加仓：首次加可变仓20-30%，确认反弹再加20-30%'
            : '首次加可变仓20-30%，待放量小阳确认后追加',
        triggeredSignals: addTriggers,
        latestDate: window30.last.tradeDate,
        retracePercent: retrace,
        ma20: ma20,
        ma30: ma30,
        ma60: ma60,
        rsi: rsi,
        adx: adx,
        macdDif: macd.dif,
        macdDea: macd.dea,
        atrStopLoss: atrStop,
        volumeRatio: volumeRatio,
      );
    }

    // --- Reduce signal (take profit) ---
    final nearHigh = current >= high30 * 0.97;
    final shrinkRally = avgVolRecent10 < avgVol30 * 1.15;
    final rsiOverbought = rsi != null && rsi > 70;
    final distFromHigh =
        high30 > 0 ? (high30 - current) / high30 * 100 : 100.0;

    if (nearHigh && (shrinkRally || rsiOverbought)) {
      final reduceTriggers = <String>[
        'rightSideUptrend',
        'nearHigh30',
        if (shrinkRally) 'volumeStagnation',
        if (rsiOverbought) 'rsiOverbought',
      ];
      return PositionSignalAnalysis(
        signalType: PositionSignalType.reduce,
        trendPhase: trendPhase,
        confidence: 68,
        strength: rsiOverbought ? 2 : 1,
        reasons: [
          '右侧趋势中接近30日高点${high30.toStringAsFixed(2)}（距高点${distFromHigh.toStringAsFixed(1)}%）',
          if (shrinkRally)
            '近10日量${volRatioPct.toStringAsFixed(0)}%均量，上涨缩量滞涨',
          if (rsiOverbought) 'RSI=${rsi.toStringAsFixed(0)}超买(>70)',
          if (shrinkRally && rsiOverbought) '量价背离：价近高但动能衰竭',
        ],
        suggestedAction: rsiOverbought
            ? '倒金字塔减仓：先减可变仓30-40%，滞涨继续减'
            : '减可变仓20-40%，锁定利润',
        triggeredSignals: reduceTriggers,
        latestDate: window30.last.tradeDate,
        retracePercent: retrace,
        ma20: ma20,
        ma30: ma30,
        ma60: ma60,
        rsi: rsi,
        adx: adx,
        macdDif: macd.dif,
        macdDea: macd.dea,
        atrStopLoss: atrStop,
        volumeRatio: volumeRatio,
      );
    }

    return PositionSignalAnalysis(
      signalType: PositionSignalType.hold,
      trendPhase: trendPhase,
      confidence: 55,
      strength: 1,
      reasons: _holdReasons(
        retrace: retrace,
        distFromHigh: distFromHigh,
        volRatioPct: volRatioPct,
        rsi: rsi,
        healthyRetrace: healthyRetrace,
        nearHigh: nearHigh,
        volumeShrink: volumeShrink,
      ),
      suggestedAction: '持有观望，等待加仓或减仓信号触发',
      triggeredSignals: const ['rightSideUptrend', 'noActionYet'],
      latestDate: window30.last.tradeDate,
      retracePercent: retrace,
      ma20: ma20,
      ma30: ma30,
      ma60: ma60,
      rsi: rsi,
      adx: adx,
      macdDif: macd.dif,
      macdDea: macd.dea,
      atrStopLoss: atrStop,
      volumeRatio: volumeRatio,
    );
  }

  bool _isReversal({
    TrendPhase? previousTrendPhase,
    ReversalSeverity? previousSeverity,
    required TrendPhase currentPhase,
    required ReversalSeverity? currentSeverity,
  }) {
    if (currentSeverity == null) return false;
    if (previousTrendPhase == TrendPhase.rightSideUptrend &&
        currentPhase == TrendPhase.leftSideDowntrend) {
      return true;
    }
    if (previousSeverity != null &&
        currentSeverity.level > previousSeverity.level) {
      return true;
    }
    if (previousTrendPhase != TrendPhase.leftSideDowntrend &&
        currentPhase == TrendPhase.leftSideDowntrend) {
      return true;
    }
    return false;
  }

  double _severityConfidence(ReversalSeverity severity) {
    return switch (severity) {
      ReversalSeverity.earlyWarning => 65,
      ReversalSeverity.confirmed => 82,
      ReversalSeverity.deepDrop => 92,
    };
  }

  bool _weeklyUptrend(List<StockBar> weekly) {
    if (weekly.length < 5) return true;
    final last = weekly.last.effectiveClose;
    final prior = weekly[weekly.length - 5].effectiveClose;
    if (last == null || prior == null) return true;
    return last >= prior;
  }

  bool _bullishReversal(List<StockBar> window) {
    if (window.length < 2) return false;
    final prev = window[window.length - 2];
    final cur = window.last;
    final po = prev.effectiveOpen;
    final pc = prev.effectiveClose;
    final co = cur.effectiveOpen;
    final cc = cur.effectiveClose;
    if (po == null || pc == null || co == null || cc == null) return false;
    return pc < po && cc > co && cc > pc;
  }

  List<String> _holdReasons({
    required double retrace,
    required double distFromHigh,
    required double volRatioPct,
    required double? rsi,
    required bool healthyRetrace,
    required bool nearHigh,
    required bool volumeShrink,
  }) {
    final reasons = <String>['右侧趋势健康，当前无加减仓触发'];
    if (!healthyRetrace) {
      if (retrace < 5) {
        reasons.add('加仓待触发：回调需达5-20%（当前${retrace.toStringAsFixed(1)}%）');
      } else {
        reasons.add('回调${retrace.toStringAsFixed(1)}%过深，需确认未破支撑再加');
      }
    }
    if (!nearHigh) {
      reasons.add(
        '减仓待触发：需接近30日高点（当前距高点${distFromHigh.toStringAsFixed(1)}%）',
      );
    }
    if (healthyRetrace && !volumeShrink) {
      reasons.add(
        '接近加仓区但量能${volRatioPct.toStringAsFixed(0)}%偏高，需缩量(<80%)再介入',
      );
    }
    if (rsi != null) {
      reasons.add('RSI=${rsi.toStringAsFixed(0)}（加仓<40，减仓>70）');
    }
    return reasons;
  }

  List<String> _holdBaseReasons({
    required bool aboveMas,
    required bool higherHL,
    required double ma30Slope,
    required bool weeklyUp,
    required bool adxOk,
    required double current,
    required double? ma20,
    required double? ma30,
    required double? ma60,
    required double? adx,
  }) {
    final reasons = <String>['趋势未完全确认，暂不加减仓'];
    if (!aboveMas) {
      reasons.add(
        '价格${current.toStringAsFixed(2)}未站稳MA20/30/60'
        '（MA20=${ma20?.toStringAsFixed(2) ?? "-"}）',
      );
    }
    if (!higherHL) reasons.add('30日未形成更高高点+更高低点');
    if (ma30Slope < -0.5) reasons.add('MA30向下(${ma30Slope.toStringAsFixed(1)}%)');
    if (!weeklyUp) reasons.add('周线趋势未向上');
    if (!adxOk) {
      reasons.add('ADX=${adx?.toStringAsFixed(0) ?? "-"}<20，震荡市只持底仓');
    }
    return reasons;
  }
}
