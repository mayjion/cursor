import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api/lan_discovery.dart';
import '../../core/background/scan_scheduler.dart';
import '../../core/engine/local_scan_engine.dart';
import '../../core/models/stock_snapshot.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/providers/investment_providers.dart';
import '../../core/providers/server_providers.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/app_strings.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _scanning = false;
  bool _searchingLan = false;
  bool _testing = false;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  List<DiscoveredServer> _discovered = const [];

  bool _syncedFromPrefs = false;

  @override
  void initState() {
    super.initState();
    _hostCtrl = TextEditingController();
    _portCtrl = TextEditingController(
      text: '${LanDiscovery.defaultHttpPort}',
    );
    // prefs 异步加载完成后同步到输入框（避免在 build 里改 controller）
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFieldsFromSettings());
  }

  void _syncFieldsFromSettings() {
    if (!mounted || _syncedFromPrefs) return;
    final settings = ref.read(appSettingsProvider);
    if (!settings.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncFieldsFromSettings());
      return;
    }
    _syncedFromPrefs = true;
    _hostCtrl.text = settings.serverHost;
    _portCtrl.text =
        '${settings.serverPort > 0 ? settings.serverPort : LanDiscovery.defaultHttpPort}';
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _onNightScanToggle(bool enabled) async {
    final notifier = ref.read(appSettingsProvider.notifier);
    final strings = ref.read(appStringsProvider);
    await notifier.setNightScanEnabled(enabled);
    if (enabled) {
      await ScanScheduler.scheduleNext();
      if (!ref.read(appSettingsProvider).batteryGuideShown) {
        if (mounted) await _showBatteryGuide(strings);
        await notifier.setBatteryGuideShown(true);
      }
    } else {
      await ScanScheduler.cancel();
    }
  }

  Future<void> _showBatteryGuide(AppStrings strings) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.batteryOptimizeTitle),
        content: Text(strings.batteryOptimizeMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.isZh ? '稍后' : 'Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: Text(strings.openSettings),
          ),
        ],
      ),
    );
  }

  Future<void> _pickScanTime(AppSettingsState settings) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: settings.scanHour, minute: settings.scanMinute),
    );
    if (picked == null) return;
    await ref.read(appSettingsProvider.notifier).setScanTime(
          picked.hour,
          picked.minute,
        );
    if (settings.nightScanEnabled) {
      await ScanScheduler.scheduleNext();
    }
  }

  Future<void> _runScan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      await runLocalScan(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(appStringsProvider).refreshDone)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${ref.read(appStringsProvider).refreshFailed}: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  int _parsePort() {
    final v = int.tryParse(_portCtrl.text.trim());
    return (v == null || v < 1 || v > 65535)
        ? LanDiscovery.defaultHttpPort
        : v;
  }

  Future<void> _searchLan() async {
    if (_searchingLan) return;
    final strings = ref.read(appStringsProvider);
    setState(() {
      _searchingLan = true;
      _discovered = const [];
    });
    try {
      final port = _parsePort();
      if (_portCtrl.text.trim().isEmpty) {
        _portCtrl.text = '$port';
      }
      final list = await LanDiscovery.discover(httpPort: port);
      if (!mounted) return;
      setState(() => _discovered = list);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            list.isEmpty
                ? strings.serverNotFound
                : '${strings.serverFound}: ${list.length}',
          ),
        ),
      );
      if (list.length == 1) {
        await _applyServer(list.first);
      }
    } finally {
      if (mounted) setState(() => _searchingLan = false);
    }
  }

  Future<void> _applyServer(DiscoveredServer s) async {
    _hostCtrl.text = s.host;
    _portCtrl.text = '${s.port}';
    final notifier = ref.read(appSettingsProvider.notifier);
    await notifier.setServerEndpoint(s.host, s.port);
    await ref.read(serverConnectionProvider.notifier).check();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${ref.read(appStringsProvider).serverConnected}: ${s.host}:${s.port}')),
    );
  }

  Future<void> _saveAndTest() async {
    if (_testing) return;
    final strings = ref.read(appStringsProvider);
    final host = _hostCtrl.text.trim();
    final port = _parsePort();
    _portCtrl.text = '$port';
    setState(() => _testing = true);
    try {
      final notifier = ref.read(appSettingsProvider.notifier);
      await notifier.setServerHost(host);
      await notifier.setServerPort(port);
      await notifier.setServerEnabled(true);
      final hit = await LanDiscovery.checkHost(host, port: port);
      await ref.read(serverConnectionProvider.notifier).check();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hit != null
                ? '${strings.serverConnected}: ${hit.host}:${hit.port}'
                : strings.serverDisconnected,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final conn = ref.watch(serverConnectionProvider);
    final scanMeta = ref.watch(scanProgressProvider);
    final isRunning = scanMeta.status == ScanStatus.running || _scanning;

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsTitle)),
      body: ListView(
        children: [
          ListTile(
            title: Text(strings.serverSection),
            subtitle: Text(strings.serverSubtitle),
          ),
          SwitchListTile(
            title: Text(strings.serverEnable),
            value: settings.serverEnabled,
            onChanged: (v) async {
              await notifier.setServerEnabled(v);
              await ref.read(serverConnectionProvider.notifier).check();
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              conn.checking
                  ? '…'
                  : (conn.connected
                      ? '${strings.serverConnected} · ${conn.baseUrl ?? ''}'
                      : '${strings.serverDisconnected}${conn.message.isNotEmpty ? ' · ${conn.message}' : ''}'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: conn.connected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _hostCtrl,
              decoration: InputDecoration(
                labelText: strings.serverHostLabel,
                hintText: strings.serverHostHint,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _portCtrl,
              decoration: InputDecoration(
                labelText: strings.serverPortLabel,
                hintText: '${LanDiscovery.defaultHttpPort}',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _searchingLan ? null : _searchLan,
                    icon: _searchingLan
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_find),
                    label: Text(
                      _searchingLan
                          ? strings.serverSearching
                          : strings.serverSearchLan,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _saveAndTest,
                    icon: const Icon(Icons.link),
                    label: Text(strings.serverSave),
                  ),
                ),
              ],
            ),
          ),
          if (_discovered.isNotEmpty)
            ..._discovered.map(
              (s) => ListTile(
                leading: Icon(
                  s.source == 'udp' ? Icons.broadcast_on_home : Icons.lan,
                ),
                title: Text('${s.host}:${s.port}'),
                subtitle: Text('${s.name} · ${s.source}'),
                trailing: TextButton(
                  onPressed: () => _applyServer(s),
                  child: Text(strings.serverSave),
                ),
              ),
            ),
          const Divider(),
          ListTile(
            title: Text(strings.themeSection),
            subtitle: Text(_themeName(strings, settings.themeIndex)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(strings.themeIndigo)),
                ButtonSegment(value: 1, label: Text(strings.themeTeal)),
                ButtonSegment(value: 2, label: Text(strings.themeOrange)),
              ],
              selected: {settings.themeIndex},
              onSelectionChanged: (s) => notifier.setThemeIndex(s.first),
            ),
          ),
          const Divider(),
          ListTile(title: Text(strings.languageSection)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'zh', label: Text('中文')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {settings.languageCode},
              onSelectionChanged: (s) => notifier.setLanguageCode(s.first),
            ),
          ),
          const Divider(),
          SwitchListTile(
            title: Text(strings.nightScanSection),
            subtitle: Text(strings.nightScanSubtitle),
            value: settings.nightScanEnabled,
            onChanged: isRunning ? null : _onNightScanToggle,
          ),
          ListTile(
            title: Text(strings.scanTimeSection),
            subtitle: Text(
              '${settings.scanHour.toString().padLeft(2, '0')}:'
              '${settings.scanMinute.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.schedule),
            onTap: isRunning ? null : () => _pickScanTime(settings),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: FilledButton.icon(
              onPressed: isRunning ? null : _runScan,
              icon: isRunning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(isRunning ? strings.scanRunning : strings.runScanNow),
            ),
          ),
          if (isRunning) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(value: scanMeta.progress / 100),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(scanMeta.progressMessage),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton(
                onPressed: () {
                  LocalScanEngine.requestCancel();
                },
                child: Text(strings.cancelScan),
              ),
            ),
          ],
          if (scanMeta.lastScanAt != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                '${strings.scanLastUpdate}: ${scanMeta.lastScanAt}'
                '${scanMeta.lastDurationMs != null ? ' · ${strings.scanDuration}: ${(scanMeta.lastDurationMs! / 1000).round()}s' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(strings.scanHint,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          const Divider(),
          ListTile(title: Text(strings.recLimitSection)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 5, label: Text('5')),
                ButtonSegment(value: 10, label: Text('10')),
                ButtonSegment(value: 15, label: Text('15')),
                ButtonSegment(value: 20, label: Text('20')),
              ],
              selected: {settings.recommendationLimit},
              onSelectionChanged: (s) => notifier.setRecommendationLimit(s.first),
            ),
          ),
          const Divider(),
          ListTile(title: Text(strings.filterSection)),
          SwitchListTile(
            title: Text(strings.excludeStar),
            value: settings.excludeStarMarket,
            onChanged: notifier.setExcludeStarMarket,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'all', label: Text(strings.marketCapAll)),
                ButtonSegment(
                    value: 'large', label: Text(strings.marketCapLarge)),
                ButtonSegment(value: 'mid', label: Text(strings.marketCapMid)),
                ButtonSegment(
                    value: 'small', label: Text(strings.marketCapSmall)),
              ],
              selected: {settings.marketCapFilter},
              onSelectionChanged: (s) => notifier.setMarketCapFilter(s.first),
            ),
          ),
          const Divider(),
          SwitchListTile(
            title: Text(strings.notifySection),
            subtitle: Text(strings.notifySubtitle),
            value: settings.notifyEnabled,
            onChanged: (v) async {
              await notifier.setNotifyEnabled(v);
              await NotificationService.instance
                  .scheduleCloseReminder(enabled: v);
            },
          ),
          SwitchListTile(
            title: Text(strings.recNotifySection),
            subtitle: Text(strings.recNotifySubtitle),
            value: settings.recommendationNotifyEnabled,
            onChanged: notifier.setRecommendationNotifyEnabled,
          ),
          SwitchListTile(
            title: Text(strings.reversalNotifySection),
            subtitle: Text(strings.reversalNotifySubtitle),
            value: settings.reversalNotifyEnabled,
            onChanged: notifier.setReversalNotifyEnabled,
          ),
          const Divider(),
          _HistoryPerformanceSection(strings: strings),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              color: Theme.of(context)
                  .colorScheme
                  .errorContainer
                  .withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(strings.disclaimer,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _themeName(AppStrings s, int i) {
    return switch (i) {
      1 => s.themeTeal,
      2 => s.themeOrange,
      _ => s.themeIndigo,
    };
  }
}

class _HistoryPerformanceSection extends ConsumerWidget {
  const _HistoryPerformanceSection({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(recommendationHistoryProvider);
    return ExpansionTile(
      title: Text(strings.historyPerformance),
      children: [
        historyAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('$e'),
          ),
          data: (items) {
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(strings.noData),
              );
            }
            return Column(
              children: items.take(20).map((item) {
                return ListTile(
                  dense: true,
                  title: Text('${item.tradeDate} · ${item.name}'),
                  subtitle: Text(
                    '${strings.compositeScore} ${item.compositeScore.toStringAsFixed(1)}',
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}
