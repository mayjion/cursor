import 'firmware_catalog.dart';
import 'firmware_target_chip.dart';

const _pyFlasherSupportedZh =
    '支持烧录 DUT 芯片：PY32F002A/B、F003、F030/F031、F040、F070/F071/F072、F403、L020（SWD）。';
const _pyFlasherSupportedEn =
    'Supported DUT chips: PY32F002A/B, F003, F030/F031, F040, F070/F071/F072, F403, L020 (SWD).';

const _pyFlasherZh =
    'PY32 SWD 烧录器固件 OTA（V4 与 V16 不可互刷）。与 ESPFlasher 同分区，可与 ESPFLASHER_V* 交叉升级。\n'
    '$_pyFlasherSupportedZh\n'
    '上电 10 秒内双击按键进入升级模式，连接 FUNLIGHT 后上传。';
const _pyFlasherEn =
    'PYFlasher (PY32 SWD) OTA (V4 and V16 are not interchangeable). Same partition as ESPFlasher; cross-flash with ESPFLASHER_V* is supported.\n'
    '$_pyFlasherSupportedEn\n'
    'Double-click the button within 10s after boot, connect FUNLIGHT, then upload.';

/// 与 assets/firmware/PYFLASHER_*.bin.enc 及设备 /info product 一致。
const List<FirmwareCatalogEntry> kPyFlasherCatalog = [
  FirmwareCatalogEntry(
    productId: 'PYFLASHER_V4',
    assetPath: 'assets/firmware/PYFLASHER_V4.bin.enc',
    otaUploadFilename: 'PYFLASHER_V4.bin',
    titleZh: 'PYFlasher（4MB / N4）',
    titleEn: 'PYFlasher (4MB / N4)',
    descriptionZh: _pyFlasherZh,
    descriptionEn: _pyFlasherEn,
    targetChip: FirmwareTargetChip.esp32s3,
  ),
  FirmwareCatalogEntry(
    productId: 'PYFLASHER_V16',
    assetPath: 'assets/firmware/PYFLASHER_V16.bin.enc',
    otaUploadFilename: 'PYFLASHER_V16.bin',
    titleZh: 'PYFlasher（16MB / N16R8）',
    titleEn: 'PYFlasher (16MB / N16R8)',
    descriptionZh: _pyFlasherZh,
    descriptionEn: _pyFlasherEn,
    targetChip: FirmwareTargetChip.esp32s3,
  ),
];

FirmwareCatalogEntry? pyFlasherCatalogForProduct(String product) {
  for (final e in kPyFlasherCatalog) {
    if (catalogEntryMatchesDeviceProduct(e, product)) return e;
  }
  return null;
}
