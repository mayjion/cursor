import 'firmware_catalog.dart';
import 'firmware_target_chip.dart';

const _triDtuZh =
    '三模无线透传 DTU OTA（N4 与 N16R8 不可互刷）。\n'
    '连接设备 SoftAP（FUN-TRI-*）后，在 APP 固件升级页上传。';
const _triDtuEn =
    'Tri-mode wireless DTU OTA (N4 and N16R8 are not interchangeable).\n'
    'Connect to device SoftAP (FUN-TRI-*) and upload from the firmware upgrade page.';

/// 与 assets/firmware/FL-TRI-S3-*.bin.enc 及设备 /info product 一致。
const List<FirmwareCatalogEntry> kTriDtuCatalog = [
  FirmwareCatalogEntry(
    productId: 'FL-TRI-S3-N4',
    assetPath: 'assets/firmware/FL-TRI-S3-N4.bin.enc',
    otaUploadFilename: 'FL-TRI-S3-N4.bin',
    titleZh: 'FL-TRI-S3（4MB / N4）',
    titleEn: 'FL-TRI-S3 (4MB / N4)',
    descriptionZh: _triDtuZh,
    descriptionEn: _triDtuEn,
    targetChip: FirmwareTargetChip.esp32s3,
  ),
  FirmwareCatalogEntry(
    productId: 'FL-TRI-S3-N16R8',
    assetPath: 'assets/firmware/FL-TRI-S3-N16R8.bin.enc',
    otaUploadFilename: 'FL-TRI-S3-N16R8.bin',
    titleZh: 'FL-TRI-S3（16MB / N16R8）',
    titleEn: 'FL-TRI-S3 (16MB / N16R8)',
    descriptionZh: _triDtuZh,
    descriptionEn: _triDtuEn,
    targetChip: FirmwareTargetChip.esp32s3,
  ),
];

enum TriDtuFlashVariant { n4, n16r8 }

bool isTriDtuProduct(String product) {
  final p = product.trim().toUpperCase();
  return p == 'FL-TRI-S3-N4' || p == 'FL-TRI-S3-N16R8';
}

TriDtuFlashVariant? triDtuFlashVariant(String product) {
  final p = product.trim().toUpperCase();
  if (p == 'FL-TRI-S3-N4') return TriDtuFlashVariant.n4;
  if (p == 'FL-TRI-S3-N16R8') return TriDtuFlashVariant.n16r8;
  return null;
}

FirmwareCatalogEntry? triDtuCatalogForProduct(String product) {
  for (final e in kTriDtuCatalog) {
    if (catalogEntryMatchesDeviceProduct(e, product)) return e;
  }
  return null;
}

List<FirmwareCatalogEntry> triDtuCatalogEntriesForDevice(String product) {
  final match = triDtuCatalogForProduct(product);
  if (match != null) return [match];
  return List<FirmwareCatalogEntry>.from(kTriDtuCatalog);
}

bool catalogEntryMatchesTriDtuDevice(FirmwareCatalogEntry entry, String deviceProduct) {
  if (catalogEntryMatchesDeviceProduct(entry, deviceProduct)) return true;
  final dv = triDtuFlashVariant(deviceProduct);
  final ev = triDtuFlashVariant(entry.productId);
  return dv != null && dv == ev;
}
