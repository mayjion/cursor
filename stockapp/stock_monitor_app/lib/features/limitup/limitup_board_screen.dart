import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/server_providers.dart';

class LimitupBoardScreen extends ConsumerWidget {
  const LimitupBoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(serverConnectionProvider);
    final asyncBoard = ref.watch(serverLimitupBoardProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('涨停观察榜'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新缓存',
            onPressed: conn.connected
                ? () => ref.invalidate(serverLimitupBoardProvider)
                : null,
          ),
        ],
      ),
      body: !conn.connected
          ? const Center(child: Text('请先在设置中连接 stockserver'))
          : asyncBoard.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$e', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            ref.invalidate(serverLimitupBoardProvider),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (payload) {
                if (payload == null) {
                  return const Center(child: Text('暂无数据'));
                }
                final focus = _rows(payload['focus']);
                final watch = _rows(payload['watch']);
                final cfg = payload['cfg'] is Map
                    ? Map<String, dynamic>.from(payload['cfg'] as Map)
                    : <String, dynamic>{};
                final updated = '${payload['updated_at'] ?? ''}';
                final target =
                    ((cfg['target_ret'] as num?)?.toDouble() ?? 0.10) * 100;
                final floor =
                    ((cfg['floor_ret'] as num?)?.toDouble() ?? 0.08) * 100;

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(serverLimitupBoardProvider);
                    await ref.read(serverLimitupBoardProvider.future);
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '次日最低价买入 · ${cfg['forward_days'] ?? 10}日最高价'
                                '目标≥${target.toStringAsFixed(0)}%'
                                '（底线${floor.toStringAsFixed(0)}%）',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '市值>${cfg['min_market_cap_yi'] ?? 100}亿 · '
                                '观察池主力/市值≥${_pct(cfg['watch_flow_to_mcap'], 0.5)} · '
                                '重点池≥${_pct(cfg['focus_flow_to_mcap'], 0.8)}'
                                '${updated.isEmpty ? '' : '\n更新 $updated'}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionTitle(context, '重点池', focus.length),
                      if (focus.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('暂无重点池标的'),
                        )
                      else
                        ...focus.map((r) => _tile(context, r, focusPool: true)),
                      const SizedBox(height: 16),
                      _sectionTitle(context, '观察池', watch.length),
                      if (watch.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('暂无观察池标的'),
                        )
                      else
                        ...watch.map((r) => _tile(context, r, focusPool: false)),
                    ],
                  ),
                );
              },
            ),
    );
  }

  static String _pct(dynamic v, double fallback) {
    final n = (v as num?)?.toDouble() ?? (fallback / 100);
    return '${(n * 100).toStringAsFixed(1)}%';
  }

  static List<Map<String, dynamic>> _rows(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Widget _sectionTitle(BuildContext context, String title, int n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        '$title（$n）',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  static Widget _tile(
    BuildContext context,
    Map<String, dynamic> row, {
    required bool focusPool,
  }) {
    final code = '${row['code'] ?? ''}'.padLeft(6, '0');
    final name = '${row['name'] ?? code}';
    final chg = (row['signal_chg'] as num?)?.toDouble();
    final flow = (row['flow_to_mcap'] as num?)?.toDouble();
    final vol = (row['vol_ma_ratio'] as num?)?.toDouble();
    final score = (row['score'] as num?)?.toDouble();
    final date = '${row['signal_date'] ?? ''}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: focusPool
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(
            focusPool ? '重' : '观',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        title: Text('$name  $code'),
        subtitle: Text(
          [
            if (date.isNotEmpty) date,
            if (chg != null) '涨停 ${chg.toStringAsFixed(1)}%',
            if (flow != null) '主力/市值 ${(flow * 100).toStringAsFixed(2)}%',
            if (vol != null) '放量 ${vol.toStringAsFixed(2)}',
            if (score != null) '分 ${score.toStringAsFixed(0)}',
          ].join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/stock/$code/analysis'),
      ),
    );
  }
}
