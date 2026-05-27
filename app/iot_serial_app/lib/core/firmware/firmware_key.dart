import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'firmware_crypto.dart';
import 'firmware_key_material.dart';

export 'firmware_key_material.dart' show kFirmwareAesDevKeyHex, resolveFirmwareAesKeyFromHex;

/// 解析固件 AES 密钥（须与加密 .bin.enc 时使用的密钥一致）。
///
/// 通过 [encrypt_firmware_assets.sh] 打包时会写入 `dart_defines.json` 并
/// `--dart-define-from-file` 注入；手动运行请带相同 hex。
SecretKey resolveFirmwareAesKey() {
  const fromEnv = String.fromEnvironment('FIRMWARE_AES_KEY_HEX');
  if (fromEnv.isNotEmpty) {
    return SecretKey(parseFirmwareAesKeyHex(fromEnv));
  }
  if (kDebugMode) {
    // 仅当 .enc 由开发钥加密时可用于本地调试；发布请用脚本生成 dart_defines.json。
    return SecretKey(parseFirmwareAesKeyHex(kFirmwareAesDevKeyHex));
  }
  throw StateError(
    'FIRMWARE_AES_KEY_HEX is required for release builds. '
    'Use ./encrypt_firmware_assets.sh or '
    '--dart-define-from-file=dart_defines.json',
  );
}
