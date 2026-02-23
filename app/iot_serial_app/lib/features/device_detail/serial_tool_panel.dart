import 'package:flutter/material.dart';

/// BLE serial tool panel: config, RX/TX, loop send (placeholder).
class SerialToolPanel extends StatelessWidget {
  const SerialToolPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('串口工具', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('串口配置、接收/发送、循环发送等功能区域'),
        ],
      ),
    );
  }
}
