import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PredictionThresholds {
  const PredictionThresholds({
    this.bullRatioPercent = 3.0,
    this.bearRatioPercent = -3.0,
    this.upChangePercent = 0.5,
    this.downChangePercent = -0.5,
  });

  final double bullRatioPercent;
  final double bearRatioPercent;
  final double upChangePercent;
  final double downChangePercent;

  PredictionThresholds copyWith({
    double? bullRatioPercent,
    double? bearRatioPercent,
    double? upChangePercent,
    double? downChangePercent,
  }) {
    return PredictionThresholds(
      bullRatioPercent: bullRatioPercent ?? this.bullRatioPercent,
      bearRatioPercent: bearRatioPercent ?? this.bearRatioPercent,
      upChangePercent: upChangePercent ?? this.upChangePercent,
      downChangePercent: downChangePercent ?? this.downChangePercent,
    );
  }
}

class AppSettingsState {
  const AppSettingsState({
    this.themeIndex = 0,
    this.languageCode = 'zh',
    this.notifyEnabled = true,
    this.thresholds = const PredictionThresholds(),
  });

  final int themeIndex;
  final String languageCode;
  final bool notifyEnabled;
  final PredictionThresholds thresholds;

  Locale get locale =>
      languageCode == 'en' ? const Locale('en') : const Locale('zh');

  AppSettingsState copyWith({
    int? themeIndex,
    String? languageCode,
    bool? notifyEnabled,
    PredictionThresholds? thresholds,
  }) {
    return AppSettingsState(
      themeIndex: themeIndex ?? this.themeIndex,
      languageCode: languageCode ?? this.languageCode,
      notifyEnabled: notifyEnabled ?? this.notifyEnabled,
      thresholds: thresholds ?? this.thresholds,
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
    final thresholds = PredictionThresholds(
      bullRatioPercent: _prefs!.getDouble('bull_ratio') ?? 3.0,
      bearRatioPercent: _prefs!.getDouble('bear_ratio') ?? -3.0,
      upChangePercent: _prefs!.getDouble('up_change') ?? 0.5,
      downChangePercent: _prefs!.getDouble('down_change') ?? -0.5,
    );
    state = AppSettingsState(
      themeIndex: themeIndex.clamp(0, 2),
      languageCode: languageCode == 'en' ? 'en' : 'zh',
      notifyEnabled: notifyEnabled,
      thresholds: thresholds,
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

  Future<void> setThresholds(PredictionThresholds t) async {
    state = state.copyWith(thresholds: t);
    await _prefs?.setDouble('bull_ratio', t.bullRatioPercent);
    await _prefs?.setDouble('bear_ratio', t.bearRatioPercent);
    await _prefs?.setDouble('up_change', t.upChangePercent);
    await _prefs?.setDouble('down_change', t.downChangePercent);
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettingsState>((ref) {
  return AppSettingsNotifier();
});
