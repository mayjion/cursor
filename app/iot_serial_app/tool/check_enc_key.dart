// ignore_for_file: avoid_print
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:iot_serial_app/core/firmware/firmware_crypto.dart';
import 'package:iot_serial_app/core/firmware/firmware_key_file.dart';
import 'package:iot_serial_app/core/firmware/firmware_key_material.dart';

Future<void> main() async {
  final path = 'assets/firmware/ESPFLASHER_V4.bin.enc';
  final enc = await File(path).readAsBytes();
  final prod = readFirmwareKeyHexFromFile();
  final keys = <String, String>{
    'dev': kFirmwareAesDevKeyHex,
    if (prod != null) 'prod_file': prod,
  };
  for (final e in keys.entries) {
    try {
      final plain = await decryptFirmwareBytes(
        enc,
        SecretKey(parseFirmwareAesKeyHex(e.value)),
      );
      print('${e.key}: OK (${plain.length} bytes)');
    } catch (err) {
      print('${e.key}: FAIL $err');
    }
  }
}
