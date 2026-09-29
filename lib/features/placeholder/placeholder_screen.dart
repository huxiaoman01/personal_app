import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 还没做的功能的占位页（错题本、问题收集箱、考点大纲）。
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.construction_outlined, size: 40, color: p.textTertiary),
              const SizedBox(height: AppSpace.md),
              Text(
                '$title 还在做，先把公式手册用起来。',
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: p.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
