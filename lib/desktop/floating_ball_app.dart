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

import 'ball_quick_menu.dart';
import 'window_arguments.dart';
import '../models/todo_item.dart';
import '../services/lightdo_storage.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';

class FloatingBallApp extends StatelessWidget {
  const FloatingBallApp({super.key, required this.ballWindowId});

  final String ballWindowId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.floatingBall(),
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
    with WindowListener, TickerProviderStateMixin {
  static final Size _ballWindowSize = Platform.isWindows
      ? const Size(76, 78)
      : const Size(76, 76);
  static const double _launchTopPadding = 28;
  static const double _launchRightPadding = 24;
  static const double _snapThreshold = 30;
  static final Size _menuWindowSize = const Size(220, 170);
  static final Offset _ballOffsetInMenu = const Offset(72, 94);

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
  bool _hasOverdueTodos = false;
  int _activeTodoCount = 0;
  bool _isHovered = false;
  bool _isSnapped = false;
  bool _showQuickMenu = false;
  Timer? _overduePollTimer;
  Timer? _snapDebounceTimer;

  late final AnimationController _breatheController;
  late final Animation<double> _breatheAnimation;

  @override
  void initState() {
    super.initState();
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _breatheAnimation = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );
    unawaited(_initialize());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    unawaited(hotKeyManager.unregisterAll());
    _overduePollTimer?.cancel();
    _snapDebounceTimer?.cancel();
    _breatheController.dispose();
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
    _startMonitoring();
    _startBreathing();
    unawaited(_warmUpEditorWindow());
    if (Platform.isWindows) {
      await _setupTray();
    }
  }

