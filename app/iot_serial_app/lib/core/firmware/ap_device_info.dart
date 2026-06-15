import 'dart:convert';

import 'firmware_target_chip.dart';

/// 从设备 AP 网页或 /info JSON 解析的信息。
class ApDeviceInfo {
  ApDeviceInfo({
    required this.rawHtml,
    this.version,
    required this.product,
    required this.inferredChip,
    this.variant,
  });

  final String rawHtml;
  final String? version;
  final String product;
  final FirmwareTargetChip inferredChip;
  final String? variant;

  bool get isEspFlasher {
    final p = product.trim().toUpperCase();
    return p == 'ESPFLASHER_V4' || p == 'ESPFLASHER_V16';
  }

  bool get isPyFlasher {
    final p = product.trim().toUpperCase();
    return p == 'PYFLASHER_V4' || p == 'PYFLASHER_V16';
  }

  /// ESPFlasher 或 PYFlasher（共用 PCB / 分区，OTA 可交叉升级）。
  bool get isFlasherBurner => isEspFlasher || isPyFlasher;

  bool get isTriDtu {
    final p = product.trim().toUpperCase();
    return p == 'FL-TRI-S3-N4' || p == 'FL-TRI-S3-N16R8';
  }
}

/// GET /info JSON（烧录器与部分 FUN 设备）。
ApDeviceInfo? parseApDeviceInfoFromJson(String jsonText) {
  try {
    final m = jsonDecode(jsonText);
    if (m is! Map<String, dynamic>) return null;
    final prod = m['product']?.toString().trim();
    if (prod == null || prod.isEmpty) return null;
    final ver = m['version']?.toString().trim();
    return ApDeviceInfo(
      rawHtml: jsonText,
      version: ver == null || ver.isEmpty ? null : ver,
      product: prod,
      inferredChip: inferChipFromProduct(prod),
      variant: m['variant']?.toString().trim(),
    );
  } catch (_) {
    return null;
  }
}

final _reDtuLine = RegExp(
  r'Version:\s*([^|]+?)\s*\|\s*产品型号:\s*([^<\n]+)',
  caseSensitive: false,
);
final _reTriDtuLine = RegExp(
  r'版本[：:]\s*([^|]+?)\s*\|\s*型号[：:]\s*([^<\n]+)',
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

  final tri = _reTriDtuLine.firstMatch(html);
  if (tri != null) {
    final ver = tri.group(1)?.trim();
    final prod = tri.group(2)?.trim();
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
