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
