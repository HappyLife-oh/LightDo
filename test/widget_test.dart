import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightdo/main.dart';
import 'package:lightdo/models/app_settings.dart';
import 'package:lightdo/models/app_snapshot.dart';
import 'package:lightdo/services/desktop_integration.dart';
import 'package:lightdo/models/todo_item.dart';
import 'package:lightdo/services/lightdo_storage.dart';

void main() {
  testWidgets('renders existing todo item', (tester) async {
    final snapshot = AppSnapshot(
      todos: [TodoItem.create(title: '整理 Flutter 需求')],
      settings: AppSettings.defaults(),
    );

    await tester.pumpWidget(
      LightDoApp(
        storage: MemoryLightDoStorage(snapshot),
        desktopIntegration: NoopDesktopIntegration(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LightDo'), findsOneWidget);
    expect(find.text('整理 Flutter 需求'), findsOneWidget);
  });

  testWidgets('adds todo item from input', (tester) async {
    await tester.pumpWidget(
      LightDoApp(
        storage: MemoryLightDoStorage(),
        desktopIntegration: NoopDesktopIntegration(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '补齐 Flutter 页面');
    await tester.tap(find.widgetWithText(TextButton, '添加'));
    await tester.pumpAndSettle();

    expect(find.text('补齐 Flutter 页面'), findsOneWidget);
  });

  testWidgets('completing recurring todo creates next occurrence', (
    tester,
  ) async {
    final recurringTodo = TodoItem.create(
      title: '写周报',
      dueAt: DateTime(2026, 4, 10, 18, 0),
      recurrence: TodoRecurrence.weekly,
    );

    await tester.pumpWidget(
      LightDoApp(
        storage: MemoryLightDoStorage(
          AppSnapshot(
            todos: [recurringTodo],
            settings: AppSettings.defaults().copyWith(
              expandCompletedByDefault: true,
            ),
          ),
        ),
        desktopIntegration: NoopDesktopIntegration(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.text('写周报'), findsOneWidget);
    expect(find.text('今天已完成 1 项'), findsOneWidget);
  });

  testWidgets('renders overdue badge for expired todo', (tester) async {
    final expiredTodo = TodoItem.create(
      title: '提交报销',
      dueAt: DateTime.now().subtract(const Duration(hours: 1)),
    );

    await tester.pumpWidget(
      LightDoApp(
        storage: MemoryLightDoStorage(
          AppSnapshot(todos: [expiredTodo], settings: AppSettings.defaults()),
        ),
        desktopIntegration: NoopDesktopIntegration(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已过期'), findsOneWidget);
  });

  testWidgets('shows collapsed completed preview for today items', (
    tester,
  ) async {
    final completedA = TodoItem.create(
      title: '整理桌面',
    ).copyWith(isCompleted: true, updatedAt: DateTime.now());
    final completedB = TodoItem.create(
      title: '发送日报',
    ).copyWith(isCompleted: true, updatedAt: DateTime.now());

    await tester.pumpWidget(
      LightDoApp(
        storage: MemoryLightDoStorage(
          AppSnapshot(
            todos: [completedA, completedB],
            settings: AppSettings.defaults(),
          ),
        ),
        desktopIntegration: NoopDesktopIntegration(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今天已完成 2 项'), findsOneWidget);
    expect(find.text('整理桌面'), findsNothing);
    expect(find.text('发送日报'), findsNothing);
  });
}
