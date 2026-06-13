import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'ota_debug_log.dart';

const String kFunApBaseUrl = 'http://192.168.4.1';
const String kExpectedApGateway = '192.168.4.1';

const Duration kOtaConnectTimeout = Duration(seconds: 20);

/// 发完 body 后等设备接收、写 flash 并返回 HTTP 头（软 AP 大固件可能很慢）。
const Duration kOtaResponseWaitTimeout = Duration(minutes: 12);

/// 整次上传硬上限（SoftAP 下 1MB+ 可能需 10+ 分钟）。
const Duration kOtaUploadTotalTimeout = Duration(minutes: 20);

/// body 全部发出后，至少再等待此时长才允许因断连/超时推断 OTA 成功（避免 TCP 尾包未收完就提示完成）。
const Duration kOtaAssumeSuccessMinAfterBody = Duration(seconds: 120);

const Duration kOtaResponseBodyTimeout = Duration(seconds: 8);

const int _uploadChunkSize = 16 * 1024;

enum OtaUploadPhase {
  uploadingBody,
  awaitingDevice,
}

typedef OtaUploadPhaseCallback = void Function(OtaUploadPhase phase);

class FunApOtaClient {
  FunApOtaClient({http.Client? client})
      : _ownsClient = client == null,
        _client = client ?? IOClient(_newHttpClient());

  final http.Client _client;
  final bool _ownsClient;

  static HttpClient _newHttpClient() {
    final httpClient = HttpClient();
    httpClient.connectionTimeout = kOtaConnectTimeout;
    /* OTA 上传时 TCP 可能因设备 flash 写入而背压，idle 过短会断连 */
    httpClient.idleTimeout = const Duration(minutes: 2);
    return httpClient;
  }

  void close() {
    if (_ownsClient) {
      _client.close();
      otaLogPhase('http_client_closed');
    }
  }

  Map<String, String> get _closeHeaders => const {'Connection': 'close'};

  /// GET /info（烧录器 JSON；失败时由调用方回退 HTML）。
  Future<String> fetchInfoJson() async {
    final req = http.Request('GET', Uri.parse('$kFunApBaseUrl/info'))
      ..headers.addAll(_closeHeaders);
    final streamed = await _client.send(req).timeout(const Duration(seconds: 8));
    final r = await http.Response.fromStream(streamed);
    if (r.statusCode != 200 || r.body.isEmpty) {
      throw StateError('HTTP ${r.statusCode}');
    }
    return r.body;
  }

  /// GET /system，失败时可再试 /status（部分页面较简）。
  Future<String> fetchSystemHtml() async {
    try {
      final req = http.Request('GET', Uri.parse('$kFunApBaseUrl/system'))
        ..headers.addAll(_closeHeaders);
      final streamed = await _client.send(req).timeout(const Duration(seconds: 8));
      final r = await http.Response.fromStream(streamed);
      if (r.statusCode == 200 && r.body.isNotEmpty) return r.body;
    } catch (_) {}
    final req2 = http.Request('GET', Uri.parse('$kFunApBaseUrl/status'))
      ..headers.addAll(_closeHeaders);
    final streamed2 = await _client.send(req2).timeout(const Duration(seconds: 8));
    final r2 = await http.Response.fromStream(streamed2);
    if (r2.statusCode != 200 || r2.body.isEmpty) {
      throw StateError('HTTP ${r2.statusCode}');
    }
    return r2.body;
  }

  /// 使用独立 [HttpClient] 直传 multipart，带进度/心跳；避免 `package:http` 的 send 长时间无反馈。
  ///
  /// 返回 HTTP 状态码；设备 OTA 后断连时可能返回 200（推断成功）。
  Future<int> uploadFirmwareComplete(
    List<int> firmwareBytes, {
    required String filename,
    OtaUploadPhaseCallback? onPhase,
  }) async {
    final uri = Uri.parse('$kFunApBaseUrl/ota_upload');
    final boundary = '----FunAp${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 20)}';
    final body = _buildMultipartFirmwareBody(
      boundary: boundary,
      filename: filename,
      firmware: firmwareBytes,
    );

    otaLogPhase(
      'http_send_start',
      detail:
          'POST $uri field=firmware file=$filename firmwareBytes=${firmwareBytes.length} '
          'bodyBytes=${body.length} boundary=$boundary',
    );

    final httpClient = _newHttpClient();
    final sw = Stopwatch()..start();
    Timer? heartbeat;
    var bodyFullySent = false;
    Duration? bodyDoneAt;

    try {
      onPhase?.call(OtaUploadPhase.uploadingBody);
      heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
        otaLogPhase(
          'http_send_waiting',
          detail: bodyFullySent ? 'awaiting_response' : 'uploading_body',
          elapsed: sw.elapsed,
        );
      });

