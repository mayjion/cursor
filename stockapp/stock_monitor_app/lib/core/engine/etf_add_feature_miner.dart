import '../models/etf_models.dart';
import '../models/stock_bar.dart';
import 'etf_flow_model.dart';

/// 全池翻倍候选样本（含可解释特征），用于挖规则与回测。
class EtfAddSample {
  const EtfAddSample({
    required this.code,
    required this.quarterEnd,
    required this.pointDate,
    required this.net,
    required this.prevNet,
    required this.qoqMultiple,
    required this.persist4,
    required this.followOnRisk,
    this.forwardReturn,
    this.isWin,
    this.settled = false,
    this.mom20,
    this.mom60,
    this.pricePercentile,
    this.netIntensity,
    this.burstVsPrior4,
  });

  final String code;
  final String quarterEnd;
  final DateTime pointDate;
  final double net;
  final double prevNet;
  final double qoqMultiple;
  final double persist4;
  final bool followOnRisk;
  final double? forwardReturn;
  final bool? isWin;
  final bool settled;
  final double? mom20;
  final double? mom60;
  final double? pricePercentile;
  /// 净申购 / 当季末总份额
  final double? netIntensity;
  /// 本季净申购 / 前几季均值（托底）
  final double? burstVsPrior4;
}

/// 从全自选历史胜/负样本提炼辅助条件，组成可解释规则包。
///
/// 底条件（QoQ≥2×）全池胜率通常很低（约一成）；本挖掘器用
/// **数据驱动阈值 + 束搜索** 收紧辅助条件，优先找到胜率>80% 的子集。
class EtfAddFeatureMiner {
  static const double minWinRate = 0.80; // 达标：胜率 ≥ 80%
  static const int minSamples = 8;
  static const int maxAux = 5;
  static const int beamWidth = 40;

  static AddRulePack mine(List<EtfAddSample> baseSettled) {
    final settled =
        baseSettled.where((s) => s.settled && s.isWin != null).toList();
    if (settled.isEmpty) {
      return AddRulePack(updatedAt: DateTime.now());
    }

    final baseHits = settled.where((s) => s.isWin!).length;
    final baseRate = baseHits / settled.length;
    final catalog = _buildDataDrivenCatalog(settled);

    // 束状态：(aux, hits, samples, winRate)
    var beam = <_BeamNode>[
      _BeamNode(
        aux: const [],
        hits: baseHits,
        samples: settled.length,
        winRate: baseRate,
      ),
    ];

    AddRulePack? validated;
    var bestAny = AddRulePack(
      auxConditions: const [],
      winRate: baseRate,
      winHits: baseHits,
      winSamples: settled.length,
      validated: false,
      updatedAt: DateTime.now(),
    );

    for (var depth = 0; depth < maxAux; depth++) {
      final next = <_BeamNode>[];
      for (final node in beam) {
        final used = node.aux.map((e) => e.kind).toSet();
        for (final c in catalog) {
          if (used.contains(c.kind)) continue;
          final aux = [...node.aux, c];
          final eval = evaluate(settled, aux);
          if (eval.samples < minSamples) continue;
          // 胜率不能比父节点更差（允许持平但样本变少时需胜率提升）
          if (eval.winRate + 1e-9 < node.winRate &&
              eval.samples < node.samples) {
            continue;
          }
          next.add(
            _BeamNode(
              aux: aux,
              hits: eval.hits,
              samples: eval.samples,
              winRate: eval.winRate,
            ),
          );
        }
      }
      if (next.isEmpty) break;

      next.sort((a, b) {
        final wr = b.winRate.compareTo(a.winRate);
        if (wr != 0) return wr;
        return b.samples.compareTo(a.samples);
      });
      // 去重：同 kind 集合只留最优
      final dedup = <String, _BeamNode>{};
      for (final n in next) {
        final key = n.aux.map((e) => '${e.kind.name}:${e.p1}:${e.p2}').join('|');
        final old = dedup[key];
        if (old == null ||
            n.winRate > old.winRate ||
            (n.winRate == old.winRate && n.samples > old.samples)) {
          dedup[key] = n;
        }
      }
      final ranked = dedup.values.toList()
        ..sort((a, b) {
          final wr = b.winRate.compareTo(a.winRate);
          if (wr != 0) return wr;
          return b.samples.compareTo(a.samples);
        });
      beam = ranked.take(beamWidth).toList();

      for (final n in beam) {
        final pack = n.toPack();
        if (_isBetterAny(pack, bestAny)) bestAny = pack;
        if (pack.validated) {
          if (validated == null || _isBetterValidated(pack, validated)) {
            validated = pack;
          }
        }
      }

      if (validated != null) break;
    }

    // 再扫一遍单条件 / 已生成束，确保不漏掉单条件就达标的情况
    for (final c in catalog) {
      final eval = evaluate(settled, [c]);
      if (eval.samples < minSamples) continue;
      final pack = AddRulePack(
        auxConditions: [c],
        winRate: eval.winRate,
        winHits: eval.hits,
        winSamples: eval.samples,
        validated: eval.winRate >= minWinRate,
        updatedAt: DateTime.now(),
      );
      if (_isBetterAny(pack, bestAny)) bestAny = pack;
      if (pack.validated &&
          (validated == null || _isBetterValidated(pack, validated))) {
        validated = pack;
      }
    }

    return validated ?? bestAny;
  }

