import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_router.dart';
import 'core/notifications/notification_service.dart';
import 'core/settings/app_settings.dart';
import 'core/settings/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await NotificationService.instance.initialize();
  await _requestNotificationPermission();
  runApp(const ProviderScope(child: StockMonitorApp()));
}

Future<void> _requestNotificationPermission() async {
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }
}

class StockMonitorApp extends ConsumerStatefulWidget {
  const StockMonitorApp({super.key});

  @override
  ConsumerState<StockMonitorApp> createState() => _StockMonitorAppState();
}

class _StockMonitorAppState extends ConsumerState<StockMonitorApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncNotifications());
  }

  Future<void> _syncNotifications() async {
    final settings = ref.read(appSettingsProvider);
    await NotificationService.instance
        .scheduleCloseReminder(enabled: settings.notifyEnabled);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appSettingsProvider, (prev, next) {
      if (prev?.notifyEnabled != next.notifyEnabled) {
        NotificationService.instance
            .scheduleCloseReminder(enabled: next.notifyEnabled);
      }
    });

    final settings = ref.watch(appSettingsProvider);
    return MaterialApp.router(
      title: '自选股监控',
      theme: appThemeForIndex(settings.themeIndex),
      locale: settings.locale,
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: goRouter,
    );
  }
}
