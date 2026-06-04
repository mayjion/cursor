import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int closeReminderId = 1001;
  static const String channelId = 'stock_close_reminder';
  static const String channelName = '收盘提醒';

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (_) {},
    );

    const channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: '交易日收盘后提醒刷新自选股',
      importance: Importance.defaultImportance,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  Future<void> scheduleCloseReminder({required bool enabled}) async {
    await initialize();
    await _plugin.cancel(closeReminderId);
    if (!enabled) return;

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      15,
      5,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      closeReminderId,
      '收盘提醒',
      '收盘了，请打开应用刷新自选股并记录今日推测',
      _nextWeekdayAt1505(scheduled),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: '交易日收盘后提醒',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  tz.TZDateTime _nextWeekdayAt1505(tz.TZDateTime from) {
    var dt = from;
    while (dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday) {
      dt = dt.add(const Duration(days: 1));
      dt = tz.TZDateTime(tz.local, dt.year, dt.month, dt.day, 15, 5);
    }
    return dt;
  }
}
