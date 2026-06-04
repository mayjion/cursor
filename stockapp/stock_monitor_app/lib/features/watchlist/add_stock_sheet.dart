import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/eastmoney_client.dart';
import '../../core/models/watch_stock.dart';
import '../../core/providers/stock_providers.dart';
import '../../core/settings/app_strings.dart';
import '../../core/storage/watchlist_storage.dart';

class AddStockSheet extends ConsumerStatefulWidget {
  const AddStockSheet({super.key});

  @override
  ConsumerState<AddStockSheet> createState() => _AddStockSheetState();
}

class _AddStockSheetState extends ConsumerState<AddStockSheet> {
  final _controller = TextEditingController();
  String? _previewName;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final code = _controller.text.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      setState(() {
        _error = ref.read(appStringsProvider).isZh
            ? '请输入6位数字代码'
            : 'Enter 6-digit code';
        _previewName = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(eastmoneyClientProvider);
      final quote = await client.fetchStockQuote(code);
      setState(() {
        _previewName = quote.name;
        _loading = false;
      });
    } on EastmoneyException catch (e) {
      setState(() {
        _error = e.message;
        _previewName = null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _previewName = null;
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final code = _controller.text.trim();
    if (_previewName == null) {
      await _lookup();
      if (_previewName == null) return;
    }
    final existing = await WatchlistStorage.getByCode(code);
    if (existing != null) {
      setState(() {
        _error = ref.read(appStringsProvider).isZh
            ? '已在自选列表中'
            : 'Already in watchlist';
      });
      return;
    }
    final market = EastmoneyClient.marketFromCode(code);
    final stock = WatchStock(
      id: code,
      code: code,
      name: _previewName!,
      market: market,
      addedAt: DateTime.now(),
    );
    await WatchlistStorage.save(stock);
    ref.invalidate(watchlistProvider);
    ref.invalidate(watchlistItemsProvider);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.paddingOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.addStock,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: strings.stockCode,
              hintText: strings.stockCodeHint,
              border: const OutlineInputBorder(),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _lookup,
                    ),
            ),
            keyboardType: TextInputType.number,
            maxLength: 6,
            onSubmitted: (_) => _lookup(),
          ),
          if (_previewName != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _previewName!,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading ? null : _add,
            child: Text(strings.addStock),
          ),
        ],
      ),
    );
  }
}
