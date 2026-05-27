import 'firmware_catalog.dart';
import 'firmware_target_chip.dart';

const _espFlasherZh =
    '烧录器自身固件 OTA（V4 与 V16 不可互刷）。上电 10 秒内双击 IO0 进入升级模式，连接 FUNLIGHT 后上传。';
const _espFlasherEn =
    'ESPFlasher self OTA (V4 and V16 are not interchangeable). Double-click IO0 within 10s after boot, connect FUNLIGHT, then upload.';

/// 与 assets/firmware/ESPFLASHER_*.bin 及设备 /info product 一致。
const List<FirmwareCatalogEntry> kEspFlasherCatalog = [
  FirmwareCatalogEntry(
    productId: 'ESPFLASHER_V4',
    assetPath: 'assets/firmware/ESPFLASHER_V4.bin',
    titleZh: 'ESPFlasher V1.1 (4MB / N4)',
    titleEn: 'ESPFlasher V1.1 (4MB / N4)',
    descriptionZh: _espFlasherZh,
    descriptionEn: _espFlasherEn,
    targetChip: FirmwareTargetChip.esp32s3,
  ),
  FirmwareCatalogEntry(
    productId: 'ESPFLASHER_V16',
    assetPath: 'assets/firmware/ESPFLASHER_V16.bin',
    titleZh: 'ESPFlasher V1.1 (16MB / N16R8)',
    titleEn: 'ESPFlasher V1.1 (16MB / N16R8)',
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
