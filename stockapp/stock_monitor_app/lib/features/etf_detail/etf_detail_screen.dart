import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/eastmoney_client.dart';
import '../../core/engine/etf_flow_model.dart';
import '../../core/models/etf_models.dart';
import '../../core/models/stock_bar.dart';
import '../../core/models/watch_stock.dart';
import '../../core/providers/etf_providers.dart';
import '../../core/providers/stock_providers.dart';
import '../../core/settings/app_strings.dart';
import '../../core/settings/app_theme.dart';
import '../../core/storage/watchlist_storage.dart';

class EtfDetailScreen extends ConsumerStatefulWidget {
  const EtfDetailScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<EtfDetailScreen> createState() => _EtfDetailScreenState();
}

class _EtfDetailScreenState extends ConsumerState<EtfDetailScreen> {
  String _name = '';
  bool _inWatchlist = false;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final stock = await WatchlistStorage.getByCode(widget.code);
    String name = stock?.name ?? widget.code;
    try {
      final info =
          await ref.read(eastmoneyClientProvider).fetchEtfInfo(widget.code);
      if (info != null) name = info.name;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _name = name;
        _inWatchlist = stock != null;
      });
    }
  }

  Future<void> _toggleWatchlist() async {
    final strings = ref.read(appStringsProvider);
    if (_inWatchlist) {
      final stock = await WatchlistStorage.getByCode(widget.code);
      if (stock != null) await WatchlistStorage.delete(stock.id);
      setState(() => _inWatchlist = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.removeFromWatchlist)),
        );
      }
    } else {
      final client = ref.read(eastmoneyClientProvider);
      final info = await client.fetchEtfInfo(widget.code);
      await WatchlistStorage.save(
        WatchStock(
          id: widget.code,
          code: widget.code,
          name: info?.name ?? _name,
          market: EastmoneyClient.marketFromCode(widget.code),
          addedAt: DateTime.now(),
          assetType: AssetType.etf,
          indexName: info?.indexName ?? '',
        ),
      );
      setState(() => _inWatchlist = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.addedToWatchlist)),
        );
      }
    }
    ref.invalidate(watchlistProvider);
    ref.invalidate(etfWatchlistProvider);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final scoreAsync = ref.watch(etfScoreProvider(widget.code));
    final shareAsync = ref.watch(etfShareHistoryProvider(widget.code));
    final weeklyAsync = ref.watch(etfWeeklyBarsProvider(widget.code));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_name.isEmpty ? widget.code : _name),
            Text(widget.code, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_inWatchlist ? Icons.star : Icons.star_outline),
            onPressed: _toggleWatchlist,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final score = await refreshEtfScoreWithClient(
            ref.read(eastmoneyClientProvider),
            widget.code,
            forceNetwork: true,
          );
          ref.read(etfScoreMapProvider.notifier).upsert(score);
          ref.invalidate(etfScoreProvider(widget.code));
          ref.invalidate(etfShareHistoryProvider(widget.code));
          ref.invalidate(etfWeeklyBarsProvider(widget.code));
          await Future.wait([
            ref.read(etfShareHistoryProvider(widget.code).future),
            ref.read(etfWeeklyBarsProvider(widget.code).future),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            scoreAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
              data: (score) {
                if (score == null) return Text(strings.noData);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${strings.etfBuyIndex}: ${score.buyIndex.toStringAsFixed(0)}（${score.label}）',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${strings.etfAddFitness}: ${score.addFitness.toStringAsFixed(0)}'
                          '${score.historySupportsAdd ? '' : '（规则未达标）'}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          strings.etfSignalSection,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          strings.etfSignalRuleHint,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          strings.etfSignalWinRateLine(
                            score.signalWinRate,
                            score.signalWinHits,
                            score.signalWinSamples,
                          ),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        if (score.ruleLines.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          ...score.ruleLines.map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                '· $line',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        if (score.signals.isEmpty)
                          Text(strings.etfSignalEmpty)
                        else
                          ...score.signals.map(
                            (s) {
                              final tag = s.type == EtfFlowSignalType.risk
                                  ? strings.etfSignalRisk
                                  : (s.isActionable
                                      ? strings.etfSignalAdd
                                      : strings.etfSignalAddHistory);
                              final tagColor = s.type == EtfFlowSignalType.risk
                                  ? Theme.of(context).colorScheme.error
                                  : (s.isActionable
                                      ? Colors.red.shade700
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(top: 2),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            tagColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        tag,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: tagColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${s.pointDate}\n${s.reason}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        const SizedBox(height: 8),
                        Text(
                          strings.etfModelBasis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        ...score.reasons.map(
                          (r) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('• $r'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(strings.etfShareSection,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            shareAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('$e'),
              data: (shares) {
                if (shares.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(strings.noData),
                    ),
                  );
                }
                final quarters = EtfFlowModel.extractQuarterReports(shares);
                final lastQ = quarters.isNotEmpty ? quarters.last : null;
                final last = shares.last;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            if (lastQ != null) ...[
                              _row(strings.etfLatestQuarter, lastQ.date),
                              _row(
                                strings.etfPeriodApply,
                                lastQ.applyShare?.toStringAsFixed(2) ?? '-',
                              ),
                              _row(
                                strings.etfPeriodRedeem,
                                lastQ.redeemShare?.toStringAsFixed(2) ?? '-',
                              ),
                              _row(
                                strings.etfPeriodNet,
                                lastQ.quarterNetShare?.toStringAsFixed(2) ??
                                    '-',
                              ),
                              const Divider(),
                            ],
                            _row('总份额', last.totalShare.toStringAsFixed(2)),
                            _row(
                              strings.etfInQuarterToDate,
                              last.shareChangeQ?.toStringAsFixed(2) ?? '-',
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (quarters.length >= 2) ...[
                      const SizedBox(height: 8),
                      Text(
                        strings.etfQuarterChart,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                          child: Column(
                            children: [
                              _ChartLegend(strings: strings),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 280,
                                child: weeklyAsync.when(
                                  loading: () => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                  error: (e, _) => Center(child: Text('$e')),
                                  data: (weekly) {
                                    if (weekly.length < 4) {
                                      return Center(
                                        child: Text(
                                          strings.isZh
                                              ? '周K暂不可用，请稍后下拉重试'
                                              : 'Weekly K unavailable, pull to retry',
                                          textAlign: TextAlign.center,
                                        ),
                                      );
                                    }
                                    return _WeeklyKWithNetChart(
                                      weekly: weekly,
                                      quarters: quarters,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              strings.etfDisclaimer,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              strings.etfForceRefreshHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final up = stockUpColor(context);
    final down = stockDownColor(context);
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _candleIcon(up),
            const SizedBox(width: 4),
            Text('${strings.etfChartPriceLegend}(${strings.etfChartUpLegend})',
                style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _candleIcon(down),
            const SizedBox(width: 4),
            Text(strings.etfChartDownLegend,
                style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 12,
              color: Colors.orange.shade400.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 4),
            Text(strings.etfChartNetLegend,
                style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ],
    );
  }

  Widget _candleIcon(Color color) {
    return SizedBox(
      width: 10,
      height: 14,
      child: CustomPaint(painter: _MiniCandlePainter(color: color)),
    );
  }
}

class _MiniCandlePainter extends CustomPainter {
  _MiniCandlePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      p,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.2, size.height * 0.25, size.width * 0.6,
          size.height * 0.5),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 上半：周K；下半：季报净申购柱（对齐到对应周）。
class _WeeklyKWithNetChart extends StatelessWidget {
  const _WeeklyKWithNetChart({
    required this.weekly,
    required this.quarters,
  });

  final List<StockBar> weekly;
  final List<EtfSharePoint> quarters;

  @override
  Widget build(BuildContext context) {
    final recentQ = quarters.length > 12
        ? quarters.sublist(quarters.length - 12)
        : quarters;
    final startDate = recentQ.first.date;
    final endDate = recentQ.last.date;

    // 覆盖季报区间的周K；过滤过严时回退到最近周K
    var weeks = weekly
        .where((b) =>
            b.open != null &&
            b.close != null &&
            b.high != null &&
            b.low != null &&
            b.tradeDate.compareTo(startDate) >= 0 &&
            b.tradeDate.compareTo(endDate) <= 0)
        .toList();
    if (weeks.length < 8) {
      weeks = weekly
          .where((b) =>
              b.open != null &&
              b.close != null &&
              b.high != null &&
              b.low != null)
          .toList();
      if (weeks.length > 120) {
        weeks = weeks.sublist(weeks.length - 120);
      }
    }
    if (weeks.isEmpty) {
      return Center(
        child: Text(
          '周K数据为空',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final netByWeek = <int, double>{};
    for (final q in recentQ) {
      final idx = _nearestWeekIndex(weeks, q.date);
      if (idx != null) {
        netByWeek[idx] = q.quarterNetShare ?? 0;
      }
    }

    return CustomPaint(
      painter: _ComboChartPainter(
        weeks: weeks,
        netByWeek: netByWeek,
        upColor: stockUpColor(context),
        downColor: stockDownColor(context),
        netColor: Colors.orange.shade500,
        axisColor: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
        labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      child: const SizedBox.expand(),
    );
  }
}

int? _nearestWeekIndex(List<StockBar> weeks, String date) {
  if (weeks.isEmpty) return null;
  var best = 0;
  var bestDiff = 1 << 30;
  final q = DateTime.tryParse(date);
  if (q == null) return null;
  for (var i = 0; i < weeks.length; i++) {
    final d = DateTime.tryParse(weeks[i].tradeDate);
    if (d == null) continue;
    final diff = (d.difference(q).inDays).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = i;
    }
  }
  return bestDiff <= 21 ? best : best;
}

class _ComboChartPainter extends CustomPainter {
  _ComboChartPainter({
    required this.weeks,
    required this.netByWeek,
    required this.upColor,
    required this.downColor,
    required this.netColor,
    required this.axisColor,
    required this.labelColor,
  });

  final List<StockBar> weeks;
  final Map<int, double> netByWeek;
  final Color upColor;
  final Color downColor;
  final Color netColor;
  final Color axisColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (weeks.isEmpty) return;

    const labelH = 22.0;
    const gap = 8.0;
    final chartH = size.height - labelH;
    final kH = chartH * 0.68;
    final netH = chartH * 0.32 - gap;
    final netTop = kH + gap;

    double minP = weeks.first.low!;
    double maxP = weeks.first.high!;
    for (final w in weeks) {
      if (w.low! < minP) minP = w.low!;
      if (w.high! > maxP) maxP = w.high!;
    }
    if ((maxP - minP).abs() < 1e-9) {
      minP -= 1;
      maxP += 1;
    } else {
      final pad = (maxP - minP) * 0.08;
      minP -= pad;
      maxP += pad;
    }

    var maxNet = 1.0;
    for (final v in netByWeek.values) {
      if (v.abs() > maxNet) maxNet = v.abs();
    }
    maxNet *= 1.15;

    final n = weeks.length;
    final slot = size.width / n;
    final bodyW = (slot * 0.55).clamp(2.0, 10.0);

    // 周K区底部分隔线
    final sep = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, kH), Offset(size.width, kH), sep);
    canvas.drawLine(Offset(0, netTop + netH / 2),
        Offset(size.width, netTop + netH / 2), sep);

    double yPrice(double p) => kH - ((p - minP) / (maxP - minP)) * kH;
    double yNet(double v) {
      final mid = netTop + netH / 2;
      return mid - (v / maxNet) * (netH / 2);
    }

    // 周K蜡烛
    for (var i = 0; i < n; i++) {
      final w = weeks[i];
      final x = slot * (i + 0.5);
      final up = w.close! >= w.open!;
      final color = up ? upColor : downColor;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1
        ..style = PaintingStyle.fill;

      final yH = yPrice(w.high!);
      final yL = yPrice(w.low!);
      final yO = yPrice(w.open!);
      final yC = yPrice(w.close!);

      canvas.drawLine(Offset(x, yH), Offset(x, yL), paint);
      final top = yO < yC ? yO : yC;
      final bottom = yO < yC ? yC : yO;
      final bodyH = (bottom - top).clamp(1.0, kH);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x, top + bodyH / 2),
          width: bodyW,
          height: bodyH,
        ),
        paint,
      );
    }

    // 净申购柱（对齐到季末附近周）
    final netPaint = Paint()..style = PaintingStyle.fill;
    for (final entry in netByWeek.entries) {
      final i = entry.key;
      if (i < 0 || i >= n) continue;
      final v = entry.value;
      final x = slot * (i + 0.5);
      final mid = netTop + netH / 2;
      final y = yNet(v);
      netPaint.color = v >= 0
          ? netColor.withValues(alpha: 0.85)
          : Colors.teal.shade400.withValues(alpha: 0.85);
      final top = v >= 0 ? y : mid;
      final h = (y - mid).abs().clamp(1.0, netH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - bodyW * 0.7, top, bodyW * 1.4, h),
          const Radius.circular(2),
        ),
        netPaint,
      );
    }

    // 底部日期标签（首、中、末 + 有净申购的周）
    final labelStyle = TextStyle(color: labelColor, fontSize: 9);
    final labelIndexes = <int>{0, n ~/ 2, n - 1, ...netByWeek.keys};
    for (final i in labelIndexes) {
      if (i < 0 || i >= n) continue;
      final d = weeks[i].tradeDate;
      final label = d.length >= 7 ? d.substring(2, 7) : d;
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = slot * (i + 0.5) - tp.width / 2;
      tp.paint(
        canvas,
        Offset(x.clamp(0, size.width - tp.width), size.height - labelH + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ComboChartPainter oldDelegate) {
    return oldDelegate.weeks != weeks || oldDelegate.netByWeek != netByWeek;
  }
}
