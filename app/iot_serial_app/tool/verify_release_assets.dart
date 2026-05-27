// ignore_for_file: avoid_print

import 'dart:io';

import 'package:iot_serial_app/core/firmware/firmware_enc_assets.dart';

/// 发布前检查：无明文 .bin，且 catalog 要求的 .enc 均存在。
Future<void> main(List<String> args) async {
  final projectRoot = Directory.current;
  final firmwareDir = Directory('${projectRoot.path}/assets/firmware');
  if (!firmwareDir.existsSync()) {
    stderr.writeln('Not found: ${firmwareDir.path}');
    exit(1);
  }

  var failed = false;

  for (final entity in firmwareDir.listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (name.endsWith('.bin') && !name.endsWith('.bin.enc')) {
      stderr.writeln('FAIL: plain firmware must not be bundled: $name');
      failed = true;
    }
  }

  for (final assetPath in kRequiredFirmwareEncAssets) {
    final file = File('${projectRoot.path}/$assetPath');
    if (!file.existsSync()) {
      stderr.writeln('FAIL: missing encrypted asset: $assetPath');
      failed = true;
    } else if (file.lengthSync() < 32) {
      stderr.writeln('FAIL: asset too small: $assetPath');
      failed = true;
    }
  }

  if (failed) {
    stderr.writeln('Run: dart run tool/encrypt_firmware.dart');
    exit(1);
  }

  print('OK: ${kRequiredFirmwareEncAssets.length} .bin.enc present, no plain .bin in assets/firmware/');
}
