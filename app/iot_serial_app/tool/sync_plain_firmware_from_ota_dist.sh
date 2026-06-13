#!/usr/bin/env bash
# 从 myproject/ota_dist 复制明文 .bin 到 assets/firmware/（供重新加密）
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OTA="${OTA_DIST:-$ROOT/../../../esp/release-v6.0/esp-idf/examples/myproject/ota_dist}"
DEST="$ROOT/assets/firmware"

if [[ ! -d "$OTA" ]]; then
  echo "错误: 未找到 ota_dist: $OTA" >&2
  echo "可设置: OTA_DIST=/path/to/ota_dist" >&2
  exit 1
fi

mkdir -p "$DEST"
copy() { cp -f "$1" "$2"; echo "  $(basename "$2")"; }

echo "==> 从 $OTA 同步明文固件"
copy "$OTA/ESPFLASHER-S3-N4.bin" "$DEST/ESPFLASHER_V4.bin"
copy "$OTA/ESPFLASHER-S3-N16R8.bin" "$DEST/ESPFLASHER_V16.bin"
copy "$OTA/PYFLASHER-S3-N4.bin" "$DEST/PYFLASHER_V4.bin"
copy "$OTA/PYFLASHER-S3-N16R8.bin" "$DEST/PYFLASHER_V16.bin"
for name in FL-WIFI-C3 FL-WIFI-S2 FL-WIFI-S2COM FL-WIFI-S3COM FL-WIFI-S3USBDEV-N4 \
  FUN-UART-C3 FUN-UART-S2 FUN-UART-S3; do
  copy "$OTA/$name.bin" "$DEST/$name.bin"
done
echo "完成。请执行:"
echo "  dart run tool/patch_catalog_asset_ext.dart bin"
echo "  flutter clean && flutter run --dart-define-from-file=dart_defines.json"
