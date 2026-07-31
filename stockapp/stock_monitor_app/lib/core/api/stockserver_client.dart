import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lan_discovery.dart';

/// 对接 stockserver HTTP API。
class StockServerClient {
  StockServerClient({
    required this.host,
    this.port = LanDiscovery.defaultHttpPort,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String host;
  final int port;
  final http.Client _http;

  String get baseUrl => 'http://$host:$port';

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> health() async {
    final resp = await _http.get(_uri('/api/health')).timeout(
          const Duration(seconds: 4),
        );
    if (resp.statusCode != 200) {
      throw Exception('health HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('invalid health payload');
    }
    return body;
  }

  Future<bool> ping() async {
    try {
      final h = await health();
      return h['ok'] == true &&
          (h['service'] == null || h['service'] == 'stockserver');
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> stockPool({bool refresh = false}) async {
    final resp = await _http
        .get(_uri('/api/stocks/pool', refresh ? {'refresh': 'true'} : null))
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw Exception('stocks/pool HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('invalid pool payload');
    }
    return body;
  }

  Future<Map<String, dynamic>> stockDetail(String code) async {
    final resp = await _http
        .get(_uri('/api/stocks/${code.padLeft(6, '0')}'))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('stocks/$code HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('invalid detail payload');
    }
    return body;
  }

  Future<Map<String, dynamic>> dashboard({bool refresh = false}) async {
    final resp = await _http
        .get(_uri('/api/dashboard', refresh ? {'refresh': 'true'} : null))
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw Exception('dashboard HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('invalid dashboard payload');
    }
    return body;
  }

  Future<Map<String, dynamic>> timing({bool refresh = false}) async {
    final resp = await _http
        .get(_uri('/api/timing', refresh ? {'refresh': 'true'} : null))
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw Exception('timing HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('invalid timing payload');
    }
    return body;
  }

  void close() => _http.close();
}
