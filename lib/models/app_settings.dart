class AppSettings {
  const AppSettings({
    required this.expandCompletedByDefault,
    required this.confirmBeforeClearingCompleted,
    required this.compactMode,
    required this.alwaysOnTop,
    required this.minimizeToTrayOnClose,
    required this.launchAtStartup,
    required this.enableGlobalHotkey,
    required this.todoTitleFontSize,
    required this.completedTitleFontSize,
    required this.cardTextFontSize,
  });

  factory AppSettings.defaults() {
    return const AppSettings(
      expandCompletedByDefault: false,
      confirmBeforeClearingCompleted: true,
      compactMode: false,
      alwaysOnTop: false,
      minimizeToTrayOnClose: true,
      launchAtStartup: false,
      enableGlobalHotkey: true,
      todoTitleFontSize: 20,
      completedTitleFontSize: 20,
      cardTextFontSize: 15,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return AppSettings.defaults();
    }
    return AppSettings(
      expandCompletedByDefault:
          json['expandCompletedByDefault'] as bool? ?? false,
      confirmBeforeClearingCompleted:
          json['confirmBeforeClearingCompleted'] as bool? ?? true,
      compactMode: json['compactMode'] as bool? ?? false,
      alwaysOnTop: json['alwaysOnTop'] as bool? ?? false,
      minimizeToTrayOnClose: json['minimizeToTrayOnClose'] as bool? ?? true,
      launchAtStartup: json['launchAtStartup'] as bool? ?? false,
      enableGlobalHotkey: json['enableGlobalHotkey'] as bool? ?? true,
      todoTitleFontSize: (json['todoTitleFontSize'] as num?)?.toDouble() ?? 20,
      completedTitleFontSize:
          (json['completedTitleFontSize'] as num?)?.toDouble() ?? 20,
      cardTextFontSize: (json['cardTextFontSize'] as num?)?.toDouble() ?? 15,
    );
  }

  final bool expandCompletedByDefault;
  final bool confirmBeforeClearingCompleted;
  final bool compactMode;
  final bool alwaysOnTop;
  final bool minimizeToTrayOnClose;
  final bool launchAtStartup;
  final bool enableGlobalHotkey;
  final double todoTitleFontSize;
  final double completedTitleFontSize;
  final double cardTextFontSize;

  AppSettings copyWith({
    bool? expandCompletedByDefault,
    bool? confirmBeforeClearingCompleted,
    bool? compactMode,
    bool? alwaysOnTop,
    bool? minimizeToTrayOnClose,
    bool? launchAtStartup,
    bool? enableGlobalHotkey,
    double? todoTitleFontSize,
    double? completedTitleFontSize,
    double? cardTextFontSize,
  }) {
    return AppSettings(
      expandCompletedByDefault:
          expandCompletedByDefault ?? this.expandCompletedByDefault,
      confirmBeforeClearingCompleted:
          confirmBeforeClearingCompleted ?? this.confirmBeforeClearingCompleted,
      compactMode: compactMode ?? this.compactMode,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      minimizeToTrayOnClose:
          minimizeToTrayOnClose ?? this.minimizeToTrayOnClose,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      enableGlobalHotkey: enableGlobalHotkey ?? this.enableGlobalHotkey,
      todoTitleFontSize: todoTitleFontSize ?? this.todoTitleFontSize,
      completedTitleFontSize:
          completedTitleFontSize ?? this.completedTitleFontSize,
      cardTextFontSize: cardTextFontSize ?? this.cardTextFontSize,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'expandCompletedByDefault': expandCompletedByDefault,
      'confirmBeforeClearingCompleted': confirmBeforeClearingCompleted,
      'compactMode': compactMode,
      'alwaysOnTop': alwaysOnTop,
      'minimizeToTrayOnClose': minimizeToTrayOnClose,
      'launchAtStartup': launchAtStartup,
      'enableGlobalHotkey': enableGlobalHotkey,
      'todoTitleFontSize': todoTitleFontSize,
      'completedTitleFontSize': completedTitleFontSize,
      'cardTextFontSize': cardTextFontSize,
    };
  }
}
