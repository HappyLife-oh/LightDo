import 'app_settings.dart';
import 'todo_item.dart';

class AppSnapshot {
  const AppSnapshot({
    required this.todos,
    required this.settings,
    this.tags = const [],
  });

  factory AppSnapshot.empty() {
    return AppSnapshot(
      todos: const [],
      settings: AppSettings.defaults(),
    );
  }

  final List<TodoItem> todos;
  final AppSettings settings;
  final List<Map<String, dynamic>> tags;

  AppSnapshot copyWith({
    List<TodoItem>? todos,
    AppSettings? settings,
    List<Map<String, dynamic>>? tags,
  }) {
    return AppSnapshot(
      todos: todos ?? this.todos,
      settings: settings ?? this.settings,
      tags: tags ?? this.tags,
    );
  }
}
