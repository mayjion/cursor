import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/eastmoney_client.dart';
import '../models/capital_flow_day.dart';
import '../models/prediction_record.dart';
import '../models/watch_stock.dart';
import '../prediction/prediction_engine.dart';
import '../settings/app_settings.dart';
import '../storage/flow_cache_storage.dart';
import '../storage/prediction_storage.dart';
import '../storage/watchlist_storage.dart';

final eastmoneyClientProvider = Provider<EastmoneyClient>((ref) {
  final client = EastmoneyClient();
  ref.onDispose(client.close);
  return client;
});

final predictionEngineProvider = Provider<PredictionEngine>((ref) {
  final settings = ref.watch(appSettingsProvider);
  return PredictionEngine(
    client: ref.watch(eastmoneyClientProvider),
    thresholds: settings.thresholds,
  );
});

final watchlistProvider = FutureProvider<List<WatchStock>>((ref) async {
  return WatchlistStorage.list();
});

final predictionListProvider =
    FutureProvider<List<PredictionRecord>>((ref) async {
  await ref.read(predictionEngineProvider).verifyPendingRecords();
  return PredictionStorage.list();
});

final predictionStatsProvider = FutureProvider<PredictionStats>((ref) async {
  final engine = ref.read(predictionEngineProvider);
  await engine.verifyPendingRecords();
  return engine.computeStats();
});

class WatchlistItemState {
  const WatchlistItemState({
    this.todayFlow,
    this.latestPrediction,
    this.loading = false,
    this.error,
  });

  final CapitalFlowDay? todayFlow;
  final PredictionRecord? latestPrediction;
  final bool loading;
  final String? error;
}

final watchlistItemsProvider =
    FutureProvider<Map<String, WatchlistItemState>>((ref) async {
  final stocks = await ref.watch(watchlistProvider.future);
  final client = ref.read(eastmoneyClientProvider);
  final map = <String, WatchlistItemState>{};
  for (final s in stocks) {
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
    final preds = await PredictionStorage.listForCode(s.code);
    map[s.code] = WatchlistItemState(
      todayFlow: today,
      latestPrediction: preds.isNotEmpty ? preds.first : null,
    );
  }
  return map;
});

Future<void> refreshAllWatchlist(WidgetRef ref) async {
  final stocks = await WatchlistStorage.list();
  final engine = ref.read(predictionEngineProvider);

  await engine.verifyPendingRecords();

  for (var i = 0; i < stocks.length; i++) {
    final stock = stocks[i];
    try {
      await engine.refreshStockFlows(stock.code);
    } catch (_) {}
    if (i < stocks.length - 1) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  ref.invalidate(watchlistProvider);
  ref.invalidate(watchlistItemsProvider);
  ref.invalidate(predictionListProvider);
  ref.invalidate(predictionStatsProvider);
}
