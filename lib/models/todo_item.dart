enum TodoRecurrence { none, daily, weekly, monthly }

enum TodoDeadlineState { normal, dueSoon, overdue }

extension TodoRecurrenceX on TodoRecurrence {
  String get storageValue {
    switch (this) {
      case TodoRecurrence.none:
        return 'none';
      case TodoRecurrence.daily:
        return 'daily';
      case TodoRecurrence.weekly:
        return 'weekly';
      case TodoRecurrence.monthly:
        return 'monthly';
    }
  }

  String get label {
    switch (this) {
      case TodoRecurrence.none:
        return '不重复';
      case TodoRecurrence.daily:
        return '每天';
      case TodoRecurrence.weekly:
        return '每周';
      case TodoRecurrence.monthly:
        return '每月';
    }
  }

  static TodoRecurrence fromStorageValue(String? value) {
    switch (value) {
      case 'daily':
        return TodoRecurrence.daily;
      case 'weekly':
        return TodoRecurrence.weekly;
      case 'monthly':
        return TodoRecurrence.monthly;
      default:
        return TodoRecurrence.none;
    }
  }
}

class TodoItem {
  const TodoItem({
    required this.id,
    required this.title,
    required this.isCompleted,
    required this.createdAt,
    required this.updatedAt,
    required this.dueAt,
    required this.recurrence,
    required this.seriesId,
  });

  factory TodoItem.create({
    required String title,
    DateTime? dueAt,
    TodoRecurrence recurrence = TodoRecurrence.none,
  }) {
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();
    final normalizedRecurrence = dueAt == null
        ? TodoRecurrence.none
        : recurrence;
    return TodoItem(
      id: id,
      title: title,
      isCompleted: false,
      createdAt: now,
      updatedAt: now,
      dueAt: dueAt,
      recurrence: normalizedRecurrence,
      seriesId: normalizedRecurrence == TodoRecurrence.none ? null : id,
    );
  }

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    final dueAt = DateTime.tryParse(json['dueAt'] as String? ?? '');
    final recurrence = dueAt == null
        ? TodoRecurrence.none
        : TodoRecurrenceX.fromStorageValue(json['recurrence'] as String?);
    return TodoItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      isCompleted: json['isCompleted'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      dueAt: dueAt,
      recurrence: recurrence,
      seriesId: json['seriesId'] as String?,
    );
  }

  static const Object _noChange = Object();

  final String id;
  final String title;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? dueAt;
  final TodoRecurrence recurrence;
  final String? seriesId;

  bool get isRecurring => recurrence != TodoRecurrence.none && dueAt != null;

  TodoDeadlineState deadlineStateAt(
    DateTime now, {
    Duration dueSoonThreshold = const Duration(minutes: 30),
  }) {
    if (isCompleted || dueAt == null) {
      return TodoDeadlineState.normal;
    }
    if (now.isAfter(dueAt!)) {
      return TodoDeadlineState.overdue;
    }
    final remaining = dueAt!.difference(now);
    if (remaining <= dueSoonThreshold) {
      return TodoDeadlineState.dueSoon;
    }
    return TodoDeadlineState.normal;
  }

  String? deadlineBadgeLabelAt(DateTime now) {
    switch (deadlineStateAt(now)) {
      case TodoDeadlineState.normal:
        return null;
      case TodoDeadlineState.dueSoon:
        return '临期';
      case TodoDeadlineState.overdue:
        return '已过期';
    }
  }

  TodoItem copyWith({
    String? title,
    bool? isCompleted,
    Object? dueAt = _noChange,
    TodoRecurrence? recurrence,
    String? seriesId,
    DateTime? updatedAt,
  }) {
    final nextDueAt = identical(dueAt, _noChange)
        ? this.dueAt
        : dueAt as DateTime?;
    final nextRecurrence = nextDueAt == null
        ? TodoRecurrence.none
        : (recurrence ?? this.recurrence);
    return TodoItem(
      id: id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      dueAt: nextDueAt,
      recurrence: nextRecurrence,
      seriesId: nextRecurrence == TodoRecurrence.none
          ? null
          : (seriesId ?? this.seriesId ?? id),
    );
  }

  TodoItem? createNextRecurringInstance() {
    if (!isRecurring) {
      return null;
    }
    final nextDueAt = _nextDueAt();
    return TodoItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      isCompleted: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      dueAt: nextDueAt,
      recurrence: recurrence,
      seriesId: seriesId ?? id,
    );
  }

  DateTime? reminderEndsAt() {
    if (isCompleted || dueAt == null) {
      return null;
    }
    return dueAt!.add(const Duration(seconds: 30));
  }

  bool shouldFlashReminderAt(DateTime now) {
    final endAt = reminderEndsAt();
    if (endAt == null) {
      return false;
    }
    return !now.isBefore(dueAt!) && now.isBefore(endAt);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'isCompleted': isCompleted,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'dueAt': dueAt?.toIso8601String(),
      'recurrence': recurrence.storageValue,
      'seriesId': seriesId,
    };
  }

  String get summary {
    final pieces = <String>[];
    if (dueAt != null) {
      pieces.add('截止 ${formatShortDateTime(dueAt!)}');
    }
    if (recurrence != TodoRecurrence.none) {
      pieces.add(recurrence.label);
    }

    final date = isCompleted ? updatedAt : updatedAt;
    final action = isCompleted ? '完成于' : '更新于';
    pieces.add('$action ${formatShortDateTime(date)}');
    return pieces.join(' · ');
  }

  DateTime _nextDueAt() {
    final base = dueAt!;
    switch (recurrence) {
      case TodoRecurrence.none:
        return base;
      case TodoRecurrence.daily:
        return base.add(const Duration(days: 1));
      case TodoRecurrence.weekly:
        return base.add(const Duration(days: 7));
      case TodoRecurrence.monthly:
        final nextMonthYear = base.month == 12 ? base.year + 1 : base.year;
        final nextMonth = base.month == 12 ? 1 : base.month + 1;
        final lastDay = DateTime(nextMonthYear, nextMonth + 1, 0).day;
        final nextDay = base.day > lastDay ? lastDay : base.day;
        return DateTime(
          nextMonthYear,
          nextMonth,
          nextDay,
          base.hour,
          base.minute,
          base.second,
          base.millisecond,
          base.microsecond,
        );
    }
  }
}

String formatShortDateTime(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  final h = value.hour.toString().padLeft(2, '0');
  final min = value.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min';
}
