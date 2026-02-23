import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/device_manager.dart';
import '../../core/protocol/frame.dart';
import '../../core/storage/device_entity.dart';
import '../../core/storage/device_storage.dart';
import '../../modules/ble/ble_device.dart';
import '../../modules/ble/ble_uuids.dart';

/// Status query ACK payload: [0]=status, [1]=ble, [2]=has_peer, [3..8]=WiFi MAC, [9]=work_mode,
/// [10]=device_type_len, [11..]=device_type UTF-8.
String _parseDeviceTypeFromStatusAck(Uint8List payload) {
  if (payload.length < 12) return DeviceEntity.defaultDeviceType;
  final len = payload[10];
  if (len <= 0 || 11 + len > payload.length) return DeviceEntity.defaultDeviceType;
  return utf8.decode(payload.sublist(11, 11 + len));
}

/// Parse WiFi MAC from status query ACK bytes [3..8]. Returns null if length < 9.
String? _parseWifiMacFromStatusAck(Uint8List payload) {
  if (payload.length < 9) return null;
  return '${payload[3].toRadixString(16).padLeft(2, '0')}:${payload[4].toRadixString(16).padLeft(2, '0')}:${payload[5].toRadixString(16).padLeft(2, '0')}:${payload[6].toRadixString(16).padLeft(2, '0')}:${payload[7].toRadixString(16).padLeft(2, '0')}:${payload[8].toRadixString(16).padLeft(2, '0')}';
}

class BleScanScreen extends ConsumerStatefulWidget {
  const BleScanScreen({super.key});

  @override
  ConsumerState<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends ConsumerState<BleScanScreen> {
  final Set<String> _seenIds = {};
  final List<ScanResult> _results = [];
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
      _results.clear();
      _seenIds.clear();
    });
    try {
      await FlutterBluePlus.startScan(
        withServices: [BleUuids.serviceUuid],
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      setState(() {
        _scanning = false;
        _error = e.toString();
      });
      return;
    }
    FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      for (final r in results) {
        final id = r.device.remoteId.toString();
        if (!_seenIds.contains(id)) {
          _seenIds.add(id);
          setState(() => _results.add(r));
        }
      }
    });
    await Future.delayed(const Duration(seconds: 15));
    if (mounted) {
      await FlutterBluePlus.stopScan();
      setState(() => _scanning = false);
    }
  }

  Future<void> _onDeviceTap(ScanResult scanResult) async {
    await FlutterBluePlus.stopScan();
    setState(() => _scanning = false);

    final device = scanResult.device;
    try {
      final bleDevice = BleDevice(bleDevice: device);
      await bleDevice.connect();

      String deviceType = DeviceEntity.defaultDeviceType;
      final manager = ref.read(deviceManagerProvider.notifier);
      manager.setCurrentDevice(bleDevice);
      final seq = manager.nextSeq();
      final ackCompleter = Completer<Uint8List?>();
      final sub = bleDevice.onFrame.listen((frame) {
        if (frame.type == FrameType.ack && frame.seq == seq && !ackCompleter.isCompleted) {
          ackCompleter.complete(frame.payload);
        }
      });
      await manager.send(Frame(
        type: FrameType.control,
        cmd: FrameCmd.statusQuery,
        seq: seq,
        payload: Uint8List(0),
      ));
      Uint8List? ack;
      try {
        ack = await ackCompleter.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () => null,
        );
      } finally {
        await sub.cancel();
      }
      String? wifiMac;
      if (ack != null && ack.isNotEmpty && ack.length >= 11) {
        final status = ack[0];
        if (status == AckStatus.ok) {
          deviceType = _parseDeviceTypeFromStatusAck(ack);
        }
        wifiMac = _parseWifiMacFromStatusAck(ack);
      }

      final name = device.platformName.isNotEmpty
          ? device.platformName
          : (device.advName.isNotEmpty ? device.advName : device.remoteId.toString());
      final entity = DeviceEntity(
        id: device.remoteId.toString(),
        type: 'ble',
        deviceType: deviceType,
        name: name,
        wifiMac: wifiMac,
      );
      await DeviceStorage.save(entity);

      if (!mounted) return;
      context.go('/device/${entity.id}');
      context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加 BLE 设备'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新扫描',
              onPressed: _startScan,
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _startScan,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          : _results.isEmpty && !_scanning
              ? const Center(child: Text('未发现设备，请确保设备已开机且可被发现'))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final r = _results[index];
                    final name = r.device.platformName.isNotEmpty
                        ? r.device.platformName
                        : (r.device.advName.isNotEmpty ? r.device.advName : r.device.remoteId.toString());
                    return ListTile(
                      leading: const Icon(Icons.bluetooth),
                      title: Text(name),
                      subtitle: Text(r.device.remoteId.toString()),
                      onTap: () => _onDeviceTap(r),
                    );
                  },
                ),
    );
  }
}
