import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/etf_models.dart';
import '../../core/models/position_signal.dart';
import '../../core/models/position_signal_record.dart';
import '../../core/models/watch_stock.dart';
import '../../core/providers/etf_providers.dart';
import '../../core/providers/stock_providers.dart';
import '../../core/settings/app_strings.dart';
import '../../core/storage/etf_share_cache_storage.dart';
import '../../core/storage/watchlist_storage.dart';
import 'add_stock_sheet.dart';
import 'bulk_add_etf_sheet.dart';
import 'etf_watch_card.dart';
import 'watch_stock_card.dart';

class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen>
    with SingleTickerProviderStateMixin {
  bool _stockRefreshing = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _onRefreshStocks() async {
    setState(() => _stockRefreshing = true);
    try {
      await refreshAllWatchlist(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(appStringsProvider).refreshDone)),
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
      if (mounted) setState(() => _stockRefreshing = false);
    }
  }

  Future<void> _onRefreshEtfs() async {
    final strings = ref.read(appStringsProvider);
    startEtfScoreSyncInBackground(ref);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.etfSyncStarted)),
      );
    }
  }

  Future<void> _onAppBarRefresh() async {
    if (_tabController.index == 1) {
      await _onRefreshEtfs();
    } else {
      await _onRefreshStocks();
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
      ref.invalidate(etfWatchlistProvider);
    }
  }

  Future<void> _openBulkAddEtf() async {
    final result = await showModalBottomSheet<BulkAddEtfResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const BulkAddEtfSheet(),
    );
    if (result == null || !mounted) return;
    final strings = ref.read(appStringsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.bulkAddEtfDone(
            matched: result.matched,
            added: result.added,
            skipped: result.skipped,
          ),
        ),
      ),
    );
  }

  Future<void> _clearAllEtfs() async {
    final strings = ref.read(appStringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.clearAllEtfs),
        content: Text(strings.clearAllEtfsConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings.isZh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings.isZh ? '清空' : 'Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final count = await clearAllEtfs(ref);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.clearAllEtfsDone(count))),
    );
  }

  List<WatchStock> _sortedBySignal(
    List<WatchStock> stocks,
    Map<String, WatchlistItemState> items,
  ) {
    final sorted = List<WatchStock>.from(stocks);
    sorted.sort((a, b) {
      final sigA = items[a.code]?.latestSignal;
      final sigB = items[b.code]?.latestSignal;
      final cmp = _signalSortOrder(sigA).compareTo(_signalSortOrder(sigB));
      if (cmp != 0) return cmp;
      return a.code.compareTo(b.code);
    });
    return sorted;
  }

  List<WatchStock> _sortedEtfsByFitness(
    List<WatchStock> etfs,
    Map<String, EtfBuyScore> scores,
  ) {
    final sorted = List<WatchStock>.from(etfs);
    sorted.sort((a, b) {
      final fa = scores[a.code]?.addFitness ?? 0;
      final fb = scores[b.code]?.addFitness ?? 0;
      final cmp = fb.compareTo(fa);
      if (cmp != 0) return cmp;
      final ba = scores[a.code]?.buyIndex ?? 0;
      final bb = scores[b.code]?.buyIndex ?? 0;
      final buyCmp = bb.compareTo(ba);
      if (buyCmp != 0) return buyCmp;
      return a.code.compareTo(b.code);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final asyncList = ref.watch(watchlistProvider);
    final itemsMap = ref.watch(watchlistItemsProvider).valueOrNull ?? {};
    final scoreMap = ref.watch(etfScoreMapProvider);
    final sync = ref.watch(etfSyncProvider);
    final busy = _stockRefreshing || sync.running;

    ref.listen<EtfSyncProgress>(etfSyncProvider, (prev, next) {
      if (prev?.running == true && !next.running && next.total > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings.etfSyncSummary(
                fetched: next.fetched,
                skipped: next.skippedFresh,
              ),
            ),
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.watchlistTitle),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(sync.running ? 52 : 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: strings.watchlistStocks),
                  Tab(text: strings.watchlistEtfs),
                ],
              ),
              if (sync.running)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
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
            ],
          ),
        ),
        actions: [
          if (_tabController.index == 1) ...[
            IconButton(
              icon: const Icon(Icons.playlist_add),
              tooltip: strings.bulkAddEtf,
              onPressed: _openBulkAddEtf,
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: strings.clearAllEtfs,
              onPressed: _clearAllEtfs,
            ),
          ],
          if (busy)
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
              onPressed: _onAppBarRefresh,
            ),
        ],
      ),
      body: asyncList.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (stocks) {
          final equity =
              stocks.where((s) => s.assetType == AssetType.stock).toList();
          final etfs =
              stocks.where((s) => s.assetType == AssetType.etf).toList();
          return TabBarView(
            controller: _tabController,
            children: [
              _buildGrid(
                strings: strings,
                stocks: _sortedBySignal(equity, itemsMap),
                emptyHint: strings.emptyWatchlist,
                onTap: (s) => context.push('/watchlist/stock/${s.code}'),
                onRefresh: _onRefreshStocks,
              ),
              _buildGrid(
                strings: strings,
                stocks: _sortedEtfsByFitness(etfs, scoreMap),
                emptyHint: strings.etfOverviewEmpty,
                onTap: (s) => context.push('/watchlist/etf/${s.code}'),
                etfScores: scoreMap,
                showBulkAdd: true,
                onRefresh: _onRefreshEtfs,
                syncing: sync.running,
              ),
            ],
          );
        },
      ),
      floatingActionButton: _tabController.index == 1
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if ((asyncList.valueOrNull ?? [])
                    .any((s) => s.assetType == AssetType.etf)) ...[
                  FloatingActionButton.extended(
                    heroTag: 'clear_etf',
                    onPressed: _clearAllEtfs,
                    backgroundColor:
                        Theme.of(context).colorScheme.errorContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onErrorContainer,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text(strings.clearAllEtfs),
                  ),
                  const SizedBox(height: 12),
                ],
                FloatingActionButton.extended(
                  heroTag: 'bulk_etf',
                  onPressed: _openBulkAddEtf,
                  icon: const Icon(Icons.playlist_add),
                  label: Text(strings.bulkAddEtf),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'add_one',
                  onPressed: _openAddSheet,
                  tooltip: strings.addStock,
                  child: const Icon(Icons.add),
                ),
              ],
            )
          : FloatingActionButton(
              onPressed: _openAddSheet,
              tooltip: strings.addStock,
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildGrid({
    required AppStrings strings,
    required List<WatchStock> stocks,
    required String emptyHint,
    required void Function(WatchStock) onTap,
    required Future<void> Function() onRefresh,
    Map<String, EtfBuyScore>? etfScores,
    bool showBulkAdd = false,
    bool syncing = false,
  }) {
    final isEtf = etfScores != null;
    if (stocks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emptyHint, textAlign: TextAlign.center),
              if (showBulkAdd) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _openBulkAddEtf,
                  icon: const Icon(Icons.playlist_add),
                  label: Text(strings.bulkAddEtf),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 160),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.78,
        ),
        itemCount: stocks.length,
        itemBuilder: (context, index) {
          final s = stocks[index];
          if (isEtf) {
            return EtfWatchCard(
              code: s.code,
              name: s.name,
              score: etfScores[s.code],
              syncing: syncing && etfScores[s.code] == null,
              onTap: () => onTap(s),
              onDelete: () async {
                await WatchlistStorage.delete(s.id);
                ref.read(etfScoreMapProvider.notifier).removeCodes([s.code]);
                await EtfShareCacheStorage.deleteMany([s.code]);
                ref.invalidate(watchlistProvider);
                ref.invalidate(watchlistItemsProvider);
                ref.invalidate(etfWatchlistProvider);
              },
            );
          }
          return WatchStockCard(
            code: s.code,
            name: s.name,
            onTap: () => onTap(s),
            onDelete: () async {
              await WatchlistStorage.delete(s.id);
              ref.invalidate(watchlistProvider);
              ref.invalidate(watchlistItemsProvider);
              ref.invalidate(etfWatchlistProvider);
            },
          );
        },
      ),
    );
  }
}

int _signalSortOrder(PositionSignalRecord? signal) {
  if (signal == null) return 99;
  final severity = signal.reversalSeverity;
  if (severity == ReversalSeverity.deepDrop) return 0;
  if (severity == ReversalSeverity.confirmed) return 1;
  final type = signal.signalType;
  return switch (type) {
    PositionSignalType.trendReversal => 2,
    PositionSignalType.trendBreak => 3,
    PositionSignalType.reduce => 4,
    PositionSignalType.add => 5,
    PositionSignalType.hold => 6,
    PositionSignalType.holdBaseOnly => 7,
  };
}
