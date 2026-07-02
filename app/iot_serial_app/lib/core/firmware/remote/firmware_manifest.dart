import 'dart:convert';

class FirmwareManifestEntry {
  const FirmwareManifestEntry({
    required this.productId,
    required this.version,
    required this.otaUploadFilename,
    required this.fileName,
    required this.downloadUrl,
    required this.size,
    required this.sha256,
    this.changelogZh,
    this.changelogEn,
    this.minAppVersion,
  });

  final String productId;
  final String version;
  final String otaUploadFilename;
  final String fileName;
  final String downloadUrl;
  final int size;
  final String sha256;
  final String? changelogZh;
  final String? changelogEn;
  final String? minAppVersion;

  factory FirmwareManifestEntry.fromJson(Map<String, dynamic> json) {
    return FirmwareManifestEntry(
      productId: json['product_id'] as String,
      version: json['version'] as String,
      otaUploadFilename: json['ota_upload_filename'] as String,
      fileName: json['file_name'] as String,
      downloadUrl: json['download_url'] as String,
      size: (json['size'] as num).toInt(),
      sha256: (json['sha256'] as String).toLowerCase(),
      changelogZh: json['changelog_zh'] as String?,
      changelogEn: json['changelog_en'] as String?,
      minAppVersion: json['min_app_version'] as String?,
    );
  }
}

class FirmwareManifest {
  const FirmwareManifest({
    required this.manifestVersion,
    required this.updatedAt,
    required this.firmwares,
  });

  final int manifestVersion;
  final String updatedAt;
  final List<FirmwareManifestEntry> firmwares;

  factory FirmwareManifest.fromJson(Map<String, dynamic> json) {
    final list = (json['firmwares'] as List<dynamic>? ?? [])
        .map((e) => FirmwareManifestEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    return FirmwareManifest(
      manifestVersion: (json['manifest_version'] as num?)?.toInt() ?? 1,
      updatedAt: json['updated_at'] as String? ?? '',
      firmwares: list,
    );
  }

  static FirmwareManifest parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('manifest root must be object');
    }
    return FirmwareManifest.fromJson(decoded);
  }

  FirmwareManifestEntry? findForProduct(String productId) {
    final target = productId.trim();
    for (final e in firmwares) {
      if (e.productId == target) return e;
    }
    if (target == 'FUN-UART') {
      return findForProduct('FUN-UART-C3');
    }
    return null;
  }
}
