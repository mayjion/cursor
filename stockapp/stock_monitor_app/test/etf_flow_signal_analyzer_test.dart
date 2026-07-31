import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor_app/core/engine/etf_add_feature_miner.dart';
import 'package:stock_monitor_app/core/engine/etf_flow_signal_analyzer.dart';
import 'package:stock_monitor_app/core/models/etf_models.dart';
import 'package:stock_monitor_app/core/models/stock_bar.dart';

void main() {
  group('EtfAddSampleBuilder & rules', () {
    List<EtfSharePoint> quarters(List<double> nets, {List<String>? dates}) {
      final defaultDates = [
        '2023-03-31',
        '2023-06-30',
        '2023-09-30',
        '2023-12-31',
        '2024-03-31',
        '2024-06-30',
        '2024-09-30',
        '2024-12-31',
      ];
      final ds = dates ?? defaultDates;
      var share = 100000.0;
      final out = <EtfSharePoint>[];
      for (var i = 0; i < nets.length; i++) {
        final net = nets[i];
        share += net;
        out.add(
          EtfSharePoint(
            date: ds[i],
            totalShare: share,
            applyShare: net > 0 ? net : 0,
            redeemShare: net < 0 ? -net : 0,
            netShareChange: net,
          ),
        );
      }
      return out;
    }

    List<StockBar> trendBars({
      required String from,
      required String to,
      required double start,
      required double end,
    }) {
      final a = DateTime.parse(from);
      final b = DateTime.parse(to);
      final days = b.difference(a).inDays;
      final list = <StockBar>[];
      for (var i = 0; i <= days; i += 7) {
        final d = a.add(Duration(days: i));
        final t = days == 0 ? 1.0 : i / days;
        final px = start + (end - start) * t;
        final ds =
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        list.add(
          StockBar(
            code: '510300',
            tradeDate: ds,
            open: px * 0.99,
            close: px,
            high: px * 1.01,
            low: px * 0.98,
          ),
        );
      }
      return list;
    }

    test('base candidate requires QoQ net >= 2x with positive prev', () {
      final shares = quarters([1000, 900, 800, 1000, 9000, 2000, 1500, 1200]);
      final bars = trendBars(
        from: '2023-01-01',
        to: '2025-03-01',
        start: 1.0,
        end: 1.5,
      );
      final samples = EtfAddSampleBuilder.build(
        code: '510300',
        shares: shares,
        bars: bars,
        asOf: DateTime(2025, 7, 1),
      );
      expect(samples, isNotEmpty);
      expect(samples.every((s) => s.qoqMultiple >= 2), isTrue);
      expect(samples.every((s) => s.prevNet > 0), isTrue);
    });

    test('skips fake multiple when previous net <= 0', () {
      final shares = quarters([1000, 900, 800, 1000, -500, 9000, 1500, 1200]);
      final bars = trendBars(
        from: '2023-01-01',
        to: '2025-03-01',
        start: 1.0,
        end: 1.2,
      );
      final samples = EtfAddSampleBuilder.build(
        code: '510300',
        shares: shares,
        bars: bars,
        asOf: DateTime(2025, 7, 1),
      );
      // -500 → 9000 不再算翻倍候选
      expect(
        samples.any((s) => s.quarterEnd.startsWith('2024-06')),
        isFalse,
      );
    });

    test('win requires next-quarter return above threshold', () {
      final shares = quarters([1000, 900, 800, 1000, 9000, 2000, 1500, 1200]);
      final bars = [
        ...trendBars(
          from: '2023-01-01',
          to: '2023-12-31',
          start: 1.0,
          end: 1.0,
        ),
        ...trendBars(
          from: '2024-01-01',
          to: '2024-04-15',
          start: 1.0,
          end: 1.2, // +20% > 15%
        ),
        ...trendBars(
          from: '2024-04-16',
          to: '2024-12-31',
          start: 1.2,
          end: 1.25,
        ),
      ];
      final samples = EtfAddSampleBuilder.build(
        code: '510300',
        shares: shares,
        bars: bars,
        asOf: DateTime(2025, 7, 1),
      );
      final s2024 = samples.firstWhere((s) => s.pointDate.year == 2024);
      expect(s2024.settled, isTrue);
      expect(s2024.forwardReturn! > EtfAddSampleBuilder.winReturnMin, isTrue);
      expect(s2024.isWin, isTrue);
    });

    test('miner can lift win rate above 80% with discriminative features', () {
      // 胜出：低价位分位；失败：高价位分位 → 价位过滤应能抬到 >80%
      final settled = <EtfAddSample>[
        ...List.generate(10, (i) {
          return EtfAddSample(
            code: 'W$i',
            quarterEnd: '2023-06-30',
            pointDate: DateTime(2023, 4, 1),
            net: 5000,
            prevNet: 1000,
            qoqMultiple: 5,
            persist4: 0.25,
            followOnRisk: false,
            forwardReturn: 0.4,
            isWin: true,
            settled: true,
            mom20: 0.03,
            mom60: 0.05,
            pricePercentile: 0.2,
            netIntensity: 0.05,
            burstVsPrior4: 4,
          );
        }),
        ...List.generate(40, (i) {
          return EtfAddSample(
            code: 'L$i',
            quarterEnd: '2023-06-30',
            pointDate: DateTime(2023, 4, 1),
            net: 3000,
            prevNet: 1000,
            qoqMultiple: 3,
            persist4: 0.75,
            followOnRisk: true,
            forwardReturn: 0.05,
            isWin: false,
            settled: true,
            mom20: 0.25,
            mom60: 0.4,
            pricePercentile: 0.85,
            netIntensity: 0.01,
            burstVsPrior4: 2.2,
          );
        }),
      ];

      final pack = EtfAddFeatureMiner.mine(settled);
      expect(pack.validated, isTrue);
      expect(pack.winRate!, greaterThan(0.8));
      expect(pack.winSamples, greaterThanOrEqualTo(8));
      expect(pack.auxConditions, isNotEmpty);
    });

    test('unvalidated pack does not mark actionable add', () {
      final shares = quarters(
        [1000, 2000, 800, 1000, 4000, 1000, 900, 5000],
        dates: [
          '2023-03-31',
          '2023-06-30',
          '2023-09-30',
          '2023-12-31',
          '2024-03-31',
          '2024-06-30',
          '2024-09-30',
          '2025-03-31',
        ],
      );
      final bars = trendBars(
        from: '2023-01-01',
        to: '2025-04-01',
        start: 1.0,
        end: 1.1,
      );
      const pack = AddRulePack(
        validated: false,
        winRate: 0.12,
        winHits: 12,
        winSamples: 100,
      );
      final result = EtfFlowSignalAnalyzer.analyze(
        code: '510300',
        shares: shares,
        bars: bars,
        rulePack: pack,
        asOf: DateTime(2025, 3, 20),
      );
      expect(
        result.signals
            .where((s) => s.isActionable && s.type == EtfFlowSignalType.add),
        isEmpty,
      );
    });

    test('validated pack marks recent matching sample as add with high fitness',
        () {
      final bars = trendBars(
        from: '2023-01-01',
        to: '2025-04-01',
        start: 1.0,
        end: 1.05,
      );
      final pack = AddRulePack(
        validated: true,
        winRate: 0.85,
        winHits: 17,
        winSamples: 20,
        auxConditions: const [
          AddAuxCondition(kind: AddAuxKind.qoqMultipleMin, p1: 2.5),
        ],
      );
      // 2025Q1: prev=30 net=100 → 3.33x
      final shares3 = quarters(
        [1000, 900, 800, 1000, 500, 400, 300, 1000],
        dates: [
          '2023-03-31',
          '2023-06-30',
          '2023-09-30',
          '2023-12-31',
          '2024-03-31',
          '2024-06-30',
          '2024-09-30',
          '2025-03-31',
        ],
      );

      final result = EtfFlowSignalAnalyzer.analyze(
        code: '510300',
        shares: shares3,
        bars: bars,
        rulePack: pack,
        asOf: DateTime(2025, 3, 20),
      );
      final actionable = result.signals
          .where((s) => s.type == EtfFlowSignalType.add && s.isActionable)
          .toList();
      expect(actionable, isNotEmpty);
      expect(actionable.first.pointDate, '2025-01-01');
      expect(result.addFitness, greaterThanOrEqualTo(70));
    });
  });
}
