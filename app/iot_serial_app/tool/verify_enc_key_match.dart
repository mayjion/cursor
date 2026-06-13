// ignore_for_file: avoid_print
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:iot_serial_app/core/firmware/firmware_crypto.dart';
import 'package:iot_serial_app/core/firmware/firmware_enc_assets.dart';
import 'package:iot_serial_app/core/firmware/firmware_key_material.dart';

/// 校验 assets 内所有 .enc 是否可用指定密钥解密。
Future<void> main(List<String> args) async {
  final keyHex = args.isNotEmpty
      ? args.first.trim()
      : (Platform.environment['FIRMWARE_AES_KEY_HEX'] ?? '').trim();
  if (keyHex.isEmpty) {
    stderr.writeln('Usage: FIRMWARE_AES_KEY_HEX=<hex> dart run tool/verify_enc_key_match.dart');
    exit(1);
  }
  final secretKey = SecretKey(parseFirmwareAesKeyHex(keyHex));
  var failed = false;
  for (final asset in kRequiredFirmwareEncAssets) {
    final f = File(asset);
    if (!f.existsSync()) {
      stderr.writeln('FAIL missing: $asset');
      failed = true;
      continue;
    }
    try {
      final enc = await f.readAsBytes();
      final plain = await decryptFirmwareBytes(enc, secretKey);
      if (plain.length < kMinFirmwarePlainBytes) {
        stderr.writeln('FAIL $asset: decrypted too small');
        failed = true;
      } else {
        print('OK $asset (${plain.length} bytes)');
      }
    } catch (e) {
      stderr.writeln('FAIL $asset: $e');
      failed = true;
    }
  }
  if (failed) {
    stderr.writeln('');
    stderr.writeln('密钥与 .bin.enc 不匹配。请放置明文 .bin 后执行: ./encrypt_firmware_assets.sh');
    exit(1);
  }
  print('All ${kRequiredFirmwareEncAssets.length} assets match the key.');
}
