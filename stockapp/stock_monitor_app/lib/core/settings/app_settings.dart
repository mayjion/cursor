import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsState {
  const AppSettingsState({
    this.themeIndex = 0,
    this.languageCode = 'zh',
    this.notifyEnabled = true,
    this.reversalNotifyEnabled = true,
    this.recommendationNotifyEnabled = true,
    this.recommendationLimit = 15,
    this.excludeStarMarket = true,
    this.marketCapFilter = 'all',
    this.nightScanEnabled = false,
    this.scanHour = 2,
    this.scanMinute = 0,
    this.batteryGuideShown = false,
    this.serverEnabled = true,
    this.serverHost = '',
    this.serverPort = 8787,
    this.ready = false,
  });

  final int themeIndex;
  final String languageCode;
  final bool notifyEnabled;
  final bool reversalNotifyEnabled;
  final bool recommendationNotifyEnabled;
  final int recommendationLimit;
  final bool excludeStarMarket;
  final String marketCapFilter;
  final bool nightScanEnabled;
  final int scanHour;
  final int scanMinute;
  final bool batteryGuideShown;
  /// 是否优先使用局域网 stockserver
  final bool serverEnabled;
  final String serverHost;
  final int serverPort;
  final bool ready;

  Locale get locale =>
      languageCode == 'en' ? const Locale('en') : const Locale('zh');

  String? get serverBaseUrl {
    final host = serverHost.trim();
    if (host.isEmpty) return null;
    return 'http://$host:$serverPort';
  }

  AppSettingsState copyWith({
    int? themeIndex,
    String? languageCode,
    bool? notifyEnabled,
    bool? reversalNotifyEnabled,
    bool? recommendationNotifyEnabled,
    int? recommendationLimit,
    bool? excludeStarMarket,
    String? marketCapFilter,
    bool? nightScanEnabled,
    int? scanHour,
    int? scanMinute,
    bool? batteryGuideShown,
    bool? serverEnabled,
    String? serverHost,
    int? serverPort,
    bool? ready,
  }) {
    return AppSettingsState(
      themeIndex: themeIndex ?? this.themeIndex,
      languageCode: languageCode ?? this.languageCode,
      notifyEnabled: notifyEnabled ?? this.notifyEnabled,
      reversalNotifyEnabled:
          reversalNotifyEnabled ?? this.reversalNotifyEnabled,
      recommendationNotifyEnabled:
          recommendationNotifyEnabled ?? this.recommendationNotifyEnabled,
      recommendationLimit: recommendationLimit ?? this.recommendationLimit,
      excludeStarMarket: excludeStarMarket ?? this.excludeStarMarket,
      marketCapFilter: marketCapFilter ?? this.marketCapFilter,
      nightScanEnabled: nightScanEnabled ?? this.nightScanEnabled,
      scanHour: scanHour ?? this.scanHour,
      scanMinute: scanMinute ?? this.scanMinute,
      batteryGuideShown: batteryGuideShown ?? this.batteryGuideShown,
      serverEnabled: serverEnabled ?? this.serverEnabled,
      serverHost: serverHost ?? this.serverHost,
      serverPort: serverPort ?? this.serverPort,
      ready: ready ?? this.ready,
    );
  }
}

class AppSettingsNotifier extends StateNotifier<AppSettingsState> {
  AppSettingsNotifier() : super(const AppSettingsState()) {
    _load();
  }

  static SharedPreferences? _prefs;

