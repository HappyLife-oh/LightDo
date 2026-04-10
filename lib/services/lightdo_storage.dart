import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';
import '../models/app_snapshot.dart';
import '../models/todo_item.dart';

abstract class LightDoStorage {
  const LightDoStorage();

  Future<AppSnapshot> load();

  Future<void> save(AppSnapshot snapshot);
}

class FileLightDoStorage extends LightDoStorage {
  const FileLightDoStorage();

  @override
  Future<AppSnapshot> load() async {
    final file = await _resolveFile();
    if (!await file.exists()) {
      return AppSnapshot.empty();
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return AppSnapshot.empty();
    }

    final json = jsonDecode(raw) as Map<String, dynamic>;
    final todos = (json['todos'] as List<dynamic>? ?? const [])
        .map((item) => TodoItem.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);

    return AppSnapshot(
      todos: todos,
      settings: AppSettings.fromJson(json['settings'] as Map<String, dynamic>?),
    );
  }

  @override
  Future<void> save(AppSnapshot snapshot) async {
    final file = await _resolveFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'todos': snapshot.todos.map((todo) => todo.toJson()).toList(growable: false),
        'settings': snapshot.settings.toJson(),
      }),
    );
  }

  Future<File> _resolveFile() async {
    final directory = await _resolveDataDirectory();
    return File('${directory.path}${Platform.pathSeparator}lightdo.json');
  }

  Future<Directory> _resolveDataDirectory() async {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) {
        throw StateError('无法定位 HOME 目录');
      }
      return Directory(
        '$home/Library/Application Support/LightDo',
      );
    }

    if (Platform.isWindows) {
      final base = Platform.environment['APPDATA'] ??
          Platform.environment['LOCALAPPDATA'];
      if (base == null || base.isEmpty) {
        throw StateError('无法定位 APPDATA 目录');
      }
      return Directory('$base\\LightDo');
    }

    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('无法定位 HOME 目录');
    }
    return Directory('$home/.lightdo');
  }
}

class MemoryLightDoStorage extends LightDoStorage {
  MemoryLightDoStorage([AppSnapshot? initial]) : _snapshot = initial ?? AppSnapshot.empty();

  AppSnapshot _snapshot;

  @override
  Future<AppSnapshot> load() async => _snapshot;

  @override
  Future<void> save(AppSnapshot snapshot) async {
    _snapshot = snapshot;
  }
}
