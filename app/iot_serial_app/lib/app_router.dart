import 'package:go_router/go_router.dart';

import 'features/automation/automation_placeholder_screen.dart';
import 'features/device_detail/device_detail_screen.dart';
import 'features/device_list/ble_scan_screen.dart';
import 'features/device_list/device_list_screen.dart';
import 'features/groups/groups_placeholder_screen.dart';
import 'features/firmware/firmware_upgrade_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/main_shell.dart';

final goRouter = GoRouter(
  initialLocation: '/',
  debugLogDiagnostics: true,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          MainShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const DeviceListScreen(),
            ),
            GoRoute(
              path: '/scan',
              builder: (context, state) => const BleScanScreen(),
            ),
            GoRoute(
              path: '/device/:id',
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return DeviceDetailScreen(deviceId: id);
              },
            ),
          ],
        ),
        StatefulShellBranch(
          initialLocation: '/groups',
          routes: [
            GoRoute(
              path: '/groups',
              builder: (context, state) => const GroupsPlaceholderScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          initialLocation: '/automation',
          routes: [
            GoRoute(
              path: '/automation',
              builder: (context, state) => const AutomationPlaceholderScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          initialLocation: '/settings',
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'firmware',
                  builder: (context, state) => const FirmwareUpgradeScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
