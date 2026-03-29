import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings.dart';

/// Simple string lookup for zh/en. Use [AppStrings.of(context)] or [ref.watch(appStringsProvider)].
class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;
  bool get isZh => locale.languageCode == 'zh';

  // Shell
  String get navDevices => isZh ? '设备' : 'Devices';
  String get navGroups => isZh ? '群组' : 'Groups';
  String get navAutomation => isZh ? '自动化' : 'Automation';
  String get navSettings => isZh ? '设置' : 'Settings';

  // Settings screen
  String get settingsTitle => isZh ? '设置' : 'Settings';
  String get themeSection => isZh ? '主题' : 'Theme';
  String get themeBlue => isZh ? '蓝色' : 'Blue';
  String get themeGreen => isZh ? '绿色' : 'Green';
  String get themePurple => isZh ? '紫色' : 'Purple';
  String get languageSection => isZh ? '语言' : 'Language';
  String get languageZh => '中文';
  String get languageEn => 'English';
  String get about => isZh ? '关于' : 'About';
  String get aboutSubtitle => 'IoT Serial App';
  String get bluetoothPermission => isZh ? '蓝牙权限说明' : 'Bluetooth permission';
  String get bluetoothPermissionSubtitle =>
      isZh ? '扫描与连接设备需要蓝牙权限' : 'Bluetooth permission is required for scan and connect';

  String get serialRxBufferSection => isZh ? '串口接收缓冲区' : 'Serial receive buffer';
  String get serialRxBufferSubtitle => isZh
      ? '超出上限时丢弃最旧数据（1–10 MB）'
      : 'Oldest data is dropped when over limit (1–10 MB)';
  String serialRxBufferValueLabel(int mb) =>
      isZh ? '上限 $mb MB' : 'Limit $mb MB';

  // Firmware OTA (FUN AP @ 192.168.4.1)
  String get settingsFirmwareUpgrade => isZh ? '固件升级' : 'Firmware upgrade';
  String get settingsFirmwareUpgradeSubtitle => isZh
      ? '连接 FUN* 热点后对设备 OTA'
      : 'OTA when connected to FUN* AP';

  String get firmwareTitle => isZh ? '固件升级' : 'Firmware upgrade';
  String get firmwareIntro => isZh
      ? '请先连接设备热点（SSID 以 FUN 开头，网关多为 192.168.4.1），再拉取设备信息并选择内置固件上传。'
      : 'Connect to the device AP (SSID starts with FUN, gateway usually 192.168.4.1), fetch info, then pick a bundled firmware.';

  String get firmwareNetworkSection => isZh ? '当前网络' : 'Network';
  String get firmwareSsidLabel => isZh ? 'WiFi：' : 'WiFi: ';
  String get firmwareGatewayLabel => isZh ? '网关：' : 'Gateway: ';
  String get firmwareUnknown => isZh ? '未知' : 'Unknown';
  String get firmwareEnvWarning => isZh
      ? '未满足条件：请连接设备 FUN* 热点，并确认网关为 192.168.4.1（若无法读取网关，仍可尝试「读取设备信息」）。'
      : 'Expected FUN* SSID and gateway 192.168.4.1 (if gateway is unknown, you may still try Probe).';
  String get firmwareEnvOk =>
      isZh ? '网络条件符合，可读取设备信息。' : 'Network looks good; you can probe the device.';

  String get firmwareProbeButton => isZh ? '读取设备信息' : 'Read device info';
  String get firmwareParseError =>
      isZh ? '无法从网页解析产品型号，请确认已打开设备配置页。' : 'Could not parse product from HTML.';
  String get firmwareDeviceSection => isZh ? '当前设备' : 'Device';
  String get firmwareProductLabel => isZh ? '产品：' : 'Product: ';
  String get firmwareVersionLabel => isZh ? '版本：' : 'Version: ';
  String get firmwareChipLabel => isZh ? '芯片：' : 'Chip: ';
  String get firmwareChipC3 => 'ESP32-C3';
  String get firmwareChipS2 => 'ESP32-S2';
  String get firmwareChipS3 => 'ESP32-S3';

  String get firmwarePickFirmware => isZh ? '可选固件（同芯片）' : 'Compatible firmware';
  String get firmwareStartUpload => isZh ? '上传到设备' : 'Upload to device';

  String get firmwareConfirmTitle => isZh ? '确认升级' : 'Confirm upgrade';
  String firmwareConfirmBody(String name) => isZh
      ? '将把「$name」写入设备并重启。错刷固件可能损坏设备，请确认芯片与产品匹配。'
      : 'Flash「$name」and reboot. Wrong image may brick the device.';
  String get firmwareCancel => isZh ? '取消' : 'Cancel';
  String get firmwareConfirmUpload => isZh ? '上传' : 'Upload';

  String get firmwareUploading => isZh ? '正在上传…' : 'Uploading…';
  String get firmwarePlaceholderError =>
      isZh ? '内置固件过小或未替换：请将 ota_dist 编译的 .bin 放入 assets/firmware/'
          : 'Bundled firmware too small: copy real .bin from ota_dist to assets/firmware/';
  String get firmwareUploadDone => isZh ? '上传完成' : 'Upload finished';
  String get firmwareUploadFailed => isZh ? '上传失败' : 'Upload failed';
  String get firmwareSuccessReboot =>
      isZh ? '设备将重启并完成 OTA，请稍候重新连接。' : 'Device will reboot; reconnect shortly.';
}

final appStringsProvider = Provider<AppStrings>((ref) {
  final state = ref.watch(appSettingsProvider);
  return AppStrings(state.locale);
});

extension AppStringsContext on BuildContext {
  AppStrings get appStrings {
    final locale = Localizations.localeOf(this);
    return AppStrings(locale);
  }
}
