# IoT Serial App

Flutter 物联网串口 APP，与 ESP-NOW 无线串口固件协议对齐。Phase 1 实现 BLE 本地模式：设备卡片列表、点击连接进入设备面板、BLE 串口工具面板（串口配置、接收/发送数据框、循环发送、HEX/字符串显示）。

## 目录结构

```
lib/
├── core/
│   ├── protocol/     # Frame 协议：frame.dart, frame_codec.dart, crc16.dart
│   ├── channel/      # DeviceChannel 抽象
│   ├── device/       # BaseDevice, DeviceType, DeviceManager
│   ├── storage/      # 本地设备列表（Hive）：device_entity.dart, device_storage.dart
│   └── automation/   # 预留（Phase 2+）
├── modules/
│   ├── ble/          # BleChannel, BleDevice, BLE 扫描/连接（Service 0xFE01, Characteristic 0xFF06）
│   ├── wifi/         # 预留（Phase 2）
│   └── gateway/      # 预留（Phase 3+）
├── features/
│   ├── device_list/  # 设备列表：设备卡片（一设备一卡）、下拉扫描、长按删除
│   ├── device_detail/# 设备面板（按类型）：BLE 串口工具面板 serial_tool_panel
│   ├── terminal/     # 串口终端（可选入口）
│   └── settings/     # 设置、关于、BLE 权限说明
├── app_router.dart   # go_router 路由
└── main.dart
```

## 运行方式

- 在项目根目录执行：`flutter run`
- 需真机或模拟器开启蓝牙；Android 需 BLUETOOTH_SCAN/CONNECT 等权限，iOS 需 NSBluetoothAlwaysUsageDescription

## 打包

在项目根目录 `iot_serial_app` 下执行。首次打包前先拉依赖：

```bash
flutter pub get
```

### Android Release APK（推荐）

内置 OTA 固件须以密文 `*.bin.enc` 打入 APK，不得包含明文 `.bin`。生产密钥放在与项目**同级**目录：`../firmware_aes_key.hex`（模板见 `../firmware_aes_key.hex.example`，勿提交 Git）。

**一键加密并打包**（默认：加密 → 校验 → release APK）：

```bash
# 首次：在上一级目录生成随机密钥
./encrypt_firmware_assets.sh --init-key

# 将明文 .bin 放入 assets/firmware/ 后执行
./encrypt_firmware_assets.sh

# 仅加密，不打包
./encrypt_firmware_assets.sh --no-build

# 已有 .bin.enc，只打 APK
./encrypt_firmware_assets.sh --apk-only

# 按 CPU 架构分包（体积更小，真机多为 arm64-v8a）
./encrypt_firmware_assets.sh --split-per-abi
```

产物目录：`build/app/outputs/flutter-apk/`（单包为 `app-release.apk`；分架构为 `app-*-release.apk`）。

资源已加密时，也可直接：

```bash
./encrypt_firmware_assets.sh --apk-only
```

或手动（需已配置 `../firmware_aes_key.hex`）：

```bash
KEY=$(grep -v '^#' ../firmware_aes_key.hex | tr -d ' \n')
flutter build apk --release \
  --dart-define=FIRMWARE_AES_KEY_HEX=$KEY \
  --obfuscate --split-debug-info=build/symbols
```

**Google Play 上架**（App Bundle）：

```bash
flutter build appbundle --release
```

产物：`build/app/outputs/bundle/release/app-release.aab`

**版本号**：`pubspec.yaml` 中 `version: 1.0.0+1`；构建时可覆盖：

```bash
flutter build apk --release --build-name=1.0.1 --build-number=2
```

**清理后重编**：

```bash
flutter clean && flutter pub get && ./encrypt_firmware_assets.sh
```

安装到已连接设备（调试）：

```bash
flutter install --release
```

更完整的说明（签名、自检、命令表）见 [RELEASE_APK.md](RELEASE_APK.md)。

### 远程 OTA（Gitee iot-ota）

