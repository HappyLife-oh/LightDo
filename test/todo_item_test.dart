import 'package:flutter_test/flutter_test.dart';
import 'package:lightdo/models/todo_item.dart';

void main() {
  test('creates next recurring item from due date', () {
    final todo = TodoItem.create(
      title: '每周复盘',
      dueAt: DateTime(2026, 4, 10, 9, 30),
      recurrence: TodoRecurrence.weekly,
    );

    final next = todo.createNextRecurringInstance();

    expect(next, isNotNull);
    expect(next!.title, todo.title);
    expect(next.recurrence, TodoRecurrence.weekly);
    expect(next.seriesId, todo.seriesId);
    expect(next.dueAt, DateTime(2026, 4, 17, 9, 30));
    expect(next.isCompleted, isFalse);
  });

  test('flashes reminder only within 30 seconds after due time', () {
    final todo = TodoItem.create(
      title: '发送日报',
      dueAt: DateTime(2026, 4, 10, 18, 0),
    );

    expect(
      todo.shouldFlashReminderAt(DateTime(2026, 4, 10, 17, 59, 59)),
      isFalse,
    );
    expect(
      todo.shouldFlashReminderAt(DateTime(2026, 4, 10, 18, 0, 15)),
      isTrue,
    );
    expect(
      todo.shouldFlashReminderAt(DateTime(2026, 4, 10, 18, 0, 30)),
      isFalse,
    );
  });

  test('marks due soon and overdue states from due time', () {
    final todo = TodoItem.create(
      title: '提交周计划',
      dueAt: DateTime(2026, 4, 10, 18, 0),
    );

    expect(
      todo.deadlineStateAt(DateTime(2026, 4, 9, 17, 59, 59)),
      TodoDeadlineState.normal,
    );
    expect(
      todo.deadlineStateAt(DateTime(2026, 4, 10, 9, 0)),
      TodoDeadlineState.dueSoon,
    );
    expect(
      todo.deadlineStateAt(DateTime(2026, 4, 10, 18, 0, 1)),
      TodoDeadlineState.overdue,
    );
  });

  test('keeps dueAt after json serialization roundtrip', () {
    final dueAt = DateTime(2026, 5, 1, 18, 47);
    final todo = TodoItem.create(
      title: '准备 LLLM-Code 微调数据集',
      dueAt: dueAt,
      recurrence: TodoRecurrence.none,
    );

    final restored = TodoItem.fromJson(todo.toJson());

    expect(restored.dueAt, isNotNull);
    expect(restored.dueAt!.isAtSameMomentAs(dueAt), isTrue);
    expect(restored.recurrence, TodoRecurrence.none);
  });
}
