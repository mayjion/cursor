import 'dart:typed_data';

/// Frame types aligned with firmware (frame_protocol.h).
class FrameType {
  FrameType._();
  static const int data = 0x01;
  static const int control = 0x02;
  static const int ack = 0x03;
  static const int event = 0x04;
}

/// Control commands aligned with firmware.
class FrameCmd {
  FrameCmd._();
  static const int dataPayload = 0x00;
  static const int peerAdd = 0x01;
  static const int peerRemove = 0x02;
  static const int uartConfig = 0x03;
  static const int nvsRead = 0x04;
  static const int nvsWrite = 0x05;
  static const int statusQuery = 0x06;
  static const int setWorkMode = 0x07;
  static const int clearAllPeers = 0x08;
  static const int setDeviceName = 0x09;
}

/// ACK status codes.
class AckStatus {
  AckStatus._();
  static const int ok = 0x00;
  static const int error = 0x01;
  static const int invalid = 0x02;
  static const int timeout = 0x03;
}

class Frame {
  const Frame({
    required this.type,
    required this.cmd,
    required this.seq,
    required this.payload,
  });

  static const int sof = 0xAA;

  final int type;
  final int cmd;
  final int seq;
  final Uint8List payload;
}
