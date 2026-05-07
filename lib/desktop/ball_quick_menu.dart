import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/colors.dart';

enum BallMenuAction {
  newTodo,
  openMain,
  searchWeb,
  settings,
}

class BallQuickMenu extends StatefulWidget {
  const BallQuickMenu({
    super.key,
    required this.action,
    required this.onDismiss,
    required this.ballWindowCenter,
  });

  final void Function(BallMenuAction action) action;
  final VoidCallback onDismiss;
  final Offset ballWindowCenter;

  @override
  State<BallQuickMenu> createState() => _BallQuickMenuState();
}

class _BallQuickMenuState extends State<BallQuickMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<Animation<double>> _itemAnimations;

  static const _menuRadius = 80.0;
  static const _itemSize = 54.0;

  static final _menuItems = <_MenuItemSpec>[
    const _MenuItemSpec(
      action: BallMenuAction.newTodo,
      icon: Icons.add_rounded,
      label: '新建待办',
    ),
    const _MenuItemSpec(
      action: BallMenuAction.openMain,
      icon: Icons.launch_rounded,
      label: '主窗口',
    ),
    const _MenuItemSpec(
      action: BallMenuAction.searchWeb,
      icon: Icons.search_rounded,
      label: '搜索',
    ),
    const _MenuItemSpec(
      action: BallMenuAction.settings,
      icon: Icons.settings_outlined,
      label: '设置',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _itemAnimations = List.generate(_menuItems.length, (i) {
      final start = i * 0.07;
      final end = 0.35 + i * 0.09;
      return CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end.clamp(0.0, 1.0), curve: Curves.easeOutBack),
      );
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> dismiss() async {
    await _controller.reverse();
    if (mounted) {
      widget.onDismiss();
    }
  }

  Offset _itemPosition(int index) {
    const total = _menuItems.length;
    // Arc above the ball: from -90° (left) to +90° (right)
    final startAngle = -math.pi * 0.58;
    final endAngle = math.pi * 0.58;
    final angle = startAngle + (endAngle - startAngle) * index / (total - 1);
    return Offset(math.cos(angle) * _menuRadius, -math.sin(angle) * _menuRadius);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => dismiss(),
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // Dismiss tap area
            Positioned.fill(child: Container(color: Colors.transparent)),
            // Menu items
            for (var i = 0; i < _menuItems.length; i++)
              _buildMenuItem(i, widget.ballWindowCenter),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(int index, Offset ballCenter) {
    final offset = _itemPosition(index);
    final spec = _menuItems[index];
    final anim = _itemAnimations[index];

    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        if (anim.value == 0) return const SizedBox.shrink();
        return Positioned(
          left: ballCenter.dx + offset.dx - _itemSize / 2,
          top: ballCenter.dy + offset.dy - _itemSize / 2,
          child: Transform.scale(
            scale: anim.value,
            child: Opacity(
              opacity: anim.value,
              child: child,
            ),
          ),
        );
      },
      child: _MenuItemWidget(
        spec: spec,
        onTap: () {
          widget.action(spec.action);
          dismiss();
        },
      ),
    );
  }
}

class _MenuItemSpec {
  const _MenuItemSpec({
    required this.action,
    required this.icon,
    required this.label,
  });

  final BallMenuAction action;
  final IconData icon;
  final String label;
}

class _MenuItemWidget extends StatelessWidget {
  const _MenuItemWidget({required this.spec, required this.onTap});

  final _MenuItemSpec spec;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.ballBorderNormal.withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.ballShadowColor.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(spec.icon, size: 22, color: AppColors.composerIconActive),
            const SizedBox(height: 2),
            Text(
              spec.label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: AppColors.cardNormalTitle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
