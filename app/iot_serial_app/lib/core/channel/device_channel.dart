import 'dart:typed_data';

/// Abstract communication channel: connect, disconnect, send raw bytes, stream of received data.
abstract class DeviceChannel {
  Future<void> connect();
  Future<void> disconnect();
  Future<void> send(Uint8List data);
  Stream<Uint8List> get onData;
  bool get isConnected;
}
