import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const String _decor1 = 'assets/decor/decor_1.png';
const String _decor2 = 'assets/decor/decor_2.png';
const String _decor3 = 'assets/decor/decor_3.png';

/// 三个装饰图案的素材路径。
///
/// 公开出来是为了让测试能先把它们解码好（见 test/decor_golden_test.dart）；
/// 顺序和 [_decor] 一致。
const List<String> kDecorAssets = <String>[
  _decor1,
  _decor2,
  _decor3,
];

/// 列表页背景上那三个淡淡的图案。
///
/// 纯装饰：整层套了 [IgnorePointer] 和 [ExcludeSemantics]，不抢点击、
/// 不进读屏，也不参与页面布局。
///
/// 位置用 [Align] 的分数对齐而不是写死的像素偏移——换台宽一点或窄一点的
/// 手机，三个图案还是待在「屏幕中部」这个相对位置上，不会跑到屏幕外面去。
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  /// 三个图案：素材、宽度、对齐位置。
  ///
  /// 尺寸都在 116–132 之间、竖着排在屏幕中部，正是「中等大小、聚在中间」；
  /// 顶部留给标题栏、右下角留给 + 号按钮，都不去挤。
  static const List<_Decor> _decor = <_Decor>[
    _Decor(_decor1, 132, Alignment(-0.55, -0.32)),
    _Decor(_decor2, 116, Alignment(0.58, -0.02)),
    _Decor(_decor3, 128, Alignment(-0.35, 0.32)),
  ];

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Stack(
                children: <Widget>[
                  for (final _Decor decor in _decor)
                    Align(
                      alignment: decor.alignment,
                      child: Image.asset(
                        decor.asset,
                        width: decor.width,
                        // 素材是纯白的，颜色交给主题：同一张图在米黄底和
                        // 深蓝底上都能配出合适的淡色（见 AppPalette.decor）。
                        color: p.decor,
                        colorBlendMode: BlendMode.srcIn,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _Decor {
  const _Decor(this.asset, this.width, this.alignment);

  final String asset;
  final double width;
  final Alignment alignment;
}
