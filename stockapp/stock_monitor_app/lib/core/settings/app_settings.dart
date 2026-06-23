import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsState {
  const AppSettingsState({
    this.themeIndex = 0,
    this.languageCode = 'zh',
    this.notifyEnabled = true,
    this.reversalNotifyEnabled = true,
  });

  final int themeIndex;
  final String languageCode;
  final bool notifyEnabled;
  final bool reversalNotifyEnabled;

  Locale get locale =>
      languageCode == 'en' ? const Locale('en') : const Locale('zh');

  AppSettingsState copyWith({
    int? themeIndex,
    String? languageCode,
    bool? notifyEnabled,
    bool? reversalNotifyEnabled,
  }) {
    return AppSettingsState(
      themeIndex: themeIndex ?? this.themeIndex,
      languageCode: languageCode ?? this.languageCode,
      notifyEnabled: notifyEnabled ?? this.notifyEnabled,
      reversalNotifyEnabled:
          reversalNotifyEnabled ?? this.reversalNotifyEnabled,
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
    state = AppSettingsState(
      themeIndex: themeIndex.clamp(0, 2),
      languageCode: languageCode == 'en' ? 'en' : 'zh',
      notifyEnabled: notifyEnabled,
      reversalNotifyEnabled: reversalNotifyEnabled,
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
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettingsState>((ref) {
  return AppSettingsNotifier();
});
