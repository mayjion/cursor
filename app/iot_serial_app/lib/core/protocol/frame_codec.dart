import 'dart:typed_data';

import 'crc16.dart';
import 'frame.dart';

/// Encodes/decodes Frame to/from bytes. Validates CRC and LEN (little-endian).
class FrameCodec {
  static const int headerLength = 6; // SOF + TYPE + CMD + SEQ + LEN(2)
  static const int crcLength = 2;
  static const int minFrameLength = headerLength + crcLength;

  /// Encode frame to bytes. CRC computed over TYPE..PAYLOAD; LEN and CRC16 little-endian.
  static Uint8List encode(Frame frame) {
    final payload = frame.payload;
    final len = payload.length;
    final bodyLength = 5 + len; // TYPE + CMD + SEQ + LEN(2) + PAYLOAD
    final bytes = Uint8List(1 + bodyLength + 2); // SOF + body + CRC
    int i = 0;
    bytes[i++] = Frame.sof;
    bytes[i++] = frame.type & 0xFF;
    bytes[i++] = frame.cmd & 0xFF;
    bytes[i++] = frame.seq & 0xFF;
    bytes[i++] = len & 0xFF;
    bytes[i++] = (len >> 8) & 0xFF;
    bytes.setRange(i, i + len, payload);
    i += len;
    // CRC over TYPE..PAYLOAD (indices 1..i-1)
    final crc = crc16Ccitt(bytes, start: 1, end: i);
    bytes[i++] = crc & 0xFF;
    bytes[i++] = (crc >> 8) & 0xFF;
    return bytes;
  }

  /// Decode bytes to Frame. Returns null if invalid (SOF, LEN, or CRC check fails).
  static Frame? decode(Uint8List data) {
    if (data.length < minFrameLength) return null;
    if (data[0] != Frame.sof) return null;
    final len = data[4] | (data[5] << 8);
    final total = minFrameLength + len;
    if (data.length < total) return null;
    final crcReceived = data[total - 2] | (data[total - 1] << 8);
    final crcComputed = crc16Ccitt(data, start: 1, end: total - 2);
    if (crcReceived != crcComputed) return null;
    return Frame(
      type: data[1],
      cmd: data[2],
      seq: data[3],
      payload: Uint8List.sublistView(data, headerLength, total - crcLength),
    );
  }
}
