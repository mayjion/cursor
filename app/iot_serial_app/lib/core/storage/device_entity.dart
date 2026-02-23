/// Stored device entity: id, type (connection), deviceType (product), name, lastConnected, config.
/// type = connection type (ble/wifi/gateway); deviceType = product type (e.g. FUN-UART) for panel selection.
class DeviceEntity {
  static const String defaultDeviceType = 'FUN-UART';

  const DeviceEntity({
    required this.id,
    required this.type,
    required this.name,
    this.deviceType = defaultDeviceType,
    this.lastConnected,
    this.config = const {},
    this.wifiMac,
  });

  final String id;
  final String type; // 'ble', 'wifi', 'gateway' (connection type)
  final String name;
  final String deviceType; // e.g. 'FUN-UART' (product type for panel)
  final int? lastConnected; // timestamp
  final Map<String, dynamic> config;
  /// WiFi MAC from status query ACK [2..7], e.g. "AA:BB:CC:DD:EE:FF". Used when adding peer from saved device.
  final String? wifiMac;

  DeviceEntity copyWith({
    String? id,
    String? type,
    String? name,
    String? deviceType,
    int? lastConnected,
    Map<String, dynamic>? config,
    String? wifiMac,
  }) {
    return DeviceEntity(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      deviceType: deviceType ?? this.deviceType,
      lastConnected: lastConnected ?? this.lastConnected,
      config: config ?? this.config,
      wifiMac: wifiMac ?? this.wifiMac,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'deviceType': deviceType,
        'lastConnected': lastConnected,
        'config': config,
        if (wifiMac != null) 'wifiMac': wifiMac,
      };

  factory DeviceEntity.fromJson(Map<String, dynamic> json) {
    return DeviceEntity(
      id: json['id'] as String,
      type: json['type'] as String,
      name: json['name'] as String,
      deviceType: json['deviceType'] as String? ?? defaultDeviceType,
      lastConnected: json['lastConnected'] as int?,
      config: json['config'] != null
          ? Map<String, dynamic>.from(json['config'] as Map)
          : {},
      wifiMac: json['wifiMac'] as String?,
    );
  }
}
