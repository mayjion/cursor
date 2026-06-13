import 'package:cryptography/cryptography.dart';

import 'firmware_crypto.dart';

/// 仅用于本地 debug / `dart run tool/*`；禁止用于外发 release APK。
const String kFirmwareAesDevKeyHex =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

/// 解析固件 AES 密钥（hex 为空时使用开发钥）。
SecretKey resolveFirmwareAesKeyFromHex(String? keyHex) {
  final hex = keyHex?.trim();
  if (hex != null && hex.isNotEmpty) {
    return SecretKey(parseFirmwareAesKeyHex(hex));
  }
  return SecretKey(parseFirmwareAesKeyHex(kFirmwareAesDevKeyHex));
}
