import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/position_signal.dart';
import '../../core/models/position_signal_record.dart';
import '../../core/providers/stock_providers.dart';
import '../../core/settings/app_strings.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final summaryAsync = ref.watch(positionSignalSummaryProvider);
    final signalsAsync = ref.watch(positionSignalListProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.statsTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(positionSignalSummaryProvider);
          ref.invalidate(positionSignalListProvider);
        },
        child: summaryAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [Center(child: Text('$e'))],
          ),
          data: (summary) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(strings.totalSignals,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('${summary.totalSignals}',
                            style: Theme.of(context)
                                .textTheme
                                .displayMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _StatChip(
                        label: strings.reversalCount,
                        value: '${summary.reversalCount}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatChip(
                        label: strings.recentChanges,
                        value: '${summary.recentChanges}',
                      ),
                    ),
                  ],
                ),
                if (summary.byType.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(strings.signalDistribution,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: _SignalDistributionChart(
                      byType: summary.byType,
                      strings: strings,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(strings.perStock,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                signalsAsync.when(
                  loading: () => const CircularProgressIndicator(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (signals) {
                    final latestByCode = <String, PositionSignalRecord>{};
                    for (final s in signals) {
                      latestByCode.putIfAbsent(s.code, () => s);
                    }
                    if (latestByCode.isEmpty) {
                      return Text(strings.chartNotEnough);
                    }
                    return Column(
                      children: latestByCode.values.map((s) {
                        final isReversal =
                            s.isReversal || s.reversalSeverity != null;
                        return Card(
                          color: isReversal
                              ? Theme.of(context)
                                  .colorScheme
                                  .errorContainer
                                  .withValues(alpha: 0.3)
                              : null,
                          child: ListTile(
                            title: Text(s.code),
                            subtitle: Text(
                              strings.signalTypeLabel(s.signalType),
                            ),
                            trailing: Text(
                              s.suggestedAction ?? s.tradeDate,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 24),
                signalsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (signals) => _SignalTimeline(
                    records: signals.take(60).toList(),
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

class _SignalDistributionChart extends StatelessWidget {
  const _SignalDistributionChart({
    required this.byType,
    required this.strings,
  });

  final Map<PositionSignalType, int> byType;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final entries = byType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return const Center(child: Text('—'));

    final maxY = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY.toDouble() * 1.2,
        barGroups: [
          for (var i = 0; i < entries.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: entries[i].value.toDouble(),
                  color: _colorForType(context, entries[i].key),
                  width: 16,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
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
                final label = strings.signalTypeLabel(entries[i].key);
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(label, style: const TextStyle(fontSize: 9)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) => Text(v.toInt().toString()),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Color _colorForType(BuildContext context, PositionSignalType type) {
    return switch (type) {
      PositionSignalType.add => Colors.green,
      PositionSignalType.reduce => Colors.orange,
      PositionSignalType.trendBreak => Colors.deepOrange,
      PositionSignalType.trendReversal => Theme.of(context).colorScheme.error,
      PositionSignalType.hold => Colors.grey,
      PositionSignalType.holdBaseOnly => Theme.of(context).colorScheme.primary,
    };
  }
}

class _SignalTimeline extends StatelessWidget {
  const _SignalTimeline({required this.records, required this.strings});

  final List<PositionSignalRecord> records;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.signalHistory,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...records.map((r) {
          final isReversal = r.isReversal || r.reversalSeverity != null;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: isReversal
                  ? Theme.of(context)
                      .colorScheme
                      .errorContainer
                      .withValues(alpha: 0.4)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              dense: true,
              title: Text('${r.code} · ${r.tradeDate}'),
              subtitle: Text(strings.signalTypeLabel(r.signalType)),
              trailing: Text(
                r.suggestedAction ?? '',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          );
        }),
      ],
    );
  }
}
