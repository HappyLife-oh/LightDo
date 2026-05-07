import 'dart:async';
import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop/floating_ball_app.dart';
import 'desktop/window_arguments.dart';
import 'theme/app_theme.dart';
import 'theme/colors.dart';
import 'models/app_settings.dart';
import 'models/app_snapshot.dart';
import 'models/todo_item.dart';
import 'services/desktop_integration.dart';
import 'services/device_id.dart';
import 'services/lightdo_storage.dart';
import 'services/sync_service.dart';
import 'widgets/qr_scanner_page.dart';
import 'package:qr_flutter/qr_flutter.dart';

Future<void> main([List<String> args = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();
  final launchContext = await _resolveLaunchContext(args);
  await _configureDesktopWindow(launchContext.arguments.role);

  if (launchContext.arguments.role == LightDoWindowRole.floatingBall) {
    runApp(
      FloatingBallApp(ballWindowId: launchContext.controller?.windowId ?? ''),
    );
    _configureBitsdojoWindow(launchContext.arguments.role);
    return;
  }

  runApp(
    LightDoApp(
      desktopIntegration: createDesktopIntegration(
        currentWindowController: launchContext.controller,
        ownerWindowId: launchContext.arguments.mainWindowId,
        enabled: true,
      ),
    ),
  );
  _configureBitsdojoWindow(launchContext.arguments.role);
}

Future<_LaunchContext> _resolveLaunchContext(List<String> args) async {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    return const _LaunchContext(
      controller: null,
      arguments: LightDoWindowArguments(role: LightDoWindowRole.main),
    );
  }

  await windowManager.ensureInitialized();
  if (args.isEmpty) {
    try {
      final controller = await WindowController.fromCurrentEngine();
      return _LaunchContext(
        controller: controller,
        arguments: LightDoWindowArguments.main(),
      );
    } catch (_) {
      return const _LaunchContext(
        controller: null,
        arguments: LightDoWindowArguments(role: LightDoWindowRole.floatingBall),
      );
    }
  }
  try {
    final controller = await WindowController.fromCurrentEngine();
    final encoded = args.length >= 3 ? args[2] : controller.arguments;
    final arguments = LightDoWindowArguments.fromEncoded(encoded);
    return _LaunchContext(controller: controller, arguments: arguments);
  } catch (_) {
    final encoded = args.length >= 3 ? args[2] : '';
    return _LaunchContext(
      controller: null,
      arguments: LightDoWindowArguments.fromEncoded(encoded),
    );
  }
}

Future<void> _configureDesktopWindow(LightDoWindowRole role) async {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    return;
  }

  final floatingBallWindowSize = Platform.isWindows
      ? const Size(76, 78)
      : const Size(76, 76);
  final options = role == LightDoWindowRole.floatingBall
      ? WindowOptions(
          size: floatingBallWindowSize,
          minimumSize: floatingBallWindowSize,
          center: false,
          title: 'LightDo',
          backgroundColor: Colors.transparent,
          alwaysOnTop: true,
          skipTaskbar: true,
          titleBarStyle: TitleBarStyle.hidden,
          windowButtonVisibility: false,
        )
      : const WindowOptions(
          size: Size(420, 720),
          minimumSize: Size(360, 600),
          center: true,
          title: 'LightDo',
          backgroundColor: AppColors.scaffoldBody,
        );
  await windowManager.waitUntilReadyToShow(options, () async {
    if (role == LightDoWindowRole.floatingBall && !Platform.isMacOS) {
      await windowManager.show();
      await windowManager.focus();
    }
  });
}

void _configureBitsdojoWindow(LightDoWindowRole role) {
  if (!(Platform.isMacOS || Platform.isWindows)) {
    return;
  }

  doWhenWindowReady(() {
    final win = appWindow;
    if (role == LightDoWindowRole.floatingBall) {
      final ballSize = Platform.isWindows
          ? const Size(76, 78)
          : const Size(76, 76);
      win.minSize = ballSize;
      win.maxSize = ballSize;
      win.size = ballSize;
      win.show();
      return;
    }

    if (Platform.isMacOS) {
      const editorMinSize = Size(360, 600);
      win.minSize = editorMinSize;
    }
  });
}

class _LaunchContext {
  const _LaunchContext({required this.controller, required this.arguments});

  final WindowController? controller;
  final LightDoWindowArguments arguments;
}

class LightDoApp extends StatelessWidget {
  const LightDoApp({super.key, this.storage, this.desktopIntegration});

  final LightDoStorage? storage;
  final DesktopIntegration? desktopIntegration;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LightDo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: LightDoHomePage(
        storage: storage ?? const FileLightDoStorage(),
        desktopIntegration: desktopIntegration ?? createDesktopIntegration(),
      ),
    );
  }
}

