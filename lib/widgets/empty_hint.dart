import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 空状态：一句轻的话，居中，不抢眼。
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 40, color: p.textTertiary),
          const SizedBox(height: AppSpace.md),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: p.textTertiary),
          ),
        ],
      ),
    );
  }
}
