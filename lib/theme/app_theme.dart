import 'dart:io';

import 'package:flutter/material.dart';

import 'colors.dart';

abstract final class AppTheme {
  static const List<Color> accentSeeds = [
    Color(0xFF1D6F5F), // cyan
    Color(0xFF1565C0), // blue
    Color(0xFF7B1FA2), // purple
    Color(0xFF2E7D32), // green
    Color(0xFFE65100), // orange
    Color(0xFF546E7A), // gray
  ];

  static Color _seedFor({required Brightness brightness, int accentIndex = 0}) {
    final base = accentSeeds[accentIndex.clamp(0, accentSeeds.length - 1)];
    if (brightness == Brightness.dark) {
      final r = (base.r * 255.0).round().clamp(0, 255);
      final g = (base.g * 255.0).round().clamp(0, 255);
      final b = (base.b * 255.0).round().clamp(0, 255);
      return Color.fromARGB(255, (r + 128).clamp(0, 255), (g + 128).clamp(0, 255), (b + 128).clamp(0, 255));
    }
    return base;
  }

  static ThemeData light({int accentIndex = 0}) => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedFor(brightness: Brightness.light, accentIndex: accentIndex),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: AppColors.scaffoldBg,
    canvasColor: Colors.transparent,
  );

  static ThemeData dark({int accentIndex = 0}) => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedFor(brightness: Brightness.dark, accentIndex: accentIndex),
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF0F172A),
    canvasColor: Colors.transparent,
  );

  /// Transparent theme for the floating ball window (no decoration).
  static ThemeData floatingBall() => ThemeData(
    fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    shadowColor: Colors.transparent,
  );
}
