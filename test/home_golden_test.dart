import 'dart:io';

import 'package:baibaoxiang/app_globals.dart';
import 'package:baibaoxiang/data/app_database.dart';
import 'package:baibaoxiang/data/card_repository.dart';
import 'package:baibaoxiang/data/image_store.dart';
import 'package:baibaoxiang/data/subject_cache.dart';
import 'package:baibaoxiang/features/home/home_screen.dart';
import 'package:baibaoxiang/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 把首页渲染成 PNG，用来在电脑上直接看效果。
///
/// 第一次生成（或改完外观后刷新）：
///     flutter test --update-goldens test/home_golden_test.dart
///
/// 之后正常跑 `flutter test` 时，它会拿当前渲染结果和这张图比对，
/// 外观被意外改坏就会失败。
/// golden 里用的字体族名，必须和 setUpAll 里注册的名字一致。
const String kTestFontFamily = 'SimHei';

/// 把系统里的一堆字体读进来注册给测试用。
///
/// Flutter 测试环境不自带任何字体：汉字会画成方块，图标也会画成方块。
/// 不加载的话 golden 图只能看布局，看不了实际观感。
Future<void> _loadFont(String family, String path) async {
  final File file = File(path);
  if (!file.existsSync()) return;
  final FontLoader loader = FontLoader(family);
  loader.addFont(
    file.readAsBytes().then<ByteData>((Uint8List bytes) =>
        ByteData.sublistView(bytes)),
  );
  await loader.load();
}

void main() {
  late AppDatabase database;

  setUpAll(() async {
    sqfliteFfiInit();

    await _loadFont(kTestFontFamily, r'C:\Windows\Fonts\simhei.ttf');
    await _loadFont(
      'MaterialIcons',
      r'C:\src\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    );

    imageStore = ImageStore(
      Directory.systemTemp.createTempSync('baibaoxiang_golden'),
    );
    database = AppDatabase(
      path: inMemoryDatabasePath,
      databaseFactoryOverride: databaseFactoryFfi,
    );
    cardRepository = CardRepository(database, imageStore);
    subjectCache = SubjectCache(cardRepository);

    // 先把库建好（会自动种入 3 条示例公式），否则首页读到的数量是 0。
    await database.open();
  });

  tearDownAll(() async {
    await database.close();
  });

  testWidgets('首页浅色模式', (WidgetTester tester) async {
    // 固定成 360×800 逻辑像素，和常见手机一致，保证每次渲染结果一样。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light, fontFamily: kTestFontFamily),
        home: const HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // 首页的数字是异步查库拿到的：一次真异步窗口只够推进一步，
    // 所以要「给窗口 + 刷一帧」交替几轮，几回查询才都排得上队。
    // 少给几轮的话，数字会悄悄停在 0，golden 图看着没错、其实不对。
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 贴纸也是异步解码的，不等它解码完，golden 里那六格就是空白。
    final BuildContext context = tester.element(find.byType(HomeScreen));
    await tester.runAsync(() async {
      for (final HubEntry entry in kHubEntries) {
        await precacheImage(AssetImage(entry.asset), context);
      }
    });
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/home_light.png'),
    );
  });
}
