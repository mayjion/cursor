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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
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
