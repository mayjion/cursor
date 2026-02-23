import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/device/base_device.dart';
import '../../core/device/device_manager.dart';
import '../../core/protocol/frame.dart';
import '../../core/storage/device_entity.dart';
import '../../core/storage/device_storage.dart';

/// BLE serial tool: RX/TX, HEX/Str, clear, byte count, timestamp, save, loop send.
class SerialToolPanel extends ConsumerStatefulWidget {
  const SerialToolPanel({super.key});

  @override
  ConsumerState<SerialToolPanel> createState() => _SerialToolPanelState();
}

class _SerialToolPanelState extends ConsumerState<SerialToolPanel> {
  /// Received packets: (timestamp, payload) for timestamp display and save.
  final List<(DateTime, Uint8List)> _rxPackets = [];
  final ScrollController _rxScrollController = ScrollController();
  final TextEditingController _sendController = TextEditingController();
  final TextEditingController _loopIntervalController = TextEditingController(text: '1000');
  bool _rxHexMode = false;
  bool _txHexMode = false;
  bool _showTimestamp = false;
  bool _loopSend = false;
  BaseDevice? _subscribedDevice;
  StreamSubscription<Frame>? _rxSubscription;
  Timer? _loopTimer;
  DeviceManagerNotifier? _cachedManager;
  int _selectedBaudIndex = 4; // 115200
  bool _useCustomBaud = false;
  int _customBaudRate = 115200;
  int _selectedDataBitsIndex = 3; // 8
  int _selectedStopBitsIndex = 0; // 1
  int _selectedParityIndex = 0; // 0=none
  int _workMode = 0; // 0=BLE, 1=ESP-NOW
  int _txByteCount = 0;
  bool _hasFetchedBaud = false;
  bool _fetchScheduled = false;
  /// Last sent data payload + time; used to filter BLE write echo (some Android stacks deliver own write as notification).
  Uint8List? _lastSentPayload;
  DateTime? _lastSentAt;

  int get _rxByteCount => _rxPackets.fold<int>(0, (s, p) => s + p.$2.length);

  /// Parse UART baud (4 bytes LE) from status query ACK.
  /// ACK layout: [0]=status, [1]=ble, [2]=has_peer, [3..8]=mac, [9]=work_mode, [10]=device_type_len, [11..]=device_type, then 4 bytes baud, then 3 bytes data_bits, stop_bits, parity.
  static int? _parseBaudFromStatusAck(Uint8List payload) {
    if (payload.length < 11) return null;
    final dtLen = payload[10];
    final baudOffset = 11 + dtLen;
    if (baudOffset + 4 > payload.length) return null;
    return payload[baudOffset] |
        (payload[baudOffset + 1] << 8) |
        (payload[baudOffset + 2] << 16) |
        (payload[baudOffset + 3] << 24);
  }

  /// Parse UART data_bits, stop_bits, parity (3 bytes) after baud in status ACK. Returns null if not present.
  static (int dataBits, int stopBits, int parity)? _parseUartExtraFromStatusAck(Uint8List payload) {
    if (payload.length < 11) return null;
    final dtLen = payload[10];
    final baudOffset = 11 + dtLen;
    if (baudOffset + 7 > payload.length) return null;
    final dataBits = payload[baudOffset + 4];
    final stopBits = payload[baudOffset + 5];
    final parity = payload[baudOffset + 6];
    return (dataBits, stopBits, parity);
  }