APP 从 Gitee 仓 `mayjion/iot-ota` 拉取固件版本清单与加密固件。固件升级页在读取设备信息后会自动检查远程是否有新版本；用户确认后才下载 `.bin.enc` 到本地缓存，上传时优先使用缓存（解密逻辑与内置 assets 相同）。内置 `assets/firmware/` 作为离线兜底。

#### 公开仓（无 Token）

默认 manifest raw 链接：

```text
https://gitee.com/mayjion/iot-ota/raw/master/manifest.json
```

#### 私有仓（需 Gitee Token）

私有仓 **不支持** raw 直链（即使带 `access_token` 也会 403）。带 Token 的 release 包会通过 **Gitee API v5** 拉取 `manifest.json` 与 `firmware/*.bin.enc`。

1. 复制模板并填入只读 Token（与 `iot_serial_app` 同级目录）：

   ```bash
   cp ../firmware_gitee_token.txt.example ../firmware_gitee_token.txt
   # 编辑 firmware_gitee_token.txt，一行 token
   ```

2. 打包时 `./encrypt_firmware_assets.sh` 会自动读取 Token 并写入 `dart_defines.json`（与 AES 密钥同模式）。

3. 使用 `--dart-define-from-file=dart_defines.json` 构建 release APK。

Token 文件已加入 `.gitignore`，**切勿提交**。Token 可从 APK 中提取，请仅授予仓库只读权限并定期轮换。

无 Token 的 APK 在私有仓上会提示「远程 OTA 需要 Gitee Token」；Token 无效时提示重新生成。

覆盖 manifest URL（公开仓 fallback，可选）：

```bash
flutter run --dart-define=FIRMWARE_MANIFEST_URL=https://example.com/manifest.json
```

固件发布与推送流程见同级目录 [iot-ota/README.md](../../iot-ota/README.md)。

### iOS

需在 macOS 上配置 Xcode 与证书后执行：

```bash
flutter build ipa --release
```

或仅编译不导出 IPA：

```bash
flutter build ios --release
```

## 与固件协议对齐

- **SOF** = 0xAA
- **CRC**：范围 TYPE～PAYLOAD，算法 CRC-16-CCITT（0x1021, 0xFFFF），结果小端
- **BLE**：Service 0xFE01，Characteristic 0xFF06（Notify + Write），仅完整 Frame 二进制
- **控制 CMD**：0x01 添加 Peer、0x02 删除 Peer、0x03 UART 配置（15 字节）、0x06 状态查询
- **UART 配置**：payload 固定 15 字节小端（baud_rate, data_bits, stop_bits, parity, tx_pin, rx_pin）
- **ACK**：TYPE=0x03，status 0x00～0x03
- **数据透传**：TYPE=0x01、CMD=0x00，payload 为原始字节

## 交互与界面（与设计文档一致）

- **设备列表**：以**设备卡片**展示，一个设备一张卡片；已保存设备 + 附近设备（BLE 扫描，Service 0xFE01）；长按已保存卡片可删除。
- **点击设备卡片**：建立连接（BLE）后进入**设备面板**；根据设备类型展示不同面板（Phase 1 仅 BLE）。
- **BLE 串口工具面板**：串口配置（可折叠）、接收数据框（HEX/字符串、清屏）、发送数据框（HEX/字符串解析）、循环发送（周期 100～5000 ms）。

详见 [work/doc/Flutter物联网APP开发设计文档.md](../doc/Flutter物联网APP开发设计文档.md) 第六、七、九章；协议对齐见 [CHECKLIST.md](CHECKLIST.md)。

## 后续扩展

- **Phase 2**：WiFi（TCP/MQTT 通道、配网）— `modules/wifi` 预留
- **Phase 3**：网关、子设备模型 — `modules/gateway` 预留
- **Phase 4**：自动化规则 — `core/automation` 预留

## 依赖

- flutter_blue_plus：BLE
- hive / hive_flutter：本地存储
- flutter_riverpod：状态管理
- go_router：路由
- permission_handler：权限
