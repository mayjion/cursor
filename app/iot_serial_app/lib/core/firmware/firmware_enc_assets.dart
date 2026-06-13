/// 发布用加密固件 asset 路径（执行 encrypt_firmware_assets.sh 后）。
const List<String> kRequiredFirmwareEncAssets = [
  'assets/firmware/FL-WIFI-C3.bin.enc',
  'assets/firmware/FUN-UART-C3.bin.enc',
  'assets/firmware/FL-WIFI-S2.bin.enc',
  'assets/firmware/FL-WIFI-S3USBDEV-N4.bin.enc',
  'assets/firmware/FUN-UART-S2.bin.enc',
  'assets/firmware/FUN-UART-S3.bin.enc',
  'assets/firmware/FL-WIFI-S2COM.bin.enc',
  'assets/firmware/FL-WIFI-S3COM.bin.enc',
  'assets/firmware/ESPFLASHER_V4.bin.enc',
  'assets/firmware/ESPFLASHER_V16.bin.enc',
  'assets/firmware/PYFLASHER_V4.bin.enc',
  'assets/firmware/PYFLASHER_V16.bin.enc',
];

/// 开发用明文固件 asset 路径（与 catalog 一致）。
const List<String> kRequiredFirmwarePlainAssets = [
  'assets/firmware/FL-WIFI-C3.bin',
  'assets/firmware/FUN-UART-C3.bin',
  'assets/firmware/FL-WIFI-S2.bin',
  'assets/firmware/FL-WIFI-S3USBDEV-N4.bin',
  'assets/firmware/FUN-UART-S2.bin',
  'assets/firmware/FUN-UART-S3.bin',
  'assets/firmware/FL-WIFI-S2COM.bin',
  'assets/firmware/FL-WIFI-S3COM.bin',
  'assets/firmware/ESPFLASHER_V4.bin',
  'assets/firmware/ESPFLASHER_V16.bin',
  'assets/firmware/PYFLASHER_V4.bin',
  'assets/firmware/PYFLASHER_V16.bin',
];
