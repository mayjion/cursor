import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/firmware/ap_device_family.dart';
import '../../core/firmware/ap_device_info.dart';
import '../../core/firmware/flasher_burner_catalog.dart';
import '../../core/firmware/firmware_asset_loader.dart';
import '../../core/firmware/firmware_catalog.dart';
import '../../core/firmware/firmware_target_chip.dart';
import '../../core/firmware/fun_ap_ota_client.dart';
import '../../core/firmware/ota_debug_log.dart';
import '../../core/firmware/tri_dtu_catalog.dart';
import '../../core/firmware/remote/firmware_manifest.dart';
import '../../core/firmware/remote/firmware_remote_errors.dart';
import '../../core/firmware/remote/firmware_remote_repository.dart';
import '../../core/settings/app_strings.dart';

class FirmwareUpgradeScreen extends ConsumerStatefulWidget {
  const FirmwareUpgradeScreen({super.key});

  @override
  ConsumerState<FirmwareUpgradeScreen> createState() => _FirmwareUpgradeScreenState();
}

class _FirmwareUpgradeScreenState extends ConsumerState<FirmwareUpgradeScreen> {
  String? _wifiSsid;
  String? _wifiGateway;
  bool _networkBusy = false;
  String? _networkError;

  ApDeviceInfo? _deviceInfo;
  bool _probeBusy = false;
  String? _probeError;

  FirmwareCatalogEntry? _selected;
  bool _uploadBusy = false;
  String? _uploadStatus;

  late final FirmwareRemoteRepository _remoteRepo;
  late final FirmwareAssetLoader _firmwareLoader;

  bool _manifestBusy = false;
  String? _manifestError;
  FirmwareManifestEntry? _remoteEntry;
  bool _remoteUpdateAvailable = false;

  bool _downloadBusy = false;
  int _downloadProgress = 0;
  String? _downloadError;
  String? _remoteCachePath;

