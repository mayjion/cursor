import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/device_manager.dart';
import '../../core/storage/device_entity.dart';
import '../../core/storage/device_storage.dart';
import '../../modules/ble/ble_device.dart';
import 'device_card.dart';

/// 设备列表数据；从详情返回时需 invalidate 以刷新列表。
final deviceListProvider = FutureProvider<List<DeviceEntity>>((ref) async {
  return DeviceStorage.list();
});

class DeviceListScreen extends ConsumerStatefulWidget {
  const DeviceListScreen({super.key});

  @override
  ConsumerState<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends ConsumerState<DeviceListScreen> {
  /// 正在连接中的设备 id，用于在卡片上显示加载并防止重复点击
  String? _connectingDeviceId;

  Future<void> _connectToDevice(DeviceEntity entity) async {
    final notifier = ref.read(deviceManagerProvider.notifier);
    final currentDevice = ref.read(deviceManagerProvider).currentDevice;
    if (currentDevice?.id == entity.id) return;
    setState(() => _connectingDeviceId = entity.id);
    try {
      if (currentDevice != null) {
        await notifier.disconnectCurrentDevice();
        if (!mounted) return;
      }
      final device = BluetoothDevice.fromId(entity.id);
      final bleDevice = BleDevice(bleDevice: device);
      await bleDevice.connect();
      if (!mounted) return;
      notifier.setCurrentDevice(bleDevice);
      if (!mounted) return;
      context.go('/device/${entity.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _connectingDeviceId = null);
    }
  }

  Future<void> _disconnectCurrent() async {
    await ref.read(deviceManagerProvider.notifier).disconnectCurrentDevice();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已断开蓝牙连接')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(deviceListProvider);
    final managerState = ref.watch(deviceManagerProvider);
    final currentDevice = managerState.currentDevice;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设备'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加设备',
            onPressed: () => context.push('/scan'),
          ),
        ],
      ),
      body: asyncList.when(
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.devices_other, size: 64, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    '暂无设备',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => context.push('/scan'),
                    icon: const Icon(Icons.add),
                    label: const Text('添加 BLE 设备'),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(deviceListProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final entity = list[index];
                final displayName = managerState.displayNames[entity.id] ?? entity.name;
                final isBle = entity.type == 'ble';
                final isConnected = currentDevice?.id == entity.id;
                final isConnecting = _connectingDeviceId == entity.id;
                return DeviceCard(
                  entity: entity,
                  displayName: displayName,
                  isConnected: isConnected,
                  isConnecting: isConnecting,
                  onConnect: isBle ? () => _connectToDevice(entity) : null,
                  onDisconnect: isBle ? _disconnectCurrent : null,
                  onDelete: () async {
                    await DeviceStorage.delete(entity.id);
                    final notifier = ref.read(deviceManagerProvider.notifier);
                    if (ref.read(deviceManagerProvider).currentDevice?.id == entity.id) {
                      notifier.setCurrentDevice(null);
                    }
                    ref.invalidate(deviceListProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已删除设备')),
                      );
                    }
                  },
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载失败: $err', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(deviceListProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
