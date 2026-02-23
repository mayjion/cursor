import 'package:flutter/material.dart';

/// Returns one of 3 themes by index: 0 = blue, 1 = green, 2 = purple.
ThemeData appThemeForIndex(int index) {
  final seedColor = switch (index) {
    1 => Colors.green,
    2 => Colors.purple,
    _ => Colors.blue,
  };
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
    useMaterial3: true,
  );
}
