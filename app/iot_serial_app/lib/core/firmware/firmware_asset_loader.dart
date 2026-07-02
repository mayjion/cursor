import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import 'firmware_catalog.dart';
import 'firmware_crypto.dart';
import 'firmware_key.dart';
import 'ota_debug_log.dart';
import 'remote/firmware_local_cache.dart';

/// 从本地缓存或 assets 加载 OTA 固件：优先 cache，回退 `.bin` ↔ `.bin.enc` assets。
class FirmwareAssetLoader {
  FirmwareAssetLoader({
    SecretKey? secretKey,
    FirmwareLocalCache? cache,
  })  : _secretKey = secretKey ?? resolveFirmwareAesKey(),
        _cache = cache ?? FirmwareLocalCache();

  final SecretKey? _secretKey;
  final FirmwareLocalCache _cache;

  Future<Uint8List> loadFirmwarePlainBytes(FirmwareCatalogEntry entry) async {
    return loadFirmwarePlainBytesFromCacheOrAsset(entry);
  }

  Future<Uint8List> loadFirmwarePlainBytesFromCacheOrAsset(
    FirmwareCatalogEntry entry, {
    String? cachePath,
  }) async {
    final sw = Stopwatch()..start();
    otaLogPhase(
      'load_start',
      detail: '${entry.productId} asset=${entry.assetPath}',
    );

    final resolvedCache = cachePath ?? await _cache.findAnyCachedPath(entry);
    if (resolvedCache != null) {
      otaLogPhase('load_cache_try', detail: resolvedCache);
      try {
        return await _loadAndDecryptEncFile(
          resolvedCache,
          entry.productId,
          sw,
        );
      } catch (e) {
        otaLogPhase('load_cache_fail', detail: '$e');
      }
    }

    final (resolvedPath, data) = await _loadFirmwareAsset(entry.assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    otaLogPhase(
      'asset_loaded',
      detail: 'path=$resolvedPath encBytes=${bytes.length}',
      elapsed: sw.elapsed,
    );

    return _decryptOrPlain(
      bytes: bytes,
      resolvedPath: resolvedPath,
      productId: entry.productId,
      sw: sw,
    );
  }

  Future<Uint8List> _loadAndDecryptEncFile(
    String path,
    String productId,
    Stopwatch sw,
  ) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    otaLogPhase(
      'cache_loaded',
      detail: 'path=$path encBytes=${bytes.length}',
      elapsed: sw.elapsed,
    );
    return _decryptOrPlain(
      bytes: bytes,
      resolvedPath: path,
      productId: productId,
      sw: sw,
    );
  }

  Future<Uint8List> _decryptOrPlain({
    required Uint8List bytes,
    required String resolvedPath,
    required String productId,
    required Stopwatch sw,
  }) async {
    final Uint8List plain;
    if (resolvedPath.endsWith('.bin.enc') || resolvedPath.endsWith('.enc')) {
      try {
        final decryptSw = Stopwatch()..start();
        plain = await decryptFirmwareBytes(bytes, _secretKey!);
        otaLogPhase(
          'decrypt_ok',
          detail: 'plainBytes=${plain.length}',
          elapsed: decryptSw.elapsed,
        );
      } on SecretBoxAuthenticationError {
        otaLogPhase('decrypt_fail', detail: 'MAC mismatch $productId');
        throw StateError(
          '固件解密密钥不匹配（$productId）。'
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
        'firmware too small (${plain.length} bytes) for $productId',
      );
    }
    otaLogPhase(
      'load_done',
      detail: '$productId plainBytes=${plain.length}',
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
      ' 请确认 assets/firmware/ 内有对应文件，或从远程下载固件到本地缓存。'
      ' ${lastError ?? ""}',
    );
  }
}
