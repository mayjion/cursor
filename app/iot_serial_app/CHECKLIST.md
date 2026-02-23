# 与固件对齐检查表

依据《Flutter物联网APP开发设计文档》第十二章。

- [x] SOF = 0xAA
- [x] CRC 范围 TYPE～PAYLOAD，算法 CRC-16-CCITT
- [x] BLE Service 0xFE01，Characteristic 0xFF06
- [x] 控制 CMD：0x01 添加 Peer、0x02 删除 Peer、0x03 UART 配置（15 字节）、0x06 状态查询
- [x] UART 配置 payload 固定 15 字节，小端
- [x] ACK TYPE=0x03，status 0x00～0x03
- [x] 数据透传 TYPE=0x01、CMD=0x00，payload 为原始字节