class LightDoHomePage extends StatefulWidget {
  const LightDoHomePage({
    super.key,
    required this.storage,
    required this.desktopIntegration,
  });

  final LightDoStorage storage;
  final DesktopIntegration desktopIntegration;

  @override
  State<LightDoHomePage> createState() => _LightDoHomePageState();
}

enum _ActiveTodoOrderGroup { overdue, dueSoon, upcoming, noDeadline }

class _LightDoHomePageState extends State<LightDoHomePage> {
  final TextEditingController _inputController = TextEditingController();

  List<TodoItem> _todos = const [];
  AppSettings _settings = AppSettings.defaults();
  DateTime? _composerDueAt;
  TodoRecurrence _composerRecurrence = TodoRecurrence.none;
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _saveTimer;
  bool _desktopInitialized = false;
  late SyncService _syncService = SyncService(nodeId: 'test');
  StreamSubscription<List<TodoItem>>? _syncSub;

  @override
  void initState() {
    super.initState();
    unawaited(_initAll());
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _syncSub?.cancel();
    _syncService.dispose();
    _inputController.dispose();
    unawaited(widget.desktopIntegration.dispose());
    super.dispose();
  }

  Future<void> _initAll() async {
    // 1. 初始化 SyncService
    final nodeId = await DeviceIdService().getOrCreate();
    _syncService = SyncService(nodeId: nodeId);

    // 2. 加载本地快照
    AppSnapshot snapshot;
    try {
      snapshot = await widget.storage.load();
    } catch (_) {
      snapshot = AppSnapshot.empty();
    }

    // 3. 加载 CRDT 状态，若为空则用现有 todos 初始化
    if (widget.storage is FileLightDoStorage) {
      final records =
          await (widget.storage as FileLightDoStorage).loadCrdtRecords();
      if (records.isEmpty) {
        _syncService.initEmpty();
        for (final todo in snapshot.todos) {
          _syncService.recordMutation(todo);
        }
      } else {
        _syncService.initFromRecords(records);
      }
    } else {
      _syncService.initEmpty();
    }

    // 4. 监听同步更新（所有平台）
    _syncSub = _syncService.todosStream.listen((mergedTodos) {
      if (!mounted) return;
      setState(() {
        _todos = mergedTodos;
      });
      _scheduleSave();
    });

    if (!mounted) return;
    setState(() {
      _todos = snapshot.todos;
      _settings = snapshot.settings.copyWith(expandCompletedByDefault: false);
      _isLoading = false;
    });
    unawaited(_initializeDesktopIntegration());
  }

