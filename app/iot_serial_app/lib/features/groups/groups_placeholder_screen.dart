import 'package:flutter/material.dart';

class GroupsPlaceholderScreen extends StatelessWidget {
  const GroupsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('群组')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.group_outlined, size: 64),
              SizedBox(height: 16),
              Text(
                '将设备分组管理，便于批量配置与场景联动',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 8),
              Text('暂无群组', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
