import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/device_detail/device_detail_screen.dart';

final goRouter = GoRouter(
  initialLocation: '/',
  debugLogDiagnostics: true,
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const _HomePlaceholder(),
    ),
    GoRoute(
      path: '/device/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return DeviceDetailScreen(deviceId: id);
      },
    ),
  ],
);

class _HomePlaceholder extends ConsumerWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('设备列表')),
      body: const Center(
        child: Text('设备列表占位：请从 BLE 扫描连接后进入设备详情'),
      ),
    );
  }
}
