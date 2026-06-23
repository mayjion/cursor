import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/capital_flow_day.dart';
import '../../core/models/capital_flow_point.dart';
import '../../core/models/position_signal_record.dart';
import '../../core/models/stock_bar.dart';
import '../../core/models/today_flow_display.dart';
import '../../core/position/position_signal_analyzer.dart';
import '../../core/providers/stock_providers.dart';
import '../../core/settings/app_strings.dart';
import '../../core/settings/app_theme.dart';
import '../../core/storage/flow_cache_storage.dart';
import '../../core/storage/position_signal_storage.dart';
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
  List<PositionSignalRecord> _signals = [];
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
    final engine = ref.read(positionSignalEngineProvider);
    await engine.refreshStockFlows(widget.code);
    final flows = await FlowCacheStorage.listForCode(widget.code);
    final signals = await PositionSignalStorage.listForCode(widget.code);
    List<CapitalFlowPoint> intraday = [];
    try {
      intraday =
          await ref.read(eastmoneyClientProvider).fetchIntradayFlow(widget.code);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _flows = flows;
        _intraday = intraday;
        _signals = signals;
        _loading = false;
      });
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
            Text(widget.code, style: Theme.of(context).textTheme.bodySmall),
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
                    _SummaryCard(display: _todayDisplay!, strings: strings),
                    const SizedBox(height: 12),
                    _SignalAnalysisCard(
                      code: widget.code,
                      flows: _flows,
                      latestSignal:
                          _signals.isNotEmpty ? _signals.first : null,
                      strings: strings,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(strings.historyFlowChart,
                      style: Theme.of(context).textTheme.titleMedium),
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
                  Text(strings.intradayFlowChart,
                      style: Theme.of(context).textTheme.titleMedium),
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
                  Text(strings.signalHistory,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_signals.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(strings.chartNotEnough),
                    )
                  else
                    ..._signals.map(
                      (s) => _SignalHistoryTile(record: s, strings: strings),
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
            Text(strings.intradaySnapshotHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
            const SizedBox(height: 12),
            Text(strings.mainNetInflow),
            Text(strings.formatMoney(display.mainNetInflow),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: colorForNetInflow(context, display.mainNetInflow),
                      fontWeight: FontWeight.bold,
                    )),
            Text('${strings.mainNetRatio} ${display.mainNetRatio.toStringAsFixed(2)}%'),
            const SizedBox(height: 12),
            Text(strings.retailNetInflow),
            Text(strings.formatMoney(display.retailNetInflow),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorForNetInflow(context, display.retailNetInflow),
                    )),
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

class _SignalAnalysisCard extends ConsumerWidget {
  const _SignalAnalysisCard({
    required this.code,
    required this.flows,
    required this.latestSignal,
    required this.strings,
  });

  final String code;
  final List<CapitalFlowDay> flows;
  final PositionSignalRecord? latestSignal;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weeklyAsync = ref.read(eastmoneyClientProvider);
    return FutureBuilder(
      future: weeklyAsync.fetchWeeklyBars(code, limit: 30),
      builder: (context, snapshot) {
        final weekly = snapshot.data ?? [];
        final previous = latestSignal;
        final analysis = const PositionSignalAnalyzer().analyze(
          dailyBars: barsFromCapitalFlowDays(flows),
          weeklyBars: weekly,
          previousTrendPhase: previous?.trendPhase,
          previousSeverity: previous?.reversalSeverity,
        );

        final signalType = latestSignal?.signalType ?? analysis.signalType;
        final confidence = latestSignal?.confidence ?? analysis.confidence;
        final trendPhase = latestSignal?.trendPhase ?? analysis.trendPhase;
        final severity = latestSignal?.reversalSeverity ?? analysis.reversalSeverity;
        final isReversal = latestSignal?.isReversal ?? analysis.isReversal;
        final triggered =
            latestSignal?.triggeredSignals ?? analysis.triggeredSignals;
        final suggestedAction =
            latestSignal?.suggestedAction ?? analysis.suggestedAction;
        final reasons = latestSignal?.analysisSummary != null
            ? latestSignal!.analysisSummary.split(' · ')
            : analysis.reasons;

        return Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isReversal || severity != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber,
                                color: Theme.of(context).colorScheme.error),
                            const SizedBox(width: 8),
                            Text(strings.reversalBanner,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                      fontWeight: FontWeight.bold,
                                    )),
                          ],
                        ),
                        if (severity != null) ...[
                          const SizedBox(height: 4),
                          Text(strings.severityLabel(severity)),
                        ],
                        if (suggestedAction != null) ...[
                          const SizedBox(height: 4),
                          Text('${strings.suggestedAction}: $suggestedAction'),
                        ],
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Text(strings.analysisSection,
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    Chip(label: Text(strings.signalTypeLabel(signalType))),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${strings.trendPhase}: ${strings.trendPhaseLabel(trendPhase)} · '
                  '${strings.confidence} ${confidence.toStringAsFixed(0)}%',
                ),
                const SizedBox(height: 8),
                _MetricRow(
                  label: strings.retracePercent,
                  value: '${(latestSignal?.retracePercent ?? analysis.retracePercent).toStringAsFixed(1)}%',
                ),
                if (analysis.ma20 != null)
                  _MetricRow(label: 'MA20', value: analysis.ma20!.toStringAsFixed(2)),
                if (analysis.ma30 != null)
                  _MetricRow(label: 'MA30', value: analysis.ma30!.toStringAsFixed(2)),
                if (analysis.ma60 != null)
                  _MetricRow(label: 'MA60', value: analysis.ma60!.toStringAsFixed(2)),
                if (analysis.rsi != null)
                  _MetricRow(label: 'RSI', value: analysis.rsi!.toStringAsFixed(1)),
                if (analysis.adx != null)
                  _MetricRow(label: 'ADX', value: analysis.adx!.toStringAsFixed(1)),
                if (analysis.macdDif != null)
                  _MetricRow(
                    label: 'MACD',
                    value:
                        '${analysis.macdDif!.toStringAsFixed(2)}/${analysis.macdDea?.toStringAsFixed(2) ?? '-'}',
                  ),
                if (analysis.volumeRatio != null)
                  _MetricRow(
                    label: strings.volumeRatio,
                    value: analysis.volumeRatio!.toStringAsFixed(2),
                  ),
                if (analysis.atrStopLoss != null)
                  _MetricRow(
                    label: strings.atrStopLoss,
                    value: analysis.atrStopLoss!.toStringAsFixed(2),
                  ),
                if (triggered.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(strings.resonanceSignals,
                      style: Theme.of(context).textTheme.labelLarge),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: triggered
                        .map((id) => Chip(
                              label: Text(strings.triggeredSignalLabel(id),
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 8),
                ...reasons.take(8).map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• '),
                            Expanded(
                                child: Text(r,
                                    style:
                                        Theme.of(context).textTheme.bodySmall)),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
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

class _SignalHistoryTile extends StatelessWidget {
  const _SignalHistoryTile({required this.record, required this.strings});

  final PositionSignalRecord record;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final isReversal = record.isReversal || record.reversalSeverity != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isReversal
          ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35)
          : null,
      child: ListTile(
        leading: Icon(
          isReversal ? Icons.warning_amber : Icons.insights_outlined,
          color: isReversal ? Theme.of(context).colorScheme.error : null,
        ),
        title: Text(
          '${record.tradeDate} · ${strings.signalTypeLabel(record.signalType)}',
        ),
        subtitle: Text(
          record.suggestedAction?.isNotEmpty == true
              ? record.suggestedAction!
              : record.analysisSummary,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
