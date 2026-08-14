import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_strings.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static bool _hideBottomBar(String path) {
    return path.contains('/stock/') ||
        path.contains('/etf/') ||
        path.contains('/limitup');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final routePath = GoRouterState.of(context).uri.path;
    final hideBar = _hideBottomBar(routePath);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: hideBar
          ? null
          : NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: (index) {
                navigationShell.goBranch(index);
                switch (index) {
                  case 0:
                    context.go('/');
                    break;
                  case 1:
                    context.go('/insights');
                    break;
                  case 2:
                    context.go('/overview');
                    break;
                  case 3:
                    context.go('/watchlist');
                    break;
                  case 4:
                    context.go('/settings');
                    break;
                }
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.trending_down_outlined),
                  selectedIcon: const Icon(Icons.trending_down),
                  label: strings.navRecommendations,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.newspaper_outlined),
                  selectedIcon: const Icon(Icons.newspaper),
                  label: strings.navInsights,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.pie_chart_outline),
                  selectedIcon: const Icon(Icons.pie_chart),
                  label: strings.navOverview,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.star_outline),
                  selectedIcon: const Icon(Icons.star),
                  label: strings.navWatchlist,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings),
                  label: strings.navSettings,
                ),
              ],
            ),
    );
  }
}
