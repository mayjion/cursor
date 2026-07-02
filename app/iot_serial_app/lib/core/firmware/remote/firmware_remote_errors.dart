import '../../settings/app_strings.dart';
import 'firmware_remote_config.dart';

/// 将远程 OTA 异常转为用户可读文案。
String formatFirmwareRemoteError(Object error, AppStrings strings) {
  final msg = error.toString();
  final lower = msg.toLowerCase();
  final hasToken = resolveGiteeToken().isNotEmpty;

  if (lower.contains('failed host lookup') ||
      lower.contains('no address associated with hostname') ||
      lower.contains('network is unreachable')) {
    return strings.firmwareRemoteNetworkError;
  }

  if (lower.contains('403') || lower.contains('access denied')) {
    if (hasToken) {
      return strings.firmwareRemoteTokenInvalid;
    }
    return strings.firmwareRemoteTokenRequired;
  }

  if (lower.contains('401') || lower.contains('bad credentials')) {
    return strings.firmwareRemoteTokenInvalid;
  }

  return msg;
}
