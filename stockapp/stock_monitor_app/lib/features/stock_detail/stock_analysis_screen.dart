import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/server_providers.dart';
import '../../core/settings/app_strings.dart';

/// 完整投研报告页（自选 / 详情入口）。
class StockAnalysisScreen extends ConsumerWidget {
  const StockAnalysisScreen({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.tabAnalysis),
        actions: [
          IconButton(
            tooltip: strings.analysisRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(stockAnalysisProvider(code).notifier).reload(),
          ),
          IconButton(
            tooltip: strings.isZh ? '详情' : 'Detail',
            icon: const Icon(Icons.info_outline),
            onPressed: () => context.push('/watchlist/stock/$code'),
          ),
        ],
      ),
      body: StockAnalysisBody(code: code),
    );
  }
}

/// 可嵌入 Tab 的投研正文：决策仪表盘优先。
class StockAnalysisBody extends ConsumerWidget {
  const StockAnalysisBody({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final conn = ref.watch(serverConnectionProvider);
    final async = ref.watch(stockAnalysisProvider(code));

    if (!conn.connected) {
      return _EmptyHint(
        icon: Icons.cloud_off_outlined,
        text: strings.analysisNeedServer,
      );
    }

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 8),
              Text('$e', textAlign: TextAlign.center),
              IconButton.filled(
                onPressed: () =>
                    ref.read(stockAnalysisProvider(code).notifier).reload(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
      ),
      data: (report) {
        if (report == null) {
          return _EmptyHint(
            icon: Icons.cloud_off_outlined,
            text: strings.analysisNeedServer,
          );
        }
        final dash =
            (report['dashboard'] as Map?)?.cast<String, dynamic>() ?? {};
        return RefreshIndicator(
          onRefresh: () =>
              ref.read(stockAnalysisProvider(code).notifier).reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _TitleRow(report: report),
              const SizedBox(height: 12),
              _DecisionLights(dashboard: dash),
              const SizedBox(height: 10),
              if (dash['trend_badge'] != null)
                _BadgeBar(text: '${dash['trend_badge']}'),
              const SizedBox(height: 12),
              _TrendPanel(report: report, dashboard: dash),
              const SizedBox(height: 12),
              _ValuationPanel(dashboard: dash, report: report),
              const SizedBox(height: 12),
              _ProspectPanel(dashboard: dash, report: report),
              const SizedBox(height: 12),
              _ResearchPanel(dashboard: dash, report: report),
              const SizedBox(height: 12),
              _CatalystRiskRow(report: report),
              const SizedBox(height: 12),
              _NarrativeFold(report: report),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.gavel_outlined,
                      size: 14, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      strings.analysisDisclaimer,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------- helpers ----------

Color _signalColor(BuildContext context, String? signal) {
  switch (signal) {
    case 'up':
      return Colors.red.shade600; // A股习惯：涨红
    case 'down':
      return Colors.green.shade700;
    case 'flat':
      return Colors.orange.shade800;
    default:
      return Theme.of(context).colorScheme.outline;
  }
}

IconData _signalIcon(String? signal) {
  switch (signal) {
    case 'up':
      return Icons.arrow_upward_rounded;
    case 'down':
      return Icons.arrow_downward_rounded;
    case 'flat':
      return Icons.trending_flat;
    default:
      return Icons.help_outline;
  }
}

IconData _lightIcon(String? key) {
  switch (key) {
    case 'revenue':
      return Icons.apartment;
    case 'profit':
      return Icons.payments_outlined;
    case 'margin':
      return Icons.percent;
    case 'valuation':
      return Icons.sell_outlined;
    case 'research':
      return Icons.groups_outlined;
    default:
      return Icons.insights_outlined;
  }
}

String _n(dynamic v, [int d = 2]) {
  if (v is! num) return '—';
  return v.toStringAsFixed(d);
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.report});
  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final quote = (report['quote'] as Map?)?.cast<String, dynamic>() ?? {};
    final chg = quote['change_pct'] is num ? quote['change_pct'] as num : null;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${report['name'] ?? ''}',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                '${report['code'] ?? ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _n(quote['price']),
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  chg == null
                      ? Icons.trending_flat
                      : (chg >= 0
                          ? Icons.arrow_drop_up
                          : Icons.arrow_drop_down),
                  color: _signalColor(
                    context,
                    chg == null ? null : (chg >= 0 ? 'up' : 'down'),
                  ),
                ),
                Text(
                  chg == null
                      ? '—'
                      : '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: _signalColor(
                      context,
                      chg == null ? null : (chg >= 0 ? 'up' : 'down'),
                    ),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _DecisionLights extends StatelessWidget {
  const _DecisionLights({required this.dashboard});
  final Map<String, dynamic> dashboard;

  @override
  Widget build(BuildContext context) {
    final lights = (dashboard['lights'] as List?) ?? const [];
    if (lights.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dashboard_customize_outlined,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text('一眼决策', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (dashboard['action'] != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${dashboard['action']}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final raw in lights)
                  Expanded(
                    child: _LightCell(
                      light: (raw as Map).cast<String, dynamic>(),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LightCell extends StatelessWidget {
  const _LightCell({required this.light});
  final Map<String, dynamic> light;

  @override
  Widget build(BuildContext context) {
    final signal = '${light['signal'] ?? 'unknown'}';
    final color = _signalColor(context, signal);
    return Column(
      children: [
        Icon(_lightIcon('${light['key']}'),
            size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 4),
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Icon(_signalIcon(signal), color: color, size: 20),
        ),
        const SizedBox(height: 4),
        Text(
          '${light['label'] ?? '—'}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          '${light['name'] ?? ''}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _BadgeBar extends StatelessWidget {
  const _BadgeBar({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.report, required this.dashboard});
  final Map<String, dynamic> report;
  final Map<String, dynamic> dashboard;

  @override
  Widget build(BuildContext context) {
    final charts = (report['charts'] as Map?)?.cast<String, dynamic>() ?? {};
    final years = (charts['annual_years'] as List?) ?? const [];
    if (years.isEmpty) return const SizedBox.shrink();

    final lights = (dashboard['lights'] as List?) ?? const [];
    Map<String, dynamic> lightOf(String key) {
      for (final raw in lights) {
        final m = (raw as Map).cast<String, dynamic>();
        if (m['key'] == key) return m;
      }
      return {};
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SecTitle(Icons.show_chart, '增长趋势'),
            const SizedBox(height: 8),
            _MiniTrendChart(
              title: '营收',
              light: lightOf('revenue'),
              years: years,
              values: (charts['annual_revenue_yi'] as List?) ?? const [],
              yoys: (charts['annual_revenue_yoy'] as List?) ?? const [],
              color: const Color(0xFF3A6EA5),
            ),
            const SizedBox(height: 14),
            _MiniTrendChart(
              title: '利润',
              light: lightOf('profit'),
              years: years,
              values: (charts['annual_profit_yi'] as List?) ?? const [],
              yoys: (charts['annual_profit_yoy'] as List?) ?? const [],
              color: const Color(0xFF1B7F4A),
            ),
            const SizedBox(height: 14),
            _MarginTrendChart(
              light: lightOf('margin'),
              years: years,
              gross: (charts['annual_gross_margin'] as List?) ?? const [],
              net: (charts['annual_net_margin'] as List?) ?? const [],
            ),
          ],
        ),
      ),
    );
  }
}

class _SecTitle extends StatelessWidget {
  const _SecTitle(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

class _MiniTrendChart extends StatelessWidget {
  const _MiniTrendChart({
    required this.title,
    required this.light,
    required this.years,
    required this.values,
    required this.yoys,
    required this.color,
  });

  final String title;
  final Map<String, dynamic> light;
  final List years;
  final List values;
  final List yoys;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < years.length; i++) {
      final v = (i < values.length && values[i] is num)
          ? (values[i] as num).toDouble()
          : 0.0;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: v,
              color: color,
              width: 10,
              borderRadius: BorderRadius.circular(3),
            ),
          ],
        ),
      );
    }
    final signal = '${light['signal'] ?? ''}';
    final sigColor = _signalColor(context, signal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Icon(_signalIcon(signal), size: 16, color: sigColor),
            Text(
              '${light['label'] ?? ''}',
              style: TextStyle(
                color: sigColor,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            if (light['detail'] != null)
              Text(
                '${light['detail']}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 110,
          child: BarChart(
            BarChartData(
              barGroups: groups,
              gridData: const FlGridData(drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, _) => Text(
                      v.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= years.length) {
                        return const SizedBox.shrink();
                      }
                      return Text('${years[i]}',
                          style: const TextStyle(fontSize: 9));
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MarginTrendChart extends StatelessWidget {
  const _MarginTrendChart({
    required this.light,
    required this.years,
    required this.gross,
    required this.net,
  });

  final Map<String, dynamic> light;
  final List years;
  final List gross;
  final List net;

  @override
  Widget build(BuildContext context) {
    final gSpots = <FlSpot>[];
    final nSpots = <FlSpot>[];
    for (var i = 0; i < years.length; i++) {
      if (i < gross.length && gross[i] is num) {
        gSpots.add(FlSpot(i.toDouble(), (gross[i] as num).toDouble()));
      }
      if (i < net.length && net[i] is num) {
        nSpots.add(FlSpot(i.toDouble(), (net[i] as num).toDouble()));
      }
    }
    final signal = '${light['signal'] ?? ''}';
    final sigColor = _signalColor(context, signal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('毛利率', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Icon(_signalIcon(signal), size: 16, color: sigColor),
            Text(
              '${light['label'] ?? ''}',
              style: TextStyle(
                color: sigColor,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFB42318),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            const Text('毛利', style: TextStyle(fontSize: 10)),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF6B4FBB),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            const Text('净利', style: TextStyle(fontSize: 10)),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 110,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, _) => Text(
                      v.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= years.length) {
                        return const SizedBox.shrink();
                      }
                      return Text('${years[i]}',
                          style: const TextStyle(fontSize: 9));
                    },
                  ),
                ),
              ),
              lineBarsData: [
                if (gSpots.isNotEmpty)
                  LineChartBarData(
                    spots: gSpots,
                    color: const Color(0xFFB42318),
                    barWidth: 2.5,
                    dotData: const FlDotData(show: true),
                  ),
                if (nSpots.isNotEmpty)
                  LineChartBarData(
                    spots: nSpots,
                    color: const Color(0xFF6B4FBB),
                    barWidth: 2.5,
                    dotData: const FlDotData(show: true),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ValuationPanel extends StatelessWidget {
  const _ValuationPanel({required this.dashboard, required this.report});
  final Map<String, dynamic> dashboard;
  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final val =
        (dashboard['valuation'] as Map?)?.cast<String, dynamic>() ?? {};
    if (val.isEmpty) return const SizedBox.shrink();
    final state = '${val['state'] ?? 'fair'}';
    final signal = state == 'cheap'
        ? 'up'
        : (state == 'expensive' ? 'down' : 'flat');
    final color = _signalColor(context, signal);
    final price = val['price'] is num ? (val['price'] as num).toDouble() : null;
    final tMin =
        val['target_min'] is num ? (val['target_min'] as num).toDouble() : null;
    final tMid = val['target_median'] is num
        ? (val['target_median'] as num).toDouble()
        : null;
    final tMax =
        val['target_max'] is num ? (val['target_max'] as num).toDouble() : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SecTitle(Icons.sell_outlined, '是否低估'),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    children: [
                      Icon(_signalIcon(signal), color: color),
                      const SizedBox(width: 6),
                      Text(
                        '${val['label'] ?? '—'}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PE ${_n(val['pe_ttm'], 1)}x · PB ${_n(val['pb_mrq'], 2)}x'),
                      if (val['upside'] != null)
                        Text(
                          '目标价空间 ${((val['upside'] as num) * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if ((val['reasons'] as List?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in (val['reasons'] as List).take(4))
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('$r', style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ],
            if (tMid != null && price != null) ...[
              const SizedBox(height: 12),
              Text('目标价带', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              _TargetBand(
                price: price,
                low: tMin ?? tMid * 0.9,
                mid: tMid,
                high: tMax ?? tMid * 1.1,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TargetBand extends StatelessWidget {
  const _TargetBand({
    required this.price,
    required this.low,
    required this.mid,
    required this.high,
  });

  final double price;
  final double low;
  final double mid;
  final double high;

  @override
  Widget build(BuildContext context) {
    final minV = [price, low, mid, high].reduce((a, b) => a < b ? a : b) * 0.95;
    final maxV = [price, low, mid, high].reduce((a, b) => a > b ? a : b) * 1.05;
    double pos(double v) => ((v - minV) / (maxV - minV)).clamp(0.0, 1.0);

    return Column(
      children: [
        SizedBox(
          height: 28,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  Positioned(
                    left: w * pos(low),
                    width: (w * (pos(high) - pos(low))).clamp(4, w),
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  Positioned(
                    left: w * pos(mid) - 5,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Positioned(
                    left: w * pos(price) - 7,
                    child: Icon(
                      Icons.place,
                      size: 18,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Row(
          children: [
            Text('低 ${_n(low)}', style: Theme.of(context).textTheme.labelSmall),
            const Spacer(),
            Text('中 ${_n(mid)}', style: Theme.of(context).textTheme.labelSmall),
            const Spacer(),
            Text('高 ${_n(high)}', style: Theme.of(context).textTheme.labelSmall),
            const Spacer(),
            Text('现 ${_n(price)}',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
      ],
    );
  }
}

class _ProspectPanel extends StatelessWidget {
  const _ProspectPanel({required this.dashboard, required this.report});
  final Map<String, dynamic> dashboard;
  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final outlook =
        (dashboard['outlook'] as Map?)?.cast<String, dynamic>() ?? {};
    final tags = (dashboard['prospect_tags'] as List?) ?? const [];
    final engines = (dashboard['engines'] as List?) ?? const [];
    final shrinking = (dashboard['shrinking'] as List?) ?? const [];
    final biz = (report['business'] as Map?)?.cast<String, dynamic>() ?? {};
    final products = (biz['by_product'] as List?) ?? const [];
    final signal = '${outlook['signal'] ?? 'flat'}';
    final color = _signalColor(context, signal);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SecTitle(Icons.rocket_launch_outlined, '主业与前景'),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(_signalIcon(signal), color: color, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${outlook['label'] ?? '—'}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: color,
                        ),
                      ),
                      if (outlook['note'] != null)
                        Text(
                          '${outlook['note']}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in tags)
                    Chip(
                      avatar: const Icon(Icons.local_offer_outlined, size: 16),
                      label: Text('$t'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            if (engines.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('增长引擎', style: Theme.of(context).textTheme.labelLarge),
              ...engines.map((raw) {
                final e = (raw as Map).cast<String, dynamic>();
                final yoy = e['yoy'] is num ? (e['yoy'] as num) * 100 : null;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.bolt, color: Colors.red.shade600),
                  title: Text('${e['name']}'),
                  trailing: Text(
                    yoy == null ? '—' : '${yoy >= 0 ? '+' : ''}${yoy.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.red.shade600,
                    ),
                  ),
                );
              }),
            ],
            if (shrinking.isNotEmpty) ...[
              Text('收缩业务', style: Theme.of(context).textTheme.labelLarge),
              ...shrinking.map((raw) {
                final e = (raw as Map).cast<String, dynamic>();
                final yoy = e['yoy'] is num ? (e['yoy'] as num) * 100 : null;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.trending_down, color: Colors.green.shade700),
                  title: Text('${e['name']}'),
                  trailing: Text(
                    yoy == null ? '—' : '${yoy.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.green.shade700,
                    ),
                  ),
                );
              }),
            ],
            if (products.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...products.take(4).map((raw) {
                final p = (raw as Map).cast<String, dynamic>();
                final ratio =
                    p['ratio'] is num ? (p['ratio'] as num).toDouble() : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p['name']}  ${(ratio * 100).toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ratio.clamp(0, 1),
                          minHeight: 5,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResearchPanel extends StatelessWidget {
  const _ResearchPanel({required this.dashboard, required this.report});
  final Map<String, dynamic> dashboard;
  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final cons =
        (dashboard['consensus'] as Map?)?.cast<String, dynamic>() ?? {};
    final research =
        (report['research'] as Map?)?.cast<String, dynamic>() ?? {};
    final reports = (research['reports'] as List?) ?? const [];
    final dist = (research['rating_dist'] as Map?)?.cast<String, dynamic>() ??
        {};
    final epsThis = cons['eps_this'];
    final epsNext = cons['eps_next'];
    final growth = cons['eps_growth'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SecTitle(Icons.menu_book_outlined, '研报预期'),
            const SizedBox(height: 10),
            Row(
              children: [
                _EpsBox('今年EPS', epsThis),
                const SizedBox(width: 8),
                Icon(
                  growth is num
                      ? (growth >= 0
                          ? Icons.arrow_forward
                          : Icons.arrow_downward)
                      : Icons.remove,
                  color: growth is num
                      ? _signalColor(context, growth >= 0 ? 'up' : 'down')
                      : null,
                ),
                const SizedBox(width: 8),
                _EpsBox('明年EPS', epsNext),
                const SizedBox(width: 8),
                if (growth is num)
                  Text(
                    '${growth >= 0 ? '+' : ''}${(growth * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: _signalColor(
                        context,
                        growth >= 0 ? 'up' : 'down',
                      ),
                    ),
                  ),
              ],
            ),
            if (dist.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 80,
                child: BarChart(
                  BarChartData(
                    barGroups: [
                      for (var i = 0; i < dist.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: (dist.values.elementAt(i) as num)
                                  .toDouble(),
                              width: 16,
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        ),
                    ],
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i < 0 || i >= dist.length) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              dist.keys.elementAt(i).toString(),
                              style: const TextStyle(fontSize: 10),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (reports.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...reports.take(3).map((raw) {
                final r = (raw as Map).cast<String, dynamic>();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.article_outlined, size: 18),
                  title: Text(
                    '${r['title'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  subtitle: Text(
                    '${r['org'] ?? ''} · ${r['publish_date'] ?? ''} · ${r['rating'] ?? ''}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                );
              }),
            ],
            if (cons['org_count'] == 0 && reports.isEmpty)
              Text(
                '近一年机构覆盖较少',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _EpsBox extends StatelessWidget {
  const _EpsBox(this.label, this.value);
  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            Text(
              _n(value, 3),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalystRiskRow extends StatelessWidget {
  const _CatalystRiskRow({required this.report});
  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final cats = (report['catalysts'] as List?) ?? const [];
    final risks = (report['risks'] as List?) ?? const [];
    if (cats.isEmpty && risks.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.bolt, color: Colors.red.shade600, size: 20),
                  const SizedBox(height: 6),
                  for (final x in cats.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('$x',
                          style: Theme.of(context).textTheme.labelSmall),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange.shade800, size: 20),
                  const SizedBox(height: 6),
                  for (final x in risks.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('$x',
                          style: Theme.of(context).textTheme.labelSmall),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NarrativeFold extends StatelessWidget {
  const _NarrativeFold({required this.report});
  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final sections = (report['sections'] as List?) ?? const [];
    if (sections.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('详细解读'),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            for (final raw in sections)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${(raw as Map)['body'] ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
