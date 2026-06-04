import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/prediction_direction.dart';
import '../../core/models/watch_stock.dart';
import '../../core/providers/stock_providers.dart';
import '../../core/settings/app_strings.dart';
import '../../core/storage/watchlist_storage.dart';
import 'add_stock_sheet.dart';
import 'watch_stock_card.dart';

class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  bool _refreshing = false;

  Future<void> _onRefresh() async {
    setState(() => _refreshing = true);
    try {
      await refreshAllWatchlist(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ref.read(appStringsProvider).refreshDone),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${ref.read(appStringsProvider).refreshFailed}: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openAddSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const AddStockSheet(),
    );
    if (added == true) {
      ref.invalidate(watchlistProvider);
      ref.invalidate(watchlistItemsProvider);
    }
  }

  List<WatchStock> _sortedByPrediction(
    List<WatchStock> stocks,
    Map<String, WatchlistItemState> items,
  ) {
    final sorted = List<WatchStock>.from(stocks);
    sorted.sort((a, b) {
      final dirA = items[a.code]?.latestPrediction?.direction;
      final dirB = items[b.code]?.latestPrediction?.direction;
      final cmp = _predictionSortOrder(dirA).compareTo(_predictionSortOrder(dirB));
      if (cmp != 0) return cmp;
      return a.code.compareTo(b.code);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final asyncList = ref.watch(watchlistProvider);
    final itemsMap = ref.watch(watchlistItemsProvider).valueOrNull ?? {};

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.watchlistTitle),
        actions: [
          if (_refreshing)
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
              onPressed: _onRefresh,
            ),
        ],
      ),
      body: asyncList.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (stocks) {
          if (stocks.isEmpty) {
            return _EmptyState(
              strings: strings,
              onAdd: _openAddSheet,
            );
          }
          final sorted = _sortedByPrediction(stocks, itemsMap);
          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.86,
              ),
              itemCount: sorted.length,
              itemBuilder: (context, index) {
                final s = sorted[index];
                return WatchStockCard(
                  code: s.code,
                  name: s.name,
                  onTap: () => context.push('/stock/${s.code}'),
                  onDelete: () async {
                    await WatchlistStorage.delete(s.id);
                    ref.invalidate(watchlistProvider);
                    ref.invalidate(watchlistItemsProvider);
                  },
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddSheet,
        tooltip: strings.addStock,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 看涨 → 观望 → 无推测 → 看跌
int _predictionSortOrder(PredictionDirection? direction) {
  return switch (direction) {
    PredictionDirection.up => 0,
    PredictionDirection.neutral => 1,
    null => 2,
    PredictionDirection.down => 3,
  };
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.strings, required this.onAdd});

  final AppStrings strings;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.candlestick_chart_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 24),
            Text(
              strings.emptyWatchlist,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              strings.emptyWatchlistHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(strings.addStock),
            ),
          ],
        ),
      ),
    );
  }
}