  Future<void> _initializeDesktopIntegration() async {
    if (_desktopInitialized) {
      return;
    }
    try {
      await widget.desktopIntegration.initialize(_settings);
      _desktopInitialized = true;
    } catch (_) {
      if (!mounted) {
        return;
      }
      if (!Platform.isMacOS) {
        setState(() {
          _errorMessage = '桌面能力初始化失败，核心待办功能仍可使用。';
        });
      }
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 240), () async {
      try {
        await widget.storage.save(
          AppSnapshot(todos: _todos, settings: _settings),
        );
        if (widget.storage is FileLightDoStorage) {
          await (widget.storage as FileLightDoStorage)
              .saveCrdtRecords(_syncService.exportRecords());
        }
        if (!mounted || _errorMessage == null) {
          return;
        }
        setState(() {
          _errorMessage = null;
        });
      } catch (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _errorMessage = '本地数据保存失败，请检查目录权限。';
        });
      }
    });
  }

  void _addTodo() {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      return;
    }
    final nextTodo = TodoItem.create(
      title: text,
      nodeId: _syncService.nodeId,
      dueAt: _composerDueAt,
      recurrence: _composerRecurrence,
    );
    _syncService.recordMutation(nextTodo);
    _syncService.notifyPeers();
    setState(() {
      _todos = [nextTodo, ..._todos];
      _inputController.clear();
      _composerDueAt = null;
      _composerRecurrence = TodoRecurrence.none;
    });
    _scheduleSave();
  }

  void _toggleTodo(String id, bool selected) {
    TodoItem? targetTodo;
    for (final todo in _todos) {
      if (todo.id == id) {
        targetTodo = todo;
        break;
      }
    }
    if (targetTodo == null) return;

    final nextRecurringTodo = selected && !targetTodo.isCompleted
        ? targetTodo.createNextRecurringInstance()
        : null;

    setState(() {
      final updatedTodos = _todos
          .map((todo) =>
              todo.id == id ? todo.copyWith(isCompleted: selected) : todo)
          .toList(growable: true);

      if (nextRecurringTodo != null &&
          !_containsRecurringInstance(updatedTodos, nextRecurringTodo)) {
        updatedTodos.insert(0, nextRecurringTodo);
        _syncService.recordMutation(nextRecurringTodo);
      }

      for (final t in updatedTodos) {
        if (t.id == id) _syncService.recordMutation(t);
      }
      _syncService.notifyPeers();

      _todos = updatedTodos;
    });
    _scheduleSave();
  }

  Future<void> _editTodo(TodoItem todo) async {
    final result = await showDialog<_TodoEditorResult>(
      context: context,
      builder: (context) => _TodoEditorDialog(todo: todo),
    );
    final trimmed = result?.title.trim() ?? '';
    if (trimmed.isEmpty) {
      return;
    }

    final noTitleChange = trimmed == todo.title;
    final noDueChange =
        (result?.dueAt == null && todo.dueAt == null) ||
        (result?.dueAt != null &&
            todo.dueAt != null &&
            result!.dueAt!.isAtSameMomentAs(todo.dueAt!));
    final noRecurrenceChange =
        (result?.recurrence ?? todo.recurrence) == todo.recurrence;

    if (noTitleChange && noDueChange && noRecurrenceChange) {
      return;
    }

    setState(() {
      _todos = _todos
          .map(
            (item) => item.id == todo.id
                ? item.copyWith(
                    title: trimmed,
                    dueAt: result?.dueAt,
                    recurrence: result?.recurrence,
                  )
                : item,
          )
          .toList(growable: false);
    });
    final updated = _todos.firstWhere((t) => t.id == todo.id);
    _syncService.recordMutation(updated);
    _syncService.notifyPeers();
    _scheduleSave();
  }

  Future<void> _openComposerScheduleDialog() async {
    final result = await showDialog<_TodoScheduleDraft>(
      context: context,
      builder: (context) => _TodoScheduleDialog(
        title: '设置截止时间',
        initialDueAt: _composerDueAt,
        initialRecurrence: _composerRecurrence,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _composerDueAt = result.dueAt;
      _composerRecurrence = result.recurrence;
    });
  }

  void _clearComposerSchedule() {
    setState(() {
      _composerDueAt = null;
      _composerRecurrence = TodoRecurrence.none;
    });
  }

  void _deleteTodo(String id) {
    _syncService.recordDeletion(id);
    _syncService.notifyPeers();
    setState(() {
      _todos = _todos
          .map((t) => t.id == id ? t.copyWith(isDeleted: true) : t)
          .toList(growable: false);
    });
    _scheduleSave();
  }

  Future<void> _clearCompleted() async {
    if (_settings.confirmBeforeClearingCompleted) {
      final shouldClear =
          await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('清空已完成任务'),
                content: const Text('该操作只会删除已完成项，且无法恢复。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('清空'),
                  ),
                ],
              );
            },
          ) ??
          false;
      if (!shouldClear) return;
    }

    final completedIds =
        _todos.where((t) => t.isCompleted).map((t) => t.id).toList();
    for (final id in completedIds) {
      _syncService.recordDeletion(id);
    }
    _syncService.notifyPeers();
    setState(() {
      _todos = _todos
          .map((t) => t.isCompleted ? t.copyWith(isDeleted: true) : t)
          .toList(growable: false);
    });
    _scheduleSave();
  }

  void _updateSettings(AppSettings nextSettings) {
    setState(() {
      _settings = nextSettings;
    });
    unawaited(_applyDesktopSettings(nextSettings));
    _scheduleSave();
  }

  Future<void> _applyDesktopSettings(AppSettings nextSettings) async {
    try {
      await widget.desktopIntegration.applySettings(nextSettings);
    } catch (_) {
      if (!mounted) {
        return;
      }
      if (!Platform.isMacOS) {
        setState(() {
          _errorMessage = '桌面设置应用失败，已保留当前任务数据。';
        });
      }
    }
  }

  List<TodoItem> get _activeTodos {
    final now = DateTime.now();
    final active = _todos
        .where((todo) => !todo.isCompleted && !todo.isDeleted)
        .toList(growable: true);
    active.sort((a, b) => _compareActiveTodoOrder(a, b, now));
    return active;
  }

  List<TodoItem> get _completedTodos => _todos
      .where((todo) => todo.isCompleted && !todo.isDeleted)
      .toList(growable: false);

  int _compareActiveTodoOrder(TodoItem a, TodoItem b, DateTime now) {
    final aGroup = _activeTodoOrderGroup(a, now);
    final bGroup = _activeTodoOrderGroup(b, now);
    final byGroup = aGroup.index.compareTo(bGroup.index);
    if (byGroup != 0) {
      return byGroup;
    }

    final aDue = a.dueAt;
    final bDue = b.dueAt;
    if (aDue != null && bDue != null) {
      final byDue = aDue.compareTo(bDue);
      if (byDue != 0) {
        return byDue;
      }
    }

    final byUpdate = b.updatedAt.compareTo(a.updatedAt);
    if (byUpdate != 0) {
      return byUpdate;
    }
    return a.id.compareTo(b.id);
  }

  _ActiveTodoOrderGroup _activeTodoOrderGroup(TodoItem todo, DateTime now) {
    switch (todo.deadlineStateAt(now)) {
      case TodoDeadlineState.overdue:
        return _ActiveTodoOrderGroup.overdue;
      case TodoDeadlineState.dueSoon:
        return _ActiveTodoOrderGroup.dueSoon;
      case TodoDeadlineState.normal:
        return todo.dueAt == null
            ? _ActiveTodoOrderGroup.noDeadline
            : _ActiveTodoOrderGroup.upcoming;
    }
  }

  bool _containsRecurringInstance(List<TodoItem> todos, TodoItem candidate) {
    return todos.any((todo) {
      final sameSeries =
          todo.seriesId != null && todo.seriesId == candidate.seriesId;
      final sameDueAt =
          todo.dueAt != null &&
          candidate.dueAt != null &&
          todo.dueAt!.isAtSameMomentAs(candidate.dueAt!);
      return sameSeries && sameDueAt;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeTodos = _activeTodos;
    final completedTodos = _completedTodos;
    final completedRate = _todos.isEmpty
        ? 0
        : ((completedTodos.length / _todos.length) * 100).round();

    return Scaffold(
      backgroundColor: AppColors.scaffoldBody,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DragToMoveArea(
                          child: _HeaderSection(
                            totalCount: _todos.length,
                            activeCount: activeTodos.length,
                            completedCount: completedTodos.length,
                            completedRate: completedRate,
                            showWindowsBadge:
                                Platform.isWindows || Platform.isMacOS,
                            onOpenSettings: () => _openSettingsSheet(context),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _ComposerCard(
                          controller: _inputController,
                          onSubmit: _addTodo,
                          onOpenSchedule: _openComposerScheduleDialog,
                          onClearSchedule: _clearComposerSchedule,
                          scheduleSummary: _composerDueAt == null
                              ? null
                              : [
                                  formatShortDateTime(_composerDueAt!),
                                  if (_composerRecurrence !=
                                      TodoRecurrence.none)
                                    _composerRecurrence.label,
                                ].join(' · '),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          _InlineNotice(message: _errorMessage!),
                        ],
                        const SizedBox(height: 14),
                        Expanded(
                          child: _TaskPanel(
                            title: '待办',
                            subtitle: activeTodos.isEmpty
                                ? '还没有进行中的任务'
                                : '${activeTodos.length} 项进行中',
                            child: Column(
                              children: [
                                Expanded(
                                  child: activeTodos.isEmpty
                                      ? const _EmptyState()
                                      : ListView.builder(
                                          padding: EdgeInsets.zero,
                                          itemCount: activeTodos.length,
                                          itemBuilder: (context, index) {
                                            final todo = activeTodos[index];
                                            return Padding(
                                              key: ValueKey(todo.id),
                                              padding: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              child: _TodoCard(
                                                todo: todo,
                                                compact: _settings.compactMode,
                                                onToggle: (selected) =>
                                                    _toggleTodo(
                                                      todo.id,
                                                      selected,
                                                    ),
                                                onEdit: () => _editTodo(todo),
                                                onDelete: () =>
                                                    _deleteTodo(todo.id),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                                const SizedBox(height: 16),
                                _CompletedPanel(
                                  completedTodos: completedTodos,
                                  expanded: _settings.expandCompletedByDefault,
                                  compact: _settings.compactMode,
                                  onToggleExpanded: (value) => _updateSettings(
                                    _settings.copyWith(
                                      expandCompletedByDefault: value,
                                    ),
                                  ),
                                  onClearCompleted: completedTodos.isEmpty
                                      ? null
                                      : _clearCompleted,
                                  onToggleTodo: (todo, selected) =>
                                      _toggleTodo(todo.id, selected),
                                  onEditTodo: _editTodo,
                                  onDeleteTodo: (todo) => _deleteTodo(todo.id),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSettingsSheet(BuildContext context) async {
    final nextSettings = await showDialog<AppSettings>(
      context: context,
      builder: (context) =>
          _SettingsDialog(settings: _settings, syncService: _syncService),
    );
    if (nextSettings == null) return;
    _updateSettings(nextSettings);

    // Android: open scanner if sync just enabled
    if (nextSettings.syncEnabled &&
        !_settings.syncEnabled &&
        Platform.isAndroid) {
      if (!mounted) return;
      final ctx = context;
      // ignore: use_build_context_synchronously
      await Navigator.of(ctx).push<bool>(
        MaterialPageRoute(
          builder: (_) => QrScannerPage(syncService: _syncService),
        ),
      );
    }
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({
    required this.totalCount,
    required this.activeCount,
    required this.completedCount,
    required this.completedRate,
    required this.showWindowsBadge,
    required this.onOpenSettings,
  });

  final int totalCount;
  final int activeCount;
  final int completedCount;
  final int completedRate;
  final bool showWindowsBadge;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LightDo',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '总计 $totalCount 项，进行中 $activeCount 项，已完成 $completedCount 项，完成率 $completedRate%',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textBody,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
          tooltip: '设置',
          color: AppColors.textSettingsIcon,
        ),
        if (showWindowsBadge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.badgeBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Desktop',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.badgeText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

class _ComposerCard extends StatelessWidget {
  const _ComposerCard({
    required this.controller,
    required this.onSubmit,
    required this.onOpenSchedule,
    required this.onClearSchedule,
    required this.scheduleSummary,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onOpenSchedule;
  final VoidCallback onClearSchedule;
  final String? scheduleSummary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.composerDivider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(Icons.add_rounded, color: AppColors.composerIcon),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  onSubmitted: (_) => onSubmit(),
                  decoration: const InputDecoration(
                    hintText: '添加待办，按回车确认',
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              IconButton(
                onPressed: onOpenSchedule,
                icon: Icon(
                  scheduleSummary == null
                      ? Icons.event_outlined
                      : Icons.event_available_rounded,
                ),
                tooltip: '设置截止时间',
                color: scheduleSummary == null
                    ? AppColors.composerIcon
                    : AppColors.composerIconActive,
              ),
              TextButton(onPressed: onSubmit, child: const Text('添加')),
            ],
          ),
          if (scheduleSummary != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.chipBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    scheduleSummary!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.chipText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onClearSchedule,
                  child: const Text('清除时间'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskPanel extends StatelessWidget {
  const _TaskPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.textBodyAlt),
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _CompletedPanel extends StatefulWidget {
  const _CompletedPanel({
    required this.completedTodos,
    required this.expanded,
    required this.compact,
    required this.onToggleExpanded,
    required this.onClearCompleted,
    required this.onToggleTodo,
    required this.onEditTodo,
    required this.onDeleteTodo,
  });

  final List<TodoItem> completedTodos;
  final bool expanded;
  final bool compact;
  final ValueChanged<bool> onToggleExpanded;
  final Future<void> Function(TodoItem todo) onEditTodo;
  final Future<void> Function()? onClearCompleted;
  final void Function(TodoItem todo, bool selected) onToggleTodo;
  final void Function(TodoItem todo) onDeleteTodo;

  @override
  State<_CompletedPanel> createState() => _CompletedPanelState();
}

class _CompletedPanelState extends State<_CompletedPanel> {
  late final ScrollController _completedScrollController = ScrollController();

  @override
  void dispose() {
    _completedScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final completedToday = _completedToday(widget.completedTodos);

    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.sectionBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '已完成',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const AppColors.completedTitle,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.completedTodos.length} 项',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const AppColors.completedCount,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => widget.onToggleExpanded(!widget.expanded),
                icon: Icon(
                  widget.expanded
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                ),
                tooltip: widget.expanded ? '折叠' : '展开',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.expanded) ...[
            if (widget.completedTodos.isEmpty)
              const _MiniEmptyState(message: '已完成任务会收纳在这里。')
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: widget.compact ? 140 : 180,
                ),
                child: Scrollbar(
                  controller: _completedScrollController,
                  thumbVisibility: true,
                  child: ListView.separated(
                    controller: _completedScrollController,
                    shrinkWrap: true,
                    itemCount: widget.completedTodos.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final todo = widget.completedTodos[index];
                      return _TodoCard(
                        todo: todo,
                        compact: widget.compact,
                        onToggle: (selected) =>
                            widget.onToggleTodo(todo, selected),
                        onEdit: () => widget.onEditTodo(todo),
                        onDelete: () => widget.onDeleteTodo(todo),
                      );
                    },
                  ),
                ),
              ),
          ] else
            _CompletedPreviewStrip(completedToday: completedToday),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: widget.onClearCompleted,
            icon: const Icon(Icons.delete_sweep_rounded),
            label: const Text('清空已完成'),
          ),
        ],
      ),
    );
  }

  List<TodoItem> _completedToday(List<TodoItem> todos) {
    final now = DateTime.now();
    return todos
        .where((todo) => _isSameDay(todo.updatedAt, now))
        .toList(growable: false);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _CompletedPreviewStrip extends StatelessWidget {
  const _CompletedPreviewStrip({required this.completedToday});

  final List<TodoItem> completedToday;

  @override
  Widget build(BuildContext context) {
    if (completedToday.isEmpty) {
      return const _MiniEmptyState(message: '已折叠，今天还没有新完成项。');
    }

    final visibleTodos = completedToday.take(8).toList(growable: false);
    final overflow = completedToday.length - visibleTodos.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今天已完成 ${completedToday.length} 项',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final todo in visibleTodos) ...[
                  Tooltip(
                    message: todo.title,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const AppColors.previewCheckBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: const AppColors.previewCheckBorder),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: AppColors.emptyIcon,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (overflow > 0)
                  Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const AppColors.previewOverflowBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '+$overflow',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.composerIcon,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodoCard extends StatelessWidget {
  const _TodoCard({
    super.key,
    required this.todo,
    required this.compact,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final TodoItem todo;
  final bool compact;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final deadlineState = todo.deadlineStateAt(now);
    final deadlineBadge = todo.deadlineBadgeLabelAt(now);
    final visualState = todo.isCompleted
        ? TodoDeadlineState.normal
        : deadlineState;
    final cardBackground = switch (visualState) {
      TodoDeadlineState.overdue => const AppColors.cardOverdueBg,
      TodoDeadlineState.dueSoon => const AppColors.cardDueSoonBg,
      TodoDeadlineState.normal => Colors.transparent,
    };
    final cardBorder = switch (visualState) {
      TodoDeadlineState.overdue => const AppColors.cardOverdueBorder,
      TodoDeadlineState.dueSoon => const AppColors.cardDueSoonBorder,
      TodoDeadlineState.normal => AppColors.sectionBorder,
    };
    final badgeBackground = switch (visualState) {
      TodoDeadlineState.overdue => const AppColors.cardOverdueBadgeBg,
      TodoDeadlineState.dueSoon => const AppColors.cardDueSoonBadgeBg,
      TodoDeadlineState.normal => Colors.transparent,
    };
    final badgeForeground = switch (visualState) {
      TodoDeadlineState.overdue => const AppColors.cardOverdueBadgeText,
      TodoDeadlineState.dueSoon => const AppColors.cardDueSoonBadgeText,
      TodoDeadlineState.normal => const AppColors.cardNormalSummary,
    };
    final summaryColor = switch (visualState) {
      TodoDeadlineState.overdue => const AppColors.cardOverdueSummary,
      TodoDeadlineState.dueSoon => const AppColors.cardDueSoonSummary,
      TodoDeadlineState.normal => const AppColors.cardNormalSummary,
    };
    final summary = todo.summary;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.25,
      color: todo.isCompleted
          ? const AppColors.cardCompletedTitle
          : visualState == TodoDeadlineState.overdue
          ? const AppColors.cardOverdueTitle
          : visualState == TodoDeadlineState.dueSoon
          ? const AppColors.cardDueSoonTitle
          : const AppColors.cardNormalTitle,
      decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
    );

    return Container(
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder, width: 1.2),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      child: Row(
        children: [
          Checkbox(
            value: todo.isCompleted,
            onChanged: (value) => onToggle(value ?? false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(todo.title, style: titleStyle)),
                    if (deadlineBadge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: badgeBackground,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          deadlineBadge,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: badgeForeground,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    summary,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: summaryColor),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: '编辑',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: '删除',
          ),
        ],
      ),
    );
  }
}

class _TodoScheduleDraft {
  const _TodoScheduleDraft({required this.dueAt, required this.recurrence});

  final DateTime? dueAt;
  final TodoRecurrence recurrence;
}

class _TodoEditorResult extends _TodoScheduleDraft {
  const _TodoEditorResult({
    required this.title,
    required super.dueAt,
    required super.recurrence,
  });

  final String title;
}

class _TodoScheduleDialog extends StatefulWidget {
  const _TodoScheduleDialog({
    required this.title,
    required this.initialDueAt,
    required this.initialRecurrence,
  });

  final String title;
  final DateTime? initialDueAt;
  final TodoRecurrence initialRecurrence;

  @override
  State<_TodoScheduleDialog> createState() => _TodoScheduleDialogState();
}

class _TodoScheduleDialogState extends State<_TodoScheduleDialog> {
  static const int _defaultDueHour = 12;
  static const int _defaultDueMinute = 0;
  late DateTime _draftDate = widget.initialDueAt ?? _defaultDueAt();
  late int _draftHour = (widget.initialDueAt ?? _draftDate).hour;
  late int _draftMinute = (widget.initialDueAt ?? _draftDate).minute;
  late bool _scheduleEnabled = widget.initialDueAt != null;
  late TodoRecurrence _draftRecurrence = widget.initialDueAt == null
      ? TodoRecurrence.none
      : widget.initialRecurrence;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                !_scheduleEnabled
                    ? '未设置截止时间'
                    : '截止 ${formatShortDateTime(_composeDraftDueAt())}',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用截止时间'),
                subtitle: const Text('在当前页面直接设置日期和时间'),
                value: _scheduleEnabled,
                onChanged: (enabled) {
                  setState(() {
                    _scheduleEnabled = enabled;
                    if (!enabled) {
                      _draftRecurrence = TodoRecurrence.none;
                    }
                  });
                },
              ),
              if (_scheduleEnabled) ...[
                const SizedBox(height: 8),
                Semantics(
                  button: true,
                  label: '截止日期选择器',
                  hint: '点击打开日历选择截止日期',
                  onTapHint: '点击打开日历',
                  value: _formatSemanticDate(context, _draftDate),
                  child: InkWell(
                    onTap: _pickDraftDate,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: '截止日期',
                        border: OutlineInputBorder(),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _formatDateOnly(_draftDate),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _draftHour,
                        decoration: const InputDecoration(
                          labelText: '小时',
                          border: OutlineInputBorder(),
                        ),
                        items: List.generate(
                          24,
                          (index) => DropdownMenuItem(
                            value: index,
                            child: Text(index.toString().padLeft(2, '0')),
                          ),
                        ),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _draftHour = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _draftMinute,
                        decoration: const InputDecoration(
                          labelText: '分钟',
                          border: OutlineInputBorder(),
                        ),
                        items: List.generate(
                          60,
                          (index) => DropdownMenuItem(
                            value: index,
                            child: Text(index.toString().padLeft(2, '0')),
                          ),
                        ),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _draftMinute = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              DropdownButtonFormField<TodoRecurrence>(
                key: ValueKey(_draftRecurrence),
                initialValue: _draftRecurrence,
                decoration: const InputDecoration(
                  labelText: '定时任务',
                  border: OutlineInputBorder(),
                ),
                items: TodoRecurrence.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: !_scheduleEnabled
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _draftRecurrence = value;
                        });
                      },
              ),
              const SizedBox(height: 8),
              Text(
                !_scheduleEnabled
                    ? '先设置截止时间后才能启用重复任务。'
                    : '支持精确到分钟，并可按每天、每周、每月重复。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const AppColors.emptyText),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _TodoScheduleDraft(
                dueAt: _scheduleEnabled ? _composeDraftDueAt() : null,
                recurrence: !_scheduleEnabled
                    ? TodoRecurrence.none
                    : _draftRecurrence,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _updateDraftDate(DateTime value) {
    setState(() {
      _draftDate = DateTime(
        value.year,
        value.month,
        value.day,
        _draftHour,
        _draftMinute,
      );
    });
  }

  Future<void> _pickDraftDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _draftDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: '选择截止日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (selected == null || !mounted) {
      return;
    }
    _updateDraftDate(selected);
  }

  DateTime _composeDraftDueAt() {
    return DateTime(
      _draftDate.year,
      _draftDate.month,
      _draftDate.day,
      _draftHour,
      _draftMinute,
    );
  }

  String _formatDateOnly(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatSemanticDate(BuildContext context, DateTime value) {
    return MaterialLocalizations.of(context).formatCompactDate(value);
  }

  static DateTime _defaultDueAt() {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
      _defaultDueHour,
      _defaultDueMinute,
    );
  }

}

class _TodoEditorDialog extends StatefulWidget {
  const _TodoEditorDialog({required this.todo});

  final TodoItem todo;

  @override
  State<_TodoEditorDialog> createState() => _TodoEditorDialogState();
}

class _TodoEditorDialogState extends State<_TodoEditorDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.todo.title,
  );
  late DateTime? _draftDueAt = widget.todo.dueAt;
  late TodoRecurrence _draftRecurrence = widget.todo.recurrence;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑任务'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '任务内容',
                hintText: '输入新的任务描述',
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _openScheduleDialog,
              icon: const Icon(Icons.event_note_rounded),
              label: Text(
                _draftDueAt == null
                    ? '设置截止时间'
                    : '截止 ${formatShortDateTime(_draftDueAt!)}',
              ),
            ),
            if (_draftDueAt != null) ...[
              const SizedBox(height: 8),
              Text(
                _draftRecurrence == TodoRecurrence.none
                    ? '当前任务不重复'
                    : '当前任务按 ${_draftRecurrence.label} 重复',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const AppColors.emptyText),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }

  Future<void> _openScheduleDialog() async {
    final result = await showDialog<_TodoScheduleDraft>(
      context: context,
      builder: (context) => _TodoScheduleDialog(
        title: '编辑任务时间',
        initialDueAt: _draftDueAt,
        initialRecurrence: _draftRecurrence,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _draftDueAt = result.dueAt;
      _draftRecurrence = result.recurrence;
    });
  }

  void _submit() {
    Navigator.of(context).pop(
      _TodoEditorResult(
        title: _controller.text.trim(),
        dueAt: _draftDueAt,
        recurrence: _draftRecurrence,
      ),
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.settings, required this.syncService});

  final AppSettings settings;
  final SyncService syncService;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late AppSettings _draft = widget.settings;
  SyncServerInfo? _serverInfo;
  bool _isStartingServer = false;

  bool get _showDesktopSection => Platform.isWindows || Platform.isMacOS;
  bool get _showQr =>
      _draft.syncEnabled &&
      (_showDesktopSection || Platform.isLinux) &&
      (_serverInfo != null || _isStartingServer);

  @override
  void initState() {
    super.initState();
    if (_draft.syncEnabled) {
      _serverInfo = widget.syncService.serverInfo;
      if (_serverInfo == null) unawaited(_startServer());
    }
  }

  Future<void> _startServer() async {
    setState(() => _isStartingServer = true);
    try {
      final info = await widget.syncService.startServer();
      if (mounted) setState(() { _serverInfo = info; });
    } finally {
      if (mounted) setState(() => _isStartingServer = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrData = _serverInfo == null
        ? null
        : 'ws://${_serverInfo!.ip}:${_serverInfo!.port}/sync?token=${_serverInfo!.token}';

    return AlertDialog(
      title: const Text('设置'),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: _showQr ? 600 : 340),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_showDesktopSection) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _draft.minimizeToTrayOnClose,
                    title: const Text('关闭时回到悬浮球'),
                    subtitle: const Text('关闭主界面后收起到桌面小球。'),
                    onChanged: (value) {
                      setState(() {
                        _draft = _draft.copyWith(minimizeToTrayOnClose: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _draft.enableGlobalHotkey,
                    title: const Text('启用全局快捷键 Alt+Shift+T'),
                    subtitle: const Text('快速显示主界面。'),
                    onChanged: (value) {
                      setState(() {
                        _draft = _draft.copyWith(enableGlobalHotkey: value);
                      });
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _draft.alwaysOnTop,
                    title: const Text('主界面置顶'),
                    subtitle: const Text('展开后保持在其他窗口前面。'),
                    onChanged: (value) {
                      setState(() {
                        _draft = _draft.copyWith(alwaysOnTop: value);
                      });
                    },
                  ),
                  if (Platform.isWindows)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _draft.launchAtStartup,
                      title: const Text('开机自启'),
                      subtitle: const Text('登录系统后自动启动 LightDo。'),
                      onChanged: (value) {
                        setState(() {
                          _draft = _draft.copyWith(launchAtStartup: value);
                        });
                      },
                    ),
                ],
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _draft.syncEnabled,
                  title: const Text('局域网同步'),
                  subtitle: const Text('通过局域网与其他设备双向同步待办。'),
                  onChanged: (value) {
                    setState(() {
                      _draft = _draft.copyWith(syncEnabled: value);
                    });
                    if (value) {
                      unawaited(_startServer());
                    } else {
                      unawaited(widget.syncService.stopServer());
                      setState(() { _serverInfo = null; });
                    }
                  },
                ),
                if (_draft.syncEnabled && Platform.isAndroid) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) =>
                                QrScannerPage(syncService: widget.syncService),
                          ),
                        );
                      },
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('扫描同步码'),
                    ),
                  ),
                  if (widget.syncService.isClientConnected)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '已连接到电脑',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const AppColors.emptyIcon,
                        ),
                      ),
                    ),
                ],
                if (_showQr) ...[
                  const SizedBox(height: 8),
                  if (_isStartingServer)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    )
                  else
                    Column(
                      children: [
                        QrImageView(data: qrData!, size: 200),
                        const SizedBox(height: 8),
                        Text(
                          '用 Android 端扫描二维码完成同步',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        StreamBuilder<int>(
                          stream: Stream.periodic(
                            const Duration(seconds: 2),
                            (_) => widget.syncService.connectedClientCount,
                          ),
                          initialData: widget.syncService.connectedClientCount,
                          builder: (context, snap) {
                            final count = snap.data ?? 0;
                            return Text(
                              count == 0 ? '等待设备连接…' : '已连接 $count 台设备',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: count == 0
                                    ? const AppColors.syncWaiting
                                    : const AppColors.emptyIcon,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_draft),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const AppColors.errorBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const AppColors.errorBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.errorIcon),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.checklist_rounded,
                  size: 32,
                  color: AppColors.emptyIcon,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '现在没有进行中的任务',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '从上方输入框添加第一条任务。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const AppColors.emptyText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniEmptyState extends StatelessWidget {
  const _MiniEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: const AppColors.textMuted),
      ),
    );
  }
}
