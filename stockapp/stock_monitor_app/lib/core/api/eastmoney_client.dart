import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/etf_models.dart';
import '../models/institutional_hold_change_record.dart';
import '../models/institutional_hold_summary.dart';
import '../models/research_summary.dart';
import '../models/capital_flow_day.dart';
import '../models/capital_flow_point.dart';
import '../models/recommendation.dart';
import '../models/stock_bar.dart';
import '../models/stock_snapshot.dart';

class EastmoneyException implements Exception {
  EastmoneyException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 东方财富资金流向 API 客户端。
class EastmoneyClient {
  EastmoneyClient({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _maxRetries = 3;
  /// 请求最小间隔（可在批量同步时临时调低）。
  static Duration minRequestGap = const Duration(milliseconds: 150);
  static DateTime? _lastRequestAt;
  static Future<void>? _requestChain;

  /// 临时加快节流，结束后恢复。
  static Future<T> withRequestGap<T>(
    Duration gap,
    Future<T> Function() action,
  ) async {
    final prev = minRequestGap;
    minRequestGap = gap;
    try {
      return await action();
    } finally {
      minRequestGap = prev;
    }
  }

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://data.eastmoney.com/zjlx/',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  static const _f10Headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://emweb.securities.eastmoney.com/',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  /// 识别市场：A 股 + 场内 ETF。
  static String marketFromCode(String code) {
    if (code.length != 6) {
      throw EastmoneyException('不支持的代码: $code');
    }
    // 上交所 ETF
    if (code.startsWith('51') ||
        code.startsWith('56') ||
        code.startsWith('58') ||
        code.startsWith('6')) {
      return 'sh';
    }
    // 深交所 ETF / A 股
    if (code.startsWith('15') ||
        code.startsWith('0') ||
        code.startsWith('3')) {
      return 'sz';
    }
    throw EastmoneyException('不支持的股票代码: $code');
  }

  static bool isEtfCode(String code) {
    if (code.length != 6) return false;
    return code.startsWith('51') ||
        code.startsWith('56') ||
        code.startsWith('58') ||
        code.startsWith('15');
  }

  static String secidFromCode(String code) {
    final market = marketFromCode(code);
    return market == 'sh' ? '1.$code' : '0.$code';
  }

  static String f10CodeFromCode(String code) {
    final market = marketFromCode(code);
    return market == 'sh' ? 'SH$code' : 'SZ$code';
  }

  static String _stripHtml(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  static Map<String, dynamic> _decodeJsonBody(String body) {
    var trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw EastmoneyException('响应为空');
    }
    if (!trimmed.startsWith('{')) {
      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start >= 0 && end > start) {
        trimmed = trimmed.substring(start, end + 1);
      }
    }
    return jsonDecode(trimmed) as Map<String, dynamic>;
  }

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

  /// 日 K OHLCV。
  Future<List<StockBar>> fetchDailyBars(String code, {int limit = 126}) async {
    final map = await _fetchKlineDetail(code, limit: limit, klt: '101');
    final list = map.values.toList()
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    return list;
  }

  /// 周 K OHLCV。
  Future<List<StockBar>> fetchWeeklyBars(String code, {int limit = 30}) async {
    final map = await _fetchKlineDetail(code, limit: limit, klt: '102');
    final list = map.values.toList()
      ..sort((a, b) => a.tradeDate.compareTo(b.tradeDate));
    return list;
  }

  /// 近6个月日资金流 + OHLCV。
  Future<List<CapitalFlowDay>> fetchSixMonthHistory(String code) async {
    const limit = 126;
    final flows = await fetchFlowHistory(code, limit: limit);
    if (flows.isEmpty) return [];

    try {
      final klines = await _fetchKlineDetail(code, limit: limit, klt: '101');
      if (klines.isEmpty) return flows;
      return flows
          .map((flow) {
            final k = klines[flow.tradeDate];
            return CapitalFlowDay(
              code: flow.code,
              tradeDate: flow.tradeDate,
              mainNetInflow: flow.mainNetInflow,
              mainNetRatio: flow.mainNetRatio,
              superNetInflow: flow.superNetInflow,
              bigNetInflow: flow.bigNetInflow,
              midNetInflow: flow.midNetInflow,
              smallNetInflow: flow.smallNetInflow,
              closePrice: k?.close ?? flow.closePrice,
              changePercent: flow.changePercent ?? k?.changePercent,
              open: k?.open,
              high: k?.high,
              low: k?.low,
              volume: k?.volume,
            );
          })
          .toList();
    } catch (_) {
      return flows;
    }
  }

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

  Future<double?> fetchChangePercentOnDate(String code, String date) async {
    final history = await fetchFlowHistory(code, limit: 60);
    for (final day in history) {
      if (day.tradeDate == date && day.changePercent != null) {
        return day.changePercent;
      }
    }
    try {
      final klines = await _fetchKlineDetail(code, limit: 60);
      return klines[date]?.changePercent;
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

  Future<Map<String, StockBar>> _fetchKlineDetail(
    String code, {
    int limit = 126,
    String klt = '101',
  }) async {
    final secid = secidFromCode(code);
    final uri = Uri.parse(
      'https://push2his.eastmoney.com/api/qt/stock/kline/get',
    ).replace(
      queryParameters: {
        'secid': secid,
        'fields1': 'f1,f2,f3,f4,f5,f6',
        'fields2': 'f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61',
        'klt': klt,
        'fqt': '1',
        // 不带 end 时东财常返回 data=null（周K尤其明显）
        'end': '20500101',
        'lmt': limit.toString(),
        'ut': 'b2884a393a59ad64002292a3e90d46a5',
      },
    );
    final resp = await _getJson(uri);
    final data = resp['data'] as Map<String, dynamic>?;
    if (data == null) return {};
    final klines = data['klines'] as List<dynamic>? ?? [];
    final map = <String, StockBar>{};
    for (final line in klines) {
      if (line is! String) continue;
      final parts = line.split(',');
      if (parts.length < 9) continue;
      final date = parts[0];
      map[date] = StockBar.fromKline(
        code: code,
        tradeDate: date,
        open: double.tryParse(parts[1]),
        close: double.tryParse(parts[2]),
        high: double.tryParse(parts[3]),
        low: double.tryParse(parts[4]),
        volume: double.tryParse(parts[5]),
        changePercent: double.tryParse(parts[8]),
      );
    }
    return map;
  }

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        await _throttle();
        final resp = await _client
            .get(uri, headers: headers ?? _headers)
            .timeout(const Duration(seconds: 20));
        if (resp.statusCode != 200) {
          throw EastmoneyException('请求失败: ${resp.statusCode}');
        }
        return _decodeJsonBody(resp.body);
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
        if (elapsed < minRequestGap) {
          await Future<void>.delayed(minRequestGap - elapsed);
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

  /// 沪深 A 股全市场列表（分页）。
  Future<List<StockSnapshot>> fetchAShareUniverse() async {
    const pageSize = 100;
    const fs = 'm:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23';
    const fields = 'f12,f14,f2,f3,f9,f23,f20,f6,f37,f100,f103,f115,f127,f129';
    final all = <StockSnapshot>[];
    var page = 1;
    var total = 1;

    while ((page - 1) * pageSize < total) {
      final uri = Uri.parse('https://push2.eastmoney.com/api/qt/clist/get').replace(
        queryParameters: {
          'pn': page.toString(),
          'pz': pageSize.toString(),
          'po': '1',
          'np': '1',
          'fltt': '2',
          'invt': '2',
          'fid': 'f3',
          'fs': fs,
          'fields': fields,
          'ut': 'fa5fd1943c7b386f172d6893dbfba10b',
        },
      );
      final resp = await _getJson(uri);
      final data = resp['data'] as Map<String, dynamic>?;
      if (data == null) break;
      total = (data['total'] as num?)?.toInt() ?? 0;
      final diff = data['diff'] as List<dynamic>? ?? [];
      for (final item in diff) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final code = (map['f12']?.toString() ?? '').padLeft(6, '0');
        if (code.length != 6) continue;
        final name = map['f14']?.toString() ?? code;
        final conceptsRaw = map['f103']?.toString() ?? '';
        final concepts = conceptsRaw
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final industryClass = map['f100']?.toString() ?? '';
        all.add(
          StockSnapshot(
            code: code,
            name: name,
            peTtm: _toDouble(map['f9']),
            pb: _toDouble(map['f23']),
            marketCap: _toDouble(map['f20']),
            avgAmount: _toDouble(map['f6']),
            changePercent: _toDouble(map['f3']),
            price: _toDouble(map['f2']),
            roe: _toDouble(map['f37']),
            revenueGrowth: _toDouble(map['f115']),
            netProfitGrowth: _toDouble(map['f127']),
            netMargin: _toDouble(map['f129']),
            industryClass: industryClass,
            industry: industryClass,
            concepts: concepts,
            isSt: name.toUpperCase().contains('ST'),
          ),
        );
      }
      page++;
      if (diff.isEmpty) break;
    }
    return all;
  }

  /// 行业板块列表。
  Future<List<IndustryItem>> fetchIndustryBoards({int limit = 50}) async {
    final uri = Uri.parse('https://push2.eastmoney.com/api/qt/clist/get').replace(
      queryParameters: {
        'pn': '1',
        'pz': limit.toString(),
        'po': '1',
        'np': '1',
        'fltt': '2',
        'invt': '2',
        'fid': 'f3',
        'fs': 'm:90+t:2',
        'fields': 'f12,f14,f3,f62',
        'ut': 'fa5fd1943c7b386f172d6893dbfba10b',
      },
    );
    final resp = await _getJson(uri);
    final data = resp['data'] as Map<String, dynamic>?;
    if (data == null) return [];
    final diff = data['diff'] as List<dynamic>? ?? [];
    return diff.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return IndustryItem(
        industry: map['f14']?.toString() ?? '',
        changePercent: _toDouble(map['f3']),
        mainNetInflow: _toDouble(map['f62']),
      );
    }).where((e) => e.industry.isNotEmpty).toList();
  }

  /// 行业成分股代码。
  Future<List<String>> fetchIndustryConstituentCodes(String boardCode) async {
    final uri = Uri.parse('https://push2.eastmoney.com/api/qt/clist/get').replace(
      queryParameters: {
        'pn': '1',
        'pz': '500',
        'po': '1',
        'np': '1',
        'fltt': '2',
        'invt': '2',
        'fid': 'f3',
        'fs': 'b:$boardCode',
        'fields': 'f12',
        'ut': 'fa5fd1943c7b386f172d6893dbfba10b',
      },
    );
    final resp = await _getJson(uri);
    final data = resp['data'] as Map<String, dynamic>?;
    if (data == null) return [];
    final diff = data['diff'] as List<dynamic>? ?? [];
    return diff
        .map((e) => (Map<String, dynamic>.from(e as Map)['f12']?.toString() ?? '').padLeft(6, '0'))
        .where((c) => c.length == 6)
        .toList();
  }

  /// 获取行业板块 code 映射。
  Future<Map<String, String>> fetchIndustryCodeMap({int limit = 30}) async {
    final uri = Uri.parse('https://push2.eastmoney.com/api/qt/clist/get').replace(
      queryParameters: {
        'pn': '1',
        'pz': limit.toString(),
        'po': '1',
        'np': '1',
        'fltt': '2',
        'invt': '2',
        'fid': 'f3',
        'fs': 'm:90+t:2',
        'fields': 'f12,f14',
        'ut': 'fa5fd1943c7b386f172d6893dbfba10b',
      },
    );
    final resp = await _getJson(uri);
    final data = resp['data'] as Map<String, dynamic>?;
    if (data == null) return {};
    final diff = data['diff'] as List<dynamic>? ?? [];
    final map = <String, String>{};
    for (final item in diff) {
      final m = Map<String, dynamic>.from(item as Map);
      final code = m['f12']?.toString() ?? '';
      final name = m['f14']?.toString() ?? '';
      if (code.isNotEmpty && name.isNotEmpty) {
        map[name] = code;
      }
    }
    return map;
  }

  Future<void> enrichSnapshotsWithIndustry(
    List<StockSnapshot> snapshots, {
    int maxBoards = 30,
  }) async {
    final codeMap = await fetchIndustryCodeMap(limit: maxBoards);
    final codeToIndustry = <String, String>{};
    for (final entry in codeMap.entries) {
      try {
        final codes = await fetchIndustryConstituentCodes(entry.value);
        for (final code in codes) {
          codeToIndustry.putIfAbsent(code, () => entry.key);
        }
      } catch (_) {}
    }
    for (var i = 0; i < snapshots.length; i++) {
      final industry = codeToIndustry[snapshots[i].code];
      if (industry != null) {
        snapshots[i] = snapshots[i].copyWith(industry: industry);
      }
    }
  }

  /// 近 20 日主力净流入趋势评分 0-100。
  Future<double> fetchCapitalFlowScore(String code) async {
    try {
      final flows = await fetchFlowHistory(code, limit: 21);
      if (flows.length < 5) return 50;
      final inflows = flows.map((f) => f.mainNetInflow).toList();
      final recent = inflows.length >= 5
          ? inflows.sublist(inflows.length - 5).reduce((a, b) => a + b)
          : inflows.reduce((a, b) => a + b);
      final prior = inflows.length >= 10
          ? inflows.sublist(inflows.length - 10, inflows.length - 5).reduce((a, b) => a + b)
          : inflows.take(inflows.length - 5).fold<double>(0, (a, b) => a + b);
      if (recent > 0 && recent > prior) {
        return (60 + recent / (prior.abs().clamp(1, double.infinity)) * 10).clamp(0, 100);
      }
      if (recent < 0 && recent < prior) {
        return (40 + recent / (prior.abs().clamp(1, double.infinity)) * 10).clamp(0, 100);
      }
      return 50;
    } catch (_) {
      return 50;
    }
  }

  /// 简化技术面评分 0-100。
  Future<double> fetchTechnicalScore(String code) async {
    try {
      final bars = await fetchDailyBars(code, limit: 60);
      if (bars.length < 30) return 50;
      final closes = bars.map((b) => b.close ?? 0).toList();
      final ma20 = closes.sublist(closes.length - 20).reduce((a, b) => a + b) / 20;
      final ma60 = closes.reduce((a, b) => a + b) / closes.length;
      final current = closes.last;
      var score = 50.0;
      if (current > ma20) score += 15;
      if (current > ma60) score += 10;
      if (ma20 > ma60) score += 10;
      final recentHigh = closes.sublist(closes.length - 20).reduce((a, b) => a > b ? a : b);
      final recentLow = closes.sublist(closes.length - 20).reduce((a, b) => a < b ? a : b);
      if (recentHigh > recentLow) {
        final retrace = (recentHigh - current) / (recentHigh - recentLow);
        if (retrace >= 0.2 && retrace <= 0.5) score += 15;
      }
      return score.clamp(0, 100);
    } catch (_) {
      return 50;
    }
  }

  /// 个股基本面与概念题材（实时）。
  Future<StockProfile> fetchStockProfile(String code) async {
    final secid = secidFromCode(code);
    final uri = Uri.parse('https://push2.eastmoney.com/api/qt/ulist.np/get').replace(
      queryParameters: {
        'secids': secid,
        'fields': 'f12,f14,f9,f23,f20,f37,f103,f100',
        'fltt': '2',
        'ut': 'fa5fd1943c7b386f172d6893dbfba10b',
      },
    );
    final resp = await _getJson(uri);
    final diff = resp['data']?['diff'] as List<dynamic>? ?? [];
    if (diff.isEmpty) {
      throw EastmoneyException('未获取到 $code 基本面数据');
    }
    final map = Map<String, dynamic>.from(diff.first as Map);
    final name = map['f14']?.toString() ?? code;
    final industry = map['f100']?.toString() ?? '';
    final conceptsRaw = map['f103']?.toString() ?? '';
    final concepts = conceptsRaw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    var profileIndustry = industry;
    var companySummary = '';
    try {
      final surveyUri = Uri.parse(
        'https://emweb.securities.eastmoney.com/PC_HSF10/CompanySurvey/PageAjax',
      ).replace(queryParameters: {'code': f10CodeFromCode(code)});
      final survey = await _getJson(surveyUri, headers: _f10Headers);
      final jbzl = survey['jbzl'] as List<dynamic>? ?? [];
      if (jbzl.isNotEmpty) {
        final info = Map<String, dynamic>.from(jbzl.first as Map);
        profileIndustry =
            info['EM2016']?.toString().trim().isNotEmpty == true
                ? info['EM2016'].toString()
                : industry;
        companySummary = info['ORG_PROFILE']?.toString().trim() ?? '';
      }
    } catch (_) {}

    final pe = _toDouble(map['f9']);
    var label = '合理';
    if (pe != null && pe < 15) label = '低估';
    if (pe != null && pe > 40) label = '高估';

    return StockProfile(
      code: code,
      name: name,
      industry: profileIndustry,
      peTtm: pe,
      pb: _toDouble(map['f23']),
      roe: _toDouble(map['f37']),
      marketCap: _toDouble(map['f20']),
      valuationLabel: label,
      concepts: concepts,
      companySummary: companySummary,
    );
  }

  /// 概念题材列表。
  Future<List<String>> fetchStockConcepts(String code) async {
    final profile = await fetchStockProfile(code);
    if (profile.concepts.isNotEmpty) return profile.concepts;

    try {
      final uri = Uri.parse(
        'https://emweb.securities.eastmoney.com/PC_HSF10/CoreConception/PageAjax',
      ).replace(queryParameters: {'code': f10CodeFromCode(code)});
      final resp = await _getJson(uri, headers: _f10Headers);
      final ssbk = resp['ssbk'] as List<dynamic>? ?? [];
      return ssbk
          .map((e) => Map<String, dynamic>.from(e as Map)['BOARD_NAME']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 个股新闻。
  Future<List<NewsArticleItem>> fetchStockNews(String code, {int limit = 10}) async {
    final articles = <NewsArticleItem>[];
    var id = 1;

    try {
      final uri = Uri.parse(
        'https://search-api-web.eastmoney.com/search/jsonp',
      ).replace(
        queryParameters: {
          'cb': 'jQuery',
          'param': jsonEncode({
            'uid': '',
            'keyword': code,
            'type': ['cmsArticleWebOld'],
            'client': 'web',
            'clientType': 'web',
            'clientVersion': '1.0.0',
            'pageIndex': 1,
            'pageSize': limit,
          }),
        },
      );
      final decoded = await _getJson(uri);
      final result = decoded['result'] as Map<String, dynamic>?;
      final newsList = result?['cmsArticleWebOld'] as List<dynamic>? ?? [];
      for (final item in newsList) {
        final map = Map<String, dynamic>.from(item as Map);
        articles.add(
          NewsArticleItem(
            id: id++,
            title: _stripHtml(map['title']?.toString() ?? ''),
            source: map['mediaName']?.toString() ?? '',
            url: map['url']?.toString() ?? '',
            summary: _stripHtml(map['content']?.toString() ?? ''),
            stockCode: code,
            publishedAt: map['date']?.toString(),
          ),
        );
      }
    } catch (_) {}

    try {
      final annUri = Uri.parse(
        'https://np-anotice-stock.eastmoney.com/api/security/ann',
      ).replace(
        queryParameters: {
          'page_size': limit.toString(),
          'page_index': '1',
          'ann_type': 'A',
          'client_source': 'web',
          'stock_list': code,
        },
      );
      final annResp = await _getJson(annUri);
      final annList = annResp['data']?['list'] as List<dynamic>? ?? [];
      for (final item in annList) {
        final map = Map<String, dynamic>.from(item as Map);
        final artCode = map['art_code']?.toString() ?? '';
        articles.add(
          NewsArticleItem(
            id: id++,
            title: map['title']?.toString() ?? '',
            source: '公司公告',
            url: artCode.isNotEmpty
                ? 'https://data.eastmoney.com/notices/detail/$code/$artCode.html'
                : '',
            summary: map['columns'] is List && (map['columns'] as List).isNotEmpty
                ? Map<String, dynamic>.from(
                    (map['columns'] as List).first as Map,
                  )['column_name']
                    ?.toString() ??
                    ''
                : '',
            stockCode: code,
            publishedAt: map['notice_date']?.toString(),
          ),
        );
      }
    } catch (_) {}

    return articles.take(limit).toList();
  }

  /// 财经要闻。
  Future<List<NewsArticleItem>> fetchMarketNews({int limit = 20}) async {
    try {
      final uri = Uri.parse(
        'https://np-listapi.eastmoney.com/comm/web/getNewsByColumns',
      ).replace(
        queryParameters: {
          'client': 'web',
          'biz': 'web_news_col',
          'column': '350',
          'order': '1',
          'needInteractData': '0',
          'page_index': '1',
          'page_size': limit.toString(),
          'req_trace': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final decoded = await _getJson(uri);
      final data = decoded['data'] as Map<String, dynamic>?;
      final list = data?['list'] as List<dynamic>? ?? [];
      var id = 1000;
      return list.take(limit).map((a) {
        final map = Map<String, dynamic>.from(a as Map);
        return NewsArticleItem(
          id: id++,
          title: map['title']?.toString() ?? '',
          source: map['mediaName']?.toString() ?? '东方财富',
          url: map['url']?.toString() ?? map['uniqueUrl']?.toString() ?? '',
          summary: map['summary']?.toString() ?? map['title']?.toString() ?? '',
          publishedAt: map['showTime']?.toString(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static const _datacenterHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://data.eastmoney.com/',
    'Accept': 'application/json, text/plain, */*',
  };

  static const _reportHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://data.eastmoney.com/',
    'Accept': 'application/json, text/plain, */*',
  };

  Future<Map<String, dynamic>> _getDatacenterJson(
    String reportName, {
    required String filter,
    String columns = 'ALL',
    int pageSize = 20,
    String sortColumns = 'REPORT_DATE',
  }) async {
    final uri = Uri.parse(
      'https://datacenter-web.eastmoney.com/api/data/v1/get',
    ).replace(
      queryParameters: {
        'reportName': reportName,
        'columns': columns,
        'filter': filter,
        'pageNumber': '1',
        'pageSize': pageSize.toString(),
        'sortTypes': '-1',
        'sortColumns': sortColumns,
        'source': 'WEB',
        'client': 'WEB',
      },
    );
    return _getJson(uri, headers: _datacenterHeaders);
  }

  /// 个股研报摘要。
  Future<ResearchSummary> fetchResearchSummary(String code, {int limit = 10}) async {
    try {
      final begin = DateTime.now().subtract(const Duration(days: 180));
      final beginStr =
          '${begin.year}-${begin.month.toString().padLeft(2, '0')}-${begin.day.toString().padLeft(2, '0')}';
      final endStr =
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
      final uri = Uri.parse('https://reportapi.eastmoney.com/report/list').replace(
        queryParameters: {
          'code': code,
          'pageSize': limit.toString(),
          'pageNo': '1',
          'qType': '0',
          'beginTime': beginStr,
          'endTime': endStr,
        },
      );
      final resp = await _getJson(uri, headers: _reportHeaders);
      final list = resp['data'] as List<dynamic>? ?? [];
      if (list.isEmpty) return const ResearchSummary();

      final ratings = <double>[];
      final predictPes = <double>[];
      double? thisEps;
      double? nextEps;
      var indvInduCode = '';

      for (final item in list) {
        final map = Map<String, dynamic>.from(item as Map);
        final rating = map['emRatingName']?.toString() ?? '';
        ratings.add(ResearchSummary.ratingToScore(rating));
        final pe = double.tryParse(map['predictNextYearPe']?.toString() ?? '');
        if (pe != null && pe > 0) predictPes.add(pe);
        thisEps ??= double.tryParse(map['predictThisYearEps']?.toString() ?? '');
        nextEps ??= double.tryParse(map['predictNextYearEps']?.toString() ?? '');
        indvInduCode = map['indvInduCode']?.toString() ?? indvInduCode;
      }

      final avgRating =
          ratings.isEmpty ? 50.0 : ratings.reduce((a, b) => a + b) / ratings.length;
      double? epsGrowth;
      if (thisEps != null && nextEps != null && thisEps > 0) {
        epsGrowth = (nextEps - thisEps) / thisEps;
      }

      final topRating = list.isNotEmpty
          ? Map<String, dynamic>.from(list.first as Map)['emRatingName']
                  ?.toString() ??
              ''
          : '';

      return ResearchSummary(
        reportCount: list.length,
        avgRatingScore: avgRating,
        epsGrowthRate: epsGrowth,
        avgPredictPe: predictPes.isEmpty
            ? null
            : predictPes.reduce((a, b) => a + b) / predictPes.length,
        topRating: topRating,
        indvInduCode: indvInduCode,
      );
    } catch (_) {
      return const ResearchSummary();
    }
  }

  /// 行业研报评级均值。
  Future<double> fetchIndustryReportScore(String induCode, {int limit = 5}) async {
    if (induCode.isEmpty) return 50;
    try {
      final begin = DateTime.now().subtract(const Duration(days: 90));
      final beginStr =
          '${begin.year}-${begin.month.toString().padLeft(2, '0')}-${begin.day.toString().padLeft(2, '0')}';
      final endStr =
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
      final uri = Uri.parse('https://reportapi.eastmoney.com/report/list').replace(
        queryParameters: {
          'indvInduCode': induCode,
          'pageSize': limit.toString(),
          'pageNo': '1',
          'qType': '1',
          'beginTime': beginStr,
          'endTime': endStr,
        },
      );
      final resp = await _getJson(uri, headers: _reportHeaders);
      final list = resp['data'] as List<dynamic>? ?? [];
      if (list.isEmpty) return 50;
      final scores = list.map((e) {
        final rating =
            Map<String, dynamic>.from(e as Map)['emRatingName']?.toString() ?? '';
        return ResearchSummary.ratingToScore(rating);
      }).toList();
      return scores.reduce((a, b) => a + b) / scores.length;
    } catch (_) {
      return 50;
    }
  }

  /// 批量拉取行业研报评分。
  Future<Map<String, double>> fetchIndustryReportScoreMap(
    Iterable<String> induCodes,
  ) async {
    final map = <String, double>{};
    for (final code in induCodes) {
      if (code.isEmpty || map.containsKey(code)) continue;
      map[code] = await fetchIndustryReportScore(code);
    }
    return map;
  }

  /// 大机构持股变动。
  Future<InstitutionalHoldSummary> fetchInstitutionalHoldChange(String code) async {
    try {
      final orgResp = await _getDatacenterJson(
        'RPT_MAIN_ORGHOLD',
        filter: '(SECURITY_CODE="$code")',
        columns:
            'SECUCODE,SECURITY_CODE,REPORT_DATE,ORG_TYPE,ORG_TYPE_NAME,HOLDCHA,HOLDCHA_NUM,QCHANGE_RATE,HOULD_NUM',
        pageSize: 30,
        sortColumns: 'REPORT_DATE',
      );
      final orgRows = orgResp['result']?['data'] as List<dynamic>? ?? [];

      String latestDate = '';
      for (final row in orgRows) {
        final date = Map<String, dynamic>.from(row as Map)['REPORT_DATE']
                ?.toString() ??
            '';
        if (date.compareTo(latestDate) > 0) latestDate = date;
      }

      InstitutionalHoldSummary? summary;
      if (latestDate.isNotEmpty) {
        final latestRows = orgRows
            .where(
              (r) =>
                  Map<String, dynamic>.from(r as Map)['REPORT_DATE']
                      ?.toString() ==
                  latestDate,
            )
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();

        Map<String, dynamic>? aggregate;
        for (final row in latestRows) {
          if (row['ORG_TYPE']?.toString() == '00') {
            aggregate = row;
            break;
          }
        }

        const majorTypes = {'01', '04', '05'};
        final increasing = <String>[];
        for (final row in latestRows) {
          final type = row['ORG_TYPE']?.toString() ?? '';
          if (!majorTypes.contains(type)) continue;
          final action = row['HOLDCHA']?.toString() ?? '';
          if (action.contains('增') || action.contains('新')) {
            increasing.add(row['ORG_TYPE_NAME']?.toString() ?? type);
          }
        }

        summary = InstitutionalHoldSummary(
          quarterChangeRate: _toDouble(aggregate?['QCHANGE_RATE']),
          summaryAction: aggregate?['HOLDCHA']?.toString() ?? '',
          increasingTypes: increasing,
          reasons: increasing.isNotEmpty
              ? ['${increasing.join('、')}季度增仓']
              : const [],
        );
      }

      final holderResp = await _getDatacenterJson(
        'RPT_F10_EH_HOLDERS',
        filter: '(SECURITY_CODE="$code")(IS_HOLDORG="1")',
        columns: 'HOLDER_NAME,HOLD_NUM_CHANGE,END_DATE,IS_HOLDORG',
        pageSize: 20,
        sortColumns: 'END_DATE',
      );
      final holders = holderResp['result']?['data'] as List<dynamic>? ?? [];

      var newCount = 0;
      var increaseCount = 0;
      var decreaseCount = 0;
      String holderDate = '';
      for (final h in holders) {
        final map = Map<String, dynamic>.from(h as Map);
        final date = map['END_DATE']?.toString() ?? '';
        if (holderDate.isEmpty) holderDate = date;
        if (date != holderDate) continue;
        final name = map['HOLDER_NAME']?.toString() ?? '';
        if (!_isInstitutionHolderName(name)) continue;
        final change = map['HOLD_NUM_CHANGE']?.toString() ?? '';
        if (change.contains('新进')) {
          newCount++;
        } else if (change.contains('增')) {
          increaseCount++;
        } else if (change.contains('减')) {
          decreaseCount++;
        }
      }

      final base = summary ?? const InstitutionalHoldSummary();
      final reasons = [...base.reasons];
      if (newCount > 0) {
        reasons.add('$newCount家大机构新进十大流通股东');
      }
      return InstitutionalHoldSummary(
        quarterChangeRate: base.quarterChangeRate,
        summaryAction: base.summaryAction,
        increasingTypes: base.increasingTypes,
        newHolderCount: newCount,
        increaseHolderCount: increaseCount,
        decreaseHolderCount: decreaseCount,
        reasons: reasons,
      );
    } catch (_) {
      return const InstitutionalHoldSummary();
    }
  }

  static bool _isInstitutionHolderName(String name) {
    if (name.isEmpty) return false;
    const keywords = ['基金', '社保', '保险', 'QFII', '香港中央结算', '证金', '汇金', '资产管理'];
    for (final k in keywords) {
      if (name.contains(k)) return true;
    }
    return false;
  }

  static String? _dateOnly(dynamic raw) {
    final text = raw?.toString() ?? '';
    if (text.isEmpty) return null;
    return text.length >= 10 ? text.substring(0, 10) : text;
  }

  /// 个股机构/股东/高管增减持明细。
  /// 合并：增减持公告 + 高管增减持 + 十大流通股东变动。
  /// 时间、金额、价格无法获取时对应字段为 null。
  Future<List<InstitutionalHoldChangeRecord>> fetchInstitutionalHoldRecords(
    String code, {
    int limit = 40,
  }) async {
    final records = <InstitutionalHoldChangeRecord>[];

    try {
      final resp = await _getDatacenterJson(
        'RPT_SHARE_HOLDER_INCREASE',
        filter: '(SECURITY_CODE="$code")',
        columns: 'ALL',
        pageSize: limit,
        sortColumns: 'NOTICE_DATE',
      );
      final rows = resp['result']?['data'] as List<dynamic>? ?? [];
      for (final item in rows) {
        final map = Map<String, dynamic>.from(item as Map);
        final direction = map['DIRECTION']?.toString() ?? '';
        // CHANGE_NUM 单位：万股
        final changeWan = _toDouble(map['CHANGE_NUM']);
        final changeShares =
            changeWan == null ? null : changeWan * 10000;
        final tradePrice = _toDouble(map['TRADE_AVERAGE_PRICE']) ??
            _toDouble(map['REAL_PRICE']);
        final closePrice = _toDouble(map['CLOSE_PRICE']);
        double? amount;
        if (changeShares != null && tradePrice != null) {
          amount = changeShares * tradePrice;
        }
        records.add(
          InstitutionalHoldChangeRecord(
            holderName: map['HOLDER_NAME']?.toString() ?? '',
            direction: direction.isEmpty ? '变动' : direction,
            tradeDate: _dateOnly(map['TRADE_DATE'] ?? map['END_DATE']),
            noticeDate: _dateOnly(map['NOTICE_DATE']),
            changeShares: changeShares,
            changeAmount: amount,
            tradePrice: tradePrice,
            closePrice: closePrice,
            changeRatio: _toDouble(map['CHANGE_RATE']),
            market: map['MARKET']?.toString() ?? '',
            source: '股东增减持公告',
          ),
        );
      }
    } catch (_) {}

    // 高管/董监高增减持（如三安光电董事长林志强）
    try {
      final execResp = await _getDatacenterJson(
        'RPT_EXECUTIVE_HOLD_DETAILS',
        filter: '(SECURITY_CODE="$code")',
        columns: 'ALL',
        pageSize: limit,
        sortColumns: 'CHANGE_DATE',
      );
      final rows = execResp['result']?['data'] as List<dynamic>? ?? [];
      for (final item in rows) {
        final map = Map<String, dynamic>.from(item as Map);
        final name = map['PERSON_NAME']?.toString() ?? '';
        if (name.isEmpty) continue;
        final begin = _toDouble(map['BEGIN_HOLD_NUM']);
        final end = _toDouble(map['END_HOLD_NUM']) ??
            _toDouble(map['CHANGE_AFTER_HOLDNUM']);
        final shares = _toDouble(map['CHANGE_SHARES']);
        String direction = '变动';
        if (begin != null && end != null) {
          if (end > begin) {
            direction = '增持';
          } else if (end < begin) {
            direction = '减持';
          }
        } else if (shares != null && shares > 0) {
          // 接口股数为绝对值；无期末持仓时按常见披露视为增持
          direction = '增持';
        }
        final position = map['POSITION_NAME']?.toString() ?? '';
        final reason = map['CHANGE_REASON']?.toString() ?? '';
        final tradePrice = _toDouble(map['AVERAGE_PRICE']);
        final amount = _toDouble(map['CHANGE_AMOUNT']) ??
            (shares != null && tradePrice != null
                ? shares * tradePrice
                : null);
        records.add(
          InstitutionalHoldChangeRecord(
            holderName: position.isEmpty ? name : '$name（$position）',
            direction: direction,
            tradeDate: _dateOnly(map['CHANGE_DATE']),
            changeShares: shares?.abs(),
            changeAmount: amount?.abs(),
            tradePrice: tradePrice,
            closePrice: null,
            changeRatio: _toDouble(map['CHANGE_RATIO']),
            market: reason,
            source: '高管增减持',
          ),
        );
      }
    } catch (_) {}

    try {
      final holderResp = await _getDatacenterJson(
        'RPT_F10_EH_HOLDERS',
        filter: '(SECURITY_CODE="$code")',
        columns:
            'HOLDER_NAME,HOLD_NUM,HOLD_NUM_CHANGE,CHANGE_RATIO,END_DATE,IS_HOLDORG,HOLDER_STATE_NEW,NEW_CHANGE_RATIO,HOLDER_MARKET_CAP',
        pageSize: 60,
        sortColumns: 'END_DATE',
      );
      final holders = holderResp['result']?['data'] as List<dynamic>? ?? [];
      for (final item in holders) {
        final map = Map<String, dynamic>.from(item as Map);
        final name = map['HOLDER_NAME']?.toString() ?? '';
        if (name.isEmpty) continue;
        final changeRaw = map['HOLD_NUM_CHANGE']?.toString() ?? '';
        if (changeRaw.isEmpty || changeRaw == '不变' || changeRaw == '-') {
          continue;
        }

        // 个人大股东也展示（不再仅限机构名关键词）
        String direction;
        double? changeShares;
        final asNum = double.tryParse(changeRaw);
        if (changeRaw.contains('新进')) {
          direction = '新进';
          changeShares = _toDouble(map['HOLD_NUM']);
        } else if (asNum != null) {
          direction = asNum > 0 ? '增持' : (asNum < 0 ? '减持' : '不变');
          changeShares = asNum.abs();
          if (direction == '不变') continue;
        } else if (changeRaw.contains('增')) {
          direction = '增持';
        } else if (changeRaw.contains('减')) {
          direction = '减持';
        } else {
          direction = changeRaw;
        }

        records.add(
          InstitutionalHoldChangeRecord(
            holderName: name,
            direction: direction,
            reportDate: _dateOnly(map['END_DATE']),
            changeShares: changeShares,
            changeAmount: null,
            tradePrice: null,
            closePrice: null,
            changeRatio: _toDouble(map['CHANGE_RATIO']) ??
                _toDouble(map['NEW_CHANGE_RATIO']),
            market: '十大流通股东',
            source: '季报披露',
          ),
        );
      }
    } catch (_) {}

    // 去重：同人同日同股数只保留一条（优先有价格的）
    final seen = <String>{};
    final deduped = <InstitutionalHoldChangeRecord>[];
    records.sort((a, b) {
      final da = a.displayDate;
      final db = b.displayDate;
      final cmp = db.compareTo(da);
      if (cmp != 0) return cmp;
      final pa = a.tradePrice != null ? 1 : 0;
      final pb = b.tradePrice != null ? 1 : 0;
      return pb.compareTo(pa);
    });
    for (final r in records) {
      final key =
          '${r.holderName}|${r.displayDate}|${r.direction}|${r.changeShares?.toStringAsFixed(0) ?? ''}';
      if (seen.contains(key)) continue;
      seen.add(key);
      deduped.add(r);
    }

    return deduped.take(limit).toList();
  }

  /// ETF 列表（场内）。
  ///
  /// [minScaleYi]：仅返回规模（亿元）≥ 该阈值的 ETF；列表按规模降序，可提前结束分页。
  Future<List<EtfInfo>> fetchEtfUniverse({
    int pageSize = 100,
    int maxPages = 20,
    double? minScaleYi,
  }) async {
    final all = <EtfInfo>[];
    var page = 1;
    var pages = 1;
    while (page <= pages && page <= maxPages) {
      final uri = Uri.parse(
        'https://datacenter-web.eastmoney.com/api/data/v1/get',
      ).replace(
        queryParameters: {
          'reportName': 'RPT_FUND_ETFLIST',
          'columns': 'ALL',
          'pageNumber': page.toString(),
          'pageSize': pageSize.toString(),
          'sortTypes': '-1',
          'sortColumns': 'DEC_NAV',
          'source': 'WEB',
          'client': 'WEB',
        },
      );
      final decoded = await _getJson(uri, headers: _datacenterHeaders);
      final result = decoded['result'] as Map<String, dynamic>?;
      if (result == null) break;
      pages = (result['pages'] as num?)?.toInt() ?? 1;
      final rows = result['data'] as List<dynamic>? ?? [];
      var hitBelowThreshold = false;
      for (final item in rows) {
        final map = Map<String, dynamic>.from(item as Map);
        final code = map['SECURITY_CODE']?.toString() ?? '';
        if (code.length != 6) continue;
        final scaleYi = _toDouble(map['DEC_NAV']);
        if (minScaleYi != null && (scaleYi ?? 0) < minScaleYi) {
          hitBelowThreshold = true;
          break;
        }
        all.add(
          EtfInfo(
            code: code,
            name: map['SECURITY_NAME_ABBR']?.toString() ?? code,
            indexCode: map['INDEX_CODE']?.toString() ?? '',
            indexName: map['INDEX_NAME']?.toString() ?? '',
            totalShare: _toDouble(map['DEC_TOTALSHARE']),
            // DEC_NAV 在该报表中为规模（亿元），非单位净值。
            scaleYi: scaleYi,
            change1w: _toDouble(map['CHANGE_RATE_1W']),
            change1m: _toDouble(map['CHANGE_RATE_1M']),
            change3m: _toDouble(map['CHANGE_RATE_3M']),
            changeYtd: _toDouble(map['YTD_CHANGE_RATE']),
            category: map['TYPE2']?.toString() ??
                map['TYPE1']?.toString() ??
                '',
          ),
        );
      }
      if (rows.isEmpty || hitBelowThreshold) break;
      page++;
    }
    return all;
  }

  /// 单只 ETF 元信息。
  Future<EtfInfo?> fetchEtfInfo(String code) async {
    try {
      final uri = Uri.parse(
        'https://datacenter-web.eastmoney.com/api/data/v1/get',
      ).replace(
        queryParameters: {
          'reportName': 'RPT_FUND_ETFLIST',
          'columns': 'ALL',
          'filter': '(SECURITY_CODE="$code")',
          'pageNumber': '1',
          'pageSize': '1',
          'source': 'WEB',
          'client': 'WEB',
        },
      );
      final decoded = await _getJson(uri, headers: _datacenterHeaders);
      final rows = decoded['result']?['data'] as List<dynamic>? ?? [];
      if (rows.isEmpty) return null;
      final map = Map<String, dynamic>.from(rows.first as Map);
      return EtfInfo(
        code: code,
        name: map['SECURITY_NAME_ABBR']?.toString() ?? code,
        indexCode: map['INDEX_CODE']?.toString() ?? '',
        indexName: map['INDEX_NAME']?.toString() ?? '',
        totalShare: _toDouble(map['DEC_TOTALSHARE']),
        scaleYi: _toDouble(map['DEC_NAV']),
        change1w: _toDouble(map['CHANGE_RATE_1W']),
        change1m: _toDouble(map['CHANGE_RATE_1M']),
        change3m: _toDouble(map['CHANGE_RATE_3M']),
        changeYtd: _toDouble(map['YTD_CHANGE_RATE']),
        category: map['TYPE2']?.toString() ?? map['TYPE1']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// ETF 份额历史（约 3 年日频）。
  ///
  /// - 日频：`TOTAL_SHARE` 差分 → 日净申购代理
  /// - 季报：`PERIOD_APPLY_SHARE` / `PERIOD_REDEEM_SHARE`（仅季末有值）
  /// - `SHARE_CHANGE_Q`：季初至今累计份额变动（日频也会更新）
  ///
  /// [alignPrices] 为 true 时额外拉日 K 做金额估算（较慢）；批量同步建议关闭。
  Future<List<EtfSharePoint>> fetchEtfShareHistory(
    String code, {
    int limit = 800,
    bool alignPrices = true,
  }) async {
    try {
      final uri = Uri.parse(
        'https://datacenter-web.eastmoney.com/api/data/v1/get',
      ).replace(
        queryParameters: {
          'reportName': 'RPT_FUND_ETF_SHARECHANGE',
          'columns':
              'SECURITY_CODE,CHANGE_DATE,TOTAL_SHARE,PERIOD_APPLY_SHARE,PERIOD_REDEEM_SHARE,SHARE_CHANGE_Q,SHARE_CHANGE_QRATE',
          'filter': '(SECURITY_CODE="$code")',
          'pageNumber': '1',
          'pageSize': limit.toString(),
          'sortTypes': '-1',
          'sortColumns': 'CHANGE_DATE',
          'source': 'WEB',
          'client': 'WEB',
        },
      );
      final decoded = await _getJson(uri, headers: _datacenterHeaders);
      final rows = decoded['result']?['data'] as List<dynamic>? ?? [];
      final raw = <EtfSharePoint>[];
      for (final item in rows) {
        final map = Map<String, dynamic>.from(item as Map);
        final date = _dateOnly(map['CHANGE_DATE']);
        final total = _toDouble(map['TOTAL_SHARE']);
        if (date == null || total == null) continue;
        raw.add(
          EtfSharePoint(
            date: date,
            totalShare: total,
            applyShare: _toDouble(map['PERIOD_APPLY_SHARE']),
            redeemShare: _toDouble(map['PERIOD_REDEEM_SHARE']),
            shareChangeQ: _toDouble(map['SHARE_CHANGE_Q']),
          ),
        );
      }
      // API 倒序 → 正序
      raw.sort((a, b) => a.date.compareTo(b.date));

      Map<String, double> priceMap = {};
      if (alignPrices) {
        try {
          final bars = await fetchDailyBars(code, limit: limit.clamp(60, 900));
          for (final b in bars) {
            if (b.close != null) priceMap[b.tradeDate] = b.close!;
          }
        } catch (_) {}
      }

      final out = <EtfSharePoint>[];
      for (var i = 0; i < raw.length; i++) {
        final cur = raw[i];
        double? net;
        if (cur.isQuarterReport) {
          net = (cur.applyShare ?? 0) - (cur.redeemShare ?? 0);
        } else if (i > 0) {
          net = cur.totalShare - raw[i - 1].totalShare;
        }
        final px = priceMap[cur.date];
        out.add(
          EtfSharePoint(
            date: cur.date,
            totalShare: cur.totalShare,
            applyShare: cur.applyShare,
            redeemShare: cur.redeemShare,
            shareChangeQ: cur.shareChangeQ,
            netShareChange: net,
            closePrice: px,
            netAmount: net != null && px != null ? net * px : null,
          ),
        );
      }
      return out;
    } catch (_) {
      return [];
    }
  }
}