  static bool _isBetterAny(AddRulePack a, AddRulePack b) {
    final ar = a.winRate ?? 0;
    final br = b.winRate ?? 0;
    if (ar != br) return ar > br;
    return a.winSamples > b.winSamples;
  }

  static bool _isBetterValidated(AddRulePack a, AddRulePack b) {
    // 达标后优先样本更多，其次条件更少
    if (a.winSamples != b.winSamples) return a.winSamples > b.winSamples;
    return a.auxConditions.length < b.auxConditions.length;
  }

  static ({double winRate, int hits, int samples}) evaluate(
    List<EtfAddSample> settled,
    List<AddAuxCondition> aux,
  ) {
    var hits = 0;
    var samples = 0;
    for (final s in settled) {
      if (!matchesAux(s, aux)) continue;
      samples++;
      if (s.isWin == true) hits++;
    }
    final rate = samples == 0 ? 0.0 : hits / samples;
    return (winRate: rate, hits: hits, samples: samples);
  }

  static bool matchesAux(EtfAddSample s, List<AddAuxCondition> aux) {
    for (final c in aux) {
      if (!c.matchesSample(
        prevNet: s.prevNet,
        qoqMultiple: s.qoqMultiple,
        persist4: s.persist4,
        followOnRisk: s.followOnRisk,
        mom20: s.mom20,
        mom60: s.mom60,
        pricePercentile: s.pricePercentile,
        netIntensity: s.netIntensity,
        burstVsPrior4: s.burstVsPrior4,
      )) {
        return false;
      }
    }
    return true;
  }

