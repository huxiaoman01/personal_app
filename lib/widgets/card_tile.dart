import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../models/study_card.dart';
import '../theme/app_theme.dart';

/// 列表里的一行：48×48 缩略图 + 标题 + 一行注释。
///
/// 公式列表、搜索结果、回收站都用它，保证三处长得一模一样。
class CardTile extends StatelessWidget {
  const CardTile({
    super.key,
    required this.card,
    this.trailing,
    this.subtitleOverride,
    this.onTap,
    this.onLongPress,
  });

  final StudyCard card;
  final Widget? trailing;

  /// 回收站里要显示「还有 N 天」，就把它塞进来。
  final String? subtitleOverride;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final String subtitle = subtitleOverride ?? card.displaySubtitle;
    final String? thumb = card.images.isEmpty ? null : card.images.first;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        height: AppSize.rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSize.pagePadding,
          ),
          child: Row(
            children: <Widget>[
              CardThumb(name: thumb),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        if (card.pinned) ...<Widget>[
                          Icon(Icons.push_pin, size: 14, color: p.primary),
                          const SizedBox(width: AppSpace.xs),
                        ],
                        Expanded(
                          child: Text(
                            card.displayTitle,
                            style: AppText.listTitle.copyWith(color: p.text),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        subtitle,
                        style: AppText.caption.copyWith(color: p.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: AppSpace.sm),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 缩略图。没图时用一块淡色占位，保证每行左边对齐。
class CardThumb extends StatelessWidget {
  const CardThumb({super.key, this.name, this.size = AppSize.thumb});

  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final BorderRadius radius = BorderRadius.circular(
      size <= AppSize.thumb ? AppRadius.thumb : AppRadius.card,
    );
    final String? fileName = name;

    if (fileName == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: p.iconBlock, borderRadius: radius),
        child: Icon(
          Icons.image_outlined,
          size: size * 0.4,
          color: p.textTertiary,
        ),
      );
    }

    final double dpr = MediaQuery.of(context).devicePixelRatio;
    return ClipRRect(
      borderRadius: radius,
      child: Image.file(
        imageStore.fileOf(fileName),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * dpr).round(),
        errorBuilder: (BuildContext _, Object _, StackTrace? _) => Container(
          width: size,
          height: size,
          color: p.iconBlock,
          child: Icon(
            Icons.broken_image_outlined,
            size: size * 0.4,
            color: p.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// 列表分隔线：左边缩进到文字起始位置，右边收在页边距。
class CardListDivider extends StatelessWidget {
  const CardListDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      indent: AppSize.dividerIndent,
      endIndent: AppSize.pagePadding,
    );
  }
}
