import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../firmware_catalog.dart';
import 'firmware_manifest.dart';

/// 远程下载的加密固件本地缓存（仍为 .bin.enc）。
class FirmwareLocalCache {
  FirmwareLocalCache({Directory? cacheRoot}) : _cacheRoot = cacheRoot;

  Directory? _cacheRoot;

  Future<Directory> _dir() async {
    if (_cacheRoot != null) return _cacheRoot!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/firmware_cache');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _cacheRoot = dir;
    return dir;
  }

  String cacheFileName(String productId, String version) {
    final safeVersion = version.replaceAll(RegExp(r'[^\w\.\-]'), '_');
    return '${productId}_$safeVersion.bin.enc';
  }

  Future<String> pathFor(String productId, String version) async {
    final dir = await _dir();
    return '${dir.path}/${cacheFileName(productId, version)}';
  }

  Future<bool> exists(String productId, String version) async {
    final file = File(await pathFor(productId, version));
    return file.existsSync();
  }

  Future<void> write(String productId, String version, List<int> bytes) async {
    final file = File(await pathFor(productId, version));
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<void> deleteOlderVersions(String productId, String keepVersion) async {
    final dir = await _dir();
    final prefix = '${productId}_';
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(prefix) || !name.endsWith('.bin.enc')) continue;
      if (name == cacheFileName(productId, keepVersion)) continue;
      try {
        await entity.delete();
      } catch (_) {}
    }
  }

  /// 查找已缓存的 manifest 条目路径（按 product + version）。
  Future<String?> cachedPathForEntry(FirmwareManifestEntry entry) async {
    if (!await exists(entry.productId, entry.version)) return null;
    return pathFor(entry.productId, entry.version);
  }

  /// 按 catalog 条目查找任意已缓存远程固件（匹配 productId）。
  Future<String?> findAnyCachedPath(FirmwareCatalogEntry entry) async {
    final dir = await _dir();
    final prefix = '${entry.productId}_';
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.startsWith(prefix) && name.endsWith('.bin.enc')) {
        return entity.path;
      }
    }
    return null;
  }
}