      final request = await httpClient
          .postUrl(uri)
          .timeout(kOtaConnectTimeout);
      request.headers.set(HttpHeaders.connectionHeader, 'close');
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      request.contentLength = body.length;

      otaLogPhase('http_connect_ok', detail: 'bodyBytes=${body.length}');

      var sent = 0;
      await () async {
        for (var offset = 0; offset < body.length; offset += _uploadChunkSize) {
          final end = min(offset + _uploadChunkSize, body.length);
          request.add(body.sublist(offset, end));
          sent = end;
          if (sent == body.length || sent % (128 * 1024) == 0) {
            otaLogPhase(
              'http_upload_progress',
              detail: '$sent/${body.length}',
              elapsed: sw.elapsed,
            );
          }
        }
      }().timeout(
        const Duration(minutes: 12),
        onTimeout: () {
          throw TimeoutException('OTA body upload exceeded 12 minutes (sent $sent/${body.length})');
        },
      );
      bodyFullySent = sent == body.length;
      bodyDoneAt = sw.elapsed;
      otaLogPhase('http_upload_body_done', detail: 'sent=$sent', elapsed: sw.elapsed);
      onPhase?.call(OtaUploadPhase.awaitingDevice);

      final HttpClientResponse response;
      try {
        response = await request.close().timeout(kOtaResponseWaitTimeout);
      } on TimeoutException catch (e) {
        if (_mayAssumeOtaSuccess(bodyFullySent, sw.elapsed, bodyDoneAt)) {
          otaLogPhase('http_response_timeout_assume_ok', detail: '$e', elapsed: sw.elapsed);
          return 200;
        }
        rethrow;
      } on SocketException catch (e) {
        if (_mayAssumeOtaSuccess(bodyFullySent, sw.elapsed, bodyDoneAt)) {
          otaLogPhase('http_socket_assume_ok', detail: '$e', elapsed: sw.elapsed);
          return 200;
        }
        rethrow;
      }

      final status = response.statusCode;
      otaLogPhase(
        'http_send_done',
        detail: 'status=$status contentLength=${response.contentLength}',
        elapsed: sw.elapsed,
      );

      try {
        await response.timeout(kOtaResponseBodyTimeout).drain();
        otaLogPhase('http_body_drain_done', elapsed: sw.elapsed);
      } catch (e) {
        otaLogPhase('http_body_drain_skip', detail: '$e', elapsed: sw.elapsed);
      }

      return status;
    } on TimeoutException catch (e) {
      if (_mayAssumeOtaSuccess(bodyFullySent, sw.elapsed, bodyDoneAt)) {
        otaLogPhase('http_total_timeout_assume_ok', detail: '$e', elapsed: sw.elapsed);
        return 200;
      }
      otaLogPhase('http_send_fail', detail: '$e', elapsed: sw.elapsed);
      rethrow;
    } catch (e, st) {
      if (_mayAssumeOtaSuccess(bodyFullySent, sw.elapsed, bodyDoneAt)) {
        otaLogPhase('http_send_fail_assume_ok', detail: '$e', elapsed: sw.elapsed);
        return 200;
      }
      otaLogPhase('http_send_fail', detail: '$e', elapsed: sw.elapsed);
      otaLog('http_send_fail stack', error: e, stackTrace: st);
      rethrow;
    } finally {
      heartbeat?.cancel();
      httpClient.close(force: true);
      otaLogPhase('http_upload_client_closed', elapsed: sw.elapsed);
    }
  }

  static bool _mayAssumeOtaSuccess(
    bool bodyFullySent,
    Duration elapsed,
    Duration? bodyDoneAt,
  ) {
    if (!bodyFullySent || bodyDoneAt == null) {
      return false;
    }
    final sinceBodyDone = elapsed - bodyDoneAt;
    return sinceBodyDone >= kOtaAssumeSuccessMinAfterBody;
  }

  static List<int> _buildMultipartFirmwareBody({
    required String boundary,
    required String filename,
    required List<int> firmware,
  }) {
    final prefix = utf8.encode(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="firmware"; filename="$filename"\r\n'
      'Content-Type: application/octet-stream\r\n'
      '\r\n',
    );
    final suffix = utf8.encode('\r\n--$boundary--\r\n');
    return [...prefix, ...firmware, ...suffix];
  }
}
