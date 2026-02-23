import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/device_manager.dart';
import '../../core/protocol/frame.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final _log = <String>[];
  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  bool _hexMode = false;
  StreamSubscription? _frameSub;

  @override
  void initState() {
    super.initState();
    final device = ref.read(currentDeviceProvider);
    if (device != null) {
      _frameSub = device.onFrame.listen((frame) {
        if (frame.type == FrameType.data && mounted) {
          setState(() {
            if (_hexMode) {
              _log.add(frame.payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '));
            } else {
              _log.add(utf8.decode(frame.payload, allowMalformed: true));
            }
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _clear() {
    setState(() => _log.clear());
  }

  Future<void> _send() async {
    final text = _textController.text;
    if (text.isEmpty) return;
    _textController.clear();
    final manager = ref.read(deviceManagerProvider.notifier);
    final payload = utf8.encode(text);
    if (payload.isEmpty) return;
    await manager.send(Frame(
      type: FrameType.data,
      cmd: FrameCmd.dataPayload,
      seq: manager.nextSeq(),
      payload: Uint8List.fromList(payload),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(currentDeviceProvider);
    if (device == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('串口终端')),
        body: const Center(child: Text('请先连接设备')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('串口终端'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        actions: [
          IconButton(
            icon: Icon(_hexMode ? Icons.text_fields : Icons.memory),
            onPressed: () => setState(() => _hexMode = !_hexMode),
            tooltip: _hexMode ? 'ASCII' : 'HEX',
          ),
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: _clear,
            tooltip: '清屏',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: _log.length,
              itemBuilder: (_, i) => SelectableText(
                _log[i],
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: '输入发送...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _send,
                  child: const Text('发送'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
