// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'package:iot_serial_app/core/firmware/firmware_crypto.dart';
import 'package:iot_serial_app/core/firmware/firmware_key_file.dart';
import 'package:iot_serial_app/core/firmware/firmware_key_material.dart';

/// 将 assets/firmware/*.bin 加密为 *.bin.enc（FUN1 / AES-256-GCM）。
///
/// 用法:
///   dart run tool/encrypt_firmware.dart
///   FIRMWARE_AES_KEY_HEX=<64hex> dart run tool/encrypt_firmware.dart
///   dart run tool/encrypt_firmware.dart --key-hex <64hex>
Future<void> main(List<String> args) async {
  String? keyHex;
  var removePlain = true;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--key-hex' && i + 1 < args.length) {
      keyHex = args[++i];
    } else if (args[i] == '--keep-plain') {
      removePlain = false;
    } else if (args[i] == '--help' || args[i] == '-h') {
      _usage();
      return;
    }
  }
  keyHex ??= Platform.environment['FIRMWARE_AES_KEY_HEX'];
  if (keyHex == null || keyHex.isEmpty) {
    keyHex = readFirmwareKeyHexFromFile();
    if (keyHex != null) {
      print('Using key from ${defaultFirmwareKeyFile().path}');
    }
  }
  final secretKey = resolveFirmwareAesKeyFromHex(keyHex);
  if (keyHex == null || keyHex.isEmpty) {
    print('Using development key (kFirmwareAesDevKeyHex); do not ship release APK with it.');
  }

  final projectRoot = Directory.current;
  final firmwareDir = Directory('${projectRoot.path}/assets/firmware');
  if (!firmwareDir.existsSync()) {
    stderr.writeln('Not found: ${firmwareDir.path} (run from iot_serial_app root)');
    exit(1);
  }

  final bins = firmwareDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.bin') && !f.path.endsWith('.bin.enc'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (bins.isEmpty) {
    stderr.writeln('No plain .bin files in assets/firmware/');
    exit(1);
  }

  print('Encrypting ${bins.length} firmware file(s)...');
  for (final binFile in bins) {
    final plain = await binFile.readAsBytes();
    final enc = await encryptFirmwareBytes(Uint8List.fromList(plain), secretKey);
    final outPath = '${binFile.path}.enc';
    await File(outPath).writeAsBytes(enc, flush: true);
    final digest = await Sha256().hash(enc);
    final hex = digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    print('  ${binFile.uri.pathSegments.last} -> ${binFile.uri.pathSegments.last}.enc');
    print('    plain=${plain.length} enc=${enc.length} sha256=${hex.substring(0, 16)}...');
    if (removePlain) {
      await binFile.delete();
    }
  }
  if (removePlain) {
    print('Removed plain .bin files (use --keep-plain to retain).');
  }
  print('Done. Run: dart run tool/verify_release_assets.dart');
}

void _usage() {
  print('''
Usage: dart run tool/encrypt_firmware.dart [--key-hex <64 hex chars>]

Reads assets/firmware/*.bin (not *.bin.enc) and writes *.bin.enc.
Key (priority): --key-hex > env FIRMWARE_AES_KEY_HEX > ../firmware_aes_key.hex > dev key.
By default deletes plain .bin after encrypt; pass --keep-plain to keep them.
''');
}
