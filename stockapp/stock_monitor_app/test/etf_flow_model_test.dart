import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor_app/core/api/eastmoney_client.dart';
import 'package:stock_monitor_app/core/engine/etf_flow_model.dart';
import 'package:stock_monitor_app/core/models/etf_models.dart';
import 'package:stock_monitor_app/core/models/watch_stock.dart';

void main() {
  group('AssetType / market', () {
    test('detects ETF codes', () {
      expect(AssetType.fromCode('510300'), AssetType.etf);
      expect(AssetType.fromCode('159915'), AssetType.etf);
      expect(AssetType.fromCode('600519'), AssetType.stock);
      expect(EastmoneyClient.marketFromCode('510300'), 'sh');
      expect(EastmoneyClient.marketFromCode('159915'), 'sz');
      expect(EastmoneyClient.secidFromCode('510300'), '1.510300');
    });

    test('invalid code still throws', () {
      expect(
        () => EastmoneyClient.marketFromCode('899999'),
        throwsA(isA<EastmoneyException>()),
      );
    });
  });

  group('EtfFlowModel quarterly', () {
    List<EtfSharePoint> buildQuarters({
      required List<double> nets,
      double startShare = 10000,
    }) {
      final dates = [
        '2023-03-31',
        '2023-06-30',
        '2023-09-30',
        '2023-12-31',
        '2024-03-31',
        '2024-06-30',
        '2024-09-30',
        '2024-12-31',
        '2025-03-31',
        '2025-06-30',
      ];
      final points = <EtfSharePoint>[];
      var share = startShare;
      for (var i = 0; i < nets.length; i++) {
        final net = nets[i];
        final apply = net >= 0 ? net : 0.0;
        final redeem = net < 0 ? -net : 0.0;
        share += net;
        points.add(
          EtfSharePoint(
            date: dates[i],
            totalShare: share,
            applyShare: apply,
            redeemShare: redeem,
            shareChangeQ: net,
            netShareChange: net,
          ),
        );
      }
      return points;
    }

    test('strong quarterly inflow scores higher', () {
      // 前几季温和，最近一季大幅净申购
      final points = buildQuarters(
        nets: [100, 80, 90, 70, 100, 90, 80, 100, 90, 800],
      );
      final features = EtfFlowModel.buildFeatures(points);
      expect(features.usedDailyFallback, isFalse);
      expect(features.quarterCount, 10);
      expect(features.burstRatio, greaterThan(1.5));
      final score = EtfFlowModel.score('510300', features);
      expect(score.buyIndex, greaterThan(55));
      expect(score.reasons.any((r) => r.contains('季')), isTrue);
    });

    test('quarterly net redeem scores lower', () {
      final points = buildQuarters(
        nets: [-200, -180, -150, -220, -190, -210, -180, -200, -170, -250],
      );
      final features = EtfFlowModel.buildFeatures(points);
      final score = EtfFlowModel.score('510300', features);
      expect(score.buyIndex, lessThan(50));
      expect(features.usedDailyFallback, isFalse);
    });

    test('extractQuarterReports ignores daily-only rows', () {
      final mixed = <EtfSharePoint>[
        const EtfSharePoint(date: '2025-06-01', totalShare: 100, netShareChange: 1),
        const EtfSharePoint(
          date: '2025-06-30',
          totalShare: 120,
          applyShare: 50,
          redeemShare: 30,
          netShareChange: 20,
        ),
        const EtfSharePoint(date: '2025-07-01', totalShare: 121, netShareChange: 1),
      ];
      final qs = EtfFlowModel.extractQuarterReports(mixed);
      expect(qs.length, 1);
      expect(qs.first.date, '2025-06-30');
      expect(qs.first.quarterNetShare, 20);
    });
  });
}
