/// 解析并比较设备 / manifest 固件版本（如 V1.3、1.3.1）。
int compareFirmwareVersions(String a, String b) {
  final pa = _parseFirmwareVersion(a);
  final pb = _parseFirmwareVersion(b);
  for (var i = 0; i < 3; i++) {
    final diff = pa[i] - pb[i];
    if (diff != 0) return diff > 0 ? 1 : -1;
  }
  return 0;
}

bool isFirmwareVersionGreater(String remote, String device) {
  return compareFirmwareVersions(remote, device) > 0;
}

List<int> _parseFirmwareVersion(String raw) {
  final trimmed = raw.trim();
  final withoutPrefix = trimmed.startsWith(RegExp(r'[vV]'))
      ? trimmed.substring(1)
      : trimmed;
  final parts = withoutPrefix.split('.');
  final nums = <int>[];
  for (var i = 0; i < 3; i++) {
    if (i < parts.length) {
      final n = int.tryParse(parts[i].trim());
      nums.add(n ?? 0);
    } else {
      nums.add(0);
    }
  }
  return nums;
}
