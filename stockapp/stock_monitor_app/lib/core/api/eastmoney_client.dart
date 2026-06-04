import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/capital_flow_day.dart';
import '../models/capital_flow_point.dart';

class EastmoneyException implements Exception {
  EastmoneyException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 东方财富资金流向 API 客户端。
class EastmoneyClient {
  EastmoneyClient({http.Client? client})
      : _client = client ??
            http.Client();

  final http.Client _client;

  static const _maxRetries = 3;
  static const _minRequestGap = Duration(milliseconds: 350);
  static DateTime? _lastRequestAt;
  static Future<void>? _requestChain;

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://data.eastmoney.com/zjlx/',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  static String marketFromCode(String code) {
    if (code.startsWith('6')) return 'sh';
    if (code.startsWith('0') || code.startsWith('3')) return 'sz';
    throw EastmoneyException('不支持的股票代码: $code');
  }

  static String secidFromCode(String code) {
    final market = marketFromCode(code);
    return market == 'sh' ? '1.$code' : '0.$code';
  }

  /// 拉取股票名称与当日实时资金流。
  Future<({String name, CapitalFlowDay? todayFlow})> fetchStockQuote(
    String code,
  ) async {
    final secid = secidFromCode(code);
    final uri = Uri.parse('https://push2.eastmoney.com/api/qt/stock/get').replace(
      queryParameters: {
        'secid': secid,
        'fltt': '2',
        'fields':
            'f57,f58,f62,f184,f66,f69,f72,f75,f78,f81,f84,f87,f43,f60,f170',
        'ut': 'fa5fd1943c7b386f172d6893dbfba10b',
      },
    );
    final resp = await _getJson(uri);
    final data = resp['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw EastmoneyException('未获取到 $code 行情数据');
    }
    final name = (data['f58'] as String?) ?? code;
    final today = _todayFromQuote(code, data);
    return (name: name, todayFlow: today);
  }

  /// 当日资金流 + 行情：主力/散户取自分时最后一笔（与当日曲线一致），占比/现价取自行情。
  Future<CapitalFlowDay?> fetchTodayCapitalFlow(String code) async {
    final quote = await fetchStockQuote(code);
    final meta = quote.todayFlow;
    List<CapitalFlowPoint> intraday = [];
    try {
      intraday = await fetchIntradayFlow(code);
    } catch (_) {}

    if (intraday.isEmpty && meta == null) return null;

    final last = intraday.isNotEmpty ? intraday.last : null;
    final date = _formatDate(DateTime.now());
    return CapitalFlowDay(
      code: code,
      tradeDate: date,
      mainNetInflow: last?.mainNetInflow ?? 0,
      smallNetInflow: last?.retailNetInflow ?? 0,
      mainNetRatio: meta?.mainNetRatio ?? 0,
      superNetInflow: 0,
      bigNetInflow: 0,
      midNetInflow: 0,
      closePrice: meta?.closePrice,
      changePercent: meta?.changePercent,
    );
  }

  CapitalFlowDay? _todayFromQuote(String code, Map<String, dynamic> data) {
    final ratio = _toDouble(data['f184']);
    final close = _toDouble(data['f43']);
    final change = _toDouble(data['f170']);
    if (close == null && ratio == null) return null;
    final date = _formatDate(DateTime.now());
    return CapitalFlowDay(
      code: code,
      tradeDate: date,
      mainNetInflow: 0,
      mainNetRatio: ratio ?? 0,
      closePrice: close,
      changePercent: change,
    );
  }

