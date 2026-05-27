import 'firmware_target_chip.dart';

/// 内置 OTA 固件清单（与 assets/firmware/*.bin.enc 及 ota_upload 文件名一致）。
class FirmwareCatalogEntry {
  const FirmwareCatalogEntry({
    required this.productId,
    required this.assetPath,
    required this.otaUploadFilename,
    required this.titleZh,
    required this.titleEn,
    required this.descriptionZh,
    required this.descriptionEn,
    required this.targetChip,
  });

  /// 网页 /system 中的「产品型号」或「产品」字符串，用于匹配当前设备。
  final String productId;

  /// pubspec 中的 assets 路径（发布用 `.bin.enc`；明文开发时改为 `.bin`）。
  final String assetPath;

  /// OTA multipart 上传文件名（设备侧仍为 `.bin`）。
  final String otaUploadFilename;

  final String titleZh;
  final String titleEn;
  final String descriptionZh;
  final String descriptionEn;
  final FirmwareTargetChip targetChip;

  String titleForLocale({required bool isZh}) => isZh ? titleZh : titleEn;
  String descriptionForLocale({required bool isZh}) => isZh ? descriptionZh : descriptionEn;
}

// --- 说明模板（中英文）；标题与 productId 一致 ---

const _espnowC3Zh =
    '可互刷产品型号：FUN-UART-C3、FL-WIFI-C3。支持蓝牙透传与 WiFi 直连低延迟透传；建议小包，单包宜小于 300 字节，适合对延迟敏感的小数据。';
const _espnowC3En =
    'Interchangeable: FUN-UART-C3, FL-WIFI-C3. BLE and WiFi direct low-latency passthrough; use small packets, preferably under 300 bytes per frame for latency-sensitive traffic.';

const _espnowS2Zh =
    '可互刷产品型号：FUN-UART-S2、FL-WIFI-S2。支持蓝牙透传与 WiFi 直连低延迟透传；建议小包，单包宜小于 300 字节，适合对延迟敏感的小数据。';
const _espnowS2En =
    'Interchangeable: FUN-UART-S2, FL-WIFI-S2. BLE and WiFi direct low-latency passthrough; use small packets, preferably under 300 bytes per frame.';

const _espnowS3Zh =
    '可互刷产品型号：FUN-UART-S3、FL-WIFI-S3USBDEV-N4。支持蓝牙透传与 WiFi 直连低延迟透传；建议小包，单包宜小于 300 字节，适合对延迟敏感的小数据。';
const _espnowS3En =
    'Interchangeable: FUN-UART-S3, FL-WIFI-S3USBDEV-N4. BLE and WiFi direct low-latency passthrough; use small packets, preferably under 300 bytes per frame.';

const _dtuC3Zh =
    '基于 WiFi，适合 TCP、低丢包与稳定传输，可大包；通常可接受约 30–100 ms 的 WiFi 侧延迟。可与同芯片 ESP-NOW 固件按网页与分区说明互刷，勿跨芯片。';
const _dtuC3En =
    'WiFi/TCP-oriented: stable, low-loss transfer, larger payloads OK; expect roughly 30–100 ms WiFi latency. OTA-interchangeable with same-chip ESP-NOW per device web/partition notes; do not cross chip.';

const _dtuS2Zh =
    '基于 WiFi，适合 TCP、低丢包与稳定传输，可大包；通常可接受约 30–100 ms 的 WiFi 侧延迟。可与同芯片 ESP-NOW / MultiCOM 按说明互刷，勿跨芯片。';
const _dtuS2En =
    'WiFi/TCP-oriented: stable, low-loss, larger payloads; ~30–100 ms WiFi latency typical. Interchangeable with same-chip ESP-NOW / MultiCOM per docs; not for other chips.';

const _dtuS3Zh =
    '基于 WiFi，适合 TCP、低丢包与稳定传输，可大包；通常可接受约 30–100 ms 的 WiFi 侧延迟。可与同芯片 ESP-NOW / MultiCOM 按说明互刷，勿跨芯片。';
const _dtuS3En =
    'WiFi/TCP-oriented: stable, low-loss, larger payloads; ~30–100 ms WiFi latency typical. Interchangeable with same-chip ESP-NOW / MultiCOM per docs; not for other chips.';

const _multiS2Zh =
    'USB 多路串口方案。基于 WiFi 的 TCP 稳定传输、可大包，可接受约 30–100 ms WiFi 延迟；与同芯片其他 FL-WIFI / FUN-UART 按说明互刷，勿跨芯片。';
const _multiS2En =
    'Multi USB-CDC. WiFi/TCP stable transfer, larger payloads, ~30–100 ms WiFi latency typical. Same-chip interchange with other FL-WIFI / FUN-UART per docs.';

const _multiS3Zh =
    'USB 多路串口方案。基于 WiFi 的 TCP 稳定传输、可大包，可接受约 30–100 ms WiFi 延迟；与同芯片其他 FL-WIFI / FUN-UART 按说明互刷，勿跨芯片。';
