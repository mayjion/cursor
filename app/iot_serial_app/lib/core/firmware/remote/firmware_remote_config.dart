/// 远程 OTA manifest 与 Gitee 私有仓配置（dart-define 注入）。
const String kDefaultFirmwareManifestUrl =
    'https://gitee.com/mayjion/iot-ota/raw/master/manifest.json';

const String kDefaultGiteeOwner = 'mayjion';
const String kDefaultGiteeRepo = 'iot-ota';
const String kDefaultGiteeBranch = 'master';

String resolveFirmwareManifestUrl() {
  const fromEnv = String.fromEnvironment('FIRMWARE_MANIFEST_URL');
  if (fromEnv.isNotEmpty) return fromEnv;
  return kDefaultFirmwareManifestUrl;
}

String resolveGiteeToken() {
  return const String.fromEnvironment('FIRMWARE_GITEE_TOKEN');
}

String resolveGiteeOwner() {
  const fromEnv = String.fromEnvironment('FIRMWARE_GITEE_OWNER');
  if (fromEnv.isNotEmpty) return fromEnv;
  return kDefaultGiteeOwner;
}

String resolveGiteeRepo() {
  const fromEnv = String.fromEnvironment('FIRMWARE_GITEE_REPO');
  if (fromEnv.isNotEmpty) return fromEnv;
  return kDefaultGiteeRepo;
}

String resolveGiteeBranch() {
  const fromEnv = String.fromEnvironment('FIRMWARE_GITEE_BRANCH');
  if (fromEnv.isNotEmpty) return fromEnv;
  return kDefaultGiteeBranch;
}

bool get useGiteePrivateApi => resolveGiteeToken().isNotEmpty;
