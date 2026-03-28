import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyThemeIndex = 'app_theme_index';
const String _keyLanguageCode = 'app_language_code';
const String _keySerialRxBufferMb = 'serial_rx_buffer_mb';

/// Theme index: 0 = blue, 1 = green, 2 = purple.
/// Language: 'zh' = 中文, 'en' = English.
/// [serialRxBufferMegabytes]: in-app RX log cap for serial tool / related UIs (1–10 MB).
class AppSettingsState {
  const AppSettingsState({
    this.themeIndex = 0,
    this.languageCode = 'zh',
    this.serialRxBufferMegabytes = 1,
  });

  final int themeIndex;
  final String languageCode;
  final int serialRxBufferMegabytes;

  Locale get locale => languageCode == 'en' ? const Locale('en') : const Locale('zh');

  int get serialRxBufferBytes => serialRxBufferMegabytes * 1024 * 1024;

  AppSettingsState copyWith({
    int? themeIndex,
    String? languageCode,
    int? serialRxBufferMegabytes,
  }) {
    return AppSettingsState(
      themeIndex: themeIndex ?? this.themeIndex,
      languageCode: languageCode ?? this.languageCode,
      serialRxBufferMegabytes: serialRxBufferMegabytes ?? this.serialRxBufferMegabytes,
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
    final rxMb = _prefs!.getInt(_keySerialRxBufferMb) ?? 1;
    state = state.copyWith(
      themeIndex: themeIndex.clamp(0, 2),
      languageCode: languageCode == 'en' ? 'en' : 'zh',
      serialRxBufferMegabytes: rxMb.clamp(1, 10),
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

  Future<void> setSerialRxBufferMegabytes(int mb) async {
    final clamped = mb.clamp(1, 10);
    state = state.copyWith(serialRxBufferMegabytes: clamped);
    await _prefs?.setInt(_keySerialRxBufferMb, clamped);
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettingsState>((ref) {
  return AppSettingsNotifier();
});

/// Bumped when user clears serial RX logs from any screen; listeners clear their local buffers.
final serialRxLogClearTickProvider = StateProvider<int>((ref) => 0);
