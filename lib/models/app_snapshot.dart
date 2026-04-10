import 'app_settings.dart';
import 'todo_item.dart';

class AppSnapshot {
  const AppSnapshot({
    required this.todos,
    required this.settings,
  });

  factory AppSnapshot.empty() {
    return AppSnapshot(
      todos: const [],
      settings: AppSettings.defaults(),
    );
  }

  final List<TodoItem> todos;
  final AppSettings settings;

  AppSnapshot copyWith({
    List<TodoItem>? todos,
    AppSettings? settings,
  }) {
    return AppSnapshot(
      todos: todos ?? this.todos,
      settings: settings ?? this.settings,
    );
  }
}
