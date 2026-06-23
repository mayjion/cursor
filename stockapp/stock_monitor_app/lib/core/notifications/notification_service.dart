import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/position_signal.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int closeReminderId = 1001;
  static const String channelId = 'stock_close_reminder';
  static const String channelName = '收盘提醒';
  static const String reversalChannelId = 'stock_reversal_alert';
  static const String reversalChannelName = '趋势逆转提醒';
  static const String signalChannelId = 'stock_signal_change';
  static const String signalChannelName = '加减仓信号';

  bool _initialized = false;
  int _nextAlertId = 2000;

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

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: '交易日收盘后提醒刷新自选股',
        importance: Importance.defaultImportance,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        reversalChannelId,
        reversalChannelName,
        description: '趋势逆转高优先级提醒',
        importance: Importance.high,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        signalChannelId,
        signalChannelName,
        description: '加减仓信号变更提醒',
        importance: Importance.defaultImportance,
      ),
    );

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
      '收盘了，请打开应用刷新自选股并查看加减仓信号',
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

  Future<void> showReversalAlert({
    required String code,
    required String name,
    required ReversalSeverity severity,
    String? suggestedAction,
  }) async {
    await initialize();
    final id = _nextAlertId++;
    final (title, body) = switch (severity) {
      ReversalSeverity.earlyWarning => (
          '⚠ 下跌预警：$name',
          suggestedAction ?? '建议减可变仓30-50%，暂停加仓',
        ),
      ReversalSeverity.confirmed => (
          '🚨 趋势逆转：$name',
          suggestedAction ?? '建议清空可变仓，底仓设止损',
        ),
      ReversalSeverity.deepDrop => (
          '🚨 深跌保护：$name',
          suggestedAction ?? '建议整体减仓或清仓',
        ),
    };

    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          reversalChannelId,
          reversalChannelName,
          channelDescription: '趋势逆转高优先级提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  Future<void> showSignalChangeAlert({
    required String code,
    required String name,
    required PositionSignalType signalType,
    String? suggestedAction,
  }) async {
    await initialize();
    final id = _nextAlertId++;
    final label = switch (signalType) {
      PositionSignalType.add => '加仓信号',
      PositionSignalType.reduce => '减仓信号',
      PositionSignalType.trendBreak => '下跌预警',
      PositionSignalType.trendReversal => '趋势逆转',
      _ => '信号变更',
    };
    await _plugin.show(
      id,
      '$label：$name',
      suggestedAction ?? '$code 出现新的30日加减仓信号',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          signalChannelId,
          signalChannelName,
          channelDescription: '加减仓信号变更',
        ),
      ),
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