  Future<void> _load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final themeIndex = _prefs!.getInt('theme_index') ?? 0;
    final languageCode = _prefs!.getString('language_code') ?? 'zh';
    final notifyEnabled = _prefs!.getBool('notify_enabled') ?? true;
    final reversalNotifyEnabled =
        _prefs!.getBool('reversal_notify_enabled') ?? true;
    final recommendationNotifyEnabled =
        _prefs!.getBool('recommendation_notify_enabled') ?? true;
    final recommendationLimit = _prefs!.getInt('recommendation_limit') ?? 15;
    final excludeStarMarket = _prefs!.getBool('exclude_star_market') ?? true;
    final marketCapFilter = _prefs!.getString('market_cap_filter') ?? 'all';
    final nightScanEnabled = _prefs!.getBool('night_scan_enabled') ?? false;
    final scanHour = _prefs!.getInt('scan_hour') ?? 2;
    final scanMinute = _prefs!.getInt('scan_minute') ?? 0;
    final batteryGuideShown = _prefs!.getBool('battery_guide_shown') ?? false;
    final serverEnabled = _prefs!.getBool('server_enabled') ?? true;
    final serverHost = _prefs!.getString('server_host') ?? '';
    final serverPort = _prefs!.getInt('server_port') ?? 8787;
    state = AppSettingsState(
      themeIndex: themeIndex.clamp(0, 2),
      languageCode: languageCode == 'en' ? 'en' : 'zh',
      notifyEnabled: notifyEnabled,
      reversalNotifyEnabled: reversalNotifyEnabled,
      recommendationNotifyEnabled: recommendationNotifyEnabled,
      recommendationLimit: recommendationLimit.clamp(5, 20),
      excludeStarMarket: excludeStarMarket,
      marketCapFilter: marketCapFilter,
      nightScanEnabled: nightScanEnabled,
      scanHour: scanHour.clamp(0, 23),
      scanMinute: scanMinute.clamp(0, 59),
      batteryGuideShown: batteryGuideShown,
      serverEnabled: serverEnabled,
      serverHost: serverHost,
      serverPort: serverPort.clamp(1, 65535),
      ready: true,
    );
  }

  Future<void> setThemeIndex(int index) async {
    final clamped = index.clamp(0, 2);
    state = state.copyWith(themeIndex: clamped);
    await _prefs?.setInt('theme_index', clamped);
  }

  Future<void> setLanguageCode(String code) async {
    final value = code == 'en' ? 'en' : 'zh';
    state = state.copyWith(languageCode: value);
    await _prefs?.setString('language_code', value);
  }

  Future<void> setNotifyEnabled(bool enabled) async {
    state = state.copyWith(notifyEnabled: enabled);
    await _prefs?.setBool('notify_enabled', enabled);
  }

  Future<void> setReversalNotifyEnabled(bool enabled) async {
    state = state.copyWith(reversalNotifyEnabled: enabled);
    await _prefs?.setBool('reversal_notify_enabled', enabled);
  }

  Future<void> setRecommendationNotifyEnabled(bool enabled) async {
    state = state.copyWith(recommendationNotifyEnabled: enabled);
    await _prefs?.setBool('recommendation_notify_enabled', enabled);
  }

  Future<void> setRecommendationLimit(int limit) async {
    final clamped = limit.clamp(5, 20);
    state = state.copyWith(recommendationLimit: clamped);
    await _prefs?.setInt('recommendation_limit', clamped);
  }

  Future<void> setExcludeStarMarket(bool exclude) async {
    state = state.copyWith(excludeStarMarket: exclude);
    await _prefs?.setBool('exclude_star_market', exclude);
  }

  Future<void> setMarketCapFilter(String filter) async {
    state = state.copyWith(marketCapFilter: filter);
    await _prefs?.setString('market_cap_filter', filter);
  }

  Future<void> setNightScanEnabled(bool enabled) async {
    state = state.copyWith(nightScanEnabled: enabled);
    await _prefs?.setBool('night_scan_enabled', enabled);
  }

  Future<void> setScanTime(int hour, int minute) async {
    state = state.copyWith(scanHour: hour, scanMinute: minute);
    await _prefs?.setInt('scan_hour', hour);
    await _prefs?.setInt('scan_minute', minute);
  }

  Future<void> setBatteryGuideShown(bool shown) async {
    state = state.copyWith(batteryGuideShown: shown);
    await _prefs?.setBool('battery_guide_shown', shown);
  }

  Future<void> setServerEnabled(bool enabled) async {
    state = state.copyWith(serverEnabled: enabled);
    await _prefs?.setBool('server_enabled', enabled);
  }

  Future<void> setServerHost(String host) async {
    final value = host.trim();
    state = state.copyWith(serverHost: value);
    await _prefs?.setString('server_host', value);
  }

  Future<void> setServerPort(int port) async {
    final value = port.clamp(1, 65535);
    state = state.copyWith(serverPort: value);
    await _prefs?.setInt('server_port', value);
  }

  Future<void> setServerEndpoint(String host, int port) async {
    await setServerHost(host);
    await setServerPort(port);
    await setServerEnabled(true);
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettingsState>((ref) {
  return AppSettingsNotifier();
});
