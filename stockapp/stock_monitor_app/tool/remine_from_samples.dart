import 'dart:convert';
import 'dart:io';

import 'package:stock_monitor_app/core/engine/etf_add_feature_miner.dart';
import 'package:stock_monitor_app/core/models/etf_models.dart';

/// 从 settled_samples.json 二次挖掘（无需再拉行情）。
Future<void> main(List<String> args) async {
  final path = args.isNotEmpty
      ? args[0]
      : 'tmp_device_hive/settled_samples.json';
  final raw = jsonDecode(await File(path).readAsString()) as List<dynamic>;
  final settled = raw.map((e) {
    final m = Map<String, dynamic>.from(e as Map);
    final fwd = (m['forwardReturn'] as num?)?.toDouble();
    final isWin = fwd != null && fwd > EtfAddSampleBuilder.winReturnMin;
    return EtfAddSample(
      code: m['code'] as String? ?? '',
      quarterEnd: m['quarterEnd'] as String? ?? '',
      pointDate: DateTime.tryParse(m['pointDate'] as String? ?? '') ??
          DateTime(2000),
      net: (m['net'] as num?)?.toDouble() ?? 0,
      prevNet: (m['prevNet'] as num?)?.toDouble() ?? 0,
      qoqMultiple: (m['qoqMultiple'] as num?)?.toDouble() ?? 0,
      persist4: (m['persist4'] as num?)?.toDouble() ?? 0.5,
      followOnRisk: m['followOnRisk'] as bool? ?? false,
      forwardReturn: fwd,
      isWin: isWin,
      settled: true,
      mom20: (m['mom20'] as num?)?.toDouble(),
      mom60: (m['mom60'] as num?)?.toDouble(),
      pricePercentile: (m['pricePercentile'] as num?)?.toDouble(),
      netIntensity: (m['netIntensity'] as num?)?.toDouble(),
      burstVsPrior4: (m['burstVsPrior4'] as num?)?.toDouble(),
    );
  }).toList();

  stdout.writeln('loaded ${settled.length} settled, '
      'wins=${settled.where((s) => s.isWin!).length}');

  final pack = EtfAddFeatureMiner.mine(settled);
  stdout.writeln('validated=${pack.validated} '
      'wr=${((pack.winRate ?? 0) * 100).toStringAsFixed(2)}% '
      '(${pack.winHits}/${pack.winSamples})');
  for (final line in pack.ruleLinesZh) {
    stdout.writeln(' - $line');
  }
  await File('tmp_device_hive/mined_rule_pack.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(pack.toJson()),
  );
}
