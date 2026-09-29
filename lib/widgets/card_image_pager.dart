import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../theme/app_theme.dart';

/// 详情页顶部的大图区：一次一张、左右滑动翻页、点一下全屏。
///
/// 公式/记忆/错题的详情页和问题详情页共用，保证几处的看图手感一模一样。
class CardImagePager extends StatelessWidget {
  const CardImagePager({
    super.key,
    required this.names,
    required this.page,
    required this.onPageChanged,
    required this.onTap,
  });

  final List<String> names;

  /// 当前是第几张，用来点亮下面那排小圆点。
  final int page;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Column(
      children: <Widget>[
        SizedBox(
          height: 280,
          child: PageView.builder(
            itemCount: names.length,
            onPageChanged: onPageChanged,
            itemBuilder: (BuildContext context, int index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSize.pagePadding,
                ),
                child: GestureDetector(
                  onTap: () => onTap(index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: Container(
                      color: p.iconBlock,
                      alignment: Alignment.center,
                      child: Image.file(
                        imageStore.fileOf(names[index]),
                        fit: BoxFit.contain,
                        errorBuilder: (
                          BuildContext _,
                          Object _,
                          StackTrace? _,
                        ) =>
                            Icon(
                          Icons.broken_image_outlined,
                          size: 32,
                          color: p.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (names.length > 1) ...<Widget>[
          const SizedBox(height: AppSpace.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (int i = 0; i < names.length; i++)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == page ? p.primary : p.divider,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
