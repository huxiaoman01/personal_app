import 'package:flutter/material.dart';

/// 全 app 的「＋」都用这颗星星。
///
/// 素材是用户给的贴纸，`tools/prepare_assets.py` 把淡蓝底抠成透明
/// （顺手丢掉了外面的小圆点和手写字，做成小图标时它们只是噪点）。
const String kAddStarAsset = 'assets/star/star.png';

/// 「＋」号：一颗星星。
///
/// 替换掉原来那个 Material 的 `Icons.add`。尺寸由调用处给——按钮上用
/// [AppSize.iconBlock]（44），小格子里用 30 上下。
///
/// 注意别给这个图套 `color`：星星本身是黄蓝渐变的，染色会把它压成一片纯色。
class AddStar extends StatelessWidget {
  const AddStar({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      kAddStarAsset,
      width: size,
      height: size,
      // 一颗星星放大到 44 时没必要解码 512 的原始尺寸。
      filterQuality: FilterQuality.medium,
    );
  }
}
