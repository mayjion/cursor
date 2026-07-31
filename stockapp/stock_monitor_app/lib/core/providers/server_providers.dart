import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/stockserver_client.dart';
import '../settings/app_settings.dart';

/// 当前配置下的客户端；未配置 host 时为 null。
final stockServerClientProvider = Provider<StockServerClient?>((ref) {
  final s = ref.watch(appSettingsProvider);
  if (!s.serverEnabled) return null;
  final host = s.serverHost.trim();
  if (host.isEmpty) return null;
  return StockServerClient(
    host: host,
    port: s.serverPort,
    password: s.serverPassword,
  );
});

class ServerConnectionState {
  const ServerConnectionState({
    this.checking = false,
    this.connected = false,
    this.message = '',
    this.baseUrl,
    this.needsPassword = false,
  });

  final bool checking;
  final bool connected;
  final String message;
  final String? baseUrl;
  final bool needsPassword;

  ServerConnectionState copyWith({
    bool? checking,
    bool? connected,
    String? message,
    String? baseUrl,
    bool? needsPassword,
  }) {
    return ServerConnectionState(
      checking: checking ?? this.checking,
      connected: connected ?? this.connected,
      message: message ?? this.message,
      baseUrl: baseUrl ?? this.baseUrl,
      needsPassword: needsPassword ?? this.needsPassword,
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
    final baseUrl = 'http://$host:${settings.serverPort}';
    if (!settings.hasServerPassword) {
      state = ServerConnectionState(
        connected: false,
        baseUrl: baseUrl,
        needsPassword: true,
        message: '首次连接请输入密码',
      );
      return false;
    }
    state = state.copyWith(checking: true, message: '检测中…');
    final client = StockServerClient(
      host: host,
      port: settings.serverPort,
      password: settings.serverPassword,
    );
    try {
      final health = await client.health();
      final alive = health['ok'] == true &&
          (health['service'] == null || health['service'] == 'stockserver');
      if (!alive) {
        state = ServerConnectionState(
          checking: false,
          connected: false,
          baseUrl: baseUrl,
          message: '无法连接 $host:${settings.serverPort}',
        );
        return false;
      }
      final ok = await client.authenticate();
      if (!ok) {
        await ref.read(appSettingsProvider.notifier).clearServerPassword();
        state = ServerConnectionState(
          checking: false,
          connected: false,
          baseUrl: baseUrl,
          needsPassword: true,
          message: '密码错误，请重新输入',
        );
        return false;
      }
      state = ServerConnectionState(
        checking: false,
        connected: true,
        baseUrl: baseUrl,
        message: '已连接 $host:${settings.serverPort}',
      );
      return true;
    } catch (_) {
      state = ServerConnectionState(
        checking: false,
        connected: false,
        baseUrl: baseUrl,
        message: '无法连接 $host:${settings.serverPort}',
      );
      return false;
    } finally {
      client.close();
    }
  }

  /// 用给定密码尝试连接并在成功后写入本地。
  Future<bool> connectWithPassword(String password) async {
    final settings = ref.read(appSettingsProvider);
    final host = settings.serverHost.trim();
    if (host.isEmpty) {
      state = const ServerConnectionState(
        connected: false,
        message: '未配置服务端',
      );
      return false;
    }
    final pwd = password.trim();
    if (pwd.isEmpty) {
      state = ServerConnectionState(
        connected: false,
        needsPassword: true,
        baseUrl: 'http://$host:${settings.serverPort}',
        message: '请输入连接密码',
      );
      return false;
    }
    state = state.copyWith(checking: true, message: '验证密码…');
    final client = StockServerClient(
      host: host,
      port: settings.serverPort,
      password: pwd,
    );
    final result = await client.authenticateResult(pwd);
    client.close();
    if (result != 'ok') {
      final msg = switch (result) {
        'wrong_password' => '密码错误',
        'unsupported' => '服务端过旧，请重启/更新 stockserver',
        _ => '无法连接服务端，请确认已启动且网络可达',
      };
      state = ServerConnectionState(
        checking: false,
        connected: false,
        needsPassword: result == 'wrong_password' || result == 'unsupported',
        baseUrl: 'http://$host:${settings.serverPort}',
        message: msg,
      );
      return false;
    }
    await ref.read(appSettingsProvider.notifier).setServerPassword(pwd);
    await ref.read(appSettingsProvider.notifier).setServerEnabled(true);
    state = ServerConnectionState(
      checking: false,
      connected: true,
      needsPassword: false,
      baseUrl: 'http://$host:${settings.serverPort}',
      message: '已连接 $host:${settings.serverPort}',
    );
    return true;
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
