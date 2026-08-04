import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/capital_flow_day.dart';
import '../../core/models/capital_flow_point.dart';
import '../../core/models/institutional_hold_change_record.dart';
import '../../core/models/position_signal_record.dart';
import '../../core/models/recommendation.dart';
import '../../core/models/stock_bar.dart';
import '../../core/models/today_flow_display.dart';
import '../../core/position/position_signal_analyzer.dart';
import '../../core/providers/investment_providers.dart';
import '../../core/providers/stock_providers.dart';
import '../../core/settings/app_strings.dart';
import '../../core/settings/app_theme.dart';
import '../../core/storage/flow_cache_storage.dart';
import '../../core/storage/position_signal_storage.dart';
import '../../core/api/watchlist_repository.dart';
import 'flow_charts.dart';
import 'stock_analysis_screen.dart';

class StockDetailScreen extends ConsumerStatefulWidget {
  const StockDetailScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends ConsumerState<StockDetailScreen>
    with SingleTickerProviderStateMixin {
  List<CapitalFlowDay> _flows = [];
  List<CapitalFlowPoint> _intraday = [];
  List<PositionSignalRecord> _signals = [];
  String _name = '';
  bool _loading = true;
  bool _inWatchlist = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stock = await WatchlistRepository.getByCodeWidget(ref, widget.code);
      _inWatchlist = stock != null;
      _name = stock?.name ?? widget.code;
    } catch (_) {
      _inWatchlist = false;
      _name = widget.code;
    }

    try {
      final profile = await ref.read(stockProfileProvider(widget.code).future);
      _name = profile.name;
    } catch (_) {}

    final engine = ref.read(positionSignalEngineProvider);
    try {
      await engine.refreshStockFlows(widget.code);
    } catch (_) {}

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

  Future<void> _toggleWatchlist() async {
    final strings = ref.read(appStringsProvider);
    try {
      if (_inWatchlist) {
        await WatchlistRepository.delete(ref, widget.code);
        setState(() => _inWatchlist = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.removeFromWatchlist)),
          );
        }
      } else {
        final market = widget.code.startsWith('6') ? 'SH' : 'SZ';
        await WatchlistRepository.save(
          ref,
          code: widget.code,
          name: _name,
          market: market,
        );
        setState(() => _inWatchlist = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.addedToWatchlist)),
          );
        }
      }
      ref.invalidate(watchlistPayloadProvider);
      ref.invalidate(watchlistProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  TodayFlowDisplay? get _todayDisplay =>
      TodayFlowDisplay.from(_intraday, _flows);

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final profileAsync = ref.watch(stockProfileProvider(widget.code));
    final newsAsync = ref.watch(stockNewsProvider(widget.code));
    final recsAsync = ref.watch(todayRecommendationsProvider);

    RecommendationItem? recItem;
    recsAsync.whenData((data) {
      for (final item in data.items) {
        if (item.code == widget.code) {
          recItem = item;
          break;
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_name),
            Text(widget.code, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            tooltip: strings.tabAnalysis,
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () {
              if (_tabController.index != 4) {
                _tabController.animateTo(4);
              }
            },
          ),
          IconButton(
            icon: Icon(_inWatchlist ? Icons.star : Icons.star_outline),
            tooltip: _inWatchlist
                ? strings.removeFromWatchlist
                : strings.addToWatchlist,
            onPressed: _toggleWatchlist,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: strings.tabOverview),
            Tab(text: strings.tabFundamentals),
            Tab(text: strings.tabTechnical),
            Tab(text: strings.tabNews),
            Tab(text: strings.tabAnalysis),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _OverviewTab(
                  display: _todayDisplay,
                  profileAsync: profileAsync,
                  recItem: recItem,
                  latestSignal:
                      _signals.isNotEmpty ? _signals.first : null,
                  strings: strings,
                  onRefresh: _load,
                ),
                _FundamentalsTab(
                  code: widget.code,
                  profileAsync: profileAsync,
                  recItem: recItem,
                  strings: strings,
                  onRefresh: () async {
                    ref.invalidate(stockProfileProvider(widget.code));
                    ref.invalidate(institutionalHoldRecordsProvider(widget.code));
                    await Future.wait([
                      ref.read(stockProfileProvider(widget.code).future),
                      ref.read(institutionalHoldRecordsProvider(widget.code).future),
                    ]);
                  },
                ),
                _TechnicalTab(
                  code: widget.code,
                  flows: _flows,
                  intraday: _intraday,
                  signals: _signals,
                  strings: strings,
                  onRefresh: _load,
                ),
                _NewsTab(
                  code: widget.code,
                  newsAsync: newsAsync,
                  strings: strings,
                ),
                StockAnalysisBody(code: widget.code),
              ],
            ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.display,
    required this.profileAsync,
    required this.recItem,
    required this.latestSignal,
    required this.strings,
    required this.onRefresh,
  });

  final TodayFlowDisplay? display;
  final AsyncValue<StockProfile> profileAsync;
  final RecommendationItem? recItem;
  final PositionSignalRecord? latestSignal;
  final AppStrings strings;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (display != null)
            _SummaryCard(display: display!, strings: strings),
          const SizedBox(height: 12),
          profileAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => const SizedBox.shrink(),
            data: (profile) => _ProfileOverviewCard(
              profile: profile,
              recItem: recItem,
              strings: strings,
            ),
          ),
          if (latestSignal != null) ...[
            const SizedBox(height: 12),
            _LinkedSignalCard(signal: latestSignal!, strings: strings),
          ],
          if (recItem != null) ...[
            const SizedBox(height: 12),
            _RecommendationSummaryCard(item: recItem!, strings: strings),
          ],
        ],
      ),
    );
  }
}