  /// 当日分时资金流（分钟级，主力/散户为当日累计净流入）。
  Future<List<CapitalFlowPoint>> fetchIntradayFlow(String code) async {
    final secid = secidFromCode(code);
    final uri = Uri.parse(
      'https://push2.eastmoney.com/api/qt/stock/fflow/kline/get',
    ).replace(
      queryParameters: {
        'lmt': '0',
        'klt': '1',
        'secid': secid,
        'fields1': 'f1,f2,f3,f7',
        'fields2':
            'f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61,f62,f63,f64,f65',
        'ut': 'b2884a393a59ad64002292a3e90d46a5',
      },
    );
    final resp = await _getJson(uri);
    final data = resp['data'] as Map<String, dynamic>?;
    if (data == null) return [];
    final klines = data['klines'] as List<dynamic>? ?? [];
    final list = <CapitalFlowPoint>[];
    for (final line in klines) {
      if (line is! String) continue;
      final parts = line.split(',');
      if (parts.length < 3) continue;
      final timeLabel = parts[0].contains(' ')
          ? parts[0].split(' ').last
          : parts[0];
      list.add(CapitalFlowPoint(
        timeLabel: timeLabel,
        mainNetInflow: double.tryParse(parts[1]) ?? 0,
        retailNetInflow: double.tryParse(parts[2]) ?? 0,
      ));
    }
    return list;
  }

  /// 近6个月（约126个交易日）日资金流，含收盘价与涨跌幅（优先资金流接口，少打 K 线）。
  Future<List<CapitalFlowDay>> fetchSixMonthHistory(String code) async {
    const limit = 126;
    final flows = await fetchFlowHistory(code, limit: limit);
    if (flows.isEmpty) return [];

    final needsKline = flows.any((d) => d.changePercent == null);
    if (!needsKline) return flows;

    try {
      final klines = await _fetchKlineDetail(code, limit: limit);
      if (klines.isEmpty) return flows;
      return flows
          .map(
            (flow) => CapitalFlowDay(
              code: flow.code,
              tradeDate: flow.tradeDate,
              mainNetInflow: flow.mainNetInflow,
              mainNetRatio: flow.mainNetRatio,
              superNetInflow: flow.superNetInflow,
              bigNetInflow: flow.bigNetInflow,
              midNetInflow: flow.midNetInflow,
              smallNetInflow: flow.smallNetInflow,
              closePrice: klines[flow.tradeDate]?.close ?? flow.closePrice,
              changePercent:
                  flow.changePercent ?? klines[flow.tradeDate]?.changePercent,
            ),
          )
          .toList();
    } catch (_) {
      return flows;
    }
  }

  /// 历史日资金流（近 N 条），含收盘价、涨跌幅（fields2 扩展字段）。
  Future<List<CapitalFlowDay>> fetchFlowHistory(
    String code, {
    int limit = 30,
  }) async {
    final secid = secidFromCode(code);
    final uri = Uri.parse(
      'https://push2his.eastmoney.com/api/qt/stock/fflow/daykline/get',
    ).replace(
      queryParameters: {
        'lmt': limit.toString(),
        'klt': '101',
        'secid': secid,
        'fields1': 'f1,f2,f3,f7',
        'fields2':
            'f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61,f62,f63,f64,f65',
        'ut': 'b2884a393a59ad64002292a3e90d46a5',
      },
    );
    final resp = await _getJson(uri);
    final data = resp['data'] as Map<String, dynamic>?;
    if (data == null) return [];
    final klines = data['klines'] as List<dynamic>? ?? [];
    final list = <CapitalFlowDay>[];
    for (final line in klines) {
      if (line is! String) continue;
      final parts = line.split(',');
      if (parts.length < 7) continue;
      list.add(CapitalFlowDay(
        code: code,
        tradeDate: parts[0],
        mainNetInflow: double.tryParse(parts[1]) ?? 0,
        smallNetInflow: double.tryParse(parts[2]) ?? 0,
        midNetInflow: double.tryParse(parts[3]) ?? 0,
        bigNetInflow: double.tryParse(parts[4]) ?? 0,
        superNetInflow: double.tryParse(parts[5]) ?? 0,
        mainNetRatio: double.tryParse(parts[6]) ?? 0,
        closePrice: parts.length >= 12 ? double.tryParse(parts[11]) : null,
        changePercent: parts.length >= 13 ? double.tryParse(parts[12]) : null,
      ));
    }
    return list.reversed.toList();
  }