  /// Fetch device state (baud + work mode) and update UI. Sets _hasFetchedBaud only on success so failure can retry.
  /// Returns true if state was updated, false on timeout or parse failure.
  Future<bool> _fetchAndSetDeviceState(BaseDevice device, DeviceManagerNotifier manager) async {
    final ack = await _sendControlAndWaitAck(device, manager, Frame(
      type: FrameType.control,
      cmd: FrameCmd.statusQuery,
      seq: manager.nextSeq(),
      payload: Uint8List(0),
    ));
    if (!mounted) return false;
    if (ack == null || ack.payload.isEmpty || ack.payload[0] != AckStatus.ok) {
      if (mounted) setState(() => _fetchScheduled = false);
      return false;
    }
    final p = ack.payload;
    final baud = _parseBaudFromStatusAck(p);
    if (baud == null) {
      if (mounted) setState(() => _fetchScheduled = false);
      return false;
    }
    final idx = _baudRates.indexOf(baud);
    final workMode = p.length > 9 ? p[9] : 0;
    final uartExtra = _parseUartExtraFromStatusAck(p);
    if (mounted) {
      setState(() {
        if (idx >= 0) {
          _selectedBaudIndex = idx;
          _useCustomBaud = false;
        } else {
          _useCustomBaud = true;
          _customBaudRate = baud;
          _selectedBaudIndex = 0;
        }
        _workMode = workMode == 1 ? 1 : 0;
        _hasFetchedBaud = true;
        if (uartExtra != null) {
          final di = _dataBitsOptions.indexOf(uartExtra.$1);
          if (di >= 0) _selectedDataBitsIndex = di;
          final si = _stopBitsOptions.indexOf(uartExtra.$2);
          if (si >= 0) _selectedStopBitsIndex = si;
          final pi = _parityOptions.indexWhere((e) => e.$1 == uartExtra.$3);
          if (pi >= 0) _selectedParityIndex = pi;
        }
      });
    }
    return true;
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    _rxSubscription?.cancel();
    _rxScrollController.dispose();
    _sendController.dispose();
    _loopIntervalController.dispose();
    super.dispose();
  }

