import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/channel/device_channel.dart';
import 'ble_uuids.dart';

/// BLE implementation of DeviceChannel: Service 0xFE01, Characteristic 0xFF06 (Notify + Write).
/// Sends/receives full Frame binary; may split large payloads by MTU if needed.
class BleChannel implements DeviceChannel {
  BleChannel({required this.device});

  final BluetoothDevice device;

  BluetoothCharacteristic? _characteristic;
  StreamSubscription<List<int>>? _notifySubscription;
  final _dataController = StreamController<Uint8List>.broadcast();

  @override
  bool get isConnected => device.isConnected;

  @override
  Future<void> connect() async {
    if (!device.isConnected) {
      await device.connect(timeout: const Duration(seconds: 35), mtu: 512);
    }
    await _ensureCharacteristic();

    // 必须每次连接都挂上新的 notify 监听。仅当 !isNotifying 才 subscribe 时，
    // 重连后部分机型/OS 上 isNotifying 仍为 true，但旧订阅已随 disconnect 取消，
    // 会导致 RX 数据不进 _dataController，面板无显示而底层仍能收到通知。
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    if (!_characteristic!.isNotifying) {
      await _characteristic!.setNotifyValue(true);
    }
    _notifySubscription = _characteristic!.onValueReceived.listen((value) {
      _dataController.add(Uint8List.fromList(value));
    });
    device.cancelWhenDisconnected(_notifySubscription!);
  }

  static bool _uuidEquals(Guid a, Guid b) {
    return a.toString().toLowerCase() == b.toString().toLowerCase();
  }

  Future<void> _ensureCharacteristic() async {
    if (_characteristic != null) return;
    await device.discoverServices();
    for (final s in device.servicesList) {
      if (_uuidEquals(s.serviceUuid, BleUuids.serviceUuid)) {
        for (final c in s.characteristics) {
          if (_uuidEquals(c.characteristicUuid, BleUuids.characteristicUuid)) {
            _characteristic = c;
            return;
          }
        }
      }
    }
    // Debug: log what was actually discovered (device only exposes 1 service = likely GAP, not 0xFE01)
    final sb = StringBuffer();
    sb.writeln('BLE discoverServices: expected 0xFE01/0xFF06, got ${device.servicesList.length} service(s):');
    for (final s in device.servicesList) {
      sb.writeln('  service: ${s.serviceUuid}');
      for (final c in s.characteristics) {
        sb.writeln('    char: ${c.characteristicUuid}');
      }
    }
    debugPrint(sb.toString());
    throw StateError('Service 0xFE01 / Characteristic 0xFF06 not found. ${sb.toString().replaceAll('\n', ' ')}');
  }

  @override
  Future<void> disconnect() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    _characteristic = null;
    await device.disconnect();
  }

  @override
  Future<void> send(Uint8List data) async {
    if (!device.isConnected || _characteristic == null) {
      throw StateError('BleChannel not connected');
    }
    await _characteristic!.write(data.toList(), withoutResponse: false);
  }

  @override
  Stream<Uint8List> get onData => _dataController.stream;
}
