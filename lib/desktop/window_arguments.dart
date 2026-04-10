import 'dart:convert';

enum LightDoWindowRole {
  main,
  floatingBall,
}

class LightDoWindowArguments {
  const LightDoWindowArguments({
    required this.role,
    this.mainWindowId,
  });

  factory LightDoWindowArguments.main() {
    return const LightDoWindowArguments(role: LightDoWindowRole.floatingBall);
  }

  factory LightDoWindowArguments.editor({
    required String mainWindowId,
  }) {
    return LightDoWindowArguments(
      role: LightDoWindowRole.main,
      mainWindowId: mainWindowId,
    );
  }

  factory LightDoWindowArguments.floatingBall({
    required String mainWindowId,
  }) {
    return LightDoWindowArguments(
      role: LightDoWindowRole.floatingBall,
      mainWindowId: mainWindowId,
    );
  }

  factory LightDoWindowArguments.fromEncoded(String encoded) {
    if (encoded.isEmpty) {
      return LightDoWindowArguments.main();
    }
    final json = jsonDecode(encoded) as Map<String, dynamic>;
    final roleValue = json['role'] as String? ?? 'main';
    final role = roleValue == 'floating_ball'
        ? LightDoWindowRole.floatingBall
        : LightDoWindowRole.main;
    return LightDoWindowArguments(
      role: role,
      mainWindowId: json['mainWindowId'] as String?,
    );
  }

  final LightDoWindowRole role;
  final String? mainWindowId;

  String encode() {
    return jsonEncode({
      'role': role == LightDoWindowRole.floatingBall ? 'floating_ball' : 'main',
      if (mainWindowId != null) 'mainWindowId': mainWindowId,
    });
  }
}
