/// Stored device entity: id (e.g. MAC), type, name, lastConnected, config.
/// Aligns with design doc "本地数据库设计".
class DeviceEntity {
  const DeviceEntity({
    required this.id,
    required this.type,
    required this.name,
    this.lastConnected,
    this.config = const {},
  });

  final String id;
  final String type; // 'ble', 'wifi', 'gateway'
  final String name;
  final int? lastConnected; // timestamp
  final Map<String, dynamic> config;

  DeviceEntity copyWith({
    String? id,
    String? type,
    String? name,
    int? lastConnected,
    Map<String, dynamic>? config,
  }) {
    return DeviceEntity(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      lastConnected: lastConnected ?? this.lastConnected,
      config: config ?? this.config,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'lastConnected': lastConnected,
        'config': config,
      };

  factory DeviceEntity.fromJson(Map<String, dynamic> json) {
    return DeviceEntity(
      id: json['id'] as String,
      type: json['type'] as String,
      name: json['name'] as String,
      lastConnected: json['lastConnected'] as int?,
      config: json['config'] != null
          ? Map<String, dynamic>.from(json['config'] as Map)
          : {},
    );
  }
}
