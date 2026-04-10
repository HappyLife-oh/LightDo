import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import 'window_arguments.dart';
import '../services/lightdo_storage.dart';

class FloatingBallApp extends StatelessWidget {
  const FloatingBallApp({super.key, required this.ballWindowId});

  final String ballWindowId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      home: FloatingBallHome(ballWindowId: ballWindowId),
    );
  }
}

class FloatingBallHome extends StatefulWidget {
  const FloatingBallHome({super.key, required this.ballWindowId});

  final String ballWindowId;

  @override
  State<FloatingBallHome> createState() => _FloatingBallHomeState();
}

class _FloatingBallHomeState extends State<FloatingBallHome>
    with WindowListener {
  static final Size _ballWindowSize = Platform.isWindows
      ? const Size(76, 78)
      : const Size(76, 76);
  static const double _launchTopPadding = 28;
  static const double _launchRightPadding = 24;

  final LightDoStorage _storage = const FileLightDoStorage();
  final SystemTray _systemTray = SystemTray();
  final Menu _trayMenu = Menu();
  final HotKey _toggleHotKey = HotKey(
    key: PhysicalKeyboardKey.keyT,
    modifiers: [HotKeyModifier.alt, HotKeyModifier.shift],
  );

  WindowController? _currentController;
  WindowController? _editorWindowController;
  bool _trayReady = false;
  bool _hotKeyEnabled = true;
  bool _launchAtStartupEnabled = false;
  bool _coveredByMain = false;
  bool _flashPhase = false;
  DateTime? _activeReminderUntil;
  Timer? _reminderPollTimer;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    unawaited(hotKeyManager.unregisterAll());
    _reminderPollTimer?.cancel();
    _flashTimer?.cancel();
    if (_trayReady && Platform.isWindows) {
      unawaited(_systemTray.destroy());
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    _currentController = await WindowController.fromCurrentEngine();
    await _currentController!.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'refreshSettings':
          await _loadSettings();
          return null;
        case 'setBallOverlayState':
          final arguments =
              (call.arguments as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final coveredByMain = arguments['coveredByMain'] as bool? ?? false;
          if (mounted) {
            setState(() {
              _coveredByMain = coveredByMain;
            });
          }
          await windowManager.setAlwaysOnTop(!coveredByMain);
          if (!coveredByMain) {
            await windowManager.show();
          }
          return null;
        default:
          throw MissingPluginException('Unknown method: ${call.method}');
      }
    });
    windowManager.addListener(this);
    await _prepareFloatingBallWindow();
    await _loadSettings();
    _startReminderMonitoring();
    unawaited(_warmUpEditorWindow());
    if (Platform.isWindows) {
      await _setupTray();
    }
  }

  Future<void> _prepareFloatingBallWindow() async {
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setResizable(false);
    await windowManager.setMinimumSize(_ballWindowSize);
    await windowManager.setMaximumSize(_ballWindowSize);
    await windowManager.setAlwaysOnTop(true);
    await _positionFloatingBallAtLaunch();
  }

  Future<void> _positionFloatingBallAtLaunch() async {
    final display = await screenRetriever.getPrimaryDisplay();
    final visiblePosition = display.visiblePosition ?? Offset.zero;
    final visibleSize = display.visibleSize ?? display.size;
    final left =
        visiblePosition.dx +
        visibleSize.width -
        _ballWindowSize.width -
        _launchRightPadding;
    final top = visiblePosition.dy + _launchTopPadding;
    await windowManager.setBounds(
      Rect.fromLTWH(left, top, _ballWindowSize.width, _ballWindowSize.height),
    );
  }

  Future<void> _spawnEditorWindowIfNeeded() async {
    if (_editorWindowController != null || _currentController == null) {
      return;
    }
    _editorWindowController = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: LightDoWindowArguments.editor(
          mainWindowId: _currentController!.windowId,
        ).encode(),
      ),
    );
  }

  Future<void> _warmUpEditorWindow() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _spawnEditorWindowIfNeeded();
  }

  Future<void> _loadSettings() async {
    final snapshot = await _storage.load();
    _hotKeyEnabled = snapshot.settings.enableGlobalHotkey;
    _launchAtStartupEnabled = snapshot.settings.launchAtStartup;
    await _syncLaunchAtStartup();
    await _syncHotKey();
  }

  void _startReminderMonitoring() {
    _reminderPollTimer?.cancel();
    _flashTimer?.cancel();
    _reminderPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refreshReminderState());
    });
    _flashTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final reminderActive = _isReminderActive;
      if (!mounted) {
        return;
      }
      if (!reminderActive) {
        if (_flashPhase) {
          setState(() {
            _flashPhase = false;
          });
        }
        return;
      }
      setState(() {
        _flashPhase = !_flashPhase;
      });
    });
    unawaited(_refreshReminderState());
  }

  Future<void> _refreshReminderState() async {
    try {
      final snapshot = await _storage.load();
      final now = DateTime.now();
      DateTime? reminderUntil;
      for (final todo in snapshot.todos) {
        if (!todo.shouldFlashReminderAt(now)) {
          continue;
        }
        final endsAt = todo.reminderEndsAt();
        if (endsAt == null) {
          continue;
        }
        if (reminderUntil == null || endsAt.isAfter(reminderUntil)) {
          reminderUntil = endsAt;
        }
      }
      if (!mounted) {
        return;
      }
      final changed =
          (reminderUntil == null && _activeReminderUntil != null) ||
          (reminderUntil != null &&
              (_activeReminderUntil == null ||
                  !_activeReminderUntil!.isAtSameMomentAs(reminderUntil)));
      if (!changed) {
        return;
      }
      setState(() {
        _activeReminderUntil = reminderUntil;
        if (reminderUntil == null) {
          _flashPhase = false;
        }
      });
    } catch (_) {
      return;
    }
  }

  Future<void> _syncLaunchAtStartup() async {
    if (!Platform.isWindows) {
      return;
    }
    launchAtStartup.setup(
      appName: 'LightDo',
      appPath: Platform.resolvedExecutable,
    );
    final enabled = await launchAtStartup.isEnabled();
    if (_launchAtStartupEnabled && !enabled) {
      await launchAtStartup.enable();
      return;
    }
    if (!_launchAtStartupEnabled && enabled) {
      await launchAtStartup.disable();
    }
  }

  Future<void> _syncHotKey() async {
    await hotKeyManager.unregisterAll();
    if (!_hotKeyEnabled) {
      return;
    }
    await hotKeyManager.register(
      _toggleHotKey,
      keyDownHandler: (_) async {
        await _openMainWindow();
      },
    );
  }

  Future<void> _setupTray() async {
    final iconPath = await _ensureTrayIconPath();
    await _systemTray.initSystemTray(
      title: 'LightDo',
      iconPath: iconPath,
      toolTip: 'LightDo',
    );
    _systemTray.registerSystemTrayEventHandler((eventName) async {
      if (eventName == kSystemTrayEventRightClick) {
        await _systemTray.popUpContextMenu();
        return;
      }
      if (eventName == kSystemTrayEventClick ||
          eventName == kSystemTrayEventDoubleClick) {
        await _openMainWindow();
      }
    });
    await _trayMenu.buildFrom([
      MenuItemLabel(
        label: '显示主窗口',
        onClicked: (_) async {
          await _openMainWindow();
        },
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: '退出 LightDo',
        onClicked: (_) async {
          await Future.wait([
            hotKeyManager.unregisterAll(),
            _systemTray.destroy(),
          ]);
          await windowManager.destroy();
          exit(0);
        },
      ),
    ]);
    await _systemTray.setContextMenu(_trayMenu);
    _trayReady = true;
  }

  Future<String> _ensureTrayIconPath() async {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}lightdo_tray.ico',
    );
    if (!await file.exists()) {
      final bytes = await rootBundle.load('assets/windows/app_icon.ico');
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
    }
    return file.path;
  }

  Future<void> _openMainWindow() async {
    await _spawnEditorWindowIfNeeded();
    final controller = _editorWindowController;
    if (controller == null) {
      return;
    }
    final position = await windowManager.getPosition();
    final size = await windowManager.getSize();
    final display = await _resolveDisplayForBall(position, size);
    final visiblePosition = display.visiblePosition ?? Offset.zero;
    final visibleSize = display.visibleSize ?? display.size;
    final centerX = position.dx + size.width / 2;
    final side = centerX >= visiblePosition.dx + visibleSize.width / 2
        ? 'right'
        : 'left';
    final payload = {
      'ballX': position.dx,
      'ballY': position.dy,
      'ballWidth': size.width,
      'ballHeight': size.height,
      'visibleX': visiblePosition.dx,
      'visibleY': visiblePosition.dy,
      'visibleWidth': visibleSize.width,
      'visibleHeight': visibleSize.height,
      'anchorSide': side,
    };
    await _invokeMainWindowWhenReady(controller, payload);
  }

  Future<void> _invokeMainWindowWhenReady(
    WindowController controller,
    Map<String, dynamic> payload,
  ) async {
    Object? lastError;
    for (var i = 0; i < 12; i++) {
      try {
        await controller.invokeMethod('showMainAtBall', payload);
        return;
      } catch (error) {
        lastError = error;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    if (lastError != null) {
      throw lastError;
    }
  }

  Future<Display> _resolveDisplayForBall(Offset position, Size size) async {
    final displays = await screenRetriever.getAllDisplays();
    if (displays.isEmpty) {
      return screenRetriever.getPrimaryDisplay();
    }

    final ballCenter = Offset(
      position.dx + size.width / 2,
      position.dy + size.height / 2,
    );
    Display? bestDisplay;
    double? bestDistance;

    for (final display in displays) {
      final displayRect = _displayRect(display);
      if (displayRect.contains(ballCenter)) {
        return display;
      }
      final distance = _distanceToRect(ballCenter, displayRect);
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        bestDisplay = display;
      }
    }

    return bestDisplay ?? screenRetriever.getPrimaryDisplay();
  }

  Rect _displayRect(Display display) {
    final position = display.visiblePosition ?? Offset.zero;
    final size = display.visibleSize ?? display.size;
    return Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
  }

  double _distanceToRect(Offset point, Rect rect) {
    final dx = point.dx < rect.left
        ? rect.left - point.dx
        : point.dx > rect.right
        ? point.dx - rect.right
        : 0.0;
    final dy = point.dy < rect.top
        ? rect.top - point.dy
        : point.dy > rect.bottom
        ? point.dy - rect.bottom
        : 0.0;
    return dx * dx + dy * dy;
  }

  @override
  Widget build(BuildContext context) {
    final reminderActive = _isReminderActive;
    final gradientColors = _ballGradientColors(
      reminderActive: reminderActive,
      coveredByMain: _coveredByMain,
      flashPhase: _flashPhase,
    );
    final borderColor = reminderActive && _flashPhase
        ? const Color(0xFFFFF1C8)
        : _coveredByMain
        ? const Color(0xFFF6E3A2)
        : Colors.white.withValues(alpha: 0.82);

    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: DragToMoveArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              unawaited(_openMainWindow());
            },
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
                border: Border.all(color: borderColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1D6F5F).withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.checklist_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _isReminderActive =>
      _activeReminderUntil != null &&
      DateTime.now().isBefore(_activeReminderUntil!);

  List<Color> _ballGradientColors({
    required bool reminderActive,
    required bool coveredByMain,
    required bool flashPhase,
  }) {
    if (reminderActive && flashPhase) {
      return const [Color(0xFFE46048), Color(0xFFF6A85E)];
    }
    if (coveredByMain) {
      return const [Color(0xFFD4AF4F), Color(0xFF91B64F)];
    }
    return const [Color(0xD91A7A68), Color(0xD93CA692)];
  }
}
