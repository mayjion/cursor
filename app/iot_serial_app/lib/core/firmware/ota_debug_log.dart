import 'package:flutter/foundation.dart';

/// logcat 过滤：`adb logcat -s flutter:I | grep '\[OTA\]'`
const String kOtaLogTag = '[OTA]';

void otaLog(String message, {Object? error, StackTrace? stackTrace}) {
  // developer.log 在部分 Release 包中不会出现在 logcat；debugPrint 走 flutter 标签更可靠。
  debugPrint('$kOtaLogTag $message');
  if (error != null) {
    debugPrint('$kOtaLogTag error: $error');
  }
  if (stackTrace != null) {
    debugPrint('$kOtaLogTag $stackTrace');
  }
}

void otaLogPhase(
  String phase, {
  String? detail,
  Duration? elapsed,
}) {
  final parts = <String>[phase];
  if (detail != null && detail.isNotEmpty) {
    parts.add(detail);
  }
  if (elapsed != null) {
    parts.add('${elapsed.inMilliseconds}ms');
  }
  otaLog(parts.join(' | '));
}
