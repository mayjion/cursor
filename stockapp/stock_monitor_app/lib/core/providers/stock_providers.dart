import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/eastmoney_client.dart';
import '../models/capital_flow_day.dart';
import '../models/position_signal_record.dart';
import '../models/watch_stock.dart';
import '../position/position_signal_engine.dart';
import '../storage/flow_cache_storage.dart';
import '../storage/position_signal_storage.dart';
import '../settings/app_settings.dart';
import '../storage/watchlist_storage.dart';

final eastmoneyClientProvider = Provider<EastmoneyClient>((ref) {
  final client = EastmoneyClient();
  ref.onDispose(client.close);
  return client;
});

final positionSignalEngineProvider = Provider<PositionSignalEngine>((ref) {
  return PositionSignalEngine(
    client: ref.watch(eastmoneyClientProvider),
  );
});

final watchlistProvider = FutureProvider<List<WatchStock>>((ref) async {
  return WatchlistStorage.list();
});

final positionSignalListProvider =
    FutureProvider<List<PositionSignalRecord>>((ref) async {
  return PositionSignalStorage.list();
});

final positionSignalSummaryProvider =
    FutureProvider<PositionSignalSummary>((ref) async {
  final engine = ref.read(positionSignalEngineProvider);
  return engine.computeSummary();
});

class WatchlistItemState {
  const WatchlistItemState({
    this.todayFlow,
    this.latestSignal,
    this.loading = false,
    this.error,
  });

  final CapitalFlowDay? todayFlow;
  final PositionSignalRecord? latestSignal;
  final bool loading;
  final String? error;
}

final watchlistItemsProvider =
    FutureProvider<Map<String, WatchlistItemState>>((ref) async {
  final stocks = await ref.watch(watchlistProvider.future);
  final client = ref.read(eastmoneyClientProvider);
  final map = <String, WatchlistItemState>{};
  for (final s in stocks) {
    if (s.assetType == AssetType.etf) {
      map[s.code] = const WatchlistItemState();
      continue;
    }
    final cached = await FlowCacheStorage.listForCode(s.code);
    CapitalFlowDay? today;
    if (cached.isNotEmpty) {
      today = cached.last;
    }
    if (today != null && today.closePrice == null) {
      try {
        final quote = await client.fetchStockQuote(s.code);
        final meta = quote.todayFlow;
        if (meta != null) {
          today = today.copyWith(
            closePrice: meta.closePrice,
            changePercent: meta.changePercent,
            mainNetRatio: today.mainNetRatio == 0
                ? meta.mainNetRatio
                : today.mainNetRatio,
          );
        }
      } catch (_) {}
    }
    final signals = await PositionSignalStorage.listForCode(s.code);
    map[s.code] = WatchlistItemState(
      todayFlow: today,
      latestSignal: signals.isNotEmpty ? signals.first : null,
    );
  }
  return map;
});

Future<void> refreshAllWatchlist(WidgetRef ref) async {
  final stocks = await WatchlistStorage.list();
  final engine = ref.read(positionSignalEngineProvider);
  final settings = ref.read(appSettingsProvider);

  final equity = stocks.where((s) => s.assetType == AssetType.stock).toList();

  for (var i = 0; i < equity.length; i++) {
    final stock = equity[i];
    try {
      await engine.refreshStockFlows(
        stock.code,
        reversalNotifyEnabled: settings.reversalNotifyEnabled,
      );
    } catch (_) {}
    if (i < equity.length - 1) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  ref.invalidate(watchlistProvider);
  ref.invalidate(watchlistItemsProvider);
  ref.invalidate(positionSignalListProvider);
  ref.invalidate(positionSignalSummaryProvider);
}
