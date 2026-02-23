import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/base_device.dart';
import '../../core/device/device_manager.dart';
import '../../core/device/device_type.dart';
import '../../core/protocol/frame.dart';
import 'serial_tool_panel.dart';

/// Max BLE GAP device name length (align with firmware).
const int kDeviceNameMaxLen = 31;

class DeviceDetailScreen extends ConsumerStatefulWidget {
  const DeviceDetailScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
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
    final result = await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        sub?.cancel();
        return false;
      },
    );
    return result;
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
    await manager.send(Frame(
      type: FrameType.control,
      cmd: FrameCmd.setDeviceName,
      seq: seq,
      payload: payload,
    ));

    final ok = await _waitForAck(device, seq);
    if (!mounted) return;
    if (ok) {
      await manager.updateDeviceName(device.id, newName);
      if (mounted) {
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
    final state = ref.watch(deviceManagerProvider);
    final device = state.currentDevice;
    if (device == null || device.id != widget.deviceId) {
      return Scaffold(
        appBar: AppBar(title: const Text('设备面板')),
        body: const Center(child: Text('设备未连接')),
      );
    }

    final manager = ref.read(deviceManagerProvider.notifier);
    final displayName = manager.displayName(device);

    return Scaffold(
      appBar: AppBar(
        title: Text(displayName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: '修改设备名称',
            onPressed: () => _showRenameDialog(device),
          ),
        ],
      ),
      body: _buildPanelByType(context, ref, device.type),
    );
  }

  Widget _buildPanelByType(BuildContext context, WidgetRef ref, DeviceType type) {
    switch (type) {
      case DeviceType.ble:
        return const SingleChildScrollView(child: SerialToolPanel());
      case DeviceType.wifi:
      case DeviceType.gateway:
        return const Center(child: Text('该类型设备面板暂未实现'));
    }
  }
}

