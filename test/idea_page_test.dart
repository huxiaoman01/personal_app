import 'dart:io';

import 'package:baibaoxiang/app_globals.dart';
import 'package:baibaoxiang/data/app_database.dart';
import 'package:baibaoxiang/data/card_repository.dart';
import 'package:baibaoxiang/data/image_store.dart';
import 'package:baibaoxiang/data/subject_cache.dart';
import 'package:baibaoxiang/features/idea/idea_list_screen.dart';
import 'package:baibaoxiang/models/study_card.dart';
import 'package:baibaoxiang/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 灵感记录页的整条链路：随手写一条 → 出现在时间线里 → 长按删掉。
void main() {
  late Directory tempDir;
  late AppDatabase database;

  setUpAll(() async {
    sqfliteFfiInit();

    // 光标闪烁的定时器在测试里纯属捣乱：它会让“等界面稳定”永远等不到头，
    // 还会在测试结束时被判定成“还有 Timer 没结束”。关掉它只影响测试。
    EditableText.debugDeterministicCursor = true;

    tempDir = await Directory.systemTemp.createTemp('baibaoxiang_idea');
    database = AppDatabase(
      path: inMemoryDatabasePath,
      databaseFactoryOverride: databaseFactoryFfi,
    );

    // app_globals 里的单例是 late final，一个测试进程只能赋一次值，
    // 所以整个文件共用这一套库，每个用例之间靠清空 cards 表隔开。
    imageStore = ImageStore(tempDir);
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
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 数据库跑在后台 isolate 上，这种真异步得放进 runAsync 才会推进；
  /// 之后再 pump 一帧，把 setState 的结果画出来。
  ///
  /// 页面加载一次要连着查两回库（先查标签再查卡片），所以这里来回推几轮，
  /// 每轮都给它一次真异步的窗口 + 一次刷帧的机会。pump 带时间是因为
  /// 页面跳转本身有转场动画，时间不往前走，新页面会一直停在屏幕外。
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 收尾把转场动画走完。光标闪烁已经在 setUpAll 里关掉了，
    // 所以这一步不会一直等下去。
    await tester.pumpAndSettle();
  }

  Future<void> pumpIdeaPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        home: const IdeaListScreen(),
      ),
    );
    await settle(tester);
  }

  testWidgets('一条灵感都没有时给一句提示', (WidgetTester tester) async {
    await pumpIdeaPage(tester);
    expect(find.textContaining('还没有灵感'), findsOneWidget);
  });

  testWidgets('点右下角 + 写一条：标题、正文都能存，保存后回到列表',
      (WidgetTester tester) async {
    await pumpIdeaPage(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);

    // 新建的页面就得能加照片，不能等写完了再回来补。
    // 只认图片网格里的那个 + 号——列表页的 FAB 上也有一个 +，别认错了。
    expect(
      find.descendant(
        of: find.byType(GridView),
        matching: find.byIcon(Icons.add),
      ),
      findsOneWidget,
    );

    // 灵感有两个输入框：第一个是标题，第二个是正文。
    await tester.enterText(find.byType(TextField).at(0), '图论复习顺序');
    await tester.pump();
    await tester.enterText(
      find.byType(TextField).at(1),
      '最小生成树：先按边权排序，再用并查集',
    );
    await tester.pump();
    await tester.tap(find.text('保存'));
    await settle(tester);

    expect(find.text('图论复习顺序'), findsOneWidget);
    // 有标题的时候，正文就退到第二行显示。
    expect(find.text('最小生成树：先按边权排序，再用并查集'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);

    final List<StudyCard>? saved = await tester.runAsync(
      () => cardRepository.listCards(type: CardType.idea),
    );
    expect(saved!.length, 1);
    // 标题存在 title 里，正文存在 content 里，一个字段都没多加。
    expect(saved.first.title, '图论复习顺序');
    expect(saved.first.content, '最小生成树：先按边权排序，再用并查集');
  });

  testWidgets('标题可以不填：列表还是拿正文首行当标题', (WidgetTester tester) async {
    await pumpIdeaPage(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);

    await tester.enterText(find.byType(TextField).at(1), '临时想到的一句话');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await settle(tester);

    expect(find.text('临时想到的一句话'), findsOneWidget);

    final List<StudyCard>? saved = await tester.runAsync(
      () => cardRepository.listCards(type: CardType.idea),
    );
    // 没填标题就存 null，老灵感全是这个样子，一条都不能坏。
    expect(saved!.first.title, isNull);
  });

  testWidgets('打开一条带标题的灵感，标题会回填进输入框', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final int now = DateTime.now().millisecondsSinceEpoch;
      await cardRepository.insertCard(
        StudyCard(
          type: CardType.idea,
          title: '复习顺序',
          content: '先图论，再动态规划',
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
    await pumpIdeaPage(tester);

    await tester.tap(find.text('复习顺序'));
    await settle(tester);

    final TextField titleField =
        tester.widget<TextField>(find.byType(TextField).at(0));
    expect(titleField.controller!.text, '复习顺序');
  });

  testWidgets('点开一条老灵感，能看到它是什么时候写的', (WidgetTester tester) async {
    final int at = DateTime(2026, 9, 18, 14, 30).millisecondsSinceEpoch;
    await tester.runAsync(() async {
      await cardRepository.insertCard(
        StudyCard(
          type: CardType.idea,
          content: '上个月想到的',
          createdAt: at,
          updatedAt: at,
        ),
      );
    });
    await pumpIdeaPage(tester);

    await tester.tap(find.text('上个月想到的'));
    await settle(tester);

    expect(find.textContaining('创建于 2026-09-18 14:30'), findsOneWidget);
  });

  testWidgets('长按一条灵感能删掉，卡片进最近删除', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final int now = DateTime.now().millisecondsSinceEpoch;
      await cardRepository.insertCard(
        StudyCard(
          type: CardType.idea,
          content: '要删掉的灵感',
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
    await pumpIdeaPage(tester);
    expect(find.text('要删掉的灵感'), findsOneWidget);

    await tester.longPress(find.text('要删掉的灵感'));
    // 长按里先有一次震动反馈的通道调用，得给它真异步的窗口才会继续弹菜单。
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await settle(tester);

    final List<StudyCard>? trashed = await tester.runAsync(
      () => cardRepository.listCards(trashed: true),
    );
    expect(trashed!.length, 1);
    expect(find.text('要删掉的灵感'), findsNothing);

    // 「已移入最近删除」那个提示有自己的定时器，不放它跑完，
    // 测试结束时会报「还有 Timer 没结束」。
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));
  });
}
