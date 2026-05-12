import '../models/todo_item.dart';

enum UndoActionType { add, delete, edit, toggle, batchDelete, batchToggle }

class UndoEntry {
  const UndoEntry({
    required this.actionType,
    required this.todoId,
    this.before,
    this.after,
  });

  final UndoActionType actionType;
  final String todoId;
  final TodoItem? before;
  final TodoItem? after;
}

class TodoUndoHistory {
  static const int _maxDepth = 50;

  final List<UndoEntry> _undoStack = [];
  final List<UndoEntry> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void pushAdd(TodoItem item) {
    _push(UndoEntry(actionType: UndoActionType.add, todoId: item.id, after: item));
  }

  void pushDelete(TodoItem before) {
    _push(UndoEntry(actionType: UndoActionType.delete, todoId: before.id, before: before));
  }

  void pushEdit(String id, TodoItem before, TodoItem after) {
    _push(UndoEntry(actionType: UndoActionType.edit, todoId: id, before: before, after: after));
  }

  void pushToggle(String id, TodoItem before, TodoItem after) {
    _push(UndoEntry(actionType: UndoActionType.toggle, todoId: id, before: before, after: after));
  }

  void pushBatch(List<UndoEntry> entries) {
    for (final entry in entries) {
      _push(entry);
    }
  }

  void _push(UndoEntry entry) {
    _undoStack.add(entry);
    _redoStack.clear();
    while (_undoStack.length > _maxDepth) {
      _undoStack.removeAt(0);
    }
  }

  UndoEntry? undo() {
    if (!canUndo) return null;
    final entry = _undoStack.removeLast();
    _redoStack.add(entry);
    return entry;
  }

  UndoEntry? redo() {
    if (!canRedo) return null;
    final entry = _redoStack.removeLast();
    _undoStack.add(entry);
    return entry;
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
