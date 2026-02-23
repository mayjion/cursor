import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/app_settings.dart';
import '../../core/settings/app_strings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final settings = ref.watch(appSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsTitle)),
      body: ListView(
        children: [
          ListTile(
            title: Text(strings.themeSection),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(strings.themeBlue)),
                ButtonSegment(value: 1, label: Text(strings.themeGreen)),
                ButtonSegment(value: 2, label: Text(strings.themePurple)),
              ],
              selected: {settings.themeIndex},
              onSelectionChanged: (s) {
                ref.read(appSettingsProvider.notifier).setThemeIndex(s.first);
              },
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            title: Text(strings.languageSection),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'zh', label: Text(strings.languageZh)),
                ButtonSegment(value: 'en', label: Text(strings.languageEn)),
              ],
              selected: {settings.languageCode},
              onSelectionChanged: (s) {
                ref.read(appSettingsProvider.notifier).setLanguageCode(s.first);
              },
            ),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(strings.about),
            subtitle: Text(strings.aboutSubtitle),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.bluetooth),
            title: Text(strings.bluetoothPermission),
            subtitle: Text(strings.bluetoothPermissionSubtitle),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
