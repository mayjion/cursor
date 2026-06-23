import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/notification_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/app_strings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsTitle)),
      body: ListView(
        children: [
          ListTile(
            title: Text(strings.themeSection),
            subtitle: Text(_themeName(strings, settings.themeIndex)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(strings.themeIndigo)),
                ButtonSegment(value: 1, label: Text(strings.themeTeal)),
                ButtonSegment(value: 2, label: Text(strings.themeOrange)),
              ],
              selected: {settings.themeIndex},
              onSelectionChanged: (s) => notifier.setThemeIndex(s.first),
            ),
          ),
          const Divider(),
          ListTile(title: Text(strings.languageSection)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'zh', label: Text('中文')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {settings.languageCode},
              onSelectionChanged: (s) => notifier.setLanguageCode(s.first),
            ),
          ),
          const Divider(),
          SwitchListTile(
            title: Text(strings.notifySection),
            subtitle: Text(strings.notifySubtitle),
            value: settings.notifyEnabled,
            onChanged: (v) async {
              await notifier.setNotifyEnabled(v);
              await NotificationService.instance
                  .scheduleCloseReminder(enabled: v);
            },
          ),
          SwitchListTile(
            title: Text(strings.reversalNotifySection),
            subtitle: Text(strings.reversalNotifySubtitle),
            value: settings.reversalNotifyEnabled,
            onChanged: notifier.setReversalNotifyEnabled,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              color: Theme.of(context)
                  .colorScheme
                  .errorContainer
                  .withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(strings.disclaimer,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _themeName(AppStrings s, int i) {
    return switch (i) {
      1 => s.themeTeal,
      2 => s.themeOrange,
      _ => s.themeIndigo,
    };
  }
}
