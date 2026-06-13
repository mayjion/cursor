import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// FUN1 密文格式头长度：魔数(4) + 版本(1) + nonce(12)。
const int kFirmwareEncHeaderLen = 17;

const int kFirmwareEncMagic0 = 0x46; // F
const int kFirmwareEncMagic1 = 0x55; // U
const int kFirmwareEncMagic2 = 0x4e; // N
const int kFirmwareEncMagic3 = 0x31; // 1
const int kFirmwareEncVersion = 0x01;

const int kFirmwareMacLen = 16;
const int kFirmwareNonceLen = 12;

/// 解密后固件最小有效长度（与升级页占位检测一致）。
const int kMinFirmwarePlainBytes = 1024;

final AesGcm _aesGcm = AesGcm.with256bits();

/// 将明文固件加密为 `.bin.enc` 字节（FUN1 格式）。
Future<Uint8List> encryptFirmwareBytes(
  Uint8List plain,
  SecretKey secretKey,
) async {
  final nonce = _aesGcm.newNonce();
  final box = await _aesGcm.encrypt(
    plain,
    secretKey: secretKey,
    nonce: nonce,
  );
  final mac = box.mac.bytes;
  if (mac.length != kFirmwareMacLen) {
    throw StateError('unexpected GCM tag length ${mac.length}');
  }
  final out = Uint8List(kFirmwareEncHeaderLen + box.cipherText.length + kFirmwareMacLen);
  out[0] = kFirmwareEncMagic0;
  out[1] = kFirmwareEncMagic1;
  out[2] = kFirmwareEncMagic2;
  out[3] = kFirmwareEncMagic3;
  out[4] = kFirmwareEncVersion;
  out.setRange(5, 5 + kFirmwareNonceLen, box.nonce);
  out.setRange(kFirmwareEncHeaderLen, kFirmwareEncHeaderLen + box.cipherText.length, box.cipherText);
  out.setRange(
    kFirmwareEncHeaderLen + box.cipherText.length,
    out.length,
    mac,
  );
  return out;
}

/// 解析 FUN1 `.bin.enc` 为明文固件。
Future<Uint8List> decryptFirmwareBytes(
  Uint8List enc,
  SecretKey secretKey,
) async {
  if (enc.length < kFirmwareEncHeaderLen + kFirmwareMacLen) {
    throw FormatException('encrypted firmware too short (${enc.length} bytes)');
  }
  if (enc[0] != kFirmwareEncMagic0 ||
      enc[1] != kFirmwareEncMagic1 ||
      enc[2] != kFirmwareEncMagic2 ||
      enc[3] != kFirmwareEncMagic3) {
    throw FormatException('invalid firmware enc magic');
  }
  if (enc[4] != kFirmwareEncVersion) {
    throw FormatException('unsupported firmware enc version ${enc[4]}');
  }
  final nonce = enc.sublist(5, 5 + kFirmwareNonceLen);
  final cipherEnd = enc.length - kFirmwareMacLen;
  final cipherText = enc.sublist(kFirmwareEncHeaderLen, cipherEnd);
  final mac = Mac(enc.sublist(cipherEnd));
  final box = SecretBox(cipherText, nonce: nonce, mac: mac);
  final plain = await _aesGcm.decrypt(box, secretKey: secretKey);
  return Uint8List.fromList(plain);
}

/// 解析 64 位十六进制字符串为 32 字节 AES 密钥。
List<int> parseFirmwareAesKeyHex(String hex) {
  final normalized = hex.trim().toLowerCase();
  if (normalized.length != 64) {
    throw FormatException('FIRMWARE_AES_KEY_HEX must be 64 hex chars (32 bytes)');
  }
  final out = <int>[];
  for (var i = 0; i < 64; i += 2) {
    final byte = int.tryParse(normalized.substring(i, i + 2), radix: 16);
    if (byte == null) {
      throw FormatException('invalid hex at $i');
    }
    out.add(byte);
  }
  return out;
}