const _multiS3En =
    'Multi USB-CDC. WiFi/TCP stable transfer, larger payloads, ~30–100 ms WiFi latency typical. Same-chip interchange with other FL-WIFI / FUN-UART per docs.';

/// 固定 8 项 FUN/FL 固件。
const List<FirmwareCatalogEntry> kFirmwareCatalog = [
  FirmwareCatalogEntry(
    productId: 'FL-WIFI-C3',
    assetPath: 'assets/firmware/FL-WIFI-C3.bin.enc',
    otaUploadFilename: 'FL-WIFI-C3.bin',
    titleZh: 'FL-WIFI-C3',
    titleEn: 'FL-WIFI-C3',
    descriptionZh: _dtuC3Zh,
    descriptionEn: _dtuC3En,
    targetChip: FirmwareTargetChip.esp32c3,
  ),
  FirmwareCatalogEntry(
    productId: 'FUN-UART-C3',
    assetPath: 'assets/firmware/FUN-UART-C3.bin.enc',
    otaUploadFilename: 'FUN-UART-C3.bin',
    titleZh: 'FUN-UART-C3',
    titleEn: 'FUN-UART-C3',
    descriptionZh: _espnowC3Zh,
    descriptionEn: _espnowC3En,
    targetChip: FirmwareTargetChip.esp32c3,
  ),
  FirmwareCatalogEntry(
    productId: 'FL-WIFI-S2',
    assetPath: 'assets/firmware/FL-WIFI-S2.bin.enc',
    otaUploadFilename: 'FL-WIFI-S2.bin',
    titleZh: 'FL-WIFI-S2',
    titleEn: 'FL-WIFI-S2',
    descriptionZh: _dtuS2Zh,
    descriptionEn: _dtuS2En,
    targetChip: FirmwareTargetChip.esp32s2,
  ),
  FirmwareCatalogEntry(
    productId: 'FL-WIFI-S3USBDEV-N4',
    assetPath: 'assets/firmware/FL-WIFI-S3USBDEV-N4.bin.enc',
    otaUploadFilename: 'FL-WIFI-S3USBDEV-N4.bin',
    titleZh: 'FL-WIFI-S3USBDEV-N4',
    titleEn: 'FL-WIFI-S3USBDEV-N4',
    descriptionZh: _dtuS3Zh,
    descriptionEn: _dtuS3En,
    targetChip: FirmwareTargetChip.esp32s3,
  ),
  FirmwareCatalogEntry(
    productId: 'FUN-UART-S2',
    assetPath: 'assets/firmware/FUN-UART-S2.bin.enc',
    otaUploadFilename: 'FUN-UART-S2.bin',
    titleZh: 'FUN-UART-S2',
    titleEn: 'FUN-UART-S2',
    descriptionZh: _espnowS2Zh,
    descriptionEn: _espnowS2En,
    targetChip: FirmwareTargetChip.esp32s2,
  ),
  FirmwareCatalogEntry(
    productId: 'FUN-UART-S3',
    assetPath: 'assets/firmware/FUN-UART-S3.bin.enc',
    otaUploadFilename: 'FUN-UART-S3.bin',
    titleZh: 'FUN-UART-S3',
    titleEn: 'FUN-UART-S3',
    descriptionZh: _espnowS3Zh,
    descriptionEn: _espnowS3En,
    targetChip: FirmwareTargetChip.esp32s3,
  ),
  FirmwareCatalogEntry(
    productId: 'FL-WIFI-S2COM',
    assetPath: 'assets/firmware/FL-WIFI-S2COM.bin.enc',
    otaUploadFilename: 'FL-WIFI-S2COM.bin',
    titleZh: 'FL-WIFI-S2COM',
    titleEn: 'FL-WIFI-S2COM',
    descriptionZh: _multiS2Zh,
    descriptionEn: _multiS2En,
    targetChip: FirmwareTargetChip.esp32s2,
  ),
  FirmwareCatalogEntry(
    productId: 'FL-WIFI-S3COM',
    assetPath: 'assets/firmware/FL-WIFI-S3COM.bin.enc',
    otaUploadFilename: 'FL-WIFI-S3COM.bin',
    titleZh: 'FL-WIFI-S3COM',
    titleEn: 'FL-WIFI-S3COM',
    descriptionZh: _multiS3Zh,
    descriptionEn: _multiS3En,
    targetChip: FirmwareTargetChip.esp32s3,
  ),
];

List<FirmwareCatalogEntry> catalogForChip(FirmwareTargetChip chip) {
  return kFirmwareCatalog.where((e) => e.targetChip == chip).toList();
}

/// 设备上报的产品字符串是否与目录条目匹配（含旧名 FUN-UART → FUN-UART-C3）。
bool catalogEntryMatchesDeviceProduct(FirmwareCatalogEntry entry, String deviceProduct) {
  final d = deviceProduct.trim();
  final id = entry.productId.trim();
  if (d == id) return true;
  if (d == 'FUN-UART' && id == 'FUN-UART-C3') return true;
  return false;
}
