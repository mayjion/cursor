import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/prediction_direction.dart';
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
    final state = items.maybeWhen(
      data: (m) => m[code],
      orElse: () => null,
    );
    final flow = state?.todayFlow;
    final pred = state?.latestPrediction;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        Text(
                          code,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        if (flow?.closePrice != null) ...[
                          const SizedBox(height: 4),
                          _PriceLine(
                            price: flow!.closePrice!,
                            changePercent: flow.changePercent,
                            strings: strings,
                          ),
                        ],
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
                      tooltip:
                          Localizations.localeOf(context).languageCode == 'zh'
                              ? '移除'
                              : 'Remove',
                    ),
                  ),
                ],
              ),
              if (pred != null) ...[
                const SizedBox(height: 4),
                _PredictionChip(direction: pred.direction),
              ],
              if (flow != null) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _FlowMetric(
                        label: strings.mainNetInflow,
                        value: strings.formatMoney(flow.mainNetInflow),
                        valueColor:
                            colorForNetInflow(context, flow.mainNetInflow),
                        subLabel:
                            '${strings.mainNetRatio} ${flow.mainNetRatio.toStringAsFixed(2)}%',
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _FlowMetric(
                        label: strings.retailNetInflow,
                        value: strings.formatMoney(flow.smallNetInflow),
                        valueColor:
                            colorForNetInflow(context, flow.smallNetInflow),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({
    required this.price,
    required this.changePercent,
    required this.strings,
  });

  final double price;
  final double? changePercent;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final change = changePercent;
    return Row(
      children: [
        Text(
          '${strings.latestPrice} ',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
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

class _FlowMetric extends StatelessWidget {
  const _FlowMetric({
    required this.label,
    required this.value,
    required this.valueColor,
    this.subLabel,
  });

  final String label;
  final String value;
  final Color valueColor;
  final String? subLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.bold,
              ),
        ),
        if (subLabel != null)
          Text(subLabel!, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _PredictionChip extends ConsumerWidget {
  const _PredictionChip({required this.direction});

  final PredictionDirection direction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final (label, color, icon) = switch (direction) {
      PredictionDirection.up => (
          strings.predictUp,
          stockUpColor(context),
          Icons.trending_up,
        ),
      PredictionDirection.down => (
          strings.predictDown,
          stockDownColor(context),
          Icons.trending_down,
        ),
      PredictionDirection.neutral => (
          strings.predictNeutral,
          Theme.of(context).colorScheme.outline,
          Icons.remove,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
