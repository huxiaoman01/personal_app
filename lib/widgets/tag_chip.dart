import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 一颗标签。
///
/// 传了 [onDeleted] 右边就多一个 ×，点它可以删掉这颗标签；
/// 传了 [onTap] 整颗都可以点（标签编辑器里「用过的标签」就是这么用的）。
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    this.onTap,
    this.onDeleted,
  });

  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final VoidCallback? onDeletedTap = onDeleted;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: EdgeInsets.only(
          left: AppSpace.md,
          right: onDeletedTap == null ? AppSpace.md : AppSpace.sm,
          top: AppSpace.xs,
          bottom: AppSpace.xs,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: p.divider),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '#$label',
              style: AppText.caption.copyWith(color: p.textSecondary),
            ),
            if (onDeletedTap != null) ...<Widget>[
              const SizedBox(width: AppSpace.xs),
              GestureDetector(
                // 删除区域比图标本身大一圈，手指才点得准。
                behavior: HitTestBehavior.opaque,
                onTap: onDeletedTap,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.xs),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: p.textTertiary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
