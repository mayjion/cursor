import 'package:go_router/go_router.dart';

import 'features/etf_detail/etf_detail_screen.dart';
import 'features/etf_overview/etf_overview_screen.dart';
import 'features/insights/insights_screen.dart';
import 'features/recommendations/recommendations_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/main_shell.dart';
import 'features/stock_detail/stock_analysis_screen.dart';
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
              builder: (context, state) => const RecommendationsScreen(),
              routes: [
                GoRoute(
                  path: 'stock/:code',
                  builder: (context, state) {
                    final code = state.pathParameters['code']!;
                    return StockDetailScreen(code: code);
                  },
                  routes: [
                    GoRoute(
                      path: 'analysis',
                      builder: (context, state) {
                        final code = state.pathParameters['code']!;
                        return StockAnalysisScreen(code: code);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          initialLocation: '/insights',
          routes: [
            GoRoute(
              path: '/insights',
              builder: (context, state) => const InsightsScreen(),
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
          initialLocation: '/overview',
          routes: [
            GoRoute(
              path: '/overview',
              builder: (context, state) => const EtfOverviewScreen(),
              routes: [
                GoRoute(
                  path: 'etf/:code',
                  builder: (context, state) {
                    final code = state.pathParameters['code']!;
                    return EtfDetailScreen(code: code);
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          initialLocation: '/watchlist',
          routes: [
            GoRoute(
              path: '/watchlist',
              builder: (context, state) => const WatchlistScreen(),
              routes: [
                GoRoute(
                  path: 'stock/:code',
                  builder: (context, state) {
                    final code = state.pathParameters['code']!;
                    return StockDetailScreen(code: code);
                  },
                  routes: [
                    GoRoute(
                      path: 'analysis',
                      builder: (context, state) {
                        final code = state.pathParameters['code']!;
                        return StockAnalysisScreen(code: code);
                      },
                    ),
                  ],
                ),
                GoRoute(
                  path: 'etf/:code',
                  builder: (context, state) {
                    final code = state.pathParameters['code']!;
                    return EtfDetailScreen(code: code);
                  },
                ),
              ],
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
