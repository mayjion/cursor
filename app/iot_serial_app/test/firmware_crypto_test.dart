import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot_serial_app/core/firmware/firmware_crypto.dart';
import 'package:iot_serial_app/core/firmware/firmware_key_material.dart';

void main() {
  final secretKey = resolveFirmwareAesKeyFromHex(kFirmwareAesDevKeyHex);

  test('encrypt decrypt roundtrip', () async {
    final plain = Uint8List.fromList(List<int>.generate(2048, (i) => i % 256));
    final enc = await encryptFirmwareBytes(plain, secretKey);
    final out = await decryptFirmwareBytes(enc, secretKey);
    expect(out, plain);
  });

  test('reject bad magic', () async {
    final enc = Uint8List.fromList(List.filled(64, 0));
    expect(
      () => decryptFirmwareBytes(enc, secretKey),
      throwsA(isA<FormatException>()),
    );
  });

  test('reject tampered tag', () async {
    final plain = Uint8List.fromList(List.filled(1500, 0xAB));
    final enc = await encryptFirmwareBytes(plain, secretKey);
    enc[enc.length - 1] ^= 0xFF;
    expect(
      () => decryptFirmwareBytes(enc, secretKey),
      throwsA(anything),
    );
  });

  test('parseFirmwareAesKeyHex validates length', () {
    expect(() => parseFirmwareAesKeyHex('abc'), throwsFormatException);
    expect(parseFirmwareAesKeyHex(kFirmwareAesDevKeyHex).length, 32);
  });
}
