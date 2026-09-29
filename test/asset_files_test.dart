import 'dart:io';

import 'package:baibaoxiang/widgets/add_star.dart';
import 'package:flutter_test/flutter_test.dart';

/// 守住「素材真的提交进仓库了」。
///
/// 这类文件最容易漏：本地跑得好好的，一提交忘了 `git add` 图片，
/// 别人拉下来就只剩一个空白方块。断言很便宜，但能挡住这种事。
void main() {
  /// 一张图至少得有这么大——太小说明是空文件或者占位图。
  const int minBytes = 1024;

  test('「＋」号的星星素材在仓库里', () {
    final File file = File(kAddStarAsset);
    expect(file.existsSync(), isTrue, reason: '找不到 $kAddStarAsset');
    expect(
      file.lengthSync(),
      greaterThan(minBytes),
      reason: '$kAddStarAsset 太小了，可能是个空文件',
    );
  });

  test('复习结束页的图案素材在仓库里', () {
    const String path = 'assets/celebrate/finish_mark.png';
    final File file = File(path);
    expect(file.existsSync(), isTrue, reason: '找不到 $path');
    expect(
      file.lengthSync(),
      greaterThan(minBytes),
      reason: '$path 太小了，可能是个空文件',
    );
  });
}
