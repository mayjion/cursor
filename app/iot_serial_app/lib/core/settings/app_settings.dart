import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyThemeIndex = 'app_theme_index';
const String _keyLanguageCode = 'app_language_code';

/// Theme index: 0 = blue, 1 = green, 2 = purple.
/// Language: 'zh' = 中文, 'en' = English.
class AppSettingsState {
  const AppSettingsState({
    this.themeIndex = 0,
    this.languageCode = 'zh',
  });

  final int themeIndex;
  final String languageCode;

  Locale get locale => languageCode == 'en' ? const Locale('en') : const Locale('zh');

  AppSettingsState copyWith({int? themeIndex, String? languageCode}) {
    return AppSettingsState(
      themeIndex: themeIndex ?? this.themeIndex,
      languageCode: languageCode ?? this.languageCode,
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
    final themeIndex = _prefs!.getInt(_keyThemeIndex) ?? 0;
    final languageCode = _prefs!.getString(_keyLanguageCode) ?? 'zh';
    state = state.copyWith(
      themeIndex: themeIndex.clamp(0, 2),
      languageCode: languageCode == 'en' ? 'en' : 'zh',
    );
  }

  Future<void> setThemeIndex(int index) async {
    final clamped = index.clamp(0, 2);
    state = state.copyWith(themeIndex: clamped);
    await _prefs?.setInt(_keyThemeIndex, clamped);
  }

  Future<void> setLanguageCode(String code) async {
    final value = code == 'en' ? 'en' : 'zh';
    state = state.copyWith(languageCode: value);
    await _prefs?.setString(_keyLanguageCode, value);
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettingsState>((ref) {
  return AppSettingsNotifier();
});
