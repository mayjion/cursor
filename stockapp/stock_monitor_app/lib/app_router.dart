import 'package:go_router/go_router.dart';

import 'features/settings/settings_screen.dart';
import 'features/shell/main_shell.dart';
import 'features/stats/stats_screen.dart';
import 'features/stock_detail/stock_detail_screen.dart';
import 'features/watchlist/watchlist_screen.dart';

final goRouter = GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          MainShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const WatchlistScreen(),
              routes: [
                GoRoute(
                  path: 'stock/:code',
                  builder: (context, state) {
                    final code = state.pathParameters['code']!;
                    return StockDetailScreen(code: code);
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          initialLocation: '/stats',
          routes: [
            GoRoute(
              path: '/stats',
              builder: (context, state) => const StatsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          initialLocation: '/settings',
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