  /// 指定交易日涨跌幅（%）；优先本地缓存逻辑，尽量不请求 K 线。
  Future<double?> fetchChangePercentOnDate(String code, String date) async {
    final history = await fetchFlowHistory(code, limit: 60);
    for (final day in history) {
      if (day.tradeDate == date && day.changePercent != null) {
        return day.changePercent;
      }
    }
    try {
      final klines = await _fetchKlineChanges(code, limit: 60);
      return klines[date];
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, double>> fetchKlineChangeMap(
    String code, {
    int limit = 126,
  }) async {
    try {
      final detail = await _fetchKlineDetail(code, limit: limit);
      final map = <String, double>{};
      for (final e in detail.entries) {
        if (e.value.changePercent != null) {
          map[e.key] = e.value.changePercent!;
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, double>> _fetchKlineChanges(
    String code, {
    int limit = 60,
  }) async {
    final detail = await _fetchKlineDetail(code, limit: limit);
    return {
      for (final e in detail.entries)
        if (e.value.changePercent != null)
          e.key: e.value.changePercent!,
    };
  }

  Future<Map<String, _KlineDay>> _fetchKlineDetail(
    String code, {
    int limit = 126,
  }) async {
    final secid = secidFromCode(code);
    final uri = Uri.parse(
      'https://push2his.eastmoney.com/api/qt/stock/kline/get',
    ).replace(
      queryParameters: {
        'secid': secid,
        'fields1': 'f1,f2,f3,f4,f5,f6',
        'fields2': 'f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61',
        'klt': '101',
        'fqt': '1',
        'lmt': limit.toString(),
        'ut': 'b2884a393a59ad64002292a3e90d46a5',
      },
    );
    final resp = await _getJson(uri);
    final data = resp['data'] as Map<String, dynamic>?;
    if (data == null) return {};
    final klines = data['klines'] as List<dynamic>? ?? [];
    final map = <String, _KlineDay>{};
    for (final line in klines) {
      if (line is! String) continue;
      final parts = line.split(',');
      if (parts.length < 9) continue;
      final date = parts[0];
      map[date] = _KlineDay(
        close: double.tryParse(parts[2]),
        changePercent: double.tryParse(parts[8]),
      );
    }
    return map;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    Object? lastError;
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        await _throttle();
        final resp = await _client
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 20));
        if (resp.statusCode != 200) {
          throw EastmoneyException('请求失败: ${resp.statusCode}');
        }
        var body = resp.body.trim();
        if (body.isEmpty) {
          throw EastmoneyException('响应为空');
        }
        if (body.startsWith('jQuery')) {
          final start = body.indexOf('{');
          final end = body.lastIndexOf('}');
          if (start >= 0 && end > start) {
            body = body.substring(start, end + 1);
          }
        }
        return jsonDecode(body) as Map<String, dynamic>;
      } on EastmoneyException catch (e) {
        lastError = e;
      } catch (e) {
        lastError = e;
      }
      if (attempt < _maxRetries - 1) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    throw EastmoneyException(
      '网络请求失败（已重试$_maxRetries次）: $lastError',
    );
  }

  static Future<void> _throttle() {
    final previous = _requestChain ?? Future<void>.value();
    final next = previous.then((_) async {
      final last = _lastRequestAt;
      if (last != null) {
        final elapsed = DateTime.now().difference(last);
        if (elapsed < _minRequestGap) {
          await Future<void>.delayed(_minRequestGap - elapsed);
        }
      }
      _lastRequestAt = DateTime.now();
    });
    _requestChain = next;
    return next;
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static String _formatDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  void close() => _client.close();
}

class _KlineDay {
  const _KlineDay({this.close, this.changePercent});
  final double? close;
  final double? changePercent;
}
