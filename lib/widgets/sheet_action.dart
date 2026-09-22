import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 底部弹出菜单里的一行。列表页和详情页共用。
class SheetAction extends StatelessWidget {
  const SheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return ListTile(
      leading: Icon(icon, color: color ?? p.textSecondary),
      title: Text(label, style: AppText.body.copyWith(color: color ?? p.text)),
      onTap: onTap,
    );
  }
}
