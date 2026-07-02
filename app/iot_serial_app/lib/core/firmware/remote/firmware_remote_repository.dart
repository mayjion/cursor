import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../firmware_catalog.dart';
import 'firmware_local_cache.dart';
import 'firmware_manifest.dart';
import 'firmware_remote_config.dart';
import 'firmware_version_compare.dart';
import 'gitee_api_client.dart';

typedef FirmwareDownloadProgress = void Function(int received, int total);

class FirmwareRemoteRepository {
  FirmwareRemoteRepository({
    http.Client? client,
    FirmwareLocalCache? cache,
    GiteeApiClient? giteeApi,
    String? manifestUrl,
    String? giteeToken,
    String? giteeOwner,
    String? giteeRepo,
    String? giteeBranch,
  })  : _ownsClient = client == null,
        _client = client ?? IOClient(HttpClient()),
        _cache = cache ?? FirmwareLocalCache(),
        _giteeApi = giteeApi ?? GiteeApiClient(),
        _ownsGiteeApi = giteeApi == null,
        _manifestUrl = manifestUrl ?? resolveFirmwareManifestUrl(),
        _giteeToken = giteeToken ?? resolveGiteeToken(),
        _giteeOwner = giteeOwner ?? resolveGiteeOwner(),
        _giteeRepo = giteeRepo ?? resolveGiteeRepo(),
        _giteeBranch = giteeBranch ?? resolveGiteeBranch();

  final http.Client _client;
  final bool _ownsClient;
  final FirmwareLocalCache _cache;
  final GiteeApiClient _giteeApi;
  final bool _ownsGiteeApi;
  final String _manifestUrl;
  final String _giteeToken;
  final String _giteeOwner;
  final String _giteeRepo;
  final String _giteeBranch;

  bool get hasGiteeToken => _giteeToken.isNotEmpty;

  void close() {
    if (_ownsClient) {
      _client.close();
    }
    if (_ownsGiteeApi) {
      _giteeApi.close();
    }
  }

  Future<FirmwareManifest> fetchManifest() async {
    if (hasGiteeToken) {
      final bytes = await _giteeApi.fetchFileContents(
        owner: _giteeOwner,
        repo: _giteeRepo,
        path: 'manifest.json',
        branch: _giteeBranch,
        token: _giteeToken,
      );
      return FirmwareManifest.parse(utf8.decode(bytes));
    }

    final response = await _client
        .get(Uri.parse(_manifestUrl))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw HttpException('manifest HTTP ${response.statusCode}');
    }
    final body = utf8.decode(response.bodyBytes);
    return FirmwareManifest.parse(body);
  }

  FirmwareManifestEntry? findEntryForProduct(
    FirmwareManifest manifest,
    String productId,
  ) {
    return manifest.findForProduct(productId);
  }

  bool hasUpdateForDevice({
    required FirmwareManifestEntry entry,
    required String? deviceVersion,
  }) {
    if (deviceVersion == null || deviceVersion.trim().isEmpty) return false;
    return isFirmwareVersionGreater(entry.version, deviceVersion);
  }

  Future<bool> isCached(FirmwareManifestEntry entry) {
    return _cache.exists(entry.productId, entry.version);
  }

  Future<String> downloadFirmware(
    FirmwareManifestEntry entry, {
    FirmwareDownloadProgress? onProgress,
  }) async {
    final Uint8List bytes;
    if (hasGiteeToken) {
      bytes = await _giteeApi.fetchFileContents(
        owner: _giteeOwner,
        repo: _giteeRepo,
        path: 'firmware/${entry.fileName}',
        branch: _giteeBranch,
        token: _giteeToken,
        onProgress: onProgress,
      );
    } else {
      bytes = await _downloadFirmwareRaw(entry, onProgress: onProgress);
    }

    if (bytes.length != entry.size) {
      throw StateError(
        'size mismatch: expected ${entry.size}, got ${bytes.length}',
      );
    }

    final digest = sha256.convert(bytes).toString();
    if (digest != entry.sha256.toLowerCase()) {
      throw StateError('sha256 mismatch for ${entry.productId}');
    }

    await _cache.write(entry.productId, entry.version, bytes);
    await _cache.deleteOlderVersions(entry.productId, entry.version);
    return await _cache.pathFor(entry.productId, entry.version);
  }

  Future<Uint8List> _downloadFirmwareRaw(
    FirmwareManifestEntry entry, {
    FirmwareDownloadProgress? onProgress,
  }) async {
    final uri = Uri.parse(entry.downloadUrl);
    final request = http.Request('GET', uri);
    final response = await _client.send(request).timeout(const Duration(minutes: 10));

    if (response.statusCode != 200) {
      throw HttpException('firmware HTTP ${response.statusCode}');
    }

    final total = response.contentLength ?? entry.size;
    final chunks = <int>[];
    var received = 0;

    await for (final chunk in response.stream) {
      chunks.addAll(chunk);
      received += chunk.length;
      onProgress?.call(received, total > 0 ? total : received);
    }

    return Uint8List.fromList(chunks);
  }

  Future<String?> cachedPathForEntry(FirmwareManifestEntry entry) {
    return _cache.cachedPathForEntry(entry);
  }

  Future<String?> cachedPathForCatalogEntry(FirmwareCatalogEntry entry) {
    return _cache.findAnyCachedPath(entry);
  }

  FirmwareLocalCache get cache => _cache;
}
