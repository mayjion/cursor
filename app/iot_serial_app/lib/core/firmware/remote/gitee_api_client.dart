import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Gitee API v5 拉取私有仓文件（contents → base64 解码）。
class GiteeApiClient {
  GiteeApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _apiBase = 'https://gitee.com/api/v5';

  void close() {
    _client.close();
  }

  /// [path] 仓库内相对路径，如 `manifest.json` 或 `firmware/FL-WIFI-C3.bin.enc`。
  Future<Uint8List> fetchFileContents({
    required String owner,
    required String repo,
    required String path,
    required String branch,
    required String token,
    void Function(int received, int total)? onProgress,
  }) async {
    final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
    final uri = Uri.parse(
      '$_apiBase/repos/$owner/$repo/contents/$encodedPath',
    ).replace(queryParameters: {
      'access_token': token,
      'ref': branch,
    });

    final response = await _client.get(uri).timeout(const Duration(minutes: 5));
    if (response.statusCode != 200) {
      throw HttpException(
        'Gitee API HTTP ${response.statusCode} for $path',
        uri: uri,
      );
    }

    onProgress?.call(response.bodyBytes.length, response.bodyBytes.length);

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Gitee API response is not an object for $path');
    }

    final encoding = decoded['encoding'] as String?;
    final content = decoded['content'] as String?;
    final expectedSize = (decoded['size'] as num?)?.toInt();

    if (encoding != 'base64' || content == null) {
      throw FormatException('Gitee API: unsupported encoding for $path');
    }

    final normalized = content.replaceAll(RegExp(r'\s+'), '');
    final bytes = base64Decode(normalized);

    if (expectedSize != null && bytes.length != expectedSize) {
      throw StateError(
        'Gitee API size mismatch for $path: expected $expectedSize, got ${bytes.length}',
      );
    }

    onProgress?.call(bytes.length, bytes.length);
    return Uint8List.fromList(bytes);
  }
}
