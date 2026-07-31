import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:stock_monitor_app/core/api/eastmoney_client.dart';
import 'package:stock_monitor_app/core/engine/etf_add_feature_miner.dart';
import 'package:stock_monitor_app/core/models/etf_models.dart';
import 'package:stock_monitor_app/core/models/stock_bar.dart';

/// 用手机拉出的 Hive 份额缓存 + 网络周K，离线回测/挖规则。
///
/// 用法：
///   dart run tool/analyze_etf_add_rules.dart [hiveDir] [maxEtfs]
Future<void> main(List<String> args) async {
  final hiveDir = args.isNotEmpty ? args[0] : 'tmp_device_hive';
  final maxEtfs = args.length > 1 ? int.parse(args[1]) : 9999;

  Hive.init(hiveDir);
  final shareBox = await Hive.openBox<String>('etf_share_cache');
  stdout.writeln('share cache keys: ${shareBox.length}');

  final client = EastmoneyClient();
  final allSamples = <EtfAddSample>[];
  final codes = shareBox.keys.map((e) => e.toString()).take(maxEtfs).toList();
  var ok = 0;
  var fail = 0;

  for (var i = 0; i < codes.length; i++) {
    final code = codes[i];
    try {
      final raw = shareBox.get(code);
      if (raw == null) continue;
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final points = (map['points'] as List<dynamic>? ?? [])
          .map((e) => EtfSharePoint.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
      if (points.isEmpty) continue;

      List<StockBar> bars = const [];
      try {
        bars = await client.fetchWeeklyBars(code, limit: 200);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final samples = EtfAddSampleBuilder.build(
        code: code,
        shares: points,
        bars: bars,
      );
      allSamples.addAll(samples);
      ok++;
    } catch (_) {
      fail++;
    }
    if ((i + 1) % 50 == 0 || i + 1 == codes.length) {
      stdout.writeln(
        'progress ${i + 1}/${codes.length} ok=$ok fail=$fail samples=${allSamples.length}',
      );
    }
  }

  final settled = allSamples.where((s) => s.settled && s.isWin != null).toList();
  final wins = settled.where((s) => s.isWin!).toList();
  final baseRate = settled.isEmpty ? 0.0 : wins.length / settled.length;

  stdout.writeln('\n=== BASE (QoQ>=2x, prev>0, intensity) ===');
  stdout.writeln(
    'candidates=${allSamples.length} settled=${settled.length} '
    'wins=${wins.length} baseWinRate=${(baseRate * 100).toStringAsFixed(2)}%',
  );

  if (settled.isNotEmpty) {
    final rets = settled.map((s) => s.forwardReturn!).toList()..sort();
    double q(double p) => rets[((rets.length - 1) * p).round()];
    stdout.writeln(
      'forwardReturn p10=${(q(0.1) * 100).toStringAsFixed(1)}% '
      'p50=${(q(0.5) * 100).toStringAsFixed(1)}% '
      'p90=${(q(0.9) * 100).toStringAsFixed(1)}% '
      'max=${(rets.last * 100).toStringAsFixed(1)}%',
    );
  }

  final pack = EtfAddFeatureMiner.mine(settled);
  stdout.writeln('\n=== MINED RULE PACK ===');
  stdout.writeln('validated=${pack.validated}');
  stdout.writeln(
    'winRate=${((pack.winRate ?? 0) * 100).toStringAsFixed(2)}% '
    '(${pack.winHits}/${pack.winSamples})',
  );
  for (final line in pack.ruleLinesZh) {
    stdout.writeln(' - $line');
  }

  stdout.writeln('\n=== TOP SINGLE FILTERS (by winRate, n>=8) ===');
  final catalog = <AddAuxCondition>[
    const AddAuxCondition(kind: AddAuxKind.noFollowOnRisk),
    const AddAuxCondition(kind: AddAuxKind.pricePercentileMax, p1: 0.3),
    const AddAuxCondition(kind: AddAuxKind.pricePercentileMax, p1: 0.4),
    const AddAuxCondition(kind: AddAuxKind.mom20Max, p1: 0.1),
    const AddAuxCondition(kind: AddAuxKind.qoqMultipleMin, p1: 5),
    const AddAuxCondition(kind: AddAuxKind.qoqMultipleMax, p1: 20),
    const AddAuxCondition(kind: AddAuxKind.netIntensityMin, p1: 0.05),
    const AddAuxCondition(kind: AddAuxKind.burstVsPrior4Min, p1: 4),
  ];
  final singles = <({AddAuxCondition c, double wr, int n, int h})>[];
  for (final c in catalog) {
    final e = EtfAddFeatureMiner.evaluate(settled, [c]);
    if (e.samples >= 8) {
      singles.add((c: c, wr: e.winRate, n: e.samples, h: e.hits));
    }
  }
  singles.sort((a, b) => b.wr.compareTo(a.wr));
  for (final s in singles.take(10)) {
    stdout.writeln(
      ' ${(s.wr * 100).toStringAsFixed(1)}% (${s.h}/${s.n})  ${s.c.labelZh}',
    );
  }

  stdout.writeln('\n=== SENSITIVITY: win if forward > X ===');
  for (final thr in [0.30, 0.20, 0.15, 0.10, 0.05]) {
    final w = settled.where((s) => s.forwardReturn! > thr).length;
    final rate = settled.isEmpty ? 0.0 : w / settled.length;
    stdout.writeln(
      ' >${(thr * 100).toStringAsFixed(0)}%: ${(rate * 100).toStringAsFixed(1)}% ($w/${settled.length})',
    );
  }

  // 写出挖到的规则，并缓存样本便于二次挖掘
  final sampleDump = settled
      .map((s) => {
            'code': s.code,
            'quarterEnd': s.quarterEnd,
            'pointDate': s.pointDate.toIso8601String(),
            'net': s.net,
            'prevNet': s.prevNet,
            'qoqMultiple': s.qoqMultiple,
            'persist4': s.persist4,
            'followOnRisk': s.followOnRisk,
            'forwardReturn': s.forwardReturn,
            'isWin': s.isWin,
            'settled': s.settled,
            'mom20': s.mom20,
            'mom60': s.mom60,
            'pricePercentile': s.pricePercentile,
            'netIntensity': s.netIntensity,
            'burstVsPrior4': s.burstVsPrior4,
          })
      .toList();
  await File('$hiveDir/settled_samples.json').writeAsString(
    jsonEncode(sampleDump),
  );

  final outFile = File('$hiveDir/mined_rule_pack.json');
  await outFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(pack.toJson()),
  );
  stdout.writeln('\nwrote ${outFile.path}');
  stdout.writeln('wrote $hiveDir/settled_samples.json (${settled.length})');

  client.close();
  await shareBox.close();
}
