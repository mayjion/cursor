import 'package:http/http.dart' as http;

const String kFunApBaseUrl = 'http://192.168.4.1';
const String kExpectedApGateway = '192.168.4.1';

class FunApOtaClient {
  FunApOtaClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// GET /system，失败时可再试 /status（部分页面较简）。
  Future<String> fetchSystemHtml() async {
    try {
      final r = await _client
          .get(Uri.parse('$kFunApBaseUrl/system'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200 && r.body.isNotEmpty) return r.body;
    } catch (_) {}
    final r2 = await _client
        .get(Uri.parse('$kFunApBaseUrl/status'))
        .timeout(const Duration(seconds: 8));
    if (r2.statusCode != 200 || r2.body.isEmpty) {
      throw StateError('HTTP ${r2.statusCode}');
    }
    return r2.body;
  }

  /// Multipart 字段名 [firmware]，与设备网页表单一致。
  Future<http.StreamedResponse> uploadFirmware(
    List<int> bytes, {
    required String filename,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$kFunApBaseUrl/ota_upload'));
    req.files.add(
      http.MultipartFile.fromBytes('firmware', bytes, filename: filename),
    );
    return _client.send(req).timeout(const Duration(minutes: 10));
  }
}
