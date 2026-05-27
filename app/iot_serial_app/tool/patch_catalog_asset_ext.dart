// ignore_for_file: avoid_print

import 'dart:io';

/// 将 catalog 中 assetPath 统一为 .bin 或 .bin.enc（otaUploadFilename 保持 .bin）。
void main(List<String> args) {
  final mode = args.isNotEmpty ? args.first : 'enc';
  if (mode != 'bin' && mode != 'enc') {
    stderr.writeln('Usage: dart run tool/patch_catalog_asset_ext.dart [bin|enc]');
    exit(1);
  }
  final files = [
    'lib/core/firmware/firmware_catalog.dart',
    'lib/core/firmware/espflasher_catalog.dart',
  ];
  final pattern = mode == 'enc'
      ? RegExp(r"assetPath: 'assets/firmware/([^']+)\.bin'")
      : RegExp(r"assetPath: 'assets/firmware/([^']+)\.bin\.enc'");
  final replacement = mode == 'enc'
      ? r"assetPath: 'assets/firmware/$1.bin.enc'"
      : r"assetPath: 'assets/firmware/$1.bin'";

  for (final path in files) {
    final f = File(path);
    if (!f.existsSync()) {
      stderr.writeln('missing $path');
      exit(1);
    }
    final text = f.readAsStringSync();
    final out = text.replaceAllMapped(pattern, (m) => replacement.replaceAll('\$1', m.group(1)!));
    if (out == text) {
      print('$path: already $mode (no change)');
    } else {
      f.writeAsStringSync(out);
      print('$path: assetPath -> .$mode');
    }
  }
}
