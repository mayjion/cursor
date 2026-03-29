import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/firmware/ap_device_info.dart';
import '../../core/firmware/firmware_catalog.dart';
import '../../core/firmware/firmware_target_chip.dart';
import '../../core/firmware/fun_ap_ota_client.dart';
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

  bool get _ssidLooksLikeFunAp {
    final s = _wifiSsid ?? '';
    return s.toUpperCase().startsWith('FUN');
  }

  bool get _gatewayLooksLikeSoftAp {
    final g = _wifiGateway;
    if (g == null || g.isEmpty) return true;
    return g == kExpectedApGateway;
  }

  bool get _environmentOk => _ssidLooksLikeFunAp && _gatewayLooksLikeSoftAp;

  Future<void> _probeDevice() async {
    setState(() {
      _probeBusy = true;
      _probeError = null;
      _deviceInfo = null;
    });
    try {
      final client = FunApOtaClient();
      final html = await client.fetchSystemHtml();
      final parsed = parseApDeviceInfo(html);
      if (!mounted) return;
      if (parsed == null) {
        setState(() {
          _probeBusy = false;
          _probeError = ref.read(appStringsProvider).firmwareParseError;
        });
        return;
      }
      setState(() {
        _deviceInfo = parsed;
        _selected = null;
        _probeBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _probeBusy = false;
        _probeError = '$e';
      });
    }
  }

  Future<void> _startUpload(FirmwareCatalogEntry entry) async {
    final strings = ref.read(appStringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.firmwareConfirmTitle),
        content: Text(strings.firmwareConfirmBody(entry.titleForLocale(isZh: strings.isZh))),
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

    try {
      final data = await rootBundle.load(entry.assetPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (bytes.length < 1024) {
        throw StateError(strings.firmwarePlaceholderError);
      }

      final client = FunApOtaClient();
      final streamed = await client.uploadFirmware(
        bytes,
        filename: entry.assetPath.split('/').last,
      );
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('HTTP ${response.statusCode}');
      }

      if (!mounted) return;
      setState(() {
        _uploadBusy = false;
        _uploadStatus = strings.firmwareUploadDone;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.firmwareSuccessReboot)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadBusy = false;
        _uploadStatus = '${strings.firmwareUploadFailed}: $e';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshNetwork());
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final chip = _deviceInfo?.inferredChip;
    final entries = chip == null ? <FirmwareCatalogEntry>[] : catalogForChip(chip);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.firmwareTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(strings.firmwareIntro, style: Theme.of(context).textTheme.bodyMedium),
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(strings.firmwarePickFirmware, style: Theme.of(context).textTheme.titleSmall),
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