  /// 由胜出/失败分布生成大量可解释阈值候选，再交给束搜索组合。
  static List<AddAuxCondition> _buildDataDrivenCatalog(
    List<EtfAddSample> settled,
  ) {
    final wins = settled.where((s) => s.isWin!).toList();
    final catalog = <AddAuxCondition>[
      const AddAuxCondition(kind: AddAuxKind.noFollowOnRisk),
    ];

    void addMaxCuts(
      AddAuxKind kind,
      double? Function(EtfAddSample) getter,
      List<double> extras,
    ) {
      final vals = <double>[
        ...extras,
        ..._quantiles(wins.map(getter).whereType<double>().toList()),
      ];
      for (final t in vals.toSet()) {
        // 扫描：特征值 ≤ t 时的子集胜率，只保留有希望抬精度的切点
        final eval = evaluate(settled, [AddAuxCondition(kind: kind, p1: t)]);
        if (eval.samples >= minSamples && eval.winRate > 0.12) {
          catalog.add(AddAuxCondition(kind: kind, p1: t));
        }
      }
      // 额外：按全量排序找「≤t 且胜率局部最优」的切点
      catalog.addAll(_bestUpperCuts(settled, kind, getter));
    }

    void addMinCuts(
      AddAuxKind kind,
      double? Function(EtfAddSample) getter,
      List<double> extras,
    ) {
      final vals = <double>[
        ...extras,
        ..._quantiles(wins.map(getter).whereType<double>().toList()),
      ];
      for (final t in vals.toSet()) {
        if (kind == AddAuxKind.netIntensityMin && t > 0.30) continue;
        if (kind == AddAuxKind.qoqMultipleMin && t > 30) continue;
        final eval = evaluate(settled, [AddAuxCondition(kind: kind, p1: t)]);
        if (eval.samples >= minSamples && eval.winRate > 0.12) {
          catalog.add(AddAuxCondition(kind: kind, p1: t));
        }
      }
      catalog.addAll(_bestLowerCuts(settled, kind, getter));
    }

    addMaxCuts(
      AddAuxKind.pricePercentileMax,
      (s) => s.pricePercentile,
      [0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.55],
    );
    addMaxCuts(
      AddAuxKind.mom20Max,
      (s) => s.mom20,
      [-0.05, 0, 0.05, 0.08, 0.1, 0.12, 0.15, 0.2, 0.25],
    );
    addMaxCuts(
      AddAuxKind.mom60Max,
      (s) => s.mom60,
      [0, 0.05, 0.1, 0.15, 0.2, 0.3, 0.4],
    );
    addMaxCuts(
      AddAuxKind.prevNetMax,
      (s) => s.prevNet,
      [0, 50, 100, 200, 500, 1000, 2000, 5000],
    );
    addMaxCuts(
      AddAuxKind.persist4Max,
      (s) => s.persist4,
      [0.25, 0.5, 0.75],
    );
    addMaxCuts(
      AddAuxKind.qoqMultipleMax,
      (s) => s.qoqMultiple,
      [5, 8, 10, 15, 20, 30, 50, 100],
    );

    addMinCuts(
      AddAuxKind.qoqMultipleMin,
      (s) => s.qoqMultiple,
      [2.5, 3, 4, 5, 6, 8, 10, 12, 15],
    );
    addMinCuts(
      AddAuxKind.mom20Min,
      (s) => s.mom20,
      [-0.15, -0.1, -0.05, 0, 0.02, 0.05],
    );
    addMinCuts(
      AddAuxKind.netIntensityMin,
      (s) => s.netIntensity,
      [0.005, 0.01, 0.02, 0.03, 0.05, 0.08, 0.1, 0.15, 0.2, 0.25],
    );
    addMinCuts(
      AddAuxKind.burstVsPrior4Min,
      (s) => s.burstVsPrior4,
      [2, 2.5, 3, 4, 5, 6, 8],
    );

    // 去重
    final seen = <String>{};
    final out = <AddAuxCondition>[];
    for (final c in catalog) {
      final key = '${c.kind.name}:${c.p1?.toStringAsFixed(6)}:${c.p2}';
      if (seen.add(key)) out.add(c);
    }
    return out;
  }

  static List<double> _quantiles(List<double> xs) {
    if (xs.isEmpty) return const [];
    final s = [...xs]..sort();
    double q(double p) {
      final i = ((s.length - 1) * p).round().clamp(0, s.length - 1);
      return s[i];
    }

    return [q(0.1), q(0.25), q(0.5), q(0.75), q(0.9)];
  }

