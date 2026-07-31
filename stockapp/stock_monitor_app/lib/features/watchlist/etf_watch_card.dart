import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/etf_models.dart';
import '../../core/settings/app_strings.dart';

class EtfWatchCard extends ConsumerWidget {
  const EtfWatchCard({
    super.key,
    required this.code,
    required this.name,
    required this.onTap,
    required this.onDelete,
    this.score,
    this.syncing = false,
  });

  final String code;
  final String name;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final EtfBuyScore? score;
  final bool syncing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final buyIndex = score?.buyIndex;
    final label = score?.label;
    final reasons = score?.reasons ?? const <String>[];
    final color = _indexColor(context, buyIndex);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          code,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
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
              const SizedBox(height: 8),
              if (score != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      buyIndex!.toStringAsFixed(0),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.bold,
                            height: 1,
                          ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${strings.etfBuyIndex} · $label',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
                if (score!.latestRisk != null || score!.latestAdd != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (score!.latestRisk != null)
                        _SignalChip(
                          text: strings.etfSignalRisk,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      if (score!.latestAdd != null && score!.latestRisk == null)
                        _SignalChip(
                          text: strings.etfSignalAdd,
                          color: Colors.red.shade700,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.etfSignalSection,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                fontSize: 9,
                              ),
                        ),
                        const SizedBox(height: 2),
                        if (score!.addFitness > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${strings.etfAddFitness} ${score!.addFitness.toStringAsFixed(0)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    fontSize: 9,
                                    height: 1.2,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        if (score!.signalWinSamples > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              strings.etfSignalWinRateLine(
                                score!.signalWinRate,
                                score!.signalWinHits,
                                score!.signalWinSamples,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(fontSize: 9, height: 1.2),
                            ),
                          ),
                        if (score!.signals.isNotEmpty)
                          ...score!.signals.take(2).map(
                                (s) {
                                  final tag = s.type == EtfFlowSignalType.risk
                                      ? strings.etfSignalRisk
                                      : (s.isActionable
                                          ? strings.etfSignalAdd
                                          : strings.etfSignalAddHistory);
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '· $tag ${s.pointDate}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                              fontSize: 10, height: 1.25),
                                    ),
                                  );
                                },
                              )
                        else if (reasons.isNotEmpty)
                          ...reasons.take(2).map(
                                (r) => Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '· $r',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(fontSize: 10, height: 1.25),
                                  ),
                                ),
                              )
                        else
                          Text(
                            strings.etfSignalEmpty,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                ),
              ] else
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (syncing)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            Icons.cloud_download_outlined,
                            size: 22,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        const SizedBox(height: 8),
                        Text(
                          syncing
                              ? (strings.isZh ? '正在更新…' : 'Updating…')
                              : (strings.isZh ? '下拉刷新获取评分' : 'Pull to refresh'),
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _indexColor(BuildContext context, double? buyIndex) {
    if (buyIndex == null) return Theme.of(context).colorScheme.outline;
    if (score?.latestRisk != null) return Theme.of(context).colorScheme.error;
    if (score?.latestAdd != null || (score?.addFitness ?? 0) >= 70) {
      return Colors.red.shade700;
    }
    if (buyIndex >= 75) return Colors.red.shade700;
    if (buyIndex >= 55) return Colors.orange.shade700;
    if (buyIndex >= 40) return Theme.of(context).colorScheme.primary;
    return Theme.of(context).colorScheme.outline;
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
