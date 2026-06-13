import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/device_entity.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.entity,
    required this.displayName,
    this.isConnected = false,
    this.isConnecting = false,
    this.onConnect,
    this.onDisconnect,
    this.onDelete,
  });

  final DeviceEntity entity;
  final String displayName;
  /// 是否为当前已连接的蓝牙设备（仅 BLE 设备在列表右侧显示连接/断开）
  final bool isConnected;
  /// 是否正在连接该设备（显示加载中，禁用连接按钮）
  final bool isConnecting;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;
  final VoidCallback? onDelete;

  IconData _iconForConnectionType(String type) {
    switch (type) {
      case 'wifi':
        return Icons.wifi;
      case 'gateway':
        return Icons.hub;
      default:
        return Icons.bluetooth;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: () {
          // 非 BLE 设备直接进入面板；BLE 设备仅在已连接时进入，否则提示先连接
          if (entity.type != 'ble' || isConnected) {
            context.go('/device/${entity.id}');
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('请先点击右侧“连接”按钮连接设备')),
            );
          }
        },
        onLongPress: () => _showLongPressMenu(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                _iconForConnectionType(entity.type),
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entity.deviceType,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (entity.type == 'ble')
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _buildBleAction(context),
                )
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBleAction(BuildContext context) {
    if (isConnecting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (isConnected) {
      return TextButton(
        onPressed: onDisconnect,
        child: const Text('断开'),
      );
    }
    return TextButton(
      onPressed: onConnect,
      child: const Text('连接'),
    );
  }

  void _showLongPressMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除设备'),
              onTap: () {
                Navigator.of(context).pop();
                onDelete?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}
