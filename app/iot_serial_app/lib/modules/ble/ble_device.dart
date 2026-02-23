import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/device/base_device.dart';
import '../../core/device/device_type.dart';
import 'ble_channel.dart';

/// BLE device: id from remoteId, name from platform/adv, channel BleChannel.
class BleDevice extends BaseDevice {
  BleDevice({required this.bleDevice})
      : _channel = BleChannel(device: bleDevice),
        super();

  final BluetoothDevice bleDevice;

  final BleChannel _channel;

  @override
  String get id => bleDevice.remoteId.toString();

  @override
  String get name =>
      bleDevice.platformName.isNotEmpty
          ? bleDevice.platformName
          : (bleDevice.advName.isNotEmpty ? bleDevice.advName : id);

  @override
  DeviceType get type => DeviceType.ble;

  @override
  BleChannel get channel => _channel;
}
