/// FUN / FUNLIGHT SoftAP SSID 识别（烧录器升级模式与 FUN 系列 OTA 共用）。
bool ssidLooksLikeOtaAp(String? ssid) {
  if (ssid == null || ssid.isEmpty) return false;
  final s = ssid.trim();
  if (s.toUpperCase() == 'FUNLIGHT') return true;
  return s.toUpperCase().startsWith('FUN');
}
