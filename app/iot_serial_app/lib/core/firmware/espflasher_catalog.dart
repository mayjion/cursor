import 'firmware_catalog.dart';
import 'firmware_target_chip.dart';

const _espFlasherSupportedZh =
    '支持烧录 DUT 芯片：ESP8266、ESP32、ESP32-S2、ESP32-S3、ESP32-C2/C3/C5/C6、ESP32-H2、ESP32-P4（UART 下载）。';
const _espFlasherSupportedEn =
    'Supported DUT chips: ESP8266, ESP32, ESP32-S2, ESP32-S3, ESP32-C2/C3/C5/C6, ESP32-H2, ESP32-P4 (UART download).';

const _espFlasherZh =
    'ESP 烧录器固件 OTA（V4 与 V16 不可互刷）。与 PYFlasher 同分区，可与 PYFLASHER_V* 交叉升级。\n'
    '$_espFlasherSupportedZh\n'
    '上电 10 秒内双击按键进入升级模式，连接 FUNLIGHT 后上传。';
const _espFlasherEn =
    'ESPFlasher OTA (V4 and V16 are not interchangeable). Same partition as PYFlasher; cross-flash with PYFLASHER_V* is supported.\n'
    '$_espFlasherSupportedEn\n'
    'Double-click the button within 10s after boot, connect FUNLIGHT, then upload.';

/// 与 assets/firmware/ESPFLASHER_*.bin.enc 及设备 /info product 一致。
const List<FirmwareCatalogEntry> kEspFlasherCatalog = [
  FirmwareCatalogEntry(
    productId: 'ESPFLASHER_V4',
    assetPath: 'assets/firmware/ESPFLASHER_V4.bin.enc',
    otaUploadFilename: 'ESPFLASHER_V4.bin',
    titleZh: 'ESPFlasher（4MB / N4）',
    titleEn: 'ESPFlasher (4MB / N4)',
    descriptionZh: _espFlasherZh,
    descriptionEn: _espFlasherEn,
    targetChip: FirmwareTargetChip.esp32s3,
  ),
  FirmwareCatalogEntry(
    productId: 'ESPFLASHER_V16',
    assetPath: 'assets/firmware/ESPFLASHER_V16.bin.enc',
    otaUploadFilename: 'ESPFLASHER_V16.bin',
    titleZh: 'ESPFlasher（16MB / N16R8）',
    titleEn: 'ESPFlasher (16MB / N16R8)',
    descriptionZh: _espFlasherZh,
    descriptionEn: _espFlasherEn,
    targetChip: FirmwareTargetChip.esp32s3,
  ),
];

FirmwareCatalogEntry? espFlasherCatalogForProduct(String product) {
  for (final e in kEspFlasherCatalog) {
    if (catalogEntryMatchesDeviceProduct(e, product)) return e;
  }
  return null;
}

List<FirmwareCatalogEntry> espFlasherCatalogEntriesForDevice(String product) {
  final match = espFlasherCatalogForProduct(product);
  if (match != null) return [match];
  return List<FirmwareCatalogEntry>.from(kEspFlasherCatalog);
}
