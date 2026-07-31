import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/etf_models.dart';
import '../../core/providers/etf_providers.dart';
import '../../core/providers/stock_providers.dart';
import '../../core/settings/app_strings.dart';

class BulkAddEtfSheet extends ConsumerStatefulWidget {
  const BulkAddEtfSheet({super.key});

  @override
  ConsumerState<BulkAddEtfSheet> createState() => _BulkAddEtfSheetState();
}

class _BulkAddEtfSheetState extends ConsumerState<BulkAddEtfSheet> {
  static const _presets = [1.0, 5.0, 10.0, 20.0, 50.0];

  double _minScaleYi = 5;
  bool _loading = false;
  String? _status;
  String? _error;
  List<EtfInfo>? _preview;
  int _existingSkip = 0;

  Future<void> _previewMatch() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = ref.read(appStringsProvider).bulkAddEtfLoading;
      _preview = null;
    });
    try {
      final client = ref.read(eastmoneyClientProvider);
      final list = await client.fetchEtfUniverse(
        pageSize: 200,
        maxPages: 20,
        minScaleYi: _minScaleYi,
      );
      final watchlist = await ref.read(watchlistProvider.future);
      final codes = watchlist.map((e) => e.code).toSet();
      final skip = list.where((e) => codes.contains(e.code)).length;
      if (!mounted) return;
      setState(() {
        _preview = list;
        _existingSkip = skip;
        _loading = false;
        _status = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _status = null;
      });
    }
  }

  Future<void> _confirmAdd() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = ref.read(appStringsProvider).bulkAddEtfAdding;
    });
    try {
      final result = await bulkAddEtfsByScale(ref, minScaleYi: _minScaleYi);
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _status = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final matched = _preview?.length;
    final toAdd =
        matched == null ? null : (matched - _existingSkip).clamp(0, matched);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: MediaQuery.paddingOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.bulkAddEtf,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            strings.bulkAddEtfHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Text(
            strings.bulkAddEtfMinScale,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _presets)
                ChoiceChip(
                  label: Text('≥${p.toStringAsFixed(0)}亿'),
                  selected: _minScaleYi == p,
                  onSelected: _loading
                      ? null
                      : (_) => setState(() {
                            _minScaleYi = p;
                            _preview = null;
                          }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _minScaleYi.clamp(1, 100),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: '≥${_minScaleYi.toStringAsFixed(0)}亿',
                  onChanged: _loading
                      ? null
                      : (v) => setState(() {
                            _minScaleYi = v.roundToDouble();
                            _preview = null;
                          }),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '≥${_minScaleYi.toStringAsFixed(0)}亿',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(_status!)),
              ],
            ),
          ],
          if (matched != null) ...[
            const SizedBox(height: 8),
            Text(
              '${strings.bulkAddEtfMatched} $matched · '
              '${strings.bulkAddEtfAdded} $toAdd · '
              '${strings.bulkAddEtfSkipped} $_existingSkip',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_preview != null && _preview!.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  itemCount: _preview!.length.clamp(0, 30),
                  itemBuilder: (context, i) {
                    final e = _preview![i];
                    final scale = e.scaleYi?.toStringAsFixed(1) ?? '-';
                    return Text(
                      '${e.code}  ${e.name}  $scale亿',
                      style: Theme.of(context).textTheme.bodySmall,
                    );
                  },
                ),
              ),
              if (_preview!.length > 30)
                Text(
                  '…共 ${_preview!.length} 只',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _loading ? null : _previewMatch,
            child: Text(strings.bulkAddEtfPreview),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _loading ? null : _confirmAdd,
            child: Text(strings.bulkAddEtfConfirm),
          ),
        ],
      ),
    );
  }
}
