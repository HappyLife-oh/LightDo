import 'dart:io';

import 'package:flutter/material.dart';

import 'colors.dart';

abstract final class AppTheme {
  static ThemeData light() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: AppColors.scaffoldBg,
    canvasColor: Colors.transparent,
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2DD4BF),
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
