烧录器 OTA 固件（请用 esp-idf myproject 编译产物替换占位文件）：

  ESPFlasher（ESP 系列 DUT / UART）:
    ESPFLASHER_V4.bin   ← build/ESPFLASHER-S3-N4.bin 或 ota_dist/ESPFLASHER-S3-N4.bin
    ESPFLASHER_V16.bin  ← build/ESPFLASHER-S3-N16R8.bin 或 ota_dist/ESPFLASHER-S3-N16R8.bin

  PYFlasher（PY32 DUT / SWD）:
    PYFLASHER_V4.bin    ← build/PYFLASHER-S3-N4.bin 或 ota_dist/PYFLASHER-S3-N4.bin
    PYFLASHER_V16.bin   ← build/PYFLASHER-S3-N16R8.bin 或 ota_dist/PYFLASHER-S3-N16R8.bin

手机连接烧录器升级模式 WiFi：FUNLIGHT / funlight
设备 /info JSON 中 product 为 ESPFLASHER_V4/V16 或 PYFLASHER_V4/V16，version 如 V1.5。
同 Flash 变体（V4 或 V16）下 ESP ↔ PY 可交叉 OTA 升级。

FUN 系列 DTU 固件仍使用原有 FL-WIFI-* / FUN-UART-* 文件名。

  FL-TRI-S3 三模无线透传 DTU:
    FL-TRI-S3-N4.bin     ← build/FL-TRI-S3-N4.bin 或 ota_dist/FL-TRI-S3-N4.bin
    FL-TRI-S3-N16R8.bin  ← build/FL-TRI-S3-N16R8.bin 或 ota_dist/FL-TRI-S3-N16R8.bin

手机连接设备 SoftAP：FUN-TRI-XXXX / funlight
设备 /info JSON 中 product 为 FL-TRI-S3-N4 或 FL-TRI-S3-N16R8，version 如 V1.5。
N4 与 N16R8 不可互刷 OTA 固件。
