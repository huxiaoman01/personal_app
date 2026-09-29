import 'dart:io';

import 'package:baibaoxiang/app_globals.dart';
import 'package:baibaoxiang/data/app_database.dart';
import 'package:baibaoxiang/data/card_repository.dart';
import 'package:baibaoxiang/data/image_store.dart';
import 'package:baibaoxiang/data/subject_cache.dart';
import 'package:baibaoxiang/features/home/home_screen.dart';
import 'package:baibaoxiang/features/question/question_list_screen.dart';
import 'package:baibaoxiang/models/study_card.dart';
import 'package:baibaoxiang/theme/app_theme.dart';
import 'package:baibaoxiang/widgets/card_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 问题收集箱的整条链路：记一条 → 待解决 → 回填答案 → 归档。
///
/// 「已解决」不是存在某个字段里的，而是「答案非空」推出来的，
/// 所以这里的用例盯的都是「答案写了没有」和「它落在哪一摊里」。
void main() {
  late Directory tempDir;
  late AppDatabase database;

  setUpAll(() async {
    sqfliteFfiInit();
    EditableText.debugDeterministicCursor = true;

    tempDir = await Directory.systemTemp.createTemp('baibaoxiang_question');
    database = AppDatabase(
      path: inMemoryDatabasePath,
      databaseFactoryOverride: databaseFactoryFfi,
    );
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

  Future<int> insertQuestion({
    String title = '为什么单纯形法要用人工变量？',
    String? content,
    int createdAt = 1,
  }) {
    return cardRepository.insertCard(
      StudyCard(
        type: CardType.question,
        title: title,
        content: content,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
  }

  testWidgets('一条问题都没有时给一句提示', (WidgetTester tester) async {
    await pumpPage(tester, const QuestionListScreen());

    expect(find.textContaining('还没有问题'), findsOneWidget);
    expect(find.textContaining('已解决的'), findsNothing);
  });

  testWidgets('点 + 只写问题：落在待解决那一摊，带一颗「待解决」角标',
      (WidgetTester tester) async {
    await pumpPage(tester, const QuestionListScreen());

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), '为什么单纯形法要用人工变量？');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await settle(tester);

    expect(find.text('为什么单纯形法要用人工变量？'), findsOneWidget);
    expect(find.text('待解决'), findsOneWidget);
    // 筛选条上也有个「未分类」，这里只认列表行里的那个。
    expect(
      find.descendant(of: find.byType(CardTile), matching: find.text('未分类')),
      findsOneWidget,
    );
    expect(find.textContaining('已解决的'), findsNothing);

    final List<StudyCard>? saved = await tester.runAsync(
      () => cardRepository.listCards(type: CardType.question),
    );
    // 没写答案 = 待解决，content 就该是空的。
    expect(saved!.first.content, isNull);
    expect(saved.first.hasContent, isFalse);
  });

  testWidgets('新建时连答案一起写：直接进归档区，不出现在待解决里',
      (WidgetTester tester) async {
    await pumpPage(tester, const QuestionListScreen());

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), '单纯形法和两阶段法什么关系？');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '两阶段法就是先造人工变量凑初始基');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await settle(tester);

    expect(find.text('没有待解决的问题了'), findsOneWidget);
    expect(find.text('已解决的 1 条'), findsOneWidget);
    // 归档默认收起，那一条得点开才看得见。
    expect(find.text('单纯形法和两阶段法什么关系？'), findsNothing);

    await tester.tap(find.text('已解决的 1 条'));
    await settle(tester);
    expect(find.text('单纯形法和两阶段法什么关系？'), findsOneWidget);
    expect(find.text('已解决'), findsOneWidget);
  });

  testWidgets('详情页回填答案：从待解决挪进归档区', (WidgetTester tester) async {
    await tester.runAsync(insertQuestion);
    await pumpPage(tester, const QuestionListScreen());

    expect(find.text('待解决'), findsOneWidget);
    await tester.tap(find.text('为什么单纯形法要用人工变量？'));
    await settle(tester);

    expect(find.textContaining('待解决'), findsWidgets);
    await tester.enterText(find.byType(TextField), '为了让初始基可行解里的变量能被人为清零');
    await tester.pump();
    await tester.tap(find.text('保存答案'));
    await settle(tester);

    expect(find.textContaining('已解决'), findsWidgets);
    final List<StudyCard>? cards = await tester.runAsync(
      () => cardRepository.listCards(type: CardType.question),
    );
    expect(cards!.first.content, '为了让初始基可行解里的变量能被人为清零');
    expect(cards.first.hasContent, isTrue);

    // 退回列表：它已经不在待解决那一摊里了。
    await tester.pageBack();
    await settle(tester);
    expect(find.text('没有待解决的问题了'), findsOneWidget);
    expect(find.text('已解决的 1 条'), findsOneWidget);
  });

  testWidgets('把答案清空再保存：退回待解决', (WidgetTester tester) async {
    final int id = (await tester.runAsync(
      () => insertQuestion(content: '先写成这样，后来发现记错了'),
    ))!;
    await pumpPage(tester, const QuestionListScreen());

    await tester.tap(find.text('已解决的 1 条'));
    await settle(tester);
    await tester.tap(find.text('为什么单纯形法要用人工变量？'));
    await settle(tester);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.text('保存答案'));
    await settle(tester);

    expect(find.textContaining('待解决'), findsWidgets);
    final StudyCard? card = await tester.runAsync<StudyCard?>(
      () => cardRepository.getCard(id),
    );
    expect(card!.content, isNull);
  });

  testWidgets('详情页 + 归档区：能算出一共有几条已解决', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await insertQuestion(title: '还没问到的', createdAt: 1);
      await insertQuestion(title: '第一个问到的', content: '答案是 A', createdAt: 2);
      await insertQuestion(title: '第二个问到的', content: '答案是 B', createdAt: 3);
    });
    await pumpPage(tester, const QuestionListScreen());

    expect(find.text('待解决'), findsOneWidget);
    expect(find.text('已解决的 2 条'), findsOneWidget);

    await tester.tap(find.text('已解决的 2 条'));
    await settle(tester);
    expect(find.text('第一个问到的'), findsOneWidget);
    expect(find.text('第二个问到的'), findsOneWidget);
    expect(find.text('已解决'), findsNWidgets(2));
  });

  testWidgets('答案改了不保存就返回：先问一句再走', (WidgetTester tester) async {
    await tester.runAsync(insertQuestion);
    await pumpPage(tester, const QuestionListScreen());
    await tester.tap(find.text('为什么单纯形法要用人工变量？'));
    await settle(tester);

    await tester.enterText(find.byType(TextField), '写到一半');
    await tester.pump();
    await tester.pageBack();
    await settle(tester);
    expect(find.text('放弃这次修改？'), findsOneWidget);

    // 「继续写」就留在原地。
    await tester.tap(find.text('继续写'));
    await settle(tester);
    expect(find.text('答案'), findsOneWidget);

    // 「放弃」才真的退回列表。
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text('放弃'));
    await settle(tester);
    expect(find.text('问题收集箱'), findsOneWidget);
  });

  testWidgets('首页「问题收集箱」显示的是还没解决的条数', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await insertQuestion(title: '没解决的一', createdAt: 1);
      await insertQuestion(title: '没解决的二', createdAt: 2);
      await insertQuestion(title: '解决了的', content: '有答案了', createdAt: 3);
    });
    await pumpPage(tester, const HomeScreen());

    expect(find.text('问题收集箱'), findsOneWidget);
    // 两条待解决 → 这个数字是 2，而不是总数 3。
    expect(find.text('2'), findsOneWidget);
  });
}
