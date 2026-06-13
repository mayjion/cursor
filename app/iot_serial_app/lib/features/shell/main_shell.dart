import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_strings.dart';

class MainShell extends ConsumerWidget {
  const MainShell({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  static bool _isDevicePanelPath(String path) {
    return path == '/device' || path.startsWith('/device/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    // 使用当前导航的完整 path，避免 Shell 层 state 与叶子路由不一致时漏隐藏
    final routePath = GoRouterState.of(context).uri.path;
    final hideShellBottomBar = _isDevicePanelPath(routePath);
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: hideShellBottomBar
          ? null
          : BottomNavigationBar(
              currentIndex: navigationShell.currentIndex,
              onTap: (int index) {
                navigationShell.goBranch(index);
                switch (index) {
                  case 0:
                    context.go('/');
                    break;
                  case 1:
                    context.go('/groups');
                    break;
                  case 2:
                    context.go('/automation');
                    break;
                  case 3:
                    context.go('/settings');
                    break;
                }
              },
              type: BottomNavigationBarType.fixed,
              items: [
                BottomNavigationBarItem(
                  icon: const Icon(Icons.devices),
                  label: strings.navDevices,
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.group),
                  label: strings.navGroups,
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.auto_awesome),
                  label: strings.navAutomation,
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.settings),
                  label: strings.navSettings,
                ),
              ],
            ),
    );
  }
}