  /// 找「特征 ≤ t」子集中胜率最高且样本够的切点（最多 6 个）。
  static List<AddAuxCondition> _bestUpperCuts(
    List<EtfAddSample> settled,
    AddAuxKind kind,
    double? Function(EtfAddSample) getter,
  ) {
    final rows = settled
        .map((s) => (s: s, v: getter(s)))
        .where((e) => e.v != null)
        .toList()
      ..sort((a, b) => a.v!.compareTo(b.v!));
    if (rows.length < minSamples) return const [];

    final scored = <({double t, double wr, int n})>[];
    var hits = 0;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].s.isWin!) hits++;
      final n = i + 1;
      if (n < minSamples) continue;
      // 只在阈值变化处记录
      if (i + 1 < rows.length && rows[i + 1].v == rows[i].v) continue;
      final wr = hits / n;
      scored.add((t: rows[i].v!, wr: wr, n: n));
    }
    scored.sort((a, b) {
      final wr = b.wr.compareTo(a.wr);
      if (wr != 0) return wr;
      return b.n.compareTo(a.n);
    });
    return scored
        .take(6)
        .where((e) => e.wr > 0.15)
        .map((e) => AddAuxCondition(kind: kind, p1: e.t))
        .toList();
  }

  /// 找「特征 ≥ t」子集中胜率最高的切点。
  static List<AddAuxCondition> _bestLowerCuts(
    List<EtfAddSample> settled,
    AddAuxKind kind,
    double? Function(EtfAddSample) getter,
  ) {
    final rows = settled
        .map((s) => (s: s, v: getter(s)))
        .where((e) => e.v != null)
        .toList()
      ..sort((a, b) => a.v!.compareTo(b.v!));
    if (rows.length < minSamples) return const [];

    final scored = <({double t, double wr, int n})>[];
    var hits = 0;
    // 从大到小扫：后缀
    for (var i = rows.length - 1; i >= 0; i--) {
      if (rows[i].s.isWin!) hits++;
      final n = rows.length - i;
      if (n < minSamples) continue;
      if (i > 0 && rows[i - 1].v == rows[i].v) continue;
      scored.add((t: rows[i].v!, wr: hits / n, n: n));
    }
    scored.sort((a, b) {
      final wr = b.wr.compareTo(a.wr);
      if (wr != 0) return wr;
      return b.n.compareTo(a.n);
    });
    return scored
        .take(8)
        .where((e) => e.wr > 0.15)
        .where((e) {
          if (kind == AddAuxKind.netIntensityMin && e.t > 0.30) return false;
          if (kind == AddAuxKind.qoqMultipleMin && e.t > 30) return false;
          return true;
        })
        .map((e) => AddAuxCondition(kind: kind, p1: e.t))
        .toList();
  }
}

class _BeamNode {
  const _BeamNode({
    required this.aux,
    required this.hits,
    required this.samples,
    required this.winRate,
  });

  final List<AddAuxCondition> aux;
  final int hits;
  final int samples;
  final double winRate;

  AddRulePack toPack() => AddRulePack(
        auxConditions: aux,
        winRate: winRate,
        winHits: hits,
        winSamples: samples,
        validated:
            samples >= EtfAddFeatureMiner.minSamples &&
            winRate >= EtfAddFeatureMiner.minWinRate,
        updatedAt: DateTime.now(),
      );
}

/// 从份额 + K 线抽取底条件翻倍样本。
class EtfAddSampleBuilder {
  static const double qoqMultipleMin = 2.0;
  /// 计胜门槛：下一季涨幅需超过该比例。
  /// 全池实测下一季>30%仅约7%，难以形成>80%有效规则；默认 15%（约处全池收益上沿）。
  static const double winReturnMin = 0.15;
  static const int forwardHorizonDays = 90;
  /// 净申购至少占总份额 0.3%，过滤噪音翻倍
  static const double minNetIntensity = 0.003;

  static List<EtfAddSample> build({
    required String code,
    required List<EtfSharePoint> shares,
    required List<StockBar> bars,
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();
    final quarters = EtfFlowModel.extractQuarterReports(shares);
    if (quarters.length < 2) return const [];

    final sortedBars = List<StockBar>.from(bars)
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));

