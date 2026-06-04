import 'package:flutter/material.dart';

ThemeData appThemeForIndex(int index) {
  final seedColor = switch (index) {
    1 => Colors.teal,
    2 => Colors.deepOrange,
    _ => Colors.indigo,
  };
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
    useMaterial3: true,
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

Color stockUpColor(BuildContext context) =>
    Theme.of(context).colorScheme.error;

Color stockDownColor(BuildContext context) =>
    Colors.green.shade700;

Color colorForNetInflow(BuildContext context, double value) {
  if (value > 0) return stockUpColor(context);
  if (value < 0) return stockDownColor(context);
  return Theme.of(context).colorScheme.onSurfaceVariant;
}
