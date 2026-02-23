import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            subtitle: const Text('IoT Serial App'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.bluetooth),
            title: const Text('蓝牙权限说明'),
            subtitle: const Text('扫描与连接设备需要蓝牙权限'),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