    final out = <EtfAddSample>[];
    for (var i = 1; i < quarters.length; i++) {
      final net = quarters[i].quarterNetShare ?? 0;
      final prevNet = quarters[i - 1].quarterNetShare ?? 0;
      // 上季须为正，才谈「较上季翻倍」；避免上季≤0 时除数托底制造假巨倍
      if (net <= 0 || prevNet <= 0) continue;
      final multiple = net / prevNet;
      if (multiple < qoqMultipleMin) continue;

      final total = quarters[i].totalShare;
      final intensity = total.abs() < 1e-9 ? null : net / total.abs();
      if (intensity != null && intensity < minNetIntensity) continue;

      final qEnd = _parseDate(quarters[i].date);
      if (qEnd == null) continue;
      final qStart = _quarterStart(qEnd);

      final fwd = _forwardReturn(sortedBars, qStart, forwardHorizonDays);
      final ageDays = now.difference(qStart).inDays;
      final settled = ageDays > forwardHorizonDays && fwd != null;
      final isWin = settled ? fwd > winReturnMin : null;

      final priorStart = i >= 4 ? i - 4 : 0;
      final priorNets = quarters
          .sublist(priorStart, i)
          .map((e) => e.quarterNetShare ?? 0)
          .toList();
      final persist4 = priorNets.isEmpty
          ? 0.5
          : priorNets.where((e) => e > 0).length / priorNets.length;
      final priorAvg = priorNets.isEmpty
          ? 0.0
          : priorNets.fold<double>(0, (a, b) => a + b) / priorNets.length;
      final priorBase = priorAvg > 1e-6 ? priorAvg : 1e-6;
      final burstVsPrior4 = net / priorBase;

      var followOn = false;
      if (i + 1 < quarters.length) {
        final nextNet = quarters[i + 1].quarterNetShare ?? 0;
        if (nextNet >= net * qoqMultipleMin) followOn = true;
      }

      out.add(
        EtfAddSample(
          code: code,
          quarterEnd: quarters[i].date,
          pointDate: qStart,
          net: net,
          prevNet: prevNet,
          qoqMultiple: multiple,
          persist4: persist4,
          followOnRisk: followOn,
          forwardReturn: fwd,
          isWin: isWin,
          settled: settled,
          mom20: _momentum(sortedBars, qStart, 20),
          mom60: _momentum(sortedBars, qStart, 60),
          pricePercentile: _percentile(sortedBars, qStart, 252),
          netIntensity: intensity,
          burstVsPrior4: burstVsPrior4,
        ),
      );
    }
    return out;
  }

  static double? _forwardReturn(
    List<StockBar> bars,
    DateTime start,
    int horizonDays,
  ) {
    if (bars.isEmpty) return null;
    final end = start.add(Duration(days: horizonDays));
    final p0 = _closeOnOrAfter(bars, start);
    final p1 = _closeOnOrBefore(bars, end);
    if (p0 == null || p1 == null || p0 <= 0) return null;
    final lastBar = bars.last.tradeDate;
    if (lastBar.compareTo(_fmt(end.add(const Duration(days: -21)))) < 0) {
      return null;
    }
    return (p1 - p0) / p0;
  }

  static double? _momentum(List<StockBar> bars, DateTime at, int days) {
    final p1 = _closeOnOrBefore(bars, at);
    final p0 = _closeOnOrBefore(bars, at.subtract(Duration(days: days)));
    if (p0 == null || p1 == null || p0 <= 0) return null;
    return (p1 - p0) / p0;
  }

  static double? _percentile(List<StockBar> bars, DateTime at, int lookbackDays) {
    final key = _fmt(at);
    final from = _fmt(at.subtract(Duration(days: lookbackDays)));
    final closes = <double>[];
    double? atClose;
    for (final b in bars) {
      if (b.close == null) continue;
      if (b.tradeDate.compareTo(from) < 0) continue;
      if (b.tradeDate.compareTo(key) > 0) break;
      closes.add(b.close!);
      atClose = b.close;
    }
    if (closes.length < 8 || atClose == null) return null;
    final below = closes.where((c) => c <= atClose!).length;
    return below / closes.length;
  }

  static double? _closeOnOrAfter(List<StockBar> bars, DateTime day) {
    final key = _fmt(day);
    for (final b in bars) {
      if (b.tradeDate.compareTo(key) >= 0 && b.close != null) return b.close;
    }
    return null;
  }

  static double? _closeOnOrBefore(List<StockBar> bars, DateTime day) {
    final key = _fmt(day);
    double? last;
    for (final b in bars) {
      if (b.tradeDate.compareTo(key) <= 0) {
        if (b.close != null) last = b.close;
      } else {
        break;
      }
    }
    return last;
  }

  static DateTime? _parseDate(String raw) {
    final t = raw.length >= 10 ? raw.substring(0, 10) : raw;
    return DateTime.tryParse(t);
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
