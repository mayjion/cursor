#!/usr/bin/env bash
# 一键：密钥 → 加密固件 → 校验 → 打 Release APK
#
# 用法（在 iot_serial_app 目录）:
#   ./encrypt_firmware_assets.sh              # 加密 + 校验 + release APK（默认）
#   ./encrypt_firmware_assets.sh --no-build   # 仅加密与校验
#   ./encrypt_firmware_assets.sh --apk-only   # 已有 .enc，只打包 APK
#   ./encrypt_firmware_assets.sh --init-key    # 仅生成 ../firmware_aes_key.hex
#   ./encrypt_firmware_assets.sh --split-per-abi
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT="$(cd "$ROOT/.." && pwd)"
KEY_FILE="$PARENT/firmware_aes_key.hex"
FIRMWARE_DIR="$ROOT/assets/firmware"

usage() {
  cat <<'EOF'
Usage: ./encrypt_firmware_assets.sh [options] [-- encrypt_firmware.dart args]

默认流程: 读取密钥 → 加密 *.bin → 校验无明文 → flutter build apk --release

Options:
  --init-key       仅生成 ../firmware_aes_key.hex（已存在则跳过）
  --no-build       只加密与校验，不打包 APK
  --apk-only       跳过加密，仅校验 .enc 并打包（无明文 .bin 时可用）
  --split-per-abi  release APK 按 CPU 架构分包（体积更小）
  --keep-plain     加密后保留明文 .bin
  -h, --help       显示此帮助

密钥: ../firmware_aes_key.hex（与 iot_serial_app 同级目录）
EOF
}

read_key_hex() {
  if [[ ! -f "$KEY_FILE" ]]; then
    echo "错误: 未找到密钥文件 $KEY_FILE" >&2
    echo "请先执行: ./encrypt_firmware_assets.sh --init-key" >&2
    exit 1
  fi
  local hex
  hex="$(grep -v '^[[:space:]]*#' "$KEY_FILE" | tr -d ' \t\r\n' | head -c 64)"
  if [[ ${#hex} -ne 64 ]]; then
    echo "错误: $KEY_FILE 须为 64 位十六进制（当前长度 ${#hex}）" >&2
    exit 1
  fi
  printf '%s' "$hex"
}

init_key() {
  if [[ -f "$KEY_FILE" ]]; then
    echo "密钥已存在，跳过: $KEY_FILE"
    return 0
  fi
  if ! command -v openssl >/dev/null 2>&1; then
    echo "错误: 需要 openssl 以生成随机密钥" >&2
    exit 1
  fi
  {
    echo "# FUN/ESPFlasher 固件 AES-256 密钥（64 位 hex，勿提交 Git）"
    openssl rand -hex 32
  } >"$KEY_FILE"
  chmod 600 "$KEY_FILE"
  echo "已生成: $KEY_FILE"
}

has_plain_bins() {
  local f
  shopt -s nullglob
  for f in "$FIRMWARE_DIR"/*.bin; do
    [[ -f "$f" ]] || continue
    [[ "$f" == *.bin.enc ]] && continue
    shopt -u nullglob
    return 0
  done
  shopt -u nullglob
  return 1
}

do_build=true
do_encrypt=true
init_only=false
split_per_abi=false
extra_args=()
pass_through=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --init-key) init_only=true; shift ;;
    --no-build) do_build=false; shift ;;
    --apk-only) do_encrypt=false; shift ;;
    --split-per-abi) split_per_abi=true; shift ;;
    --keep-plain) extra_args+=(--keep-plain); shift ;;
    -h|--help) usage; exit 0 ;;
    --)
      shift
      pass_through=("$@")
      break
      ;;
    *) extra_args+=("$1"); shift ;;
  esac
done

cd "$ROOT"

if $init_only; then
  init_key
  exit 0
fi

if [[ ! -f "$KEY_FILE" ]]; then
  echo "未找到密钥，正在生成..."
  init_key
fi

KEY_HEX="$(read_key_hex)"
export FIRMWARE_AES_KEY_HEX="$KEY_HEX"

if $do_encrypt; then
  if has_plain_bins; then
    echo "==> 加密固件 (密钥: $KEY_FILE)"
    dart run tool/encrypt_firmware.dart "${extra_args[@]}" "${pass_through[@]}"
    echo "==> catalog assetPath 切换为 .bin.enc"
    dart run tool/patch_catalog_asset_ext.dart enc
  else
    echo "==> 跳过加密: assets/firmware/ 下无明文 .bin（将使用已有 .bin.enc）"
    dart run tool/patch_catalog_asset_ext.dart enc
  fi
else
  echo "==> 跳过加密 (--apk-only)"
  dart run tool/patch_catalog_asset_ext.dart enc
fi

echo "==> 校验发布资源"
dart run tool/verify_release_assets.dart

echo "==> 校验 .enc 与密钥一致"
FIRMWARE_AES_KEY_HEX="$KEY_HEX" dart run tool/verify_enc_key_match.dart

DART_DEFINES="$ROOT/dart_defines.json"
printf '%s\n' "{\"FIRMWARE_AES_KEY_HEX\":\"$KEY_HEX\"}" >"$DART_DEFINES"
echo "==> 已写入 $DART_DEFINES（flutter run --dart-define-from-file=dart_defines.json）"

if ! $do_build; then
  echo ""
  echo "完成（未打包）。若要打 APK: ./encrypt_firmware_assets.sh 或去掉 --no-build"
  exit 0
fi

echo ""
echo "==> flutter pub get"
flutter pub get

build_args=(
  build apk --release
  --dart-define-from-file=dart_defines.json
  --obfuscate
  --split-debug-info=build/symbols
)
if $split_per_abi; then
  build_args+=(--split-per-abi)
fi

echo "==> flutter ${build_args[*]}"
flutter "${build_args[@]}"

echo ""
echo "======== 完成 ========"
echo "密钥: $KEY_FILE"
if $split_per_abi; then
  echo "APK (分架构): $ROOT/build/app/outputs/flutter-apk/app-*-release.apk"
else
  echo "APK: $ROOT/build/app/outputs/flutter-apk/app-release.apk"
fi