  void _ensureSubscribed(BaseDevice? device) {
    if (device == _subscribedDevice) return;
    _rxSubscription?.cancel();
    _subscribedDevice = device;
    if (device == null) return;
    _rxSubscription = device.onFrame.listen((frame) {
      if (frame.type != FrameType.data || frame.cmd != FrameCmd.dataPayload) return;
      if (frame.payload.isEmpty) return;
      // Filter BLE write echo: some Android BLE stacks deliver our own write as onValueReceived.
      if (_lastSentPayload != null &&
          _lastSentAt != null &&
          frame.payload.length == _lastSentPayload!.length &&
          _listEquals(frame.payload, _lastSentPayload!) &&
          DateTime.now().difference(_lastSentAt!).inMilliseconds < 500) {
        return;
      }
      if (mounted) {
        setState(() {
          _rxPackets.add((DateTime.now(), Uint8List.fromList(frame.payload)));
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_rxScrollController.hasClients) return;
          final pos = _rxScrollController.position;
          _rxScrollController.jumpTo(pos.maxScrollExtent);
        });
      }
    });
  }

  String _rxContentToSave(bool hex) {
    if (_rxPackets.isEmpty) return '';
    final sb = StringBuffer();
    for (final (dt, bytes) in _rxPackets) {
      if (_showTimestamp) {
        sb.write('[${_formatTime(dt)}] ');
      }
      sb.write(_bytesToDisplay(bytes.toList(), hex));
      if (_showTimestamp) sb.writeln();
    }
    return sb.toString().trim();
  }

  static String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  static String _bytesToDisplay(List<int> bytes, bool hex) {
    if (bytes.isEmpty) return '';
    if (hex) {
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _bytesToDisplayFromUint8(Uint8List bytes, bool hex) {
    return _bytesToDisplay(bytes.toList(), hex);
  }

  static Uint8List _parseSendContent(String text, bool hexMode) {
    if (hexMode) {
      final parts = text.replaceAll(RegExp(r'\s+'), ' ').trim().split(' ');
      final bytes = <int>[];
      for (final p in parts) {
        if (p.isEmpty) continue;
        final v = int.tryParse(p, radix: 16);
        if (v == null || v < 0 || v > 255) continue;
        bytes.add(v);
      }
      return Uint8List.fromList(bytes);
    }
    return Uint8List.fromList(utf8.encode(text));
  }

  /// Send control frame and wait for ACK (same seq). Returns ACK frame or null on timeout.
  Future<Frame?> _sendControlAndWaitAck(BaseDevice device, DeviceManagerNotifier manager, Frame frame) async {
    final completer = Completer<Frame?>();
    StreamSubscription<Frame>? sub;
    sub = device.onFrame.listen((f) {
      if (f.type != FrameType.ack || f.seq != frame.seq) return;
      if (!completer.isCompleted) completer.complete(f);
      sub?.cancel();
    });
    await manager.send(frame);
    final result = await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        sub?.cancel();
        return null;
      },
    );
    return result;
  }

  static const List<int> _baudRates = [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600];
  static const int _minCustomBaud = 300;
  static const int _maxCustomBaud = 2000000;
  static const List<int> _dataBitsOptions = [5, 6, 7, 8];
  static const List<int> _stopBitsOptions = [1, 2];
  static const List<(int value, String label)> _parityOptions = [(0, '无'), (1, '奇'), (2, '偶')];

  static Uint8List _uartConfigPayload(int baud, int dataBits, int stopBits, int parity) {
    final payload = Uint8List(15);
    payload[0] = baud & 0xFF;
    payload[1] = (baud >> 8) & 0xFF;
    payload[2] = (baud >> 16) & 0xFF;
    payload[3] = (baud >> 24) & 0xFF;
    payload[4] = dataBits;
    payload[5] = stopBits;
    payload[6] = parity;
    for (int i = 7; i < 15; i++) payload[i] = 0; // tx/rx pins default 0
    return payload;
  }

  /// Parse "AA:BB:CC:DD:EE:FF" or "AABBCCDDEEFF" to 6 bytes, or null.
  static List<int>? _parseMacString(String s) {
    final normalized = s.replaceAll(RegExp(r'[\s\-:]'), '').toLowerCase();
    if (normalized.length != 12) return null;
    final bytes = <int>[];
    for (int i = 0; i < 12; i += 2) {
      final v = int.tryParse(normalized.substring(i, i + 2), radix: 16);
      if (v == null || v < 0 || v > 255) return null;
      bytes.add(v);
    }
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(currentDeviceProvider);
    final manager = ref.read(deviceManagerProvider.notifier);
    _cachedManager = manager;
    _ensureSubscribed(device);

    if (device == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('设备未连接')),
      );
    }

    if (!_hasFetchedBaud && !_fetchScheduled) {
      _fetchScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAndSetDeviceState(device, manager));
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('串口工具', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // Receive area: byte count + 清空/保存 on first row; 字符串/HEX/时间戳 on second row
          Row(
            children: [
              Text(
                '接收 ($_rxByteCount 字节)',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: _rxPackets.isEmpty && _txByteCount == 0
                    ? null
                    : () => setState(() {
                          _rxPackets.clear();
                          _txByteCount = 0;
                        }),
                child: const Text('清空'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: _rxPackets.isEmpty ? null : () => Share.share(_rxContentToSave(_rxHexMode), subject: '串口接收数据'),
                child: const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              SegmentedButton<bool>(
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                segments: const [
                  ButtonSegment(value: false, label: Text('字符串')),
                  ButtonSegment(value: true, label: Text('HEX')),
                ],
                selected: {_rxHexMode},
                onSelectionChanged: (s) => setState(() => _rxHexMode = s.first),
              ),
              FilterChip(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                label: const Text('时间戳'),
                selected: _showTimestamp,
                onSelected: (v) => setState(() => _showTimestamp = v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              controller: _rxScrollController,
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                _rxPackets.isEmpty
                    ? ''
                    : _rxPackets
                        .map((p) => _showTimestamp
                            ? '[${_formatTime(p.$1)}] ${_bytesToDisplayFromUint8(p.$2, _rxHexMode)}'
                            : _bytesToDisplayFromUint8(p.$2, _rxHexMode))
                        .join(_showTimestamp ? '\n' : ''),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Send area: byte count on first row, then mode toggle
          Row(
            children: [
              Text(
                '发送 ($_txByteCount 字节)',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('字符串')),
                  ButtonSegment(value: true, label: Text('HEX')),
                ],
                selected: {_txHexMode},
                onSelectionChanged: (s) => setState(() => _txHexMode = s.first),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _sendController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: '输入要发送的内容（HEX 模式用空格分隔，如 01 02 0A）',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: () => _doSend(manager),
                child: const Text('发送'),
              ),
              const SizedBox(width: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('循环发送', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 70,
                    child: TextField(
                      controller: _loopIntervalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '间隔(ms)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => _updateLoopTimer(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _loopSend,
                    onChanged: (v) => setState(() {
                      _loopSend = v;
                      _updateLoopTimer();
                    }),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          const Text('串口配置', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<int>(
                value: _useCustomBaud ? -1 : (_selectedBaudIndex < _baudRates.length ? _baudRates[_selectedBaudIndex] : 115200),
                items: [
                  ..._baudRates.map((b) => DropdownMenuItem(value: b, child: Text('$b'))),
                  DropdownMenuItem(value: -1, child: Text('自定义 (${_customBaudRate})')),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  if (v == -1) {
                    final result = await _showCustomBaudDialog(context);
                    if (result != null && mounted) {
                      setState(() {
                        _customBaudRate = result;
                        _useCustomBaud = true;
                      });
                    }
                  } else {
                    setState(() {
                      _useCustomBaud = false;
                      _selectedBaudIndex = _baudRates.indexOf(v);
                    });
                  }
                },
              ),
              DropdownButton<int>(
                value: _dataBitsOptions[_selectedDataBitsIndex.clamp(0, _dataBitsOptions.length - 1)],
                items: _dataBitsOptions.map((b) => DropdownMenuItem(value: b, child: Text('$b 位'))).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedDataBitsIndex = _dataBitsOptions.indexOf(v));
                },
              ),
              DropdownButton<int>(
                value: _stopBitsOptions[_selectedStopBitsIndex.clamp(0, _stopBitsOptions.length - 1)],
                items: _stopBitsOptions.map((s) => DropdownMenuItem(value: s, child: Text('$s 停止位'))).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedStopBitsIndex = _stopBitsOptions.indexOf(v));
                },
              ),
              DropdownButton<int>(
                value: _parityOptions[_selectedParityIndex.clamp(0, _parityOptions.length - 1)].$1,
                items: _parityOptions.map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedParityIndex = _parityOptions.indexWhere((e) => e.$1 == v));
                },
              ),
              FilledButton.tonal(
                onPressed: () async {
                  final device = ref.read(currentDeviceProvider);
                  final manager = ref.read(deviceManagerProvider.notifier);
                  if (device == null) return;
                  final baud = _useCustomBaud ? _customBaudRate : _baudRates[_selectedBaudIndex.clamp(0, _baudRates.length - 1)];
                  final dataBits = _dataBitsOptions[_selectedDataBitsIndex.clamp(0, _dataBitsOptions.length - 1)];
                  final stopBits = _stopBitsOptions[_selectedStopBitsIndex.clamp(0, _stopBitsOptions.length - 1)];
                  final parity = _parityOptions[_selectedParityIndex.clamp(0, _parityOptions.length - 1)].$1;
                  final seq = manager.nextSeq();
                  final ack = await _sendControlAndWaitAck(device, manager, Frame(
                    type: FrameType.control,
                    cmd: FrameCmd.uartConfig,
                    seq: seq,
                    payload: _uartConfigPayload(baud, dataBits, stopBits, parity),
                  ));
                  if (!mounted) return;
                  final ok = ack != null && ack.payload.isNotEmpty && ack.payload[0] == AckStatus.ok;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok ? '串口参数已设置' : '设置失败'),
                  ));
                },
                child: const Text('应用'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('工作模式', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Row(
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('BLE')),
                  ButtonSegment(value: 1, label: Text('ESP-NOW 仅')),
                ],
                selected: {_workMode},
                onSelectionChanged: (s) => setState(() => _workMode = s.first),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: () async {
                  final device = ref.read(currentDeviceProvider);
                  final manager = ref.read(deviceManagerProvider.notifier);
                  if (device == null) return;
                  final seq = manager.nextSeq();
                  final ack = await _sendControlAndWaitAck(device, manager, Frame(
                    type: FrameType.control,
                    cmd: FrameCmd.setWorkMode,
                    seq: seq,
                    payload: Uint8List.fromList([_workMode]),
                  ));
                  if (!mounted) return;
                  final ok = ack != null && ack.payload.isNotEmpty && ack.payload[0] == AckStatus.ok;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok ? '工作模式已设置，设备将重启' : '设置失败'),
                  ));
                },
                child: const Text('应用'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Peer 管理（添加请使用对端 WiFi MAC）', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () async {
                  final ok = await _fetchAndSetDeviceState(device, manager);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok ? '已刷新波特率与工作模式' : '刷新失败或超时'),
                    ));
                  }
                },
                child: const Text('刷新'),
              ),
              FilledButton.tonal(
                onPressed: () => _showStatusQuery(context, device, manager),
                child: const Text('状态查询'),
              ),
              FilledButton.tonal(
                onPressed: () => _showPeerAddDialog(context, device, manager),
                child: const Text('添加 Peer'),
              ),
              FilledButton.tonal(
                onPressed: () => _showPeerRemoveDialog(context, device, manager),
                child: const Text('删除 Peer'),
              ),
              FilledButton.tonal(
                onPressed: () => _clearAllPeers(context, device, manager),
                child: const Text('清空全部'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showStatusQuery(BuildContext context, BaseDevice device, DeviceManagerNotifier manager) async {
    final seq = manager.nextSeq();
    final ack = await _sendControlAndWaitAck(device, manager, Frame(
      type: FrameType.control,
      cmd: FrameCmd.statusQuery,
      seq: seq,
      payload: Uint8List(0),
    ));
    if (!context.mounted) return;
    if (ack == null || ack.payload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('状态查询超时')));
      return;
    }
    final p = ack.payload;
    // [0]=status, [1]=ble_connected, [2]=has_peer, [3..8]=wifi_mac(6), [9]=work_mode
    final bleConnected = p.length > 1 && p[1] == 1;
    final hasPeer = p.length > 2 && p[2] == 1;
    String wifiMac = '';
    if (p.length >= 9) {
      wifiMac = '${p[3].toRadixString(16).padLeft(2, '0')}:${p[4].toRadixString(16).padLeft(2, '0')}:${p[5].toRadixString(16).padLeft(2, '0')}:${p[6].toRadixString(16).padLeft(2, '0')}:${p[7].toRadixString(16).padLeft(2, '0')}:${p[8].toRadixString(16).padLeft(2, '0')}';
    }
    final workMode = p.length > 9 ? p[9] : 0;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设备状态'),
        content: SingleChildScrollView(
          child: Text(
            'BLE 已连接: ${bleConnected ? "是" : "否"}\n'
            '有 Peer: ${hasPeer ? "是" : "否"}\n'
            '本机 WiFi MAC: ${wifiMac.isEmpty ? "-" : wifiMac}\n'
            '工作模式: ${workMode == 0 ? "BLE" : "ESP-NOW 仅"}',
          ),
        ),
        actions: [
          if (wifiMac.isNotEmpty)
            TextButton(
              onPressed: () async {
                final entity = await DeviceStorage.get(device.id);
                if (entity != null) {
                  await DeviceStorage.save(entity.copyWith(wifiMac: wifiMac));
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已更新本机 WiFi MAC 到已保存设备')));
                  }
                }
              },
              child: const Text('更新本机 WiFi MAC 到已保存设备'),
            ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _showPeerAddDialog(BuildContext context, BaseDevice device, DeviceManagerNotifier manager) async {
    final allSaved = await DeviceStorage.list();
    final peersWithMac = allSaved.where((e) => e.wifiMac != null && e.id != device.id).toList();

    final macController = TextEditingController();
    bool useFromList = peersWithMac.isNotEmpty;
    DeviceEntity? selectedEntity = peersWithMac.isNotEmpty ? peersWithMac.first : null;
    int channel = 1;

    final result = await showDialog<(String?, int)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('添加 Peer'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('从已保存设备选择')),
                      ButtonSegment(value: false, label: Text('手动输入 MAC')),
                    ],
                    selected: {useFromList},
                    onSelectionChanged: (s) => setDialogState(() => useFromList = s.first),
                  ),
                  const SizedBox(height: 12),
                  if (useFromList) ...[
                    if (peersWithMac.isEmpty)
                      const Text('暂无带 WiFi MAC 的其它设备。请先保存对端设备并连接一次以获取其 WiFi MAC。', style: TextStyle(fontSize: 13))
                    else ...[
                      DropdownButton<DeviceEntity>(
                        value: selectedEntity,
                        isExpanded: true,
                        items: peersWithMac
                            .map((e) => DropdownMenuItem(value: e, child: Text('${e.name} (${e.wifiMac})')))
                            .toList(),
                        onChanged: (v) => setDialogState(() => selectedEntity = v),
                      ),
                    ],
                  ] else
                    TextField(
                      controller: macController,
                      decoration: const InputDecoration(
                        labelText: 'WiFi MAC（如 AA:BB:CC:DD:EE:FF）',
                        hintText: '对端设备的 WiFi MAC，非 BLE 地址',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  DropdownButton<int>(
                    value: channel,
                    items: List.generate(14, (i) => i + 1).map((c) => DropdownMenuItem(value: c, child: Text('信道 $c'))).toList(),
                    onChanged: (v) => v != null ? setDialogState(() => channel = v) : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
              FilledButton(
                onPressed: (useFromList && (peersWithMac.isEmpty || selectedEntity == null))
                    ? null
                    : () {
                        if (useFromList) {
                          Navigator.of(ctx).pop((selectedEntity!.wifiMac, channel));
                        } else {
                          Navigator.of(ctx).pop((macController.text, channel));
                        }
                      },
                child: const Text('添加'),
              ),
            ],
          );
        },
      ),
    );
    macController.dispose();
    if (result == null) return;
    final (macStr, chan) = result;
    if (macStr == null) return;
    final macBytes = _parseMacString(macStr);
    if (macBytes == null || macBytes.length != 6) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入有效的 6 字节 WiFi MAC')));
      return;
    }
    final payload = Uint8List(7);
    payload.setRange(0, 6, macBytes);
    payload[6] = chan;
    final seq = manager.nextSeq();
    final ack = await _sendControlAndWaitAck(device, manager, Frame(
      type: FrameType.control,
      cmd: FrameCmd.peerAdd,
      seq: seq,
      payload: payload,
    ));
    if (!context.mounted) return;
    final ok = ack != null && ack.payload.isNotEmpty && ack.payload[0] == AckStatus.ok;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Peer 已添加' : '添加失败')));
  }

  Future<void> _showPeerRemoveDialog(BuildContext context, BaseDevice device, DeviceManagerNotifier manager) async {
    final macController = TextEditingController();
    final macStr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除 Peer'),
        content: TextField(
          controller: macController,
          decoration: const InputDecoration(
            labelText: 'WiFi MAC',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(macController.text), child: const Text('删除')),
        ],
      ),
    );
    macController.dispose();
    if (macStr == null) return;
    final macBytes = _parseMacString(macStr);
    if (macBytes == null || macBytes.length != 6) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入有效的 6 字节 MAC')));
      return;
    }
    final seq = manager.nextSeq();
    final ack = await _sendControlAndWaitAck(device, manager, Frame(
      type: FrameType.control,
      cmd: FrameCmd.peerRemove,
      seq: seq,
      payload: Uint8List.fromList(macBytes),
    ));
    if (!context.mounted) return;
    final ok = ack != null && ack.payload.isNotEmpty && ack.payload[0] == AckStatus.ok;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Peer 已删除' : '删除失败')));
  }

  Future<void> _clearAllPeers(BuildContext context, BaseDevice device, DeviceManagerNotifier manager) async {
    final seq = manager.nextSeq();
    final ack = await _sendControlAndWaitAck(device, manager, Frame(
      type: FrameType.control,
      cmd: FrameCmd.clearAllPeers,
      seq: seq,
      payload: Uint8List(0),
    ));
    if (!context.mounted) return;
    final ok = ack != null && ack.payload.isNotEmpty && ack.payload[0] == AckStatus.ok;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '已清空全部 Peer' : '清空失败')));
  }

  static bool _listEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) if (a[i] != b[i]) return false;
    return true;
  }

  /// Shows a dialog to enter custom baud rate. Returns the value (clamped to [_minCustomBaud, _maxCustomBaud]) or null on cancel.
  Future<int?> _showCustomBaudDialog(BuildContext context) async {
    final controller = TextEditingController(text: '$_customBaudRate');
    String? errorText;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('自定义波特率'),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '波特率',
                hintText: '$_minCustomBaud ~ $_maxCustomBaud',
                errorText: errorText,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setDialogState(() => errorText = null),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  final v = int.tryParse(controller.text.trim());
                  if (v == null || v < _minCustomBaud || v > _maxCustomBaud) {
                    setDialogState(() => errorText = '请输入 $_minCustomBaud ~ $_maxCustomBaud 之间的整数');
                    return;
                  }
                  Navigator.of(ctx).pop(v.clamp(_minCustomBaud, _maxCustomBaud));
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _doSend(DeviceManagerNotifier manager) {
    final text = _sendController.text;
    final payload = _parseSendContent(text, _txHexMode);
    if (payload.isEmpty) return;
    _lastSentPayload = Uint8List.fromList(payload);
    _lastSentAt = DateTime.now();
    final seq = manager.nextSeq();
    manager.send(Frame(
      type: FrameType.data,
      cmd: FrameCmd.dataPayload,
      seq: seq,
      payload: payload,
    ));
    if (mounted) setState(() => _txByteCount += payload.length);
  }

  void _updateLoopTimer() {
    _loopTimer?.cancel();
    _loopTimer = null;
    if (!_loopSend || _cachedManager == null) return;
    final ms = int.tryParse(_loopIntervalController.text) ?? 1000;
    final interval = Duration(milliseconds: ms < 100 ? 100 : ms);
    final manager = _cachedManager!;
    _loopTimer = Timer.periodic(interval, (_) {
      if (!_loopSend || !mounted) return;
      _doSend(manager);
    });
  }
}
