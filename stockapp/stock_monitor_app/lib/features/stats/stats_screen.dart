import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/prediction_direction.dart';
import '../../core/models/prediction_record.dart';
import '../../core/prediction/prediction_engine.dart';
import '../../core/providers/stock_providers.dart';
import '../../core/settings/app_strings.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final statsAsync = ref.watch(predictionStatsProvider);
    final predsAsync = ref.watch(predictionListProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.statsTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(predictionEngineProvider).verifyPendingRecords();
          ref.invalidate(predictionStatsProvider);
          ref.invalidate(predictionListProvider);
        },
        child: statsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [Center(child: Text('$e'))],
          ),
          data: (stats) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _AccuracyHero(
                  accuracy: stats.accuracyPercent,
                  hits: stats.hits,
                  scored: stats.scoredPredictions,
                  strings: strings,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _StatChip(
                        label: strings.totalPredictions,
                        value: '${stats.totalPredictions}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatChip(
                        label: strings.hits,
                        value: '${stats.hits}',
                      ),
                    ),
                  ],
                ),
                if (stats.scoredPredictions > 0) ...[
                  const SizedBox(height: 24),
                  Text(
                    strings.perStock,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: _PerStockChart(byCode: stats.byCode),
                  ),
                  ...stats.byCode.entries.map((e) {
                    return ListTile(
                      title: Text(e.key),
                      trailing: Text(
                        '${e.value.accuracyPercent.toStringAsFixed(1)}% '
                        '(${e.value.hits}/${e.value.scored})',
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 24),
                predsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (preds) => _CalendarSection(
                    records: preds.take(60).toList(),
                    strings: strings,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AccuracyHero extends StatelessWidget {
  const _AccuracyHero({
    required this.accuracy,
    required this.hits,
    required this.scored,
    required this.strings,
  });

  final double accuracy;
  final int hits;
  final int scored;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(strings.accuracy, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              scored == 0 ? '—' : '${accuracy.toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
            ),
            if (scored > 0)
              Text(
                '$hits / $scored',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }
}

class _PerStockChart extends StatelessWidget {
  const _PerStockChart({required this.byCode});

  final Map<String, CodeStats> byCode;

  @override
  Widget build(BuildContext context) {
    if (byCode.isEmpty) {
      return const Center(child: Text('—'));
    }
    final entries = byCode.entries.toList();
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 100,
        barGroups: [
          for (var i = 0; i < entries.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: entries[i].value.accuracyPercent.clamp(0, 100),
                  color: Theme.of(context).colorScheme.primary,
                  width: 16,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            ),
        ],
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= entries.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    entries[i].key,
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, _) => Text('${v.toInt()}%'),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}

class _CalendarSection extends StatelessWidget {
  const _CalendarSection({required this.records, required this.strings});

  final List<PredictionRecord> records;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.predictionHistory,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ...records.map((r) {
          Color bg;
          if (!r.isVerified) {
            bg = Theme.of(context).colorScheme.surfaceContainerHighest;
          } else if (r.isHit) {
            bg = Colors.green.withValues(alpha: 0.15);
          } else if (r.direction == PredictionDirection.neutral) {
            bg = Theme.of(context).colorScheme.surfaceContainerHigh;
          } else {
            bg = Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4);
          }
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              dense: true,
              title: Text('${r.code} · ${r.tradeDate}'),
              subtitle: Text(strings.directionLabel(r.direction.key)),
              trailing: Text(
                !r.isVerified
                    ? strings.pending
                    : r.actualChangePercent != null
                        ? '${r.actualChangePercent!.toStringAsFixed(2)}%'
                        : strings.verifyUnavailable,
              ),
            ),
          );
        }),
      ],
    );
  }
}
