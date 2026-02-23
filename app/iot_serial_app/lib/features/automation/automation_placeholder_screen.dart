import 'package:flutter/material.dart';

class AutomationPlaceholderScreen extends StatelessWidget {
  const AutomationPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自动化')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome_outlined, size: 64),
              SizedBox(height: 16),
              Text(
                '设置条件与动作，实现设备联动',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 8),
              Text('功能即将开放', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
