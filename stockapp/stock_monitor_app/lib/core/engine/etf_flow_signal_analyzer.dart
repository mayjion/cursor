import '../models/etf_models.dart';
import '../models/stock_bar.dart';
import 'etf_add_feature_miner.dart';
import 'etf_flow_model.dart';

/// 基于「季净申购环比≥2倍」底条件 + 全池校验规则包的量价信号。
class EtfFlowSignalAnalyzer {
  static const double qoqMultipleMin = 2.0;
  static const double followMultiple = 2.0;
  static const int activeWindowDays = 92;
  static const double winReturnMin = 0.15;

  /// 用已挖好的全池规则包，对单只 ETF 生成信号与加仓适配度。
  static EtfFlowSignalResult analyze({
    required String code,
    required List<EtfSharePoint> shares,
    required List<StockBar> bars,
    required AddRulePack rulePack,
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    final samples = EtfAddSampleBuilder.build(
      code: code,
      shares: shares,
      bars: bars,
      asOf: now,
    );
    if (samples.isEmpty) {
      return EtfFlowSignalResult(
        signals: const [],
        winRate: rulePack.winRate,
        winHits: rulePack.winHits,
        winSamples: rulePack.winSamples,
        historySupportsAdd: rulePack.validated,
        addFitness: 0,
        rulePackValidated: rulePack.validated,
      );
    }

    final signals = <EtfFlowSignal>[];
    var addFitness = 0.0;
    EtfAddSample? bestLive;

    for (final s in samples) {
      final passAux = EtfAddFeatureMiner.matchesAux(s, rulePack.auxConditions);
      final ageDays = now.difference(s.pointDate).inDays;
      final isRecent = ageDays >= 0 && ageDays <= activeWindowDays;
      final startStr = _fmt(s.pointDate);
      final retText = s.forwardReturn == null
          ? ''
          : '，其后约一季涨跌${(s.forwardReturn! * 100).toStringAsFixed(1)}%';

      // 当下适合加仓：规则已校验 + 近一季 + 底条件(已在样本) + 辅助全中
      final actionable =
          rulePack.validated && isRecent && passAux && !s.followOnRisk;

      if (actionable) {
        if (bestLive == null ||
            s.pointDate.isAfter(bestLive.pointDate) ||
            s.qoqMultiple > bestLive.qoqMultiple) {
          bestLive = s;
        }
        signals.add(
          EtfFlowSignal(
            type: EtfFlowSignalType.add,
            quarterEnd: s.quarterEnd,
            pointDate: startStr,
            netShare: s.net,
            multiple: s.qoqMultiple,
            isHistorical: false,
            isActionable: true,
            forwardReturn: s.forwardReturn,
            isWin: s.isWin,
            reason:
                '适合加仓：环比净申购${s.qoqMultiple.toStringAsFixed(1)}倍，'
                '且命中已校验全池规则（胜率${((rulePack.winRate ?? 0) * 100).toStringAsFixed(0)}%）',
          ),
        );
      } else {
        final why = !rulePack.validated
            ? '全池规则胜率未达80%门槛，暂不预测加仓'
            : (!isRecent
                ? '距今超过约一季，仅作历史规律'
                : (!passAux
                    ? '未命中全部辅助条件'
                    : (s.followOnRisk ? '存在跟风再放大风险' : '未升格')));
        final outcome = s.isWin == null
            ? ''
            : (s.isWin! ? '（回测：胜>30%）' : '（回测：未达30%）');
        signals.add(
          EtfFlowSignal(
            type: EtfFlowSignalType.add,
            quarterEnd: s.quarterEnd,
            pointDate: startStr,
            netShare: s.net,
            multiple: s.qoqMultiple,
            isHistorical: true,
            isActionable: false,
            forwardReturn: s.forwardReturn,
            isWin: s.isWin,
            reason:
                '历史/候选：环比${s.qoqMultiple.toStringAsFixed(1)}倍$retText$outcome。$why',
          ),
        );

        // 近一季仅翻倍未过辅助：给中低分参考
        if (rulePack.validated && isRecent && !passAux && !s.followOnRisk) {
          addFitness = addFitness < 35 ? 35 : addFitness;
        }
      }
    }

    // 风险点：翻倍后再跟风 ≥2 倍
    final quarters = EtfFlowModel.extractQuarterReports(shares);
    for (var i = 1; i < quarters.length; i++) {
      final net = quarters[i].quarterNetShare ?? 0;
      final prev = quarters[i - 1].quarterNetShare ?? 0;
      if (net <= 0) continue;
      final denom = prev > 1e-6 ? prev : 1e-6;
      if (net / denom < qoqMultipleMin) continue;
      if (i + 1 >= quarters.length) continue;
      final nextNet = quarters[i + 1].quarterNetShare ?? 0;
      if (nextNet < net * followMultiple) continue;
      final qEnd = DateTime.tryParse(
        quarters[i + 1].date.length >= 10
            ? quarters[i + 1].date.substring(0, 10)
            : quarters[i + 1].date,
      );
      if (qEnd == null) continue;
      final qStart = _quarterStart(qEnd);
      final ageDays = now.difference(qStart).inDays;
      final recent = ageDays >= 0 && ageDays <= activeWindowDays;
      signals.add(
        EtfFlowSignal(
          type: EtfFlowSignalType.risk,
          quarterEnd: quarters[i + 1].date,
          pointDate: _fmt(qStart),
          netShare: nextNet,
          multiple: nextNet / net,
          relatedAddDate: _fmt(_quarterStart(DateTime.parse(
            quarters[i].date.length >= 10
                ? quarters[i].date.substring(0, 10)
                : quarters[i].date,
          ))),
          isHistorical: !recent,
          isActionable: recent,
          reason:
              '${recent ? '当前' : '历史'}风险点：加仓季后再放大≥2倍，疑似跟风盘',
        ),
      );
      if (recent) {
        addFitness = (addFitness - 25).clamp(0, 100);
      }
    }

    if (bestLive != null && rulePack.validated) {
      // 适配度：基数 + 倍数贡献 + 全池胜率贡献
      final multBoost = ((bestLive.qoqMultiple - 2) * 8).clamp(0, 25);
      final wrBoost = ((rulePack.winRate ?? 0) - 0.8) * 100;
      addFitness = (70 + multBoost + wrBoost).clamp(70, 100);
    }

    signals.sort((a, b) {
      final aPri = a.isActionable ? 0 : 1;
      final bPri = b.isActionable ? 0 : 1;
      if (aPri != bPri) return aPri.compareTo(bPri);
      return b.pointDate.compareTo(a.pointDate);
    });

    return EtfFlowSignalResult(
      signals: signals,
      winRate: rulePack.winRate,
      winHits: rulePack.winHits,
      winSamples: rulePack.winSamples,
      historySupportsAdd: rulePack.validated,
      addFitness: double.parse(addFitness.toStringAsFixed(1)),
      rulePackValidated: rulePack.validated,
    );
  }

  static DateTime _quarterStart(DateTime quarterEnd) {
    final m = quarterEnd.month;
    if (m <= 3) return DateTime(quarterEnd.year, 1, 1);
    if (m <= 6) return DateTime(quarterEnd.year, 4, 1);
    if (m <= 9) return DateTime(quarterEnd.year, 7, 1);
    return DateTime(quarterEnd.year, 10, 1);
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
