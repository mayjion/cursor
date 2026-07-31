import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// stockserver 局域网发现与健康检查。
class DiscoveredServer {
  const DiscoveredServer({
    required this.host,
    required this.port,
    this.name = '星沉观察',
    this.source = 'probe',
  });

  final String host;
  final int port;
  final String name;
  final String source; // udp | probe | manual

  String get baseUrl => 'http://$host:$port';

  @override
  String toString() => '$name · $host:$port ($source)';
}

class LanDiscovery {
  static const int defaultHttpPort = 8787;
  static const int defaultDiscoveryPort = 48787;

  /// 并行探测 + UDP 监听，返回找到的服务端列表。
  static Future<List<DiscoveredServer>> discover({
    int httpPort = defaultHttpPort,
    int discoveryPort = defaultDiscoveryPort,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final found = <String, DiscoveredServer>{};

    void add(DiscoveredServer s) {
      final key = '${s.host}:${s.port}';
      final prev = found[key];
      if (prev == null || (prev.source == 'probe' && s.source == 'udp')) {
        found[key] = s;
      }
    }

    final udpFuture = _listenUdp(
      discoveryPort: discoveryPort,
      timeout: timeout,
      onFound: add,
    );
    final probeFuture = _probeSubnet(
      httpPort: httpPort,
      timeout: timeout,
      onFound: add,
    );

    await Future.wait([udpFuture, probeFuture]);
    final list = found.values.toList()
      ..sort((a, b) => a.host.compareTo(b.host));
    return list;
  }

  static Future<DiscoveredServer?> checkHost(
    String host, {
    int port = defaultHttpPort,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final h = host.trim();
    if (h.isEmpty) return null;
    try {
      final uri = Uri.parse('http://$h:$port/api/health');
      final resp = await http.get(uri).timeout(timeout);
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is! Map || body['ok'] != true) return null;
      if (body['service'] != null && body['service'] != 'stockserver') {
        return null;
      }
      final name = (body['name'] as String?) ?? '星沉观察';
      final httpPort = (body['http_port'] as num?)?.toInt() ?? port;
      return DiscoveredServer(
        host: h,
        port: httpPort,
        name: name,
        source: 'manual',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _listenUdp({
    required int discoveryPort,
    required Duration timeout,
    required void Function(DiscoveredServer) onFound,
  }) async {
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
    } catch (_) {
      // 端口被占时仍可走 HTTP 探测
      try {
        sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      } catch (_) {
        return;
      }
    }

    final done = Completer<void>();
    Timer(timeout, () {
      if (!done.isCompleted) done.complete();
    });

    sock.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = sock!.receive();
      if (dg == null) return;
      try {
        final text = utf8.decode(dg.data);
        final map = jsonDecode(text);
        if (map is! Map || map['service'] != 'stockserver') return;
        final port = (map['http_port'] as num?)?.toInt() ?? defaultHttpPort;
        final name = (map['name'] as String?) ?? '星沉观察';
        final host = dg.address.address;
        if (host.startsWith('127.')) return;
        onFound(DiscoveredServer(
          host: host,
          port: port,
          name: name,
          source: 'udp',
        ));
        final ips = map['lan_ips'];
        if (ips is List) {
          for (final ip in ips) {
            if (ip is String && ip.isNotEmpty && !ip.startsWith('127.')) {
              onFound(DiscoveredServer(
                host: ip,
                port: port,
                name: name,
                source: 'udp',
              ));
            }
          }
        }
      } catch (_) {}
    });

    await done.future;
    sock.close();
  }

  static Future<void> _probeSubnet({
    required int httpPort,
    required Duration timeout,
    required void Function(DiscoveredServer) onFound,
  }) async {
    final prefixes = await _localPrefixes();
    if (prefixes.isEmpty) {
      prefixes.addAll(['192.168.1', '192.168.0', '10.0.0']);
    }

    const concurrency = 40;
    final hosts = <String>[];
    for (final prefix in prefixes) {
      for (var i = 1; i <= 254; i++) {
        hosts.add('$prefix.$i');
      }
    }

    var index = 0;
    Future<void> worker() async {
      while (true) {
        if (index >= hosts.length) return;
        final i = index++;
        final host = hosts[i];
        final hit = await checkHost(
          host,
          port: httpPort,
          timeout: const Duration(milliseconds: 450),
        );
        if (hit != null) {
          onFound(DiscoveredServer(
            host: hit.host,
            port: hit.port,
            name: hit.name,
            source: 'probe',
          ));
        }
      }
    }

    await Future.wait(
      List.generate(concurrency, (_) => worker()),
    ).timeout(timeout, onTimeout: () => <void>[]);
  }

  static Future<List<String>> _localPrefixes() async {
    final prefixes = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.')) continue;
          final parts = ip.split('.');
          if (parts.length == 4) {
            prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
          }
        }
      }
    } catch (_) {}
    return prefixes.toList();
  }
}
