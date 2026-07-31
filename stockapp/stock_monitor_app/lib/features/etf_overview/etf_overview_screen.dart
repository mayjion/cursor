import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/etf_providers.dart';
import '../../core/settings/app_strings.dart';

class EtfOverviewScreen extends ConsumerWidget {
  const EtfOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final items = ref.watch(etfOverviewProvider);
    final etfsAsync = ref.watch(etfWatchlistProvider);
    final sync = ref.watch(etfSyncProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.etfOverviewTitle),
        bottom: sync.running
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(value: sync.fraction),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        strings.etfSyncProgress(sync.current, sync.total),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              )
            : null,
        actions: [
          if (sync.running)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: strings.pullToRefresh,
              onPressed: () {
                startEtfScoreSyncInBackground(ref);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(strings.etfSyncStarted)),
                );
              },
            ),
        ],
      ),
      body: etfsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (_) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  strings.etfOverviewEmpty,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              startEtfScoreSyncInBackground(ref);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(strings.etfSyncStarted)),
                );
              }
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              children: [
                Text(
                  strings.etfDisclaimer,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                ...items.map(
                  (item) => Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () => context.push('/overview/etf/${item.code}'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      Text(
                                        '${item.code}${item.indexName.isNotEmpty ? ' · ${item.indexName}' : ''}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                _BuyIndexBadge(
                                  score: item.score.addFitness > 0
                                      ? item.score.addFitness
                                      : item.score.buyIndex,
                                  label: item.score.latestAdd != null
                                      ? strings.etfSignalAdd
                                      : item.score.label,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              strings.etfModelBasis,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 4),
                            ...item.score.reasons.take(3).map(
                                  (r) => Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Text(
                                      '• $r',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                ),
                            const SizedBox(height: 8),
                            Text(
                              item.narrative,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BuyIndexBadge extends StatelessWidget {
  const _BuyIndexBadge({required this.score, required this.label});

  final double score;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = score >= 75
        ? Colors.red.shade700
        : score >= 55
            ? Colors.orange.shade700
            : Colors.grey;
    return Column(
      children: [
        Text(
          score.toStringAsFixed(0),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
