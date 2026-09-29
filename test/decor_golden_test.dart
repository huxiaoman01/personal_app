import 'dart:io';

import 'package:baibaoxiang/app_globals.dart';
import 'package:baibaoxiang/data/app_database.dart';
import 'package:baibaoxiang/data/card_repository.dart';
import 'package:baibaoxiang/data/image_store.dart';
import 'package:baibaoxiang/data/subject_cache.dart';
import 'package:baibaoxiang/features/idea/idea_list_screen.dart';
import 'package:baibaoxiang/theme/app_theme.dart';
import 'package:baibaoxiang/widgets/app_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 灵感记录页（空态）的渲染结果，专门用来盯住背景上那三个图案。
///
/// 首页不铺图案，所以 goldens/home_light.png 不受影响；图案只在列表页露面，
/// 尺寸 / 位置 / 浓淡被改坏时这张图会直接失败，也方便你在电脑上打开 PNG
/// 直接看观感。
///
/// 改完外观刷新它：
///     flutter test --update-goldens test/decor_golden_test.dart
const String kDecorTestFontFamily = 'SimHei';

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

    await _loadFont(kDecorTestFontFamily, r'C:\Windows\Fonts\simhei.ttf');
    await _loadFont(
      'MaterialIcons',
      r'C:\src\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    );

    imageStore = ImageStore(
      Directory.systemTemp.createTempSync('baibaoxiang_decor'),
    );
    database = AppDatabase(
      path: inMemoryDatabasePath,
      databaseFactoryOverride: databaseFactoryFfi,
    );
    cardRepository = CardRepository(database, imageStore);
    subjectCache = SubjectCache(cardRepository);
    await database.open();
  });

  tearDownAll(() async {
    await database.close();
  });

  /// 同一页渲染两种配色：图案的线条色由主题给（AppPalette.decor），
  /// 深浅两套都得亲眼看过才算数。
  Future<void> pumpAndShoot(
    WidgetTester tester, {
    required Brightness brightness,
    required String golden,
  }) async {
    // 和首页 golden 一样固定成 360×800 逻辑像素，保证每次渲染结果一样。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(
          brightness,
          fontFamily: kDecorTestFontFamily,
        ),
        home: const IdeaListScreen(),
      ),
    );

    // 列表是异步查库查出来的：一次真异步窗口只够推进一步，
    // 所以要「给窗口 + 刷一帧」交替几轮。
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 图案是异步解码的，不等它解完，golden 里就是空的。
    final BuildContext context = tester.element(find.byType(IdeaListScreen));
    await tester.runAsync(() async {
      for (final String asset in kDecorAssets) {
        await precacheImage(AssetImage(asset), context);
      }
    });
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(golden),
    );
  }

  testWidgets('灵感记录页空态 · 浅色', (WidgetTester tester) async {
    await pumpAndShoot(
      tester,
      brightness: Brightness.light,
      golden: 'goldens/idea_empty_light.png',
    );
  });

  testWidgets('灵感记录页空态 · 深色', (WidgetTester tester) async {
    await pumpAndShoot(
      tester,
      brightness: Brightness.dark,
      golden: 'goldens/idea_empty_dark.png',
    );
  });
}
