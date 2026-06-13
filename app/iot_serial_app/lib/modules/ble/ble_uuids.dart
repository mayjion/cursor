import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BLE Service/Characteristic UUIDs aligned with firmware (0xFE01 / 0xFF06).
class BleUuids {
  static final Guid serviceUuid = Guid('0000fe01-0000-1000-8000-00805f9b34fb');
  static final Guid characteristicUuid = Guid('0000ff06-0000-1000-8000-00805f9b34fb');
}
