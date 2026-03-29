import 'firmware_target_chip.dart';

/// 从设备 AP 网页解析的信息。
class ApDeviceInfo {
  ApDeviceInfo({
    required this.rawHtml,
    this.version,
    required this.product,
    required this.inferredChip,
  });

  final String rawHtml;
  final String? version;
  final String product;
  final FirmwareTargetChip inferredChip;
}

final _reDtuLine = RegExp(
  r'Version:\s*([^|]+?)\s*\|\s*产品型号:\s*([^<\n]+)',
  caseSensitive: false,
);
final _reProductLabel = RegExp(
  r'产品[：:]\s*([^<\n|]+)',
);

/// 从 GET /system（或同类 HTML）解析产品与版本，并推断芯片。
ApDeviceInfo? parseApDeviceInfo(String html) {
  final dtu = _reDtuLine.firstMatch(html);
  if (dtu != null) {
    final ver = dtu.group(1)?.trim();
    final prod = dtu.group(2)?.trim();
    if (prod != null && prod.isNotEmpty) {
      return ApDeviceInfo(
        rawHtml: html,
        version: ver?.isEmpty ?? true ? null : ver,
        product: prod,
        inferredChip: inferChipFromProduct(prod),
      );
    }
  }

  final p = _reProductLabel.firstMatch(html);
  if (p != null) {
    final prod = p.group(1)?.trim();
    if (prod != null && prod.isNotEmpty) {
      return ApDeviceInfo(
        rawHtml: html,
        version: _tryParseVersionLoose(html),
        product: prod,
        inferredChip: inferChipFromProduct(prod),
      );
    }
  }
  return null;
}

String? _tryParseVersionLoose(String html) {
  final v = RegExp(r'Version:\s*([^|<\n]+)', caseSensitive: false).firstMatch(html);
  return v?.group(1)?.trim();
}

/// 与网页展示的产品字符串一致；顺序避免 S2/S3、COM 误匹配。
FirmwareTargetChip inferChipFromProduct(String raw) {
  final s = raw.trim();
  if (s.contains('S3COM') || s.contains('S3USBDEV') || s.contains('FUN-UART-S3')) {
    return FirmwareTargetChip.esp32s3;
  }
  if (s.contains('S2COM') || s.contains('FUN-UART-S2')) {
    return FirmwareTargetChip.esp32s2;
  }
  if (s.contains('FL-WIFI-S2') && !s.contains('S3')) {
    return FirmwareTargetChip.esp32s2;
  }
  if (s.contains('C3') || s == 'FUN-UART-C3' || s == 'FUN-UART') {
    return FirmwareTargetChip.esp32c3;
  }
  if (s.contains('S3')) {
    return FirmwareTargetChip.esp32s3;
  }
  return FirmwareTargetChip.esp32c3;
}
