import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import 'firmware_catalog.dart';
import 'firmware_crypto.dart';
import 'firmware_key.dart';
import 'ota_debug_log.dart';

/// 从 assets 加载 OTA 固件：优先 catalog 路径，自动回退 `.bin` ↔ `.bin.enc`。
class FirmwareAssetLoader {
  FirmwareAssetLoader({SecretKey? secretKey})
      : _secretKey = secretKey ?? resolveFirmwareAesKey();

  final SecretKey? _secretKey;

  Future<Uint8List> loadFirmwarePlainBytes(FirmwareCatalogEntry entry) async {
    final sw = Stopwatch()..start();
    otaLogPhase(
      'load_start',
      detail: '${entry.productId} asset=${entry.assetPath}',
    );

    final (resolvedPath, data) = await _loadFirmwareAsset(entry.assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    otaLogPhase(
      'asset_loaded',
      detail: 'path=$resolvedPath encBytes=${bytes.length}',
      elapsed: sw.elapsed,
    );

    final Uint8List plain;
    if (resolvedPath.endsWith('.bin.enc')) {
      try {
        final decryptSw = Stopwatch()..start();
        plain = await decryptFirmwareBytes(bytes, _secretKey!);
        otaLogPhase(
          'decrypt_ok',
          detail: 'plainBytes=${plain.length}',
          elapsed: decryptSw.elapsed,
        );
      } on SecretBoxAuthenticationError {
        otaLogPhase('decrypt_fail', detail: 'MAC mismatch ${entry.productId}');
        throw StateError(
          '固件解密密钥不匹配（${entry.productId}）。'
          '请用 ../firmware_aes_key.hex 执行 ./encrypt_firmware_assets.sh 后重装 APK，'
          '或 flutter run --dart-define-from-file=dart_defines.json',
        );
      }
    } else {
      plain = bytes;
      otaLogPhase('plain_bin', detail: 'plainBytes=${plain.length}', elapsed: sw.elapsed);
    }

    if (plain.length < kMinFirmwarePlainBytes) {
      throw StateError(
        'firmware too small (${plain.length} bytes) for ${entry.productId}',
      );
    }
    otaLogPhase(
      'load_done',
      detail: '${entry.productId} plainBytes=${plain.length}',
      elapsed: sw.elapsed,
    );
    return plain;
  }

  /// 先尝试 [preferred]，失败则尝试另一种扩展名（便于开发 .bin / 发布 .enc 混用）。
  static Future<(String path, ByteData data)> _loadFirmwareAsset(String preferred) async {
    final candidates = <String>[
      preferred,
      if (preferred.endsWith('.bin.enc'))
        preferred.replaceFirst(RegExp(r'\.enc$'), '')
      else if (preferred.endsWith('.bin'))
        '$preferred.enc',
    ];

    Object? lastError;
    for (final path in candidates) {
      try {
        final data = await rootBundle.load(path);
        return (path, data);
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError(
      '无法加载固件资源: "$preferred"'
      '${candidates.length > 1 ? "（已尝试 ${candidates.skip(1).join(", ")}）" : ""}。'
      ' 请确认 assets/firmware/ 内有对应文件，并完整重新运行 '
      'flutter run（热重载不会更新 assets）。'
      ' ${lastError ?? ""}',
    );
  }
}
