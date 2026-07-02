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
      ? '连接 FUN* / FUNLIGHT 热点后对设备 OTA'
      : 'OTA when connected to FUN* / FUNLIGHT AP';

  String get firmwareTitle => isZh ? '固件升级' : 'Firmware upgrade';
  String get firmwareIntro => isZh
      ? '请先连接设备热点（FUN 系列或烧录器 FUNLIGHT，网关多为 192.168.4.1），再读取设备信息并选择内置固件上传。'
      : 'Connect to the device AP (FUN series or flasher FUNLIGHT, gateway usually 192.168.4.1), fetch info, then upload.';
  String get firmwareEspFlasherHint => isZh
      ? '烧录器：上电 10 秒内双击按键进入升级模式（全部 LED 亮），WiFi FUNLIGHT / funlight。硬件型号 ESPFLASHER_V4/V16 或 PYFLASHER_V4/V16（同 Flash 变体可交叉升级）。'
      : 'Flasher: double-click within 10s after boot (all LEDs on). WiFi FUNLIGHT / funlight. Models ESPFLASHER_V4/V16 or PYFLASHER_V4/V16 (cross-flash within same flash variant).';

  String get firmwareNetworkSection => isZh ? '当前网络' : 'Network';
  String get firmwareSsidLabel => isZh ? 'WiFi：' : 'WiFi: ';
  String get firmwareGatewayLabel => isZh ? '网关：' : 'Gateway: ';
  String get firmwareUnknown => isZh ? '未知' : 'Unknown';
  String get firmwareEnvWarning => isZh
      ? '未满足条件：请连接设备 FUN* / FUNLIGHT 热点，并确认网关为 192.168.4.1（若无法读取网关，仍可尝试「读取设备信息」）。'
      : 'Expected FUN* / FUNLIGHT SSID and gateway 192.168.4.1 (if gateway is unknown, you may still try Probe).';
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

  String get firmwareVariantLabel => isZh ? '变体：' : 'Variant: ';
  String get firmwarePickFirmwareBurner => isZh
      ? '可选固件（须同 Flash 变体；ESP ↔ PY 可交叉升级）'
      : 'Firmware (same flash variant; ESP ↔ PY cross-flash OK)';
  String get firmwareBurnerMismatch => isZh
      ? '所选固件与设备 Flash 变体不匹配（V4 与 V16 不可互刷）'
      : 'Selected firmware does not match flash variant (V4/V16 not interchangeable)';
  String get firmwareTriDtuMismatch => isZh
      ? '所选固件与设备 Flash 变体不匹配（N4 与 N16R8 不可互刷）'
      : 'Selected firmware does not match flash variant (N4/N16R8 not interchangeable)';

  String firmwareConfirmBodyCrossFamily(String fromProduct, String toName) => isZh
      ? '将把设备从 $fromProduct 切换为「$toName」。ESP 与 PY 烧录器共用分区，离线项目数据可能失效，请确认。'
      : 'Switch device from $fromProduct to「$toName」. ESP and PY flashers share partitions; offline projects may be invalid. Continue?';

  String get firmwarePickFirmware => isZh ? '可选固件（同芯片）' : 'Compatible firmware';
  String get firmwareStartUpload => isZh ? '上传到设备' : 'Upload to device';

  String get firmwareConfirmTitle => isZh ? '确认升级' : 'Confirm upgrade';
  String firmwareConfirmBody(String name) => isZh
      ? '将把「$name」写入设备并重启。错刷固件可能损坏设备，请确认芯片与产品匹配。'
      : 'Flash「$name」and reboot. Wrong image may brick the device.';
  String get firmwareCancel => isZh ? '取消' : 'Cancel';
  String get firmwareConfirmUpload => isZh ? '上传' : 'Upload';

  String get firmwareUploading => isZh ? '正在上传…' : 'Uploading…';
  String get firmwareUploadingDevice =>
      isZh ? '上传完成，正在等待设备写入 Flash…' : 'Upload sent; waiting for device to write flash…';
  String get firmwarePlaceholderError =>
      isZh ? '内置固件过小或未放入 assets/firmware/ 对应 .bin'
          : 'Bundled firmware too small or missing .bin in assets/firmware/';
  String get firmwareUploadDone => isZh ? '升级完成，设备将重启' : 'Upgrade complete; device rebooting';
  String get firmwareUploadFailed => isZh ? '上传失败' : 'Upload failed';
  String get firmwareUploadTimeoutHint => isZh
      ? '等待设备完成 OTA 超时。请重新连接 FUNLIGHT 后读取版本确认是否已成功。'
      : 'Timed out waiting for the device to finish OTA. Reconnect to FUNLIGHT and verify the version.';
  String get firmwareSuccessReboot =>
      isZh ? '设备正在重启，请稍候重新连接 FUNLIGHT 并读取版本确认。' : 'Device is rebooting; reconnect to FUNLIGHT and verify the version.';

  // Remote firmware OTA (Gitee manifest)
  String get firmwareCheckUpdate => isZh ? '检查更新' : 'Check update';
  String get firmwareCheckingUpdate => isZh ? '正在检查远程固件…' : 'Checking remote firmware…';
  String get firmwareNoRemoteUpdate =>
      isZh ? '远程仓库无新版本（或无法连接网络）。' : 'No newer remote firmware (or network unavailable).';
  String get firmwareRemoteUpdateTitle => isZh ? '发现远程固件更新' : 'Remote firmware update';
  String firmwareRemoteUpdateBody(String current, String remote) => isZh
      ? '设备版本 $current，远程仓库版本 $remote。下载后可用于 OTA 升级。'
      : 'Device $current, remote $remote. Download to use for OTA.';
  String get firmwareDownloadFirmware => isZh ? '下载固件' : 'Download firmware';
  String get firmwareDownloading => isZh ? '正在下载固件…' : 'Downloading firmware…';
  String firmwareDownloadProgress(int pct) =>
      isZh ? '下载进度 $pct%' : 'Download $pct%';
  String get firmwareDownloadDone => isZh ? '固件已下载到本地' : 'Firmware saved locally';
  String get firmwareDownloadFailed => isZh ? '固件下载失败' : 'Firmware download failed';
  String get firmwareChecksumFailed => isZh ? '固件校验失败' : 'Firmware checksum failed';
  String get firmwareUseRemoteFirmware => isZh ? '将使用已下载的远程固件' : 'Using downloaded remote firmware';
  String get firmwareRemoteNetworkHint => isZh
      ? '下载远程固件需要互联网。连接设备热点时请开启移动数据，或使用双网卡。'
      : 'Downloading requires internet. On device AP, enable cellular or use dual network.';
  String get firmwareRemoteNetworkError => isZh
      ? '无法连接远程服务器。请开启移动数据；若已连设备热点，请同时开启移动数据或使用双网卡。'
      : 'Cannot reach remote server. Enable cellular; if on device AP, use cellular or dual network.';
  String get firmwareRemoteTokenRequired => isZh
      ? '远程 OTA 需要 Gitee Token。请配置 firmware_gitee_token.txt 后重新打包 APK。'
      : 'Remote OTA requires a Gitee token. Configure firmware_gitee_token.txt and rebuild the APK.';
  String get firmwareRemoteTokenInvalid => isZh
      ? 'Gitee Token 无效或已过期。请在 Gitee 重新生成令牌并更新 firmware_gitee_token.txt 后重打 APK。'
      : 'Gitee token invalid or expired. Regenerate the token, update firmware_gitee_token.txt, and rebuild.';
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
