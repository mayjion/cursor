import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/base_device.dart';
import '../../core/device/device_manager.dart';
import '../../core/storage/device_entity.dart';
import '../../core/storage/device_storage.dart';
import '../../core/protocol/frame.dart';
import '../../modules/ble/ble_device.dart';
import '../device_list/device_list_screen.dart';
import 'serial_tool_panel.dart';

/// Max BLE GAP device name length (align with firmware).
const int kDeviceNameMaxLen = 31;

enum _BleConnectState { none, connecting, success, failed }

class DeviceDetailScreen extends ConsumerStatefulWidget {
  const DeviceDetailScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  _BleConnectState _connectState = _BleConnectState.none;
  String? _connectError;
  bool _autoConnectStarted = false;

  @override
  void didUpdateWidget(covariant DeviceDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId) {
      _autoConnectStarted = false;
      _connectState = _BleConnectState.none;
      _connectError = null;
    }
  }

  Future<void> _tryBleConnect() async {
    try {
      final manager = ref.read(deviceManagerProvider.notifier);
      final oldDevice = ref.read(deviceManagerProvider).currentDevice;
      if (oldDevice != null && oldDevice.id != widget.deviceId) {
        // Don't await — old device may have stopped BLE (e.g. switched to ESP-NOW),
        // causing disconnect to block until OS-level timeout. Fire-and-forget with a safety timeout.
        manager.disconnectCurrentDevice().timeout(const Duration(seconds: 2)).catchError((_) {});
      }

      final device = BluetoothDevice.fromId(widget.deviceId);
      final bleDevice = BleDevice(bleDevice: device);
      await bleDevice.connect();
      if (!mounted) return;
      manager.setCurrentDevice(bleDevice);
      if (!mounted) return;
      setState(() {
        _connectState = _BleConnectState.success;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectState = _BleConnectState.failed;
        _connectError = e.toString();
      });
    }
  }

  void _startBleAutoConnect() {
    if (_autoConnectStarted) return;
    _autoConnectStarted = true;
    setState(() => _connectState = _BleConnectState.connecting);
    _tryBleConnect();
  }
  /// Subscribes for ACK with [seq] and returns a Future that completes when ACK is received or timeout.
  /// Call this before sending the frame so the ACK is not missed.
  Future<bool> _waitForAck(BaseDevice device, int seq) async {
    final completer = Completer<bool>();
    StreamSubscription? sub;
    sub = device.onFrame.listen((frame) {
      if (frame.type != FrameType.ack || frame.seq != seq) return;
      if (!completer.isCompleted) {
        final status = frame.payload.isNotEmpty ? frame.payload[0] : AckStatus.error;
        completer.complete(status == AckStatus.ok);
      }
      sub?.cancel();
    });
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        sub?.cancel();
        return false;
      },
    );
  }

  Future<void> _showRenameDialog(BaseDevice device) async {
    final manager = ref.read(deviceManagerProvider.notifier);
    final currentName = manager.displayName(device);
    final controller = TextEditingController(text: currentName);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: currentName.length,
    );

    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('修改设备名称'),
          content: TextField(
            controller: controller,
            maxLength: kDeviceNameMaxLen,
            decoration: const InputDecoration(
              hintText: '输入设备名称（1–31 字符）',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            onSubmitted: (v) => Navigator.of(context).pop(v.trim().isNotEmpty ? v.trim() : null),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final v = controller.text.trim();
                Navigator.of(context).pop(v.isNotEmpty ? v : null);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (newName == null || newName.isEmpty) return;

    final payload = Uint8List.fromList(utf8.encode(newName));
    if (payload.length > kDeviceNameMaxLen) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('名称过长，请不超过 31 字节')),
        );
      }
      return;
    }

    final seq = manager.nextSeq();
    final ackFuture = _waitForAck(device, seq);
    await manager.send(Frame(
      type: FrameType.control,
      cmd: FrameCmd.setDeviceName,
      seq: seq,
      payload: payload,
    ));
    final ok = await ackFuture;
    if (!mounted) return;
    if (ok) {
      await manager.updateDeviceName(device.id, newName);
      if (mounted) {
        ref.invalidate(deviceListProvider);
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('设备名称已更新')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('修改失败，请重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DeviceEntity?>(
      future: DeviceStorage.get(widget.deviceId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('设备面板')),
            body: snapshot.connectionState == ConnectionState.waiting
                ? const Center(child: CircularProgressIndicator())
                : const Center(child: Text('设备不存在')),
          );
        }
        final entity = snapshot.data!;
        final state = ref.watch(deviceManagerProvider);
        final device = state.currentDevice;
        final connected = device != null && device.id == widget.deviceId;
        final manager = ref.read(deviceManagerProvider.notifier);
        final displayName = connected
            ? manager.displayName(device)
            : entity.name;

        if (entity.type == 'ble' && !connected && !_autoConnectStarted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _startBleAutoConnect();
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(displayName),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                // Fire-and-forget: don't block navigation waiting for BLE disconnect
                // (device may have switched to ESP-NOW and BLE is already off).
                ref.read(deviceManagerProvider.notifier).disconnectCurrentDevice()
                    .timeout(const Duration(seconds: 2)).catchError((_) {});
                ref.invalidate(deviceListProvider);
                context.go('/');
              },
            ),
            actions: [
              if (connected)
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: '修改设备名称',
                  onPressed: () => _showRenameDialog(device),
                ),
            ],
          ),
          body: _buildBody(context, ref, entity, connected, device),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    DeviceEntity entity,
    bool connected,
    BaseDevice? device,
  ) {
    if (connected) {
      return _buildPanelByDeviceType(context, ref, entity.deviceType);
    }
    if (entity.type == 'ble') {
      if (_connectState == _BleConnectState.connecting ||
          _connectState == _BleConnectState.none) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在连接…'),
            ],
          ),
        );
      }
      if (_connectState == _BleConnectState.failed) {
        return _buildBleNotConnected(context, entity);
      }
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在连接…'),
          ],
        ),
      );
    }
    return _buildNotConnected(context, entity);
  }

  Widget _buildBleNotConnected(BuildContext context, DeviceEntity entity) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('设备未连接', style: TextStyle(fontSize: 16)),
            if (_connectError != null && _connectError!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '连接失败',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                _connectError!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _connectState = _BleConnectState.connecting;
                  _connectError = null;
                });
                _tryBleConnect();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/scan'),
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('扫描并连接'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotConnected(BuildContext context, DeviceEntity entity) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('设备未连接'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.push('/scan'),
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('扫描并连接'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelByDeviceType(BuildContext context, WidgetRef ref, String deviceType) {
    switch (deviceType) {
      case 'FUN-UART-C3':
      case 'FUN-UART': // 旧固件存盘兼容
        return const SerialToolPanel();
      default:
        return const Center(child: Text('该设备类型面板即将支持'));
    }
  }
}

