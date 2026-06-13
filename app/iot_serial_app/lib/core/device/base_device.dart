import 'dart:async';
import 'dart:typed_data';

import '../channel/device_channel.dart';
import '../protocol/frame.dart';
import '../protocol/frame_codec.dart';
import 'device_type.dart';

/// Max payload length to avoid malicious or corrupted LEN (e.g. 0xFFFF).
const int _kMaxPayloadLen = 2048;

/// Base device: id, name, type, channel; send(Frame) and onFrame stream.
/// onFrame is a broadcast stream so multiple listeners (e.g. scan ACK + panel RX) can subscribe.
abstract class BaseDevice {
  BaseDevice() {
    // Lazy init of frame decoder in _ensureFrameDecoderStarted() when onFrame is first accessed.
  }

  String get id;
  String get name;
  DeviceType get type;
  DeviceChannel get channel;

  Future<void> connect() => channel.connect();

  Future<void> disconnect() async {
    await _frameChannelSub?.cancel();
    _frameChannelSub = null;
    await _frameController?.close();
    _frameController = null;
    _frameBuffer.clear();
    await channel.disconnect();
  }

  bool get isConnected => channel.isConnected;

  /// Send a Frame (encoded to bytes via FrameCodec).
  Future<void> send(Frame frame) => channel.send(FrameCodec.encode(frame));

  StreamController<Frame>? _frameController;
  StreamSubscription<Uint8List>? _frameChannelSub;
  final List<int> _frameBuffer = [];

  /// Stream of decoded Frames from channel data (SOF-framed, CRC-validated).
  /// Broadcast: multiple listeners allowed (scan ACK, serial panel RX, etc.).
  Stream<Frame> get onFrame {
    _ensureFrameDecoderStarted();
    return _frameController!.stream;
  }

  void _ensureFrameDecoderStarted() {
    if (_frameController != null) return;
    _frameController = StreamController<Frame>.broadcast();
    _frameChannelSub = channel.onData.listen((chunk) {
      _frameBuffer.addAll(chunk);
      while (_frameBuffer.length >= FrameCodec.minFrameLength) {
        if (_frameBuffer[0] != Frame.sof) {
          _frameBuffer.removeAt(0);
          continue;
        }
        final len = _frameBuffer[4] | (_frameBuffer[5] << 8);
        final frameLen = FrameCodec.headerLength + len + FrameCodec.crcLength;
        if (len > _kMaxPayloadLen || _frameBuffer.length < frameLen) {
          if (_frameBuffer.length < frameLen) break;
          _frameBuffer.removeAt(0);
          continue;
        }
        final bytes = Uint8List.fromList(_frameBuffer.take(frameLen).toList());
        _frameBuffer.removeRange(0, frameLen);
        final frame = FrameCodec.decode(bytes);
        if (frame != null) {
          if (!_frameController!.isClosed) {
            _frameController!.add(frame);
          }
        } else {
          _frameBuffer.removeAt(0);
        }
      }
    });
  }
}
