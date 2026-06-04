import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/capital_flow_day.dart';
import '../../core/models/capital_flow_point.dart';
import '../../core/models/today_flow_display.dart';
import '../../core/settings/app_settings.dart';
import '../../core/models/prediction_direction.dart';
import '../../core/models/prediction_record.dart';
import '../../core/providers/stock_providers.dart';
import '../../core/prediction/prediction_analyzer.dart';
import '../../core/settings/app_strings.dart';
import '../../core/settings/app_theme.dart';
import '../../core/storage/flow_cache_storage.dart';
import '../../core/storage/prediction_storage.dart';
import '../../core/storage/watchlist_storage.dart';
import 'flow_charts.dart';

class StockDetailScreen extends ConsumerStatefulWidget {
  const StockDetailScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends ConsumerState<StockDetailScreen> {
  List<CapitalFlowDay> _flows = [];
  List<CapitalFlowPoint> _intraday = [];
  List<PredictionRecord> _predictions = [];
  String _name = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final stock = await WatchlistStorage.getByCode(widget.code);
    _name = stock?.name ?? widget.code;
    final engine = ref.read(predictionEngineProvider);
    await engine.refreshStockFlows(widget.code);
    final flows = await FlowCacheStorage.listForCode(widget.code);
    final preds = await PredictionStorage.listForCode(widget.code);
    List<CapitalFlowPoint> intraday = [];
    try {
      intraday =
          await ref.read(eastmoneyClientProvider).fetchIntradayFlow(widget.code);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _flows = flows;
        _intraday = intraday;
        _predictions = preds;
        _loading = false;
      });
    }
  }

  Future<void> _generateToday() async {
    if (_flows.isEmpty) return;
    final engine = ref.read(predictionEngineProvider);
    await engine.generatePredictionForCode(widget.code, _flows, force: true);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(appStringsProvider).generatePrediction)),
      );
    }
  }

  TodayFlowDisplay? get _todayDisplay =>
      TodayFlowDisplay.from(_intraday, _flows);

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_name),
            Text(
              widget.code,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_todayDisplay != null) ...[
                    _SummaryCard(
                      display: _todayDisplay!,
                      strings: strings,
                    ),
                    const SizedBox(height: 12),
                    _AnalysisCard(
                      flows: _flows,
                      latestPrediction:
                          _predictions.isNotEmpty ? _predictions.first : null,
                      strings: strings,
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: _generateToday,
                    icon: const Icon(Icons.auto_graph),
                    label: Text(strings.generatePrediction),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    strings.historyFlowChart,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: HistoricalFlowChart(
                        flows: _flows,
                        strings: strings,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    strings.intradayFlowChart,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: IntradayFlowChart(
                        points: _intraday,
                        strings: strings,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    strings.predictionHistory,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_predictions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        strings.pending,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  else
                    ..._predictions.map(
                      (p) => _PredictionTile(record: p, strings: strings),
                    ),
                ],
              ),
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.display, required this.strings});

  final TodayFlowDisplay display;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final price = display.closePrice;
    final change = display.changePercent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(display.tradeDate,
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              strings.intradaySnapshotHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            Text(strings.mainNetInflow),
            Text(
              strings.formatMoney(display.mainNetInflow),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: colorForNetInflow(context, display.mainNetInflow),
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              '${strings.mainNetRatio} ${display.mainNetRatio.toStringAsFixed(2)}%',
            ),
            const SizedBox(height: 12),
            Text(strings.retailNetInflow),
            Text(
              strings.formatMoney(display.retailNetInflow),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color:
                        colorForNetInflow(context, display.retailNetInflow),
                  ),
            ),
            if (price != null) ...[
              const SizedBox(height: 8),
              Text(
                '${strings.latestPrice} ${price.toStringAsFixed(2)}'
                '${change != null ? ' · ${change.toStringAsFixed(2)}%' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnalysisCard extends ConsumerWidget {
  const _AnalysisCard({
    required this.flows,
    required this.latestPrediction,
    required this.strings,
  });

  final List<CapitalFlowDay> flows;
  final PredictionRecord? latestPrediction;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final analysis = PredictionAnalyzer(thresholds: settings.thresholds)
        .analyze(flows);
    final direction = latestPrediction?.direction ?? analysis.direction;
    final confidence = latestPrediction?.confidenceScore ?? analysis.confidence;
    final reasons = latestPrediction?.analysisSummary != null
        ? latestPrediction!.analysisSummary!.split('；')
        : analysis.reasons;

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  strings.analysisSection,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Chip(
                  label: Text(strings.directionLabel(direction.key)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${strings.compositeScore} ${analysis.score.toStringAsFixed(1)} · '
              '${strings.confidence} ${(confidence * 100).toStringAsFixed(0)}%',
            ),
            const SizedBox(height: 8),
            _MetricRow(
              label: strings.priceChange6m,
              value: '${analysis.sixMonthPriceChangePercent.toStringAsFixed(1)}%',
            ),
            _MetricRow(
              label: strings.mainFlow20d,
              value: strings.formatMoney(analysis.recent20MainFlowSum),
            ),
            _MetricRow(
              label: strings.patternWinRate,
              value: '${analysis.historicalSamePatternRate.toStringAsFixed(0)}%',
            ),
            const SizedBox(height: 8),
            ...reasons.take(6).map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(child: Text(r, style: Theme.of(context).textTheme.bodySmall)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _PredictionTile extends StatelessWidget {
  const _PredictionTile({required this.record, required this.strings});

  final PredictionRecord record;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String status;
    if (!record.isVerified) {
      icon = Icons.schedule;
      color = Theme.of(context).colorScheme.outline;
      status = strings.pending;
    } else if (record.direction == PredictionDirection.neutral) {
      icon = Icons.remove_circle_outline;
      color = Theme.of(context).colorScheme.outline;
      status = strings.predictNeutral;
    } else if (record.isHit) {
      icon = Icons.check_circle;
      color = Colors.green;
      status = strings.hit;
    } else {
      icon = Icons.cancel;
      color = Theme.of(context).colorScheme.error;
      status = strings.miss;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text('${record.tradeDate} · ${strings.directionLabel(record.direction.key)}'),
        subtitle: Text(
          record.analysisSummary?.isNotEmpty == true
              ? record.analysisSummary!
              : record.isVerified && record.actualChangePercent != null
                  ? '$status · ${record.actualChangePercent!.toStringAsFixed(2)}%'
                  : '${strings.mainNetRatio} ${record.mainNetRatio.toStringAsFixed(2)}%',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