class _ProfileOverviewCard extends StatelessWidget {
  const _ProfileOverviewCard({
    required this.profile,
    required this.recItem,
    required this.strings,
  });

  final StockProfile profile;
  final RecommendationItem? recItem;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final score = recItem?.compositeScore ?? profile.compositeScore;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(profile.industry,
                style: Theme.of(context).textTheme.labelLarge),
            if (profile.valuationLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              Chip(
                label: Text('${strings.valuationLabel}: ${profile.valuationLabel}'),
              ),
            ],
            if (score != null) ...[
              const SizedBox(height: 8),
              Text('${strings.compositeScore}: ${score.toStringAsFixed(1)}',
                  style: Theme.of(context).textTheme.titleLarge),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (profile.peTtm != null)
                  _MetricTile(label: 'PE', value: profile.peTtm!.toStringAsFixed(1)),
                if (profile.pb != null)
                  _MetricTile(label: 'PB', value: profile.pb!.toStringAsFixed(2)),
                if (profile.roe != null)
                  _MetricTile(label: 'ROE', value: '${profile.roe!.toStringAsFixed(1)}%'),
              ],
            ),
            if (profile.concepts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: profile.concepts
                    .take(4)
                    .map(
                      (c) => Chip(
                        label: Text(c, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinkedSignalCard extends StatelessWidget {
  const _LinkedSignalCard({required this.signal, required this.strings});

  final PositionSignalRecord signal;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: const Icon(Icons.link),
        title: Text(strings.linkedSignal),
        subtitle: Text(
          '${strings.signalTypeLabel(signal.signalType)} · '
          '${strings.confidence} ${signal.confidence.toStringAsFixed(0)}%',
        ),
      ),
    );
  }
}

class _RecommendationSummaryCard extends StatelessWidget {
  const _RecommendationSummaryCard({required this.item, required this.strings});

  final RecommendationItem item;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.recommendationScore,
                style: Theme.of(context).textTheme.titleSmall),
            Text('#${item.rank} · ${item.compositeScore.toStringAsFixed(1)}',
                style: Theme.of(context).textTheme.headlineSmall),
            ...item.reasons.take(3).map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $r', style: Theme.of(context).textTheme.bodySmall),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _FundamentalsTab extends ConsumerWidget {
  const _FundamentalsTab({
    required this.code,
    required this.profileAsync,
    required this.recItem,
    required this.strings,
    required this.onRefresh,
  });

  final String code;
  final AsyncValue<StockProfile> profileAsync;
  final RecommendationItem? recItem;
  final AppStrings strings;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdAsync = ref.watch(institutionalHoldRecordsProvider(code));

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (profile) => RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (profile.industry.isNotEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: Text(profile.industry),
                  subtitle: Text(strings.tabFundamentals),
                ),
              ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _FundRow(label: 'PE (TTM)', value: profile.peTtm?.toStringAsFixed(2)),
                    _FundRow(label: 'PB', value: profile.pb?.toStringAsFixed(2)),
                    _FundRow(
                      label: 'ROE',
                      value: profile.roe != null
                          ? '${profile.roe!.toStringAsFixed(1)}%'
                          : null,
                    ),
                    _FundRow(
                      label: strings.dividendYield,
                      value: profile.dividendYield != null
                          ? '${profile.dividendYield!.toStringAsFixed(2)}%'
                          : null,
                    ),
                    _FundRow(
                      label: strings.valuationLabel,
                      value: profile.valuationLabel.isNotEmpty
                          ? profile.valuationLabel
                          : null,
                    ),
                    if (profile.marketCap != null)
                      _FundRow(
                        label: '市值',
                        value: strings.formatMoney(profile.marketCap!),
                      ),
                  ],
                ),
              ),
            ),
            if (profile.concepts.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(strings.conceptsSection,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: profile.concepts
                        .map(
                          (c) => Chip(
                            label: Text(c),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
            if (profile.companySummary.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(strings.companyProfileSection,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    profile.companySummary,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(strings.institutionHoldRecords,
                style: Theme.of(context).textTheme.titleMedium),
            Text(
              strings.institutionHoldRecordsHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            holdAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('${strings.apiError}: $e'),
              data: (records) {
                if (records.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(strings.noData),
                    ),
                  );
                }
                return Column(
                  children: records
                      .map(
                        (r) => _InstitutionHoldRecordCard(
                          record: r,
                          strings: strings,
                        ),
                      )
                      .toList(),
                );
              },
            ),
            if (recItem != null) ...[
              const SizedBox(height: 16),
              Text(strings.recommendationScore,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _FundRow(
                        label: strings.scoreValuation,
                        value: recItem!.valuationScore.toStringAsFixed(0),
                      ),
                      _FundRow(
                        label: strings.scoreGrowth,
                        value: recItem!.growthScore.toStringAsFixed(0),
                      ),
                      _FundRow(
                        label: strings.scoreSpace,
                        value: recItem!.spaceScore.toStringAsFixed(0),
                      ),
                      _FundRow(
                        label: strings.scoreInstitution,
                        value: recItem!.institutionScore.toStringAsFixed(0),
                      ),
                      _FundRow(
                        label: strings.scoreMomentum,
                        value: recItem!.momentumScore.toStringAsFixed(0),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InstitutionHoldRecordCard extends StatelessWidget {
  const _InstitutionHoldRecordCard({
    required this.record,
    required this.strings,
  });

  final InstitutionalHoldChangeRecord record;
  final AppStrings strings;

  Color? _directionColor(BuildContext context) {
    if (record.direction.contains('增') || record.direction.contains('新')) {
      return Colors.red.shade700;
    }
    if (record.direction.contains('减')) {
      return Colors.green.shade700;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final color = _directionColor(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    record.holderName,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    record.direction,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _FundRow(
              label: strings.holdChangeDate,
              value: strings.orDash(record.displayDate),
            ),
            _FundRow(
              label: strings.holdChangeShares,
              value: record.changeShares == null
                  ? strings.emptyValue
                  : strings.formatShares(record.changeShares!),
            ),
            _FundRow(
              label: strings.holdChangeAmount,
              value: record.changeAmount == null
                  ? strings.emptyValue
                  : strings.formatMoney(record.changeAmount!),
            ),
            _FundRow(
              label: strings.holdChangePrice,
              value: record.tradePrice == null
                  ? strings.emptyValue
                  : '${record.tradePrice!.toStringAsFixed(2)}元',
            ),
            if (record.closePrice != null)
              _FundRow(
                label: '收盘价',
                value: '${record.closePrice!.toStringAsFixed(2)}元',
              ),
            if (record.changeRatio != null)
              _FundRow(
                label: '变动比例',
                value: '${record.changeRatio!.toStringAsFixed(2)}%',
              ),
            if (record.market.isNotEmpty || record.source.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [
                    if (record.source.isNotEmpty) record.source,
                    if (record.market.isNotEmpty) record.market,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FundRow extends StatelessWidget {
  const _FundRow({required this.label, this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _TechnicalTab extends ConsumerWidget {
  const _TechnicalTab({
    required this.code,
    required this.flows,
    required this.intraday,
    required this.signals,
    required this.strings,
    required this.onRefresh,
  });

  final String code;
  final List<CapitalFlowDay> flows;
  final List<CapitalFlowPoint> intraday;
  final List<PositionSignalRecord> signals;
  final AppStrings strings;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SignalAnalysisCard(
            code: code,
            flows: flows,
            latestSignal: signals.isNotEmpty ? signals.first : null,
            strings: strings,
          ),
          const SizedBox(height: 24),
          Text(strings.historyFlowChart,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: HistoricalFlowChart(flows: flows, strings: strings),
            ),
          ),
          const SizedBox(height: 24),
          Text(strings.intradayFlowChart,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: IntradayFlowChart(points: intraday, strings: strings),
            ),
          ),
          const SizedBox(height: 24),
          Text(strings.signalHistory,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (signals.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(strings.chartNotEnough),
            )
          else
            ...signals.map(
              (s) => _SignalHistoryTile(record: s, strings: strings),
            ),
        ],
      ),
    );
  }
}

class _NewsTab extends ConsumerWidget {
  const _NewsTab({
    required this.code,
    required this.newsAsync,
    required this.strings,
  });

  final String code;
  final AsyncValue<List<NewsArticleItem>> newsAsync;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return newsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (news) {
        if (news.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(stockNewsProvider(code));
              await ref.read(stockNewsProvider(code).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.4,
                  child: Center(child: Text(strings.noData)),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(stockNewsProvider(code));
            await ref.read(stockNewsProvider(code).future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: news.length,
            itemBuilder: (context, index) {
              final article = news[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                    article.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${article.source}${article.publishedAt != null ? ' · ${article.publishedAt}' : ''}',
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
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
            const SizedBox(height: 12),
            Text(strings.mainNetInflow),
            Text(strings.formatMoney(display.mainNetInflow),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: colorForNetInflow(context, display.mainNetInflow),
                      fontWeight: FontWeight.bold,
                    )),
            Text('${strings.mainNetRatio} ${display.mainNetRatio.toStringAsFixed(2)}%'),
            if (price != null) ...[
              const SizedBox(height: 8),
              Text(
                '${strings.latestPrice} ${price.toStringAsFixed(2)}'
                '${change != null ? ' · ${change.toStringAsFixed(2)}%' : ''}',
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
                if (isReversal || severity != null) ...[
                  const SizedBox(height: 8),
                  Text(strings.reversalBanner,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                if (suggestedAction != null) ...[
                  const SizedBox(height: 4),
                  Text('${strings.suggestedAction}: $suggestedAction'),
                ],
                if (triggered.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: triggered
                        .take(6)
                        .map((id) => Chip(
                              label: Text(strings.triggeredSignalLabel(id),
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 8),
                ...reasons.take(6).map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $r',
                            style: Theme.of(context).textTheme.bodySmall),
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

class _SignalHistoryTile extends StatelessWidget {
  const _SignalHistoryTile({required this.record, required this.strings});

  final PositionSignalRecord record;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          '${record.tradeDate} · ${strings.signalTypeLabel(record.signalType)}',
        ),
        subtitle: Text(record.analysisSummary, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
