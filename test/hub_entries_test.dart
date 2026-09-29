import 'dart:io';

import 'package:baibaoxiang/features/home/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// 守住首页六宫格的「配置数据」。
///
/// 这些断言很便宜，但能挡住最容易犯的错：配图路径写错、图片忘了提交、
/// 加了新功能却忘了写描述、顺序被调乱。
void main() {
  test('首页有六个功能入口', () {
    expect(kHubEntries.length, 6);
  });

  test('每个入口都有名称和一句描述', () {
    for (final HubEntry entry in kHubEntries) {
      expect(entry.label.trim(), isNotEmpty);
      expect(
        entry.description.trim(),
        isNotEmpty,
        reason: '「${entry.label}」缺描述',
      );
    }
  });

  test('入口名称不重复', () {
    final List<String> labels =
        kHubEntries.map((HubEntry e) => e.label).toList();
    expect(labels.toSet().length, labels.length);
  });

  test('每个入口的配图都真实存在', () {
    for (final HubEntry entry in kHubEntries) {
      final File file = File(entry.asset);
      expect(
        file.existsSync(),
        isTrue,
        reason: '找不到配图 ${entry.asset}：路径写错了，还是图片没提交？',
      );
      expect(
        file.lengthSync(),
        greaterThan(1024),
        reason: '${entry.asset} 太小了，可能是个空文件',
      );
    }
  });

  test('配图按 hub_1 到 hub_6 顺序对应', () {
    expect(
      kHubEntries.map((HubEntry e) => e.asset).toList(),
      <String>[
        'assets/hub/hub_1.png',
        'assets/hub/hub_2.png',
        'assets/hub/hub_3.png',
        'assets/hub/hub_4.png',
        'assets/hub/hub_5.png',
        'assets/hub/hub_6.png',
      ],
    );
  });

  test('已经做完的功能才允许点开', () {
    expect(
      kHubEntries
          .where((HubEntry e) => e.ready)
          .map((HubEntry e) => e.label)
          .toList(),
      <String>['公式手册', '灵感记录', '记忆卡片', '错题本', '问题收集箱'],
    );
  });
}
