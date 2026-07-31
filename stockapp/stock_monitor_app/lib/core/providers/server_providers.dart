import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/lan_discovery.dart';
import '../api/stockserver_client.dart';
import '../settings/app_settings.dart';

/// 当前配置下的客户端；未配置 host 时为 null。
final stockServerClientProvider = Provider<StockServerClient?>((ref) {
  final s = ref.watch(appSettingsProvider);
  if (!s.serverEnabled) return null;
  final host = s.serverHost.trim();
  if (host.isEmpty) return null;
  return StockServerClient(host: host, port: s.serverPort);
});

class ServerConnectionState {
  const ServerConnectionState({
    this.checking = false,
    this.connected = false,
    this.message = '',
    this.baseUrl,
  });

  final bool checking;
  final bool connected;
  final String message;
  final String? baseUrl;

  ServerConnectionState copyWith({
    bool? checking,
    bool? connected,
    String? message,
    String? baseUrl,
  }) {
    return ServerConnectionState(
      checking: checking ?? this.checking,
      connected: connected ?? this.connected,
      message: message ?? this.message,
      baseUrl: baseUrl ?? this.baseUrl,
    );
  }
}

class ServerConnectionNotifier extends StateNotifier<ServerConnectionState> {
  ServerConnectionNotifier(this.ref) : super(const ServerConnectionState()) {
    Future.microtask(check);
  }

  final Ref ref;

  Future<bool> check() async {
    final settings = ref.read(appSettingsProvider);
    if (!settings.serverEnabled) {
      state = const ServerConnectionState(
        connected: false,
        message: '已关闭服务端对接',
      );
      return false;
    }
    final host = settings.serverHost.trim();
    if (host.isEmpty) {
      state = const ServerConnectionState(
        connected: false,
        message: '未配置服务端，请搜索局域网或手动填写 IP',
      );
      return false;
    }
    state = state.copyWith(checking: true, message: '检测中…');
    final client = StockServerClient(host: host, port: settings.serverPort);
    final ok = await client.ping();
    client.close();
    state = ServerConnectionState(
      checking: false,
      connected: ok,
      baseUrl: 'http://$host:${settings.serverPort}',
      message: ok ? '已连接 $host:${settings.serverPort}' : '无法连接 $host:${settings.serverPort}',
    );
    return ok;
  }
}

final serverConnectionProvider =
    StateNotifierProvider<ServerConnectionNotifier, ServerConnectionState>(
        (ref) {
  return ServerConnectionNotifier(ref);
});

/// 服务端推荐股票池（仅在已配置并连通时拉取）。
final serverStockPoolProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final conn = ref.watch(serverConnectionProvider);
  final client = ref.watch(stockServerClientProvider);
  if (!conn.connected || client == null) return null;
  return client.stockPool();
});
