import 'dart:typed_data';

import '../channel/device_channel.dart';
import '../protocol/frame.dart';
import '../protocol/frame_codec.dart';
import 'device_type.dart';

/// Base device: id, name, type, channel; send(Frame) and onFrame stream.
abstract class BaseDevice {
  String get id;
  String get name;
  DeviceType get type;
  DeviceChannel get channel;

  Future<void> connect() => channel.connect();
  Future<void> disconnect() => channel.disconnect();
  bool get isConnected => channel.isConnected;

  /// Send a Frame (encoded to bytes via FrameCodec).
  Future<void> send(Frame frame) => channel.send(FrameCodec.encode(frame));

  /// Stream of decoded Frames from channel data (SOF-framed, CRC-validated).
  Stream<Frame> get onFrame => _frameStream;

  /// Max payload length to avoid malicious or corrupted LEN (e.g. 0xFFFF).
  static const int _maxPayloadLen = 2048;

  Stream<Frame> get _frameStream async* {
    final buffer = <int>[];
    await for (final chunk in channel.onData) {
      buffer.addAll(chunk);
      while (buffer.length >= FrameCodec.minFrameLength) {
        // Only accept SOF at start; do not use indexOf(SOF) so payload containing 0xAA won't be treated as next frame.
        if (buffer[0] != Frame.sof) {
          buffer.removeAt(0);
          continue;
        }
        final len = buffer[4] | (buffer[5] << 8);
        final frameLen = FrameCodec.headerLength + len + FrameCodec.crcLength;
        if (len > _maxPayloadLen || buffer.length < frameLen) {
          if (buffer.length < frameLen) break;
          buffer.removeAt(0);
          continue;
        }
        final bytes = Uint8List.fromList(buffer.take(frameLen).toList());
        buffer.removeRange(0, frameLen);
        final frame = FrameCodec.decode(bytes);
        if (frame != null) {
          yield frame;
        } else {
          buffer.removeAt(0);
        }
      }
    }
  }
}
