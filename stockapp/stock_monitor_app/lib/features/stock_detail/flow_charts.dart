import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/models/capital_flow_day.dart';
import '../../core/models/capital_flow_point.dart';
import '../../core/settings/app_strings.dart';

/// 历史日资金流：主力 + 散户两条曲线。
class HistoricalFlowChart extends StatelessWidget {
  const HistoricalFlowChart({
    super.key,
    required this.flows,
    required this.strings,
    this.maxDays = 60,
  });

  final List<CapitalFlowDay> flows;
  final AppStrings strings;
  final int maxDays;

  @override
  Widget build(BuildContext context) {
    if (flows.length < 2) {
      return _EmptyChart(message: strings.chartNotEnough);
    }
    final recent = flows.length > maxDays
        ? flows.sublist(flows.length - maxDays)
        : flows;
    return _DualFlowLineChart(
      labels: recent.map((d) => _shortDate(d.tradeDate)).toList(),
      mainValues: recent.map((d) => d.mainNetInflow).toList(),
      retailValues: recent.map((d) => d.smallNetInflow).toList(),
      mainLegend: strings.mainNetInflow,
      retailLegend: strings.retailNetInflow,
      strings: strings,
    );
  }

  String _shortDate(String d) {
    if (d.length >= 10) return d.substring(5);
    return d;
  }
}

/// 当日分时累计资金流：主力 + 散户两条曲线。
class IntradayFlowChart extends StatelessWidget {
  const IntradayFlowChart({
    super.key,
    required this.points,
    required this.strings,
  });

  final List<CapitalFlowPoint> points;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return _EmptyChart(message: strings.intradayChartEmpty);
    }
    return _DualFlowLineChart(
      labels: points.map((p) => p.timeLabel).toList(),
      mainValues: points.map((p) => p.mainNetInflow).toList(),
      retailValues: points.map((p) => p.retailNetInflow).toList(),
      mainLegend: strings.mainNetInflow,
      retailLegend: strings.retailNetInflow,
      strings: strings,
      showSparseBottomLabels: true,
    );
  }
}

class _DualFlowLineChart extends StatelessWidget {
  const _DualFlowLineChart({
    required this.labels,
    required this.mainValues,
    required this.retailValues,
    required this.mainLegend,
    required this.retailLegend,
    required this.strings,
    this.showSparseBottomLabels = false,
  });

  final List<String> labels;
  final List<double> mainValues;
  final List<double> retailValues;
  final String mainLegend;
  final String retailLegend;
  final AppStrings strings;
  final bool showSparseBottomLabels;

  @override
  Widget build(BuildContext context) {
    final all = [...mainValues, ...retailValues];
    var minY = all.reduce((a, b) => a < b ? a : b) / 1e8;
    var maxY = all.reduce((a, b) => a > b ? a : b) / 1e8;
    if (minY == maxY) {
      minY -= 0.5;
      maxY += 0.5;
    } else {
      final pad = (maxY - minY) * 0.1;
      minY -= pad;
      maxY += pad;
    }

    final mainSpots = <FlSpot>[];
    final retailSpots = <FlSpot>[];
    for (var i = 0; i < mainValues.length; i++) {
      mainSpots.add(FlSpot(i.toDouble(), mainValues[i] / 1e8));
      retailSpots.add(FlSpot(i.toDouble(), retailValues[i] / 1e8));
    }

    final mainColor = Theme.of(context).colorScheme.primary;
    final retailColor = Colors.orange.shade700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChartLegend(
          items: [
            _LegendItem(color: mainColor, label: mainLegend),
            _LegendItem(color: retailColor, label: retailLegend),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (v, _) => Text(
                      v.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: showSparseBottomLabels
                        ? (labels.length / 5).clamp(1, 30).toDouble()
                        : (labels.length / 8).clamp(1, 20).toDouble(),
                    getTitlesWidget: (v, meta) {
                      final i = v.round();
                      if (i < 0 || i >= labels.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          labels[i],
                          style: const TextStyle(fontSize: 9),
                        ),
                      );
                    },
                  ),
                ),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) {
                    return spots.map((s) {
                      final i = s.x.round();
                      if (i < 0 || i >= labels.length) return null;
                      final label = s.barIndex == 0 ? mainLegend : retailLegend;
                      return LineTooltipItem(
                        '$label\n${labels[i]}\n${strings.formatMoney(s.y * 1e8)}',
                        const TextStyle(fontSize: 11, color: Colors.white),
                      );
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: mainSpots,
                  isCurved: true,
                  color: mainColor,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: retailSpots,
                  isCurved: true,
                  color: retailColor,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            strings.chartUnitYi,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.items});

  final List<_LegendItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      children: items
          .map(
            (e) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: e.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(e.label, style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          )
          .toList(),
    );
  }
}

class _LegendItem {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Center(
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}
