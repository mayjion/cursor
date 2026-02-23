/// CRC-16-CCITT: polynomial 0x1021, initial value 0xFFFF.
/// Used for Frame checksum over TYPE through PAYLOAD (little-endian result).
int crc16Ccitt(List<int> data, {int start = 0, int? end}) {
  const int poly = 0x1021;
  const int init = 0xFFFF;
  final int length = end ?? data.length;
  int crc = init;
  for (int i = start; i < length; i++) {
    crc ^= (data[i] << 8);
    for (int bit = 0; bit < 8; bit++) {
      if ((crc & 0x8000) != 0) {
        crc = (crc << 1) ^ poly;
      } else {
        crc = crc << 1;
      }
    }
    crc &= 0xFFFF;
  }
  return crc;
}
