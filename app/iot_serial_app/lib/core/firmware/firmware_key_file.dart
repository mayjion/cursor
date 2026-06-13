import 'dart:io';

/// 默认密钥文件：iot_serial_app 的上一级目录。
File defaultFirmwareKeyFile() {
  final appRoot = Directory.current;
  return File('${appRoot.parent.path}/firmware_aes_key.hex');
}

/// 从密钥文件读取 64 位十六进制字符串（忽略空行与 # 注释）。
String? readFirmwareKeyHexFromFile({File? file}) {
  final f = file ?? defaultFirmwareKeyFile();
  if (!f.existsSync()) return null;
  for (final line in f.readAsLinesSync()) {
    var s = line.trim();
    if (s.isEmpty || s.startsWith('#')) continue;
    if (s.contains('#')) {
      s = s.substring(0, s.indexOf('#')).trim();
    }
    s = s.replaceAll(RegExp(r'\s+'), '');
    if (s.length == 64) return s.toLowerCase();
  }
  return null;
}
