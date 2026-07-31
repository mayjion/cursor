import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/recommendation.dart';
import '../../core/providers/investment_providers.dart';
import '../../core/settings/app_strings.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final digestAsync = ref.watch(todayDigestProvider);
    final industriesAsync = ref.watch(industriesProvider);
    final newsAsync = ref.watch(marketNewsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.insightsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: strings.refreshNews,
            onPressed: () => refreshMarketNews(ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => refreshMarketNews(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          children: [
            digestAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('${strings.apiError}: $e'),
              data: (digest) => _DigestCard(digest: digest, strings: strings),
            ),
            const SizedBox(height: 16),
            Text(strings.industrySection,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            industriesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('$e'),
              data: (items) {
                if (items.isEmpty) {
                  return Text(strings.noData);
                }
                return Card(
                  child: Column(
                    children: items.take(10).map((ind) {
                      final chg = ind.changePercent;
                      final color = chg == null
                          ? null
                          : chg >= 0
                              ? Colors.red
                              : Colors.green;
                      return ListTile(
                        title: Text(ind.industry),
                        trailing: Text(
                          chg != null ? '${chg >= 0 ? '+' : ''}${chg.toStringAsFixed(2)}%' : '-',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onTap: () {},
                      );
                    }).toList(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(strings.newsSection,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            newsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('$e'),
              data: (news) {
                if (news.isEmpty) {
                  return Text(strings.noData);
                }
                return Column(
                  children: news.take(20).map((article) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(article.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${article.source}${article.publishedAt != null ? ' · ${article.publishedAt}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: article.stockCode != null
                            ? () => context.push('/stock/${article.stockCode}')
                            : null,
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DigestCard extends StatelessWidget {
  const _DigestCard({required this.digest, required this.strings});

  final DailyDigest digest;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.newspaper, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(strings.dailyDigest,
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(digest.marketSummary),
            if (digest.keyEvents.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(strings.keyEvents,
                  style: Theme.of(context).textTheme.labelLarge),
              ...digest.keyEvents.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(e.toString())),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
