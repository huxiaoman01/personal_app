import 'dart:io';

import 'package:baibaoxiang/app_globals.dart';
import 'package:baibaoxiang/data/app_database.dart';
import 'package:baibaoxiang/data/card_repository.dart';
import 'package:baibaoxiang/data/image_store.dart';
import 'package:baibaoxiang/data/subject_cache.dart';
import 'package:baibaoxiang/features/card/card_feature.dart';
import 'package:baibaoxiang/features/card/card_library_screen.dart';
import 'package:baibaoxiang/features/card/card_review_screen.dart';
import 'package:baibaoxiang/models/study_card.dart';
import 'package:baibaoxiang/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 通用卡片库的整条链路：列表 → 新建 → 复习（两个按钮判定）。
///
/// 记忆卡片和错题本共用同一套页面，所以测试也共用一个文件：
/// 前面是记忆卡（改动前后断言一字不改），后面是错题本。
void main() {
  late Directory tempDir;
  late AppDatabase database;

  setUpAll(() async {
    sqfliteFfiInit();

    // 光标闪烁的定时器在测试里纯属捣乱，关掉它只影响测试。
    EditableText.debugDeterministicCursor = true;

    tempDir = await Directory.systemTemp.createTemp('baibaoxiang_library');
    database = AppDatabase(
      path: inMemoryDatabasePath,
      databaseFactoryOverride: databaseFactoryFfi,
    );

    // app_globals 里的单例是 late final，一个测试进程只能赋一次值，
    // 所以整个文件共用这一套库，用例之间靠清空 cards 表隔开。
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

  /// 页面加载要连着查几回库，这种真异步得放进 runAsync 才会推进；
  /// 每轮给它一次真异步的窗口 + 一次刷帧的机会，转场动画也要时间走完。
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        home: page,
      ),
    );
    await settle(tester);
  }

  Future<int> insertCard({
    String type = CardType.memory,
    String title = '题目',
    String content = '答案',
    int? subjectId,
    int? reviewedAt,
    int forgotCount = 0,
    int createdAt = 1,
  }) {
    return cardRepository.insertCard(
      StudyCard(
        type: type,
        subjectId: subjectId,
        title: title,
        content: content,
        reviewedAt: reviewedAt,
        forgotCount: forgotCount,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
  }

  int todayStart() {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  }

  // ------------------------------------------------------------ 记忆卡片

  testWidgets('一张记忆卡都没有时给一句提示，也没有复习条', (WidgetTester tester) async {
    await pumpPage(tester, const CardLibraryScreen(feature: memoryFeature));

    expect(find.textContaining('还没有记忆卡'), findsOneWidget);
    expect(find.textContaining('今天先做'), findsNothing);
  });

  testWidgets('点右下角 + 写一条：填题目和答案、选科目，保存后回到列表', (WidgetTester tester) async {
    await pumpPage(tester, const CardLibraryScreen(feature: memoryFeature));

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);

    // 记忆卡的编辑页只有两个输入框：题目和答案。
    await tester.enterText(find.byType(TextField).at(0), '单纯形法的判别准则是什么？');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '检验数 σj ≤ 0 时达到最优解。');
    await tester.pump();
    // 科目在选择器里排得靠下，测试窗口只有 800×600，先滚到看得见的地方。
    await tester.ensureVisible(find.text('运筹'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('运筹'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await settle(tester);

    expect(find.text('单纯形法的判别准则是什么？'), findsOneWidget);
    expect(find.text('运筹 · 还没复习'), findsOneWidget);

    final List<StudyCard>? saved = await tester.runAsync(
      () => cardRepository.listCards(type: CardType.memory),
    );
    expect(saved!.length, 1);
    // 题目存在 title、答案存在 content，一个字段都没多加。
    expect(saved.first.title, '单纯形法的判别准则是什么？');
    expect(saved.first.content, '检验数 σj ≤ 0 时达到最优解。');
    expect(saved.first.subjectId, isNotNull);
  });

  testWidgets('列表第二行显示科目和忘了几次', (WidgetTester tester) async {
    await tester.runAsync(
      () => insertCard(title: '老忘的题', forgotCount: 2),
    );
    await pumpPage(tester, const CardLibraryScreen(feature: memoryFeature));

    expect(find.text('未分类 · 忘了 2 次'), findsOneWidget);
  });

  testWidgets('顶部复习条说清楚今天做几张，已经复习过的不算', (WidgetTester tester) async {
    await tester.runAsync(() async {
      // 今天已经复习过的卡：今天不该再出现。
      await insertCard(
        title: '今天看过的',
        reviewedAt: todayStart() + 1000,
        createdAt: 1,
      );
    });
    await pumpPage(tester, const CardLibraryScreen(feature: memoryFeature));

    expect(find.text('今天看过的'), findsOneWidget);
    expect(find.textContaining('今天先做'), findsNothing);
  });

  testWidgets('复习：点开看答案 → 点「忘了」→ 次数 +1 且今天还留在队列里',
      (WidgetTester tester) async {
    await tester.runAsync(
      () => insertCard(title: '什么是闭包', content: '函数和它的词法环境的组合'),
    );
    await pumpPage(tester, const CardLibraryScreen(feature: memoryFeature));

    expect(find.text('今天先做 1 张'), findsOneWidget);
    await tester.tap(find.text('开始复习'));
    await settle(tester);

    // 答案一开始是遮住的。
    expect(find.text('什么是闭包'), findsOneWidget);
    expect(find.text('函数和它的词法环境的组合'), findsNothing);
    expect(find.text('点一下看答案'), findsOneWidget);

    await tester.tap(find.text('什么是闭包'));
    await settle(tester);
    expect(find.text('函数和它的词法环境的组合'), findsOneWidget);

    await tester.tap(find.text('忘了'));
    await settle(tester);
    expect(find.text('今天这 1 张看完了'), findsOneWidget);

    final List<StudyCard>? cards = await tester.runAsync(
      () => cardRepository.listCards(type: CardType.memory),
    );
    expect(cards!.first.forgotCount, 1);
    // 忘了不动 reviewed_at，所以它今天还会再出现。
    expect(cards.first.reviewedAt, isNull);

    await tester.tap(find.text('再来 10 张'));
    await settle(tester);
    expect(find.text('什么是闭包'), findsOneWidget);
  });

  testWidgets('复习：点「记得」之后今天不再出现', (WidgetTester tester) async {
    await tester.runAsync(() => insertCard(title: '记得住的题'));
    await pumpPage(tester, const CardLibraryScreen(feature: memoryFeature));

    await tester.tap(find.text('开始复习'));
    await settle(tester);
    await tester.tap(find.text('记得'));
    await settle(tester);

    final List<StudyCard>? cards = await tester.runAsync(
      () => cardRepository.listCards(type: CardType.memory),
    );
    expect(cards!.first.reviewedAt, isNotNull);

    await tester.tap(find.text('再来 10 张'));
    await settle(tester);
    expect(find.textContaining('今天没有要复习的卡片'), findsOneWidget);
  });

  testWidgets('一次最多 10 张，做完给「再来 10 张」', (WidgetTester tester) async {
    await tester.runAsync(() async {
      for (int i = 0; i < 12; i++) {
        await insertCard(title: '第 $i 张题', createdAt: i);
      }
    });
    await pumpPage(tester, const CardLibraryScreen(feature: memoryFeature));

    expect(find.text('还有 12 张待复习'), findsOneWidget);
    await tester.tap(find.text('开始复习'));
    await settle(tester);

    // 12 张待复习，但这一批只放 10 张进来。
    expect(find.text('第 1 / 10 张'), findsOneWidget);
    for (int i = 0; i < 10; i++) {
      await tester.tap(find.text('记得'));
      await settle(tester);
    }
    expect(find.text('今天这 10 张看完了'), findsOneWidget);
    expect(find.text('再来 10 张'), findsOneWidget);
  });

  testWidgets('复习结束页：举对勾的小图放大出现，最后停在原尺寸',
      (WidgetTester tester) async {
    await tester.runAsync(() => insertCard(title: '唯一的一张'));
    await pumpPage(tester, const CardLibraryScreen(feature: memoryFeature));

    await tester.tap(find.text('开始复习'));
    await settle(tester);
    await tester.tap(find.text('记得'));
    await settle(tester);

    // 结束页的标志是那张贴纸，不再是原来那个 Material 对勾图标。
    final Finder mark = find.byWidgetPredicate(
      (Widget widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName ==
              'assets/celebrate/finish_mark.png',
    );
    expect(mark, findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    expect(find.text('今天这 1 张看完了'), findsOneWidget);

    // 动画是一次性放大到位：停下来的时候应该是原始大小（缩放系数 1），
    // 不能停在 0.6 那一步。
    final Transform scale = tester.widget<Transform>(
      find.ancestor(of: mark, matching: find.byType(Transform)).first,
    );
    expect(scale.transform.getMaxScaleOnAxis(), closeTo(1, 0.001));
    expect(tester.getSize(mark).width, 160);
  });

  testWidgets('队列空的时候进复习页，给一句空提示', (WidgetTester tester) async {
    await pumpPage(tester, const CardReviewScreen(feature: memoryFeature));

    expect(find.text('今天没有要复习的卡片'), findsOneWidget);
  });

  // -------------------------------------------------------------- 错题本

  testWidgets('错题：一张都没有时的提示是错题本的说法', (WidgetTester tester) async {
    await pumpPage(tester, const CardLibraryScreen(feature: mistakeFeature));

    expect(find.textContaining('还没有错题'), findsOneWidget);
  });

  testWidgets('错题：编辑页能写标题和「我当时错在哪」', (WidgetTester tester) async {
    await pumpPage(tester, const CardLibraryScreen(feature: mistakeFeature));

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);

    expect(find.text('我当时错在哪'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '对偶单纯形法那题');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '符号搞反了，应该先看检验数');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await settle(tester);

    expect(find.text('对偶单纯形法那题'), findsOneWidget);
    expect(find.text('未分类 · 还没复习'), findsOneWidget);

    final List<StudyCard>? saved = await tester.runAsync(
      () => cardRepository.listCards(type: CardType.mistake),
    );
    expect(saved!.length, 1);
    // 标题存 title，「我当时错在哪」存 content。
    expect(saved.first.title, '对偶单纯形法那题');
    expect(saved.first.content, '符号搞反了，应该先看检验数');
  });

  testWidgets('错题：列表第二行说「错了 N 次」', (WidgetTester tester) async {
    await tester.runAsync(
      () => insertCard(
        type: CardType.mistake,
        title: '总错的题',
        forgotCount: 3,
      ),
    );
    await pumpPage(tester, const CardLibraryScreen(feature: mistakeFeature));

    expect(find.text('未分类 · 错了 3 次'), findsOneWidget);
  });

  testWidgets('错题：复习页按钮是「又错了 / 做对了」，翻面看错在哪',
      (WidgetTester tester) async {
    await tester.runAsync(
      () => insertCard(
        type: CardType.mistake,
        title: '两阶段法那题',
        content: '漏了人工变量',
      ),
    );
    await pumpPage(tester, const CardLibraryScreen(feature: mistakeFeature));

    await tester.tap(find.text('开始复习'));
    await settle(tester);

    expect(find.text('又错了'), findsOneWidget);
    expect(find.text('做对了'), findsOneWidget);
    expect(find.text('点一下看错在哪'), findsOneWidget);
    expect(find.text('漏了人工变量'), findsNothing);

    await tester.tap(find.text('两阶段法那题'));
    await settle(tester);
    expect(find.text('漏了人工变量'), findsOneWidget);

    await tester.tap(find.text('又错了'));
    await settle(tester);

    final List<StudyCard>? cards = await tester.runAsync(
      () => cardRepository.listCards(type: CardType.mistake),
    );
    expect(cards!.first.forgotCount, 1);
    // 又错了不动 reviewed_at，所以它今天还留在队列里。
    expect(cards.first.reviewedAt, isNull);
  });

  testWidgets('记忆卡和错题各查各的，互不串台', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await insertCard(title: '这是一张记忆卡');
      await insertCard(type: CardType.mistake, title: '这是一道错题');
    });
    await pumpPage(tester, const CardLibraryScreen(feature: mistakeFeature));

    expect(find.text('这是一道错题'), findsOneWidget);
    expect(find.text('这是一张记忆卡'), findsNothing);
    expect(find.text('今天先做 1 张'), findsOneWidget);
  });
}
