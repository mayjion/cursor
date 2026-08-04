import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lan_discovery.dart';

/// 对接 stockserver HTTP API。
class StockServerClient {
  StockServerClient({
    required this.host,
    this.port = LanDiscovery.defaultHttpPort,
    this.password = '',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String host;
  final int port;
  final String password;
  final http.Client _http;

  static const String passwordHeader = 'X-App-Password';

  String get baseUrl => 'http://$host:$port';

  Map<String, String> get _authHeaders {
    final pwd = password.trim();
    if (pwd.isEmpty) return const {};
    return {passwordHeader: pwd};
  }

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

  /// 校验连接密码。
  /// 返回：ok / wrong_password / unreachable / unsupported
  Future<String> authenticateResult([String? overridePassword]) async {
    final pwd = (overridePassword ?? password).trim();
    try {
      final resp = await _http
          .post(
            _uri('/api/auth'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              if (pwd.isNotEmpty) passwordHeader: pwd,
            },
            body: jsonEncode({'password': pwd}),
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is Map && body['ok'] == true) return 'ok';
        return 'wrong_password';
      }
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return 'wrong_password';
      }
      if (resp.statusCode == 404) return 'unsupported';
      return 'unreachable';
    } catch (_) {
      return 'unreachable';
    }
  }

  /// 校验连接密码；成功返回 true，密码错误返回 false。
  Future<bool> authenticate([String? overridePassword]) async {
    return (await authenticateResult(overridePassword)) == 'ok';
  }

  Future<bool> ping() async {
    try {
      final h = await health();
      final alive = h['ok'] == true &&
          (h['service'] == null || h['service'] == 'stockserver');
      if (!alive) return false;
      if (password.trim().isEmpty) return false;
      return authenticate();
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> stockPool({bool refresh = false}) async {
    final resp = await _http
        .get(
          _uri('/api/stocks/pool', refresh ? {'refresh': 'true'} : null),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode == 401) {
      throw Exception('密码错误或未授权');
    }
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
        .get(
          _uri('/api/stocks/${code.padLeft(6, '0')}'),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 401) {
      throw Exception('密码错误或未授权');
    }
    if (resp.statusCode != 200) {
      throw Exception('stocks/$code HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('invalid detail payload');
    }
    return body;
  }

  /// Kimi 风格投研报告（多年财务 / 业务结构 / SWOT / 评级）。
  Future<Map<String, dynamic>> stockAnalysis(
    String code, {
    bool refresh = false,
  }) async {
    final resp = await _http
        .get(
          _uri(
            '/api/stocks/${code.padLeft(6, '0')}/analysis',
            refresh ? {'refresh': 'true'} : null,
          ),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 90));
    return _decodeMap(resp, 'stocks/analysis');
  }

  Future<Map<String, dynamic>> dashboard({bool refresh = false}) async {
    final resp = await _http
        .get(
          _uri('/api/dashboard', refresh ? {'refresh': 'true'} : null),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode == 401) {
      throw Exception('密码错误或未授权');
    }
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
        .get(
          _uri('/api/timing', refresh ? {'refresh': 'true'} : null),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode == 401) {
      throw Exception('密码错误或未授权');
    }
    if (resp.statusCode != 200) {
      throw Exception('timing HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('invalid timing payload');
    }
    return body;
  }

  Future<Map<String, dynamic>> _decodeMap(http.Response resp, String tag) async {
    if (resp.statusCode == 401) {
      throw Exception('密码错误或未授权');
    }
    if (resp.statusCode == 404) {
      throw Exception('$tag 不存在');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('$tag HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('invalid $tag payload');
    }
    return body;
  }

  Future<Map<String, dynamic>> watchlist({bool refresh = true}) async {
    final resp = await _http
        .get(
          _uri('/api/watchlist', {'refresh': refresh ? 'true' : 'false'}),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 30));
    return _decodeMap(resp, 'watchlist');
  }

  Future<Map<String, dynamic>> addWatchlist({
    required String code,
    String? name,
    String? market,
    String? assetType,
    String indexName = '',
    String note = '',
  }) async {
    final resp = await _http
        .post(
          _uri('/api/watchlist'),
          headers: {
            ..._authHeaders,
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode({
            'code': code.padLeft(6, '0'),
            if (name != null) 'name': name,
            if (market != null) 'market': market,
            if (assetType != null) 'asset_type': assetType,
            'index_name': indexName,
            'note': note,
          }),
        )
        .timeout(const Duration(seconds: 20));
    return _decodeMap(resp, 'watchlist/add');
  }

  Future<Map<String, dynamic>> addWatchlistBatch(
    List<Map<String, dynamic>> items,
  ) async {
    final resp = await _http
        .post(
          _uri('/api/watchlist/batch'),
          headers: {
            ..._authHeaders,
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode({'items': items}),
        )
        .timeout(const Duration(seconds: 60));
    return _decodeMap(resp, 'watchlist/batch');
  }

  Future<Map<String, dynamic>> removeWatchlist(String code) async {
    final resp = await _http
        .delete(
          _uri('/api/watchlist/${code.padLeft(6, '0')}'),
          headers: _authHeaders,
        )
        .timeout(const Duration(seconds: 15));
    return _decodeMap(resp, 'watchlist/delete');
  }

  Future<Map<String, dynamic>> removeWatchlistBatch(List<String> codes) async {
    final resp = await _http
        .post(
          _uri('/api/watchlist/delete'),
          headers: {
            ..._authHeaders,
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode({
            'codes': codes.map((c) => c.padLeft(6, '0')).toList(),
          }),
        )
        .timeout(const Duration(seconds: 20));
    return _decodeMap(resp, 'watchlist/delete-batch');
  }

  void close() => _http.close();
}
