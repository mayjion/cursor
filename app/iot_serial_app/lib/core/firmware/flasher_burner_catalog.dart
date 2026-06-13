import 'espflasher_catalog.dart';
import 'firmware_catalog.dart';
import 'pyflasher_catalog.dart';

/// 烧录器 Flash 变体：N4（4MB）与 N16R8（16MB）不可互刷。
enum BurnerFlashVariant { v4, v16 }

bool isEspFlasherProduct(String product) {
  final p = product.trim().toUpperCase();
  return p == 'ESPFLASHER_V4' || p == 'ESPFLASHER_V16';
}

bool isPyFlasherProduct(String product) {
  final p = product.trim().toUpperCase();
  return p == 'PYFLASHER_V4' || p == 'PYFLASHER_V16';
}

bool isFlasherBurnerProduct(String product) {
  return isEspFlasherProduct(product) || isPyFlasherProduct(product);
}

BurnerFlashVariant? burnerFlashVariant(String product) {
  final p = product.trim().toUpperCase();
  if (p.endsWith('_V4')) return BurnerFlashVariant.v4;
  if (p.endsWith('_V16')) return BurnerFlashVariant.v16;
  return null;
}

FirmwareCatalogEntry? flasherBurnerCatalogForProduct(String product) {
  return espFlasherCatalogForProduct(product) ?? pyFlasherCatalogForProduct(product);
}

/// 同 Flash 变体下展示 ESP + PY 两条（支持交叉升级）；未知型号则展示全部烧录器固件。
List<FirmwareCatalogEntry> flasherBurnerCatalogEntriesForDevice(String product) {
  final variant = burnerFlashVariant(product);
  if (variant == BurnerFlashVariant.v4) {
    return [
      kEspFlasherCatalog.firstWhere((e) => e.productId == 'ESPFLASHER_V4'),
      kPyFlasherCatalog.firstWhere((e) => e.productId == 'PYFLASHER_V4'),
    ];
  }
  if (variant == BurnerFlashVariant.v16) {
    return [
      kEspFlasherCatalog.firstWhere((e) => e.productId == 'ESPFLASHER_V16'),
      kPyFlasherCatalog.firstWhere((e) => e.productId == 'PYFLASHER_V16'),
    ];
  }
  return [
    ...kEspFlasherCatalog,
    ...kPyFlasherCatalog,
  ];
}

/// 允许同 product 或同 Flash 变体（ESP ↔ PY 交叉升级）；禁止 V4 ↔ V16。
bool catalogEntryMatchesBurnerDevice(FirmwareCatalogEntry entry, String deviceProduct) {
  if (catalogEntryMatchesDeviceProduct(entry, deviceProduct)) return true;
  final dv = burnerFlashVariant(deviceProduct);
  final ev = burnerFlashVariant(entry.productId);
  return dv != null && dv == ev;
}

bool isBurnerCrossFamilyUpgrade(FirmwareCatalogEntry entry, String deviceProduct) {
  if (catalogEntryMatchesDeviceProduct(entry, deviceProduct)) return false;
  return catalogEntryMatchesBurnerDevice(entry, deviceProduct);
}
