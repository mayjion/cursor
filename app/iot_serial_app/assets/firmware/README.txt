ESPFlasher 烧录器 OTA 固件（请用 esp-idf myproject 编译产物替换占位文件）：

  ESPFLASHER_V4.bin   ← build/ESPFLASHER-S3-N4.bin 或 ota_dist/ESPFLASHER-S3-N4.bin
  ESPFLASHER_V16.bin  ← build/ESPFLASHER-S3-N16R8.bin 或 ota_dist/ESPFLASHER-S3-N16R8.bin

手机连接烧录器升级模式 WiFi：FUNLIGHT / funlight
设备 /info JSON 中 product 为 ESPFLASHER_V4 或 ESPFLASHER_V16，version 如 V1.5。

FUN 系列 DTU 固件仍使用原有 FL-WIFI-* / FUN-UART-* 文件名。
