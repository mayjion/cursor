import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/position_signal.dart';
import '../../core/models/position_signal_record.dart';
import '../../core/providers/investment_providers.dart';
import '../../core/providers/stock_providers.dart';
import '../../core/settings/app_strings.dart';
import '../../core/settings/app_theme.dart';

class WatchStockCard extends ConsumerWidget {
  const WatchStockCard({
    super.key,
    required this.code,
    required this.name,
    required this.onTap,
    required this.onDelete,
  });

  final String code;
  final String name;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final items = ref.watch(watchlistItemsProvider);
    final recs = ref.watch(todayRecommendationsProvider).valueOrNull;
    final isFromRec = recs?.items.any((r) => r.code == code) ?? false;
    final state = items.maybeWhen(
      data: (m) => m[code],
      orElse: () => null,
    );
    final flow = state?.todayFlow;
    final signal = state?.latestSignal;
    final isReversal = signal?.isReversal == true ||
        signal?.reversalSeverity != null;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: isReversal
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.error.withValues(alpha: 0.7),
                width: 2,
              ),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          code,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        if (isFromRec)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Chip(
                              label: Text(
                                strings.isZh ? '今日推荐' : 'Today pick',
                                style: const TextStyle(fontSize: 9),
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      onPressed: onDelete,
                      tooltip: strings.isZh ? '移除' : 'Remove',
                    ),
                  ),
                ],
              ),
              if (flow?.closePrice != null) ...[
                const SizedBox(height: 4),
                _PriceLine(
                  price: flow!.closePrice!,
                  changePercent: flow.changePercent,
                ),
              ],
              const SizedBox(height: 6),
              Expanded(
                child: signal != null
                    ? _StrategySignalPanel(record: signal, strings: strings)
                    : _NoSignalPanel(strings: strings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.price, required this.changePercent});

  final double price;
  final double? changePercent;

  @override
  Widget build(BuildContext context) {
    final change = changePercent;
    return Row(
      children: [
        Text(
          price.toStringAsFixed(2),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        if (change != null) ...[
          const SizedBox(width: 6),
          Text(
            '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorForNetInflow(context, change),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ],
    );
  }
}

class _NoSignalPanel extends StatelessWidget {
  const _NoSignalPanel({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        strings.isZh ? '下拉刷新获取信号' : 'Pull to refresh for signal',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _StrategySignalPanel extends StatelessWidget {
  const _StrategySignalPanel({required this.record, required this.strings});

  final PositionSignalRecord record;
  final AppStrings strings;

  List<String> get _displayReasons {
    if (record.reasons.isNotEmpty) return record.reasons;
    if (record.triggeredSignals.isNotEmpty) {
      return record.triggeredSignals
          .map(strings.triggeredSignalLabel)
          .toList();
    }
    if (record.analysisSummary.isNotEmpty) {
      return record.analysisSummary
          .split(RegExp(r'[·；]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final type = record.signalType;
    final severity = record.reversalSeverity;
    final (label, color, icon) = _signalStyle(context, type, severity);
    final reasons = _displayReasons;
    final action = record.suggestedAction;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              strings.triggerConditions,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            ...reasons.take(3).map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('· ',
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              height: 1.25,
                            )),
                        Expanded(
                          child: Text(
                            r,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(fontSize: 10, height: 1.25),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          if (action != null && action.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${strings.executeAction}：$action',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  (String, Color, IconData) _signalStyle(
    BuildContext context,
    PositionSignalType type,
    ReversalSeverity? severity,
  ) {
    if (severity == ReversalSeverity.deepDrop) {
      return (
        strings.severityLabel(severity!),
        Theme.of(context).colorScheme.error,
        Icons.error,
      );
    }
    if (severity == ReversalSeverity.confirmed) {
      return (
        strings.signalTrendReversal,
        Theme.of(context).colorScheme.error,
        Icons.warning_amber,
      );
    }
    if (severity == ReversalSeverity.earlyWarning) {
      return (
        strings.signalTrendBreak,
        Colors.deepOrange,
        Icons.trending_down,
      );
    }
    return switch (type) {
      PositionSignalType.add => (
          strings.signalAdd,
          stockUpColor(context),
          Icons.add_circle_outline,
        ),
      PositionSignalType.reduce => (
          strings.signalReduce,
          Colors.orange.shade700,
          Icons.remove_circle_outline,
        ),
      PositionSignalType.trendBreak => (
          strings.signalTrendBreak,
          Colors.deepOrange,
          Icons.trending_down,
        ),
      PositionSignalType.trendReversal => (
          strings.signalTrendReversal,
          Theme.of(context).colorScheme.error,
          Icons.warning_amber,
        ),
      PositionSignalType.hold => (
          strings.signalHold,
          Theme.of(context).colorScheme.outline,
          Icons.pause_circle_outline,
        ),
      PositionSignalType.holdBaseOnly => (
          strings.signalHoldBaseOnly,
          Theme.of(context).colorScheme.primary,
          Icons.shield_outlined,
        ),
    };
  }
}