  Future<void> _refreshNetwork() async {
    setState(() {
      _networkBusy = true;
      _networkError = null;
    });
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final st = await Permission.location.status;
        if (!st.isGranted) {
          await Permission.location.request();
        }
      }
      final info = NetworkInfo();
      final name = await info.getWifiName();
      final gw = await info.getWifiGatewayIP();
      if (!mounted) return;
      setState(() {
        _wifiSsid = _stripQuotes(name);
        _wifiGateway = gw;
        _networkBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _networkBusy = false;
        _networkError = '$e';
      });
    }
  }

  static String? _stripQuotes(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
      return t.substring(1, t.length - 1);
    }
    return t;
  }

  bool get _ssidLooksLikeFunAp => ssidLooksLikeOtaAp(_wifiSsid);

  bool get _gatewayLooksLikeSoftAp {
    final g = _wifiGateway;
    if (g == null || g.isEmpty) return true;
    return g == kExpectedApGateway;
  }

  bool get _environmentOk => _ssidLooksLikeFunAp && _gatewayLooksLikeSoftAp;

  Future<void> _checkRemoteUpdate({bool showNoUpdateSnack = false}) async {
    final device = _deviceInfo;
    if (device == null) return;

    setState(() {
      _manifestBusy = true;
      _manifestError = null;
      _remoteEntry = null;
      _remoteUpdateAvailable = false;
    });

    try {
      final manifest = await _remoteRepo.fetchManifest();
      final entry = _remoteRepo.findEntryForProduct(manifest, device.product);
      if (!mounted) return;

      final hasUpdate = entry != null &&
          _remoteRepo.hasUpdateForDevice(
            entry: entry,
            deviceVersion: device.version,
          );
      String? cachedPath;
      if (entry != null && await _remoteRepo.isCached(entry)) {
        cachedPath = await _remoteRepo.cachedPathForEntry(entry);
      }

      setState(() {
        _manifestBusy = false;
        _remoteEntry = entry;
        _remoteUpdateAvailable = hasUpdate;
        _remoteCachePath = cachedPath;
      });

      if (showNoUpdateSnack && !hasUpdate && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(appStringsProvider).firmwareNoRemoteUpdate)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final strings = ref.read(appStringsProvider);
      setState(() {
        _manifestBusy = false;
        _manifestError = formatFirmwareRemoteError(e, strings);
      });
    }
  }

  Future<void> _downloadRemoteFirmware() async {
    final entry = _remoteEntry;
    if (entry == null) return;
    final strings = ref.read(appStringsProvider);

    setState(() {
      _downloadBusy = true;
      _downloadProgress = 0;
      _downloadError = null;
    });

    try {
      final path = await _remoteRepo.downloadFirmware(
        entry,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() {
            _downloadProgress = ((received * 100) / total).clamp(0, 100).round();
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _downloadBusy = false;
        _downloadProgress = 100;
        _remoteCachePath = path;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.firmwareDownloadDone)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadBusy = false;
        _downloadError = formatFirmwareRemoteError(e, strings);
      });
    }
  }

  Future<void> _probeDevice() async {
    setState(() {
      _probeBusy = true;
      _probeError = null;
      _deviceInfo = null;
      _remoteEntry = null;
      _remoteUpdateAvailable = false;
      _remoteCachePath = null;
    });
    final client = FunApOtaClient();
    try {
      ApDeviceInfo? parsed;

      try {
        final jsonText = await client.fetchInfoJson();
        parsed = parseApDeviceInfoFromJson(jsonText);
      } catch (_) {}

      if (parsed == null) {
        final html = await client.fetchSystemHtml();
        parsed = parseApDeviceInfo(html);
      }

      if (!mounted) return;
      if (parsed == null) {
        setState(() {
          _probeBusy = false;
          _probeError = ref.read(appStringsProvider).firmwareParseError;
        });
        return;
      }
      final info = parsed;
      setState(() {
        _deviceInfo = info;
        if (info.isFlasherBurner) {
          _selected = flasherBurnerCatalogForProduct(info.product);
        } else if (info.isTriDtu) {
          _selected = triDtuCatalogForProduct(info.product);
        } else {
          _selected = null;
        }
        _probeBusy = false;
      });
      await _checkRemoteUpdate();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _probeBusy = false;
        _probeError = '$e';
      });
    } finally {
      client.close();
    }
  }

  Future<void> _startUpload(FirmwareCatalogEntry entry) async {
    final strings = ref.read(appStringsProvider);
    final device = _deviceInfo;
    if (device != null &&
        device.isFlasherBurner &&
        !catalogEntryMatchesBurnerDevice(entry, device.product)) {
      setState(() {
        _uploadStatus = strings.firmwareBurnerMismatch;
      });
      return;
    }
    if (device != null &&
        device.isTriDtu &&
        !catalogEntryMatchesTriDtuDevice(entry, device.product)) {
      setState(() {
        _uploadStatus = strings.firmwareTriDtuMismatch;
      });
      return;
    }

    final crossFamily =
        device != null && isBurnerCrossFamilyUpgrade(entry, device.product);
    final confirmBody = crossFamily
        ? strings.firmwareConfirmBodyCrossFamily(
            device.product,
            entry.titleForLocale(isZh: strings.isZh),
          )
        : strings.firmwareConfirmBody(entry.titleForLocale(isZh: strings.isZh));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.firmwareConfirmTitle),
        content: Text(confirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.firmwareCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(strings.firmwareConfirmUpload)),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _uploadBusy = true;
      _uploadStatus = strings.firmwareUploading;
    });

    final uploadSw = Stopwatch()..start();
    otaLogPhase(
      'upload_start',
      detail:
          'product=${entry.productId} uploadFile=${entry.otaUploadFilename} '
          'device=${_deviceInfo?.product ?? "?"}',
    );

    final client = FunApOtaClient();
    try {
      final cachePath = _remoteCachePath ??
          await _remoteRepo.cachedPathForCatalogEntry(entry);
      final bytes = await _firmwareLoader.loadFirmwarePlainBytesFromCacheOrAsset(
        entry,
        cachePath: cachePath,
      );

      final status = await client
          .uploadFirmwareComplete(
            bytes,
            filename: entry.otaUploadFilename,
            onPhase: (phase) {
              if (!mounted) return;
              setState(() {
                _uploadStatus = phase == OtaUploadPhase.awaitingDevice
                    ? strings.firmwareUploadingDevice
                    : strings.firmwareUploading;
              });
            },
          )
          .timeout(kOtaUploadTotalTimeout);
      if (status < 200 || status >= 300) {
        throw StateError('HTTP $status');
      }

      otaLogPhase('upload_ok', elapsed: uploadSw.elapsed);

      if (!mounted) return;
      setState(() {
        _uploadBusy = false;
        _uploadStatus = strings.firmwareUploadDone;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.firmwareSuccessReboot)));
      }
    } on TimeoutException catch (e, st) {
      otaLogPhase('upload_timeout', detail: '$e', elapsed: uploadSw.elapsed);
      otaLog('upload_timeout stack', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _uploadBusy = false;
        _uploadStatus = strings.firmwareUploadTimeoutHint;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.firmwareUploadTimeoutHint)),
        );
      }
    } catch (e, st) {
      otaLogPhase('upload_fail', detail: '$e', elapsed: uploadSw.elapsed);
      otaLog('upload_fail stack', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _uploadBusy = false;
        _uploadStatus = '${strings.firmwareUploadFailed}: $e';
      });
    } finally {
      client.close();
    }
  }

  @override
  void initState() {
    super.initState();
    _remoteRepo = FirmwareRemoteRepository();
    _firmwareLoader = FirmwareAssetLoader(cache: _remoteRepo.cache);
    otaLogPhase('firmware_screen_open');
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshNetwork());
  }

  @override
  void dispose() {
    _remoteRepo.close();
    super.dispose();
  }

  Widget _buildRemoteUpdateCard(AppStrings strings) {
    final entry = _remoteEntry;
    final device = _deviceInfo;
    if (entry == null || device == null || !_remoteUpdateAvailable) {
      return const SizedBox.shrink();
    }

    final changelog = strings.isZh
        ? (entry.changelogZh ?? '')
        : (entry.changelogEn ?? '');
    final hasCache = _remoteCachePath != null;

    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.firmwareRemoteUpdateTitle, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              strings.firmwareRemoteUpdateBody(
                device.version ?? strings.firmwareUnknown,
                entry.version,
              ),
            ),
            if (changelog.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(changelog, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 4),
            Text(
              strings.firmwareRemoteNetworkHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
            ),
            if (hasCache) ...[
              const SizedBox(height: 8),
              Text(
                strings.firmwareUseRemoteFirmware,
                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            if (_downloadBusy) ...[
              LinearProgressIndicator(value: _downloadProgress > 0 ? _downloadProgress / 100 : null),
              const SizedBox(height: 8),
              Text(
                _downloadProgress > 0
                    ? strings.firmwareDownloadProgress(_downloadProgress)
                    : strings.firmwareDownloading,
                style: const TextStyle(fontSize: 13),
              ),
            ] else if (!hasCache)
              FilledButton.tonal(
                onPressed: _downloadBusy ? null : _downloadRemoteFirmware,
                child: Text(strings.firmwareDownloadFirmware),
              ),
            if (_downloadError != null) ...[
              const SizedBox(height: 8),
              Text(_downloadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final chip = _deviceInfo?.inferredChip;
    final entries = _deviceInfo == null
        ? <FirmwareCatalogEntry>[]
        : (_deviceInfo!.isFlasherBurner
            ? flasherBurnerCatalogEntriesForDevice(_deviceInfo!.product)
            : _deviceInfo!.isTriDtu
                ? triDtuCatalogEntriesForDevice(_deviceInfo!.product)
                : (chip == null ? <FirmwareCatalogEntry>[] : catalogForChip(chip)));

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.firmwareTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            onPressed: _deviceInfo == null || _manifestBusy
                ? null
                : () => _checkRemoteUpdate(showNoUpdateSnack: true),
            tooltip: strings.firmwareCheckUpdate,
            icon: _manifestBusy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(strings.firmwareIntro, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            strings.firmwareEspFlasherHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.firmwareNetworkSection, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${strings.firmwareSsidLabel}${_wifiSsid ?? strings.firmwareUnknown}\n'
                          '${strings.firmwareGatewayLabel}${_wifiGateway ?? strings.firmwareUnknown}',
                        ),
                      ),
                      IconButton(
                        onPressed: _networkBusy ? null : _refreshNetwork,
                        icon: _networkBusy
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  if (_networkError != null) Text(_networkError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 8),
                  if (!_environmentOk)
                    Text(
                      strings.firmwareEnvWarning,
                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
                    )
                  else
                    Text(strings.firmwareEnvOk, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: (!_environmentOk && _wifiSsid != null) || _probeBusy ? null : _probeDevice,
            child: _probeBusy
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(strings.firmwareProbeButton),
          ),
          if (_probeError != null) ...[
            const SizedBox(height: 8),
            Text(_probeError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_manifestError != null) ...[
            const SizedBox(height: 8),
            Text(_manifestError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ],
          if (_deviceInfo != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strings.firmwareDeviceSection, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Text('${strings.firmwareProductLabel} ${_deviceInfo!.product}'),
                    Text(
                      '${strings.firmwareVersionLabel} '
                      '${_deviceInfo!.version ?? strings.firmwareUnknown}',
                    ),
                    Text(
                      '${strings.firmwareChipLabel} ${_chipLabel(_deviceInfo!.inferredChip, strings)}',
                    ),
                    if (_deviceInfo!.variant != null)
                      Text('${strings.firmwareVariantLabel} ${_deviceInfo!.variant}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildRemoteUpdateCard(strings),
            const SizedBox(height: 8),
            Text(
              _deviceInfo!.isFlasherBurner
                  ? strings.firmwarePickFirmwareBurner
                  : strings.firmwarePickFirmware,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ...entries.map((e) {
              final isCurrentDevice =
                  catalogEntryMatchesDeviceProduct(e, _deviceInfo!.product);
              final scheme = Theme.of(context).colorScheme;
              return Card(
                color: isCurrentDevice ? scheme.secondaryContainer : null,
                clipBehavior: Clip.antiAlias,
                child: RadioListTile<FirmwareCatalogEntry>(
                  value: e,
                  groupValue: _selected,
                  onChanged: _uploadBusy
                      ? null
                      : (v) {
                          setState(() => _selected = v);
                        },
                  title: Text(e.titleForLocale(isZh: strings.isZh)),
                  subtitle: Text(
                    e.descriptionForLocale(isZh: strings.isZh),
                    maxLines: 8,
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _selected == null || _uploadBusy ? null : () => _startUpload(_selected!),
              child: Text(strings.firmwareStartUpload),
            ),
          ],
          if (_uploadBusy || _uploadStatus != null) ...[
            const SizedBox(height: 16),
            if (_uploadBusy) const LinearProgressIndicator(),
            if (_uploadStatus != null) Text(_uploadStatus!, style: const TextStyle(fontSize: 13)),
          ],
        ],
      ),
    );
  }

  String _chipLabel(FirmwareTargetChip c, AppStrings strings) {
    switch (c) {
      case FirmwareTargetChip.esp32c3:
        return strings.firmwareChipC3;
      case FirmwareTargetChip.esp32s2:
        return strings.firmwareChipS2;
      case FirmwareTargetChip.esp32s3:
        return strings.firmwareChipS3;
    }
  }
}
