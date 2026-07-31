import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/recommendation.dart';
import '../../core/models/stock_snapshot.dart';
import '../../core/providers/investment_providers.dart';
import '../../core/providers/server_providers.dart';
import '../../core/providers/stock_providers.dart';
import '../../core/settings/app_strings.dart';

class RecommendationsScreen extends ConsumerStatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  ConsumerState<RecommendationsScreen> createState() =>
      _RecommendationsScreenState();
}

class _RecommendationsScreenState extends ConsumerState<RecommendationsScreen> {
  bool _scanning = false;

  Future<void> _triggerScan() async {
    if (_scanning) return;
    final conn = ref.read(serverConnectionProvider);
    if (conn.connected) {
      ref.invalidate(serverStockPoolProvider);
      await ref.read(serverStockPoolProvider.future);
      return;
    }
    if (ref.read(scanProgressProvider).status == ScanStatus.running) return;
    setState(() => _scanning = true);
    try {
      await runLocalScan(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  List<RecommendationItem> _fromServerPool(Map<String, dynamic> payload) {
    final pool = payload['pool'];
    if (pool is! List) return const [];
    final items = <RecommendationItem>[];
    for (var i = 0; i < pool.length; i++) {
      final row = pool[i];
      if (row is! Map) continue;
      final code = '${row['code'] ?? ''}'.padLeft(6, '0');
      if (code.length != 6) continue;
      final name = '${row['name'] ?? code}';
      final score = (row['score'] as num?)?.toDouble() ?? 50;
      final upside = (row['upside'] as num?)?.toDouble();
      final pct = (row['price_percentile'] as num?)?.toDouble();
      final reasons = <String>[
        if (pct != null) '一年价格分位 ${(pct * 100).toStringAsFixed(0)}%',
        if (upside != null) '研报上行 ${(upside * 100).toStringAsFixed(0)}%',
        if (row['insider_events'] != null) '高管增持 ${row['insider_events']} 次',
        if (row['report_count'] != null) '研报 ${row['report_count']} 篇',
      ];
      items.add(
        RecommendationItem(
          code: code,
          name: name,
          industry: '服务端初选',
          rank: i + 1,
          compositeScore: score,
          valuationScore: pct == null ? 50 : ((1 - pct) * 100).clamp(0, 100),
          growthScore: 50,
          spaceScore: upside == null ? 50 : (upside * 100).clamp(0, 100),
          institutionScore: 60,
          capitalScore: 55,
          technicalScore: 55,
          reasons: reasons,
        ),
      );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final conn = ref.watch(serverConnectionProvider);
    final serverPool = ref.watch(serverStockPoolProvider);
    final asyncRecs = ref.watch(todayRecommendationsProvider);
    final scanMeta = ref.watch(scanProgressProvider);
    final isRunning = scanMeta.status == ScanStatus.running || _scanning;
    final useServer = conn.connected;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.recTitle),
        actions: [
          IconButton(
            icon: isRunning || (useServer && serverPool.isLoading)
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: useServer ? strings.serverTest : strings.runScanNow,
            onPressed: isRunning ? null : _triggerScan,
          ),
        ],
      ),
      body: Column(
        children: [
          if (useServer)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.cloud_done_outlined),
                title: Text(strings.serverPoolBanner),
                subtitle: Text(conn.baseUrl ?? ''),
              ),
            )
          else
            _ScanStatusBar(
              scanMeta: scanMeta,
              strings: strings,
              isRunning: isRunning,
            ),
          Expanded(
            child: useServer
                ? serverPool.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => _ErrorState(
                      strings: strings,
                      onRetry: _triggerScan,
                    ),
                    data: (payload) {
                      final items = payload == null
                          ? const <RecommendationItem>[]
                          : _fromServerPool(payload);
                      if (items.isEmpty) {
                        return _EmptyState(
                          strings: strings,
                          onScan: _triggerScan,
                        );
                      }
                      final tradeDate =
                          '${payload?['updated_at'] ?? ''}'.substring(
                        0,
                        ('${payload?['updated_at'] ?? ''}').length >= 10
                            ? 10
                            : ('${payload?['updated_at'] ?? ''}').length,
                      );
                      return RefreshIndicator(
                        onRefresh: _triggerScan,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                          children: [
                            _DateBanner(
                              tradeDate: tradeDate.isEmpty ? '服务端' : tradeDate,
                              strings: strings,
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                strings.serverSubtitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                            ...items.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: RecommendationCard(
                                  item: item,
                                  strings: strings,
                                  onTap: () =>
                                      context.push('/stock/${item.code}'),
                                  onAddWatchlist: () async {
                                    final added =
                                        await addRecommendationToWatchlist(
                                            item);
                                    if (context.mounted) {
                                      ref.invalidate(watchlistProvider);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            added
                                                ? strings.addedToWatchlist
                                                : strings.alreadyInWatchlist,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : asyncRecs.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => _ErrorState(
                      strings: strings,
                      onRetry: _triggerScan,
                    ),
                    data: (data) {
                      if (data.items.isEmpty && !isRunning) {
                        return _EmptyState(
                            strings: strings, onScan: _triggerScan);
                      }
                      if (data.items.isEmpty && isRunning) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              Text(scanMeta.progressMessage),
                            ],
                          ),
                        );
                      }
                      return RefreshIndicator(
                        onRefresh: _triggerScan,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                          children: [
                            _DateBanner(
                                tradeDate: data.tradeDate, strings: strings),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                strings.garpDisclaimer,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                            ...data.items.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: RecommendationCard(
                                  item: item,
                                  strings: strings,
                                  onTap: () =>
                                      context.push('/stock/${item.code}'),
                                  onAddWatchlist: () async {
                                    final added =
                                        await addRecommendationToWatchlist(
                                            item);
                                    if (context.mounted) {
                                      ref.invalidate(watchlistProvider);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            added
                                                ? strings.addedToWatchlist
                                                : strings.alreadyInWatchlist,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ScanStatusBar extends StatelessWidget {
  const _ScanStatusBar({
    required this.scanMeta,
    required this.strings,
    required this.isRunning,
  });

  final ScanMeta scanMeta;
  final AppStrings strings;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    if (isRunning) {
      return Material(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.scanRunning,
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: scanMeta.progress / 100),
              const SizedBox(height: 4),
              Text(scanMeta.progressMessage,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
    }
    if (scanMeta.lastScanAt == null) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          '${strings.scanLastUpdate}: ${scanMeta.lastScanAt}'
          '${scanMeta.lastDurationMs != null ? ' (${(scanMeta.lastDurationMs! / 1000).round()}s)' : ''}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.strings, required this.onScan});

  final AppStrings strings;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.nightlight_round,
                size: 64,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(strings.recEmpty, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.play_arrow),
              label: Text(strings.runScanNow),
            ),
          ],
        ),
      ),
    );
  }
}

class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    super.key,
    required this.item,
    required this.strings,
    required this.onTap,
    required this.onAddWatchlist,
  });

  final RecommendationItem item;
  final AppStrings strings;
  final VoidCallback onTap;
  final VoidCallback onAddWatchlist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    child: Text('${item.rank}',
                        style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text('${item.code} · ${item.industry}',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  _ScoreBadge(score: item.compositeScore),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (item.peTtm != null)
                    _MetricChip(label: 'PE', value: item.peTtm!.toStringAsFixed(1)),
                  if (item.pb != null)
                    _MetricChip(label: 'PB', value: item.pb!.toStringAsFixed(2)),
                  if (item.roe != null)
                    _MetricChip(label: 'ROE', value: '${item.roe!.toStringAsFixed(1)}%'),
                ],
              ),
              const SizedBox(height: 8),
              _ScoreBar(label: strings.scoreValuation, score: item.valuationScore),
              _ScoreBar(label: strings.scoreGrowth, score: item.growthScore),
              _ScoreBar(label: strings.scoreSpace, score: item.spaceScore),
              _ScoreBar(label: strings.scoreInstitution, score: item.institutionScore),
              _ScoreBar(label: strings.scoreMomentum, score: item.momentumScore),
              if (item.reasons.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...item.reasons.take(3).map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text('• $r', style: theme.textTheme.bodySmall),
                      ),
                    ),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onAddWatchlist,
                  icon: const Icon(Icons.star_outline, size: 18),
                  label: Text(strings.addToWatchlist),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});
  final double score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? Colors.green
        : score >= 60
            ? Colors.orange
            : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        score.toStringAsFixed(0),
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label $value', style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.label, required this.score});
  final String label;
  final double score;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label, style: const TextStyle(fontSize: 11))),
          Expanded(
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Text(score.toStringAsFixed(0), style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _DateBanner extends StatelessWidget {
  const _DateBanner({required this.tradeDate, required this.strings});
  final String tradeDate;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text('${strings.recDate}: $tradeDate'),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.strings, required this.onRetry});
  final AppStrings strings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.storage_outlined, size: 64),
            const SizedBox(height: 16),
            Text(strings.apiError, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: Text(strings.runScanNow)),
          ],
        ),
      ),
    );
  }
}
