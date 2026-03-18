import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../protocol/frame.dart';
import '../storage/device_storage.dart';
import 'base_device.dart';

class DeviceManagerState {
  const DeviceManagerState({
    this.currentDevice,
    this.displayNames = const {},
  });

  final BaseDevice? currentDevice;
  final Map<String, String> displayNames;

  /// [currentDevice] 传 null 表示清空当前设备；不传参表示保留原值。
  /// 因 Dart 无法区分「未传参」与「传 null」，用 [clearCurrentDevice] 表示显式清空。
  DeviceManagerState copyWith({
    BaseDevice? currentDevice,
    bool clearCurrentDevice = false,
    Map<String, String>? displayNames,
  }) {
    return DeviceManagerState(
      currentDevice: clearCurrentDevice ? null : (currentDevice ?? this.currentDevice),
      displayNames: displayNames ?? this.displayNames,
    );
  }
}

class DeviceManagerNotifier extends StateNotifier<DeviceManagerState> {
  DeviceManagerNotifier() : super(const DeviceManagerState());

  int _seq = 0;
  int nextSeq() => _seq++;

  void setCurrentDevice(BaseDevice? device) async {
    if (device == null) {
      state = state.copyWith(clearCurrentDevice: true);
      return;
    }
    final entity = await DeviceStorage.get(device.id);
    final displayNames = Map<String, String>.from(state.displayNames);
    if (entity != null && entity.name.isNotEmpty) {
      displayNames[device.id] = entity.name;
    }
    state = state.copyWith(currentDevice: device, displayNames: displayNames);
  }

  /// 断开当前已连接设备并清空 currentDevice。同一时刻 APP 只能连接一个蓝牙设备，连接新设备前需先断开当前设备。
  Future<void> disconnectCurrentDevice() async {
    final device = state.currentDevice;
    if (device != null) {
      await device.disconnect();
    }
    state = state.copyWith(clearCurrentDevice: true);
  }

  Future<void> send(Frame frame) async {
    await state.currentDevice?.send(frame);
  }

  /// Update display name for a device (e.g. after CMD_SET_DEVICE_NAME ACK).
  /// Persists to DeviceStorage and updates UI.
  Future<void> updateDeviceName(String deviceId, String name) async {
    final entity = await DeviceStorage.get(deviceId);
    if (entity != null) {
      await DeviceStorage.save(entity.copyWith(name: name));
    }
    state = state.copyWith(
      displayNames: {...state.displayNames, deviceId: name},
    );
  }

  String displayName(BaseDevice device) {
    return state.displayNames[device.id] ?? device.name;
  }
}

final deviceManagerProvider =
    StateNotifierProvider<DeviceManagerNotifier, DeviceManagerState>((ref) {
  return DeviceManagerNotifier();
});

final currentDeviceProvider = Provider<BaseDevice?>((ref) {
  return ref.watch(deviceManagerProvider).currentDevice;
});
