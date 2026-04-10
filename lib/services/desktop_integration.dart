import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/app_settings.dart';

DesktopIntegration createDesktopIntegration({
  WindowController? currentWindowController,
  String? ownerWindowId,
  bool enabled = true,
}) {
  if (!enabled ||
      !(Platform.isWindows || Platform.isMacOS || Platform.isLinux) ||
      currentWindowController == null ||
      ownerWindowId == null ||
      ownerWindowId.isEmpty) {
    return const NoopDesktopIntegration();
  }

  return EditorDesktopIntegration(
    currentWindowController: currentWindowController,
    ownerWindowId: ownerWindowId,
  );
}

abstract class DesktopIntegration {
  const DesktopIntegration();

  Future<void> initialize(AppSettings settings);
  Future<void> applySettings(AppSettings settings);
  Future<void> dispose();
}

class NoopDesktopIntegration extends DesktopIntegration {
  const NoopDesktopIntegration();

  @override
  Future<void> applySettings(AppSettings settings) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize(AppSettings settings) async {}
}

class EditorDesktopIntegration extends DesktopIntegration with WindowListener {
  EditorDesktopIntegration({
    required WindowController currentWindowController,
    required String ownerWindowId,
    WindowManager? windowManagerInstance,
  }) : _currentWindowController = currentWindowController,
       _ownerWindowController = WindowController.fromWindowId(ownerWindowId),
       _windowManager = windowManagerInstance ?? windowManager;

  static const Size _editorWindowSize = Size(420, 720);
  static const Size _editorWindowMinSize = Size(360, 600);
  static const double _screenPadding = 20;
  static const double _ballOverlap = 56;
  static const double _ballVerticalAnchorOffset = 24;

  final WindowController _currentWindowController;
  final WindowController _ownerWindowController;
  final WindowManager _windowManager;

  AppSettings _settings = AppSettings.defaults();
  bool _initialized = false;
  bool _disposed = false;

  @override
  Future<void> initialize(AppSettings settings) async {
    _settings = settings;
    if (_initialized) {
      await applySettings(settings);
      return;
    }

    _windowManager.addListener(this);
    await _currentWindowController.setWindowMethodHandler(_handleWindowCall);
    await _applyEditorWindowChrome();
    await _windowManager.hide();
    _initialized = true;
    await applySettings(settings);
  }

  @override
  Future<void> applySettings(AppSettings settings) async {
    _settings = settings;
    if (!_initialized || _disposed) {
      return;
    }

    await _windowManager.setAlwaysOnTop(settings.alwaysOnTop);
    try {
      await _ownerWindowController.invokeMethod('refreshSettings');
    } on PlatformException {
      return;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _windowManager.removeListener(this);
  }

  @override
  Future<void> onWindowBlur() async {
    if (!_settings.minimizeToTrayOnClose) {
      return;
    }
    await _hideEditorToBall();
  }

  @override
  Future<bool> onWindowClose() async {
    if (_settings.minimizeToTrayOnClose) {
      await _hideEditorToBall();
      return false;
    }
    return true;
  }

  Future<dynamic> _handleWindowCall(MethodCall call) async {
    if (call.method == 'showMainAtBall') {
      final payload =
          (call.arguments as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      await _showEditorAtBall(payload);
      return null;
    }

    throw MissingPluginException('Unknown method: ${call.method}');
  }

  Future<void> _applyEditorWindowChrome() async {
    if (Platform.isMacOS) {
      await _windowManager.setAsFrameless();
    } else {
      await _windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
    }
    await _windowManager.setPreventClose(true);
    await _windowManager.setResizable(true);
    await _windowManager.setMinimumSize(_editorWindowMinSize);
    await _windowManager.setBackgroundColor(const Color(0xFFF7F4ED));
    await _windowManager.setSkipTaskbar(false);
  }

  Future<void> _showEditorAtBall(Map<String, dynamic> payload) async {
    final ballX = (payload['ballX'] as num?)?.toDouble() ?? 0;
    final ballY = (payload['ballY'] as num?)?.toDouble() ?? 0;
    final ballWidth = (payload['ballWidth'] as num?)?.toDouble() ?? 76;
    final visibleX = (payload['visibleX'] as num?)?.toDouble() ?? 0;
    final visibleY = (payload['visibleY'] as num?)?.toDouble() ?? 0;
    final visibleWidth = (payload['visibleWidth'] as num?)?.toDouble() ?? 1440;
    final visibleHeight = (payload['visibleHeight'] as num?)?.toDouble() ?? 900;
    final anchorSide = payload['anchorSide'] as String? ?? 'right';

    final left = anchorSide == 'right'
        ? ballX + ballWidth - _ballOverlap - _editorWindowSize.width
        : ballX - ballWidth + _ballOverlap;
    final top = ballY + ballWidth - _ballVerticalAnchorOffset;

    final clampedLeft = left.clamp(
      visibleX + _screenPadding,
      visibleX + visibleWidth - _editorWindowSize.width - _screenPadding,
    );
    final clampedTop = top.clamp(
      visibleY + _screenPadding,
      visibleY + visibleHeight - _editorWindowSize.height - _screenPadding,
    );

    try {
      await _ownerWindowController.invokeMethod('setBallOverlayState', {
        'coveredByMain': true,
      });
    } on PlatformException {
      return;
    }

    await _windowManager.setBounds(
      Rect.fromLTWH(
        clampedLeft,
        clampedTop,
        _editorWindowSize.width,
        _editorWindowSize.height,
      ),
    );
    await _windowManager.setAlwaysOnTop(_settings.alwaysOnTop);
    await _windowManager.show();
    await _windowManager.focus();
  }

  Future<void> _hideEditorToBall() async {
    await _windowManager.hide();
    await _restoreFloatingBall();
  }

  Future<void> _restoreFloatingBall() async {
    try {
      await _ownerWindowController.invokeMethod('setBallOverlayState', {
        'coveredByMain': false,
      });
    } on PlatformException {
      return;
    }
  }
}