  void _startBreathing() {
    // Start idle breathing after a brief delay to avoid clashing with launch.
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _breatheController.repeat(reverse: true);
      }
    });
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

  void _startMonitoring() {
    _overduePollTimer?.cancel();
    _overduePollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refreshBallState());
    });
    unawaited(_refreshBallState());
  }

  Future<void> _refreshBallState() async {
    try {
      final snapshot = await _storage.load();
      final now = DateTime.now();
      var hasOverdue = false;
      var activeCount = 0;
      for (final todo in snapshot.todos) {
        if (todo.isDeleted) continue;
        if (todo.isCompleted) continue;
        activeCount++;
        if (todo.deadlineStateAt(now) == TodoDeadlineState.overdue) {
          hasOverdue = true;
        }
      }
      if (!mounted) return;
      if (_hasOverdueTodos != hasOverdue ||
          _activeTodoCount != activeCount) {
        setState(() {
          _hasOverdueTodos = hasOverdue;
          _activeTodoCount = activeCount;
        });
      }
    } catch (_) {}
  }

  Future<void> _syncLaunchAtStartup() async {
    if (!Platform.isWindows) return;
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
    if (!_hotKeyEnabled) return;
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
    if (controller == null) return;
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
    _editorWindowController = null;
    if (lastError != null) throw lastError;
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
      if (displayRect.contains(ballCenter)) return display;
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

  // ── Edge snapping ────────────────────────────────────────────────────

  @override
  void onWindowMove() {
    _snapDebounceTimer?.cancel();
    _snapDebounceTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_trySnapToEdge());
    });
  }

  @override
  void onWindowMoved() {
    _snapDebounceTimer?.cancel();
    unawaited(_trySnapToEdge());
  }

  Future<void> _trySnapToEdge() async {
    if (_coveredByMain || !mounted) return;
    final position = await windowManager.getPosition();
    final display = await screenRetriever.getPrimaryDisplay();
    final visibleX = display.visiblePosition?.dx ?? 0;
    final visibleWidth = display.visibleSize?.width ?? display.size.width;
    final ballCenterX = position.dx + _ballWindowSize.width / 2;
    final ballCenterY = position.dy + _ballWindowSize.height / 2;
    final visibleY = display.visiblePosition?.dy ?? 0;
    final visibleHeight = display.visibleSize?.height ?? display.size.height;

    int newX = position.dx;
    int newY = position.dy;

    // Horizontal snap
    if (ballCenterX - visibleX < _snapThreshold) {
      newX = visibleX;
    } else if (visibleX + visibleWidth - ballCenterX < _snapThreshold) {
      newX = (visibleX + visibleWidth - _ballWindowSize.width).toInt();
    }

    // Vertical snap — only snap to top edge
    if (ballCenterY - visibleY < _snapThreshold + 10) {
      newY = visibleY;
    }

    if (newX != position.dx || newY != position.dy) {
      await windowManager.setPosition(
        Offset(newX.toDouble(), newY.toDouble()),
      );
      if (mounted) setState(() => _isSnapped = true);
    } else {
      if (mounted) setState(() => _isSnapped = false);
    }
  }

  // ── Quick menu ──────────────────────────────────────────────────────

  Future<void> _openQuickMenu() async {
    if (_showQuickMenu || _coveredByMain) return;
    // Stop breathing while menu is shown.
    _breatheController.stop();
    final position = await windowManager.getPosition();
    // Expand window so menu items have room; keep ball visually in place.
    await windowManager.setSize(_menuWindowSize);
    final newX = position.dx - _ballOffsetInMenu.dx;
    final newY = position.dy - _ballOffsetInMenu.dy;
    await windowManager.setPosition(Offset(newX, newY));
    if (mounted) setState(() => _showQuickMenu = true);
  }

  Future<void> _closeQuickMenu() async {
    if (!_showQuickMenu) return;
    final position = await windowManager.getPosition();
    if (mounted) setState(() => _showQuickMenu = false);
    // Restore ball size and screen position.
    await windowManager.setSize(_ballWindowSize);
    final restoredX = position.dx + _ballOffsetInMenu.dx;
    final restoredY = position.dy + _ballOffsetInMenu.dy;
    await windowManager.setPosition(Offset(restoredX, restoredY));
    _startBreathing();
  }

  void _handleMenuAction(BallMenuAction action) {
    switch (action) {
      case BallMenuAction.newTodo:
        unawaited(_openMainWindow());
      case BallMenuAction.openMain:
        unawaited(_openMainWindow());
      case BallMenuAction.searchWeb:
        // Placeholder — will open default browser
        break;
      case BallMenuAction.settings:
        unawaited(_openMainWindow());
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final gradientColors = _ballGradientColors(
      hasOverdueTodos: _hasOverdueTodos,
      coveredByMain: _coveredByMain,
    );
    final borderColor = _hasOverdueTodos
        ? AppColors.ballBorderOverdue
        : _coveredByMain
        ? AppColors.ballBorderCovered
        : AppColors.ballBorderNormal.withValues(alpha: 0.82);

    final ball = _buildBall(gradientColors, borderColor);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Ball area at the bottom of the expanded window (or centered if normal).
          if (_showQuickMenu)
            Positioned(
              left: _ballOffsetInMenu.dx,
              top: _ballOffsetInMenu.dy,
              child: Stack(
                clipBehavior: Clip.none,
                children: [ball, if (_activeTodoCount > 0) _buildBadge()],
              ),
            )
          else
            Center(
              child: DragToMoveArea(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ball,
                    if (_activeTodoCount > 0) _buildBadge(),
                  ],
                ),
              ),
            ),
          // Quick menu overlay
          if (_showQuickMenu)
            BallQuickMenu(
              ballWindowCenter: Offset(
                _ballOffsetInMenu.dx + _ballWindowSize.width / 2,
                _ballOffsetInMenu.dy + _ballWindowSize.height / 2,
              ),
              onAction: _handleMenuAction,
              onDismiss: () => _closeQuickMenu(),
            ),
        ],
      ),
    );
  }

  Widget _buildBall(List<Color> gradientColors, Color borderColor) {
    final shadowAlpha = _isHovered ? 0.28 : 0.18;
    final ballOpacity = _isSnapped ? 0.5 : 1.0;

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_showQuickMenu) {
            unawaited(_closeQuickMenu());
            return;
          }
          unawaited(_openMainWindow());
        },
        onSecondaryTapUp: (_) {
          if (_showQuickMenu) {
            unawaited(_closeQuickMenu());
          } else {
            unawaited(_openQuickMenu());
          }
        },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: ballOpacity,
          child: AnimatedScale(
            scale: _isHovered ? 1.05 : _breatheAnimation.value,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
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
                    color: AppColors.ballShadowColor.withValues(
                      alpha: shadowAlpha,
                    ),
                    blurRadius: _isHovered ? 24 : 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.checklist_rounded,
                color: AppColors.ballIconColor,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge() {
    return Positioned(
      right: -2,
      top: -2,
      child: Container(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Text(
          _activeTodoCount > 99 ? '99+' : '$_activeTodoCount',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  List<Color> _ballGradientColors({
    required bool hasOverdueTodos,
    required bool coveredByMain,
  }) {
    if (hasOverdueTodos) {
      return const [AppColors.ballOverdueStart, AppColors.ballOverdueEnd];
    }
    if (coveredByMain) {
      return const [AppColors.ballCoveredStart, AppColors.ballCoveredEnd];
    }
    return const [AppColors.ballNormalStart, AppColors.ballNormalEnd];
  }
}
