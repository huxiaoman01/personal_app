import 'dart:io';

import 'package:baibaoxiang/app_globals.dart';
import 'package:baibaoxiang/data/app_database.dart';
import 'package:baibaoxiang/data/card_repository.dart';
import 'package:baibaoxiang/data/image_store.dart';
import 'package:baibaoxiang/data/subject_cache.dart';
import 'package:baibaoxiang/features/card/card_feature.dart';
import 'package:baibaoxiang/features/card/card_library_screen.dart';
import 'package:baibaoxiang/features/export/export_select_screen.dart';
import 'package:baibaoxiang/models/study_card.dart';
import 'package:baibaoxiang/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 两页新界面的渲染结果，方便在电脑上直接看观感：
///   1. 导出数据页（取消勾选之后的样子）
///   2. 复习结束页（图案的大小和位置）
///
/// 改完外观刷新：
///     flutter test --update-goldens test/flow_golden_test.dart
const String kFlowTestFontFamily = 'SimHei';

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
    await _loadFont(kFlowTestFontFamily, r'C:\Windows\Fonts\simhei.ttf');
    await _loadFont(
      'MaterialIcons',
      r'C:\src\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    );

    imageStore = ImageStore(
      Directory.systemTemp.createTempSync('baibaoxiang_flow'),
    );
    database = AppDatabase(
      path: inMemoryDatabasePath,
      databaseFactoryOverride: databaseFactoryFfi,
    );
    cardRepository = CardRepository(database, imageStore);
    subjectCache = SubjectCache(cardRepository);
    await database.open();
  });

  setUp(() async {
    final db = await database.open();
    await db.delete('cards');
  });

  tearDownAll(() async {
    await database.close();
  });

  /// 真异步 + 刷帧交替几轮：页面加载要连着查几回库，动画也要时间走完。
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester, Widget page) async {
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
          Brightness.light,
          fontFamily: kFlowTestFontFamily,
        ),
        home: page,
      ),
    );
  }

  testWidgets('导出数据页', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final int now = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < 3; i++) {
        await cardRepository.insertCard(
          StudyCard(
            type: CardType.formula,
            title: '第 $i 条公式',
            createdAt: now + i,
            updatedAt: now + i,
          ),
        );
      }
    });
    await pump(tester, const ExportSelectScreen());
    await settle(tester);

    // 取消勾选一个功能和一个科目，golden 里能看到选中/未选中两种样子。
    await tester.tap(find.text('灵感记录'));
    await tester.pump();
    await tester.tap(find.text('高数'));
    await settle(tester);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/export_select_light.png'),
    );
  });

  testWidgets('复习结束页', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final int now = DateTime.now().millisecondsSinceEpoch;
      await cardRepository.insertCard(
        StudyCard(
          type: CardType.memory,
          title: '单纯形法的判别准则是什么？',
          content: '检验数 σj ≤ 0 时达到最优解。',
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
    await pump(tester, const CardLibraryScreen(feature: memoryFeature));
    await settle(tester);

    await tester.tap(find.text('开始复习'));
    await settle(tester);
    await tester.tap(find.text('记得'));

    // 图案是异步解码的，不等它解完 golden 里就是空的；顺带把放大动画走完。
    final BuildContext context = tester.element(find.byType(Scaffold).last);
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/celebrate/finish_mark.png'),
        context,
      );
    });
    await settle(tester);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/review_finished_light.png'),
    );
  });
}
