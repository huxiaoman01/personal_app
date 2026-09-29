import 'dart:io';

import 'package:baibaoxiang/data/app_database.dart';
import 'package:baibaoxiang/data/card_repository.dart';
import 'package:baibaoxiang/data/image_store.dart';
import 'package:baibaoxiang/models/study_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late ImageStore images;
  late CardRepository repo;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('baibaoxiang_test');
    database = AppDatabase(
      path: inMemoryDatabasePath,
      databaseFactoryOverride: databaseFactoryFfi,
    );
    images = ImageStore(tempDir);
    repo = CardRepository(database, images);
    await database.open();
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<int> addCard({
    String type = CardType.formula,
    String? title = '临时卡',
    String? content,
    int? subjectId,
    List<String> imageNames = const <String>[],
    List<String> tags = const <String>[],
    int createdAt = 1,
  }) {
    return repo.insertCard(
      StudyCard(
        type: type,
        subjectId: subjectId,
        title: title,
        content: content,
        images: imageNames,
        tags: tags,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
  }

  test('首次建库会种入 5 个科目和 3 条示例卡', () async {
    final subjects = await repo.listSubjects();
    expect(
      subjects.map((s) => s.name).toList(),
      <String>['运筹', '高数', '线代', '数据库', '408'],
    );
    expect((await repo.listCards(type: CardType.formula)).length, 3);
  });

  test('新增的卡片能原样读回来', () async {
    final subjects = await repo.listSubjects();
    final int id = await addCard(
      title: '测试标题',
      content: '测试注释',
      subjectId: subjects.first.id,
    );
    final StudyCard? card = await repo.getCard(id);
    expect(card, isNotNull);
    expect(card!.title, '测试标题');
    expect(card.content, '测试注释');
    expect(card.subjectId, subjects.first.id);
    expect(card.images, isEmpty);
    expect(card.pinned, isFalse);
  });

  test('按科目筛选只返回这个科目的卡片', () async {
    final subjects = await repo.listSubjects();
    final yunchou = subjects.firstWhere((s) => s.name == '运筹');
    final cards = await repo.listCards(
      type: CardType.formula,
      subject: SubjectFilter.one(yunchou.id),
    );
    expect(cards.length, 1);
    expect(cards.first.title, '单纯形法判别准则');
  });

  test('未分类筛选只返回没有科目的卡片', () async {
    final int id = await addCard(title: '没有科目的卡');
    final cards = await repo.listCards(
      type: CardType.formula,
      subject: const SubjectFilter.uncategorized(),
    );
    expect(cards.length, 1);
    expect(cards.first.id, id);
  });

  test('搜索能命中标题、注释和科目名', () async {
    final byTitle =
        await repo.listCards(type: CardType.formula, keyword: '单纯形');
    expect(byTitle.length, 1);

    final byContent =
        await repo.listCards(type: CardType.formula, keyword: '检验数');
    expect(byContent.length, 1);

    // 「线代」只出现在科目名里，不该命中别的卡片。
    final bySubject =
        await repo.listCards(type: CardType.formula, keyword: '线代');
    expect(bySubject.length, 1);
    expect(bySubject.first.title, '矩阵求逆');
  });

  test('置顶的卡片排在最前，其余按创建时间倒序', () async {
    final subjects = await repo.listSubjects();
    final int newest = await addCard(
      title: '最新的卡',
      subjectId: subjects.first.id,
      // 必须比预置示例卡的创建时间更新，否则排序断言不成立。
      createdAt: DateTime.now().millisecondsSinceEpoch + 1000,
    );
    final before = await repo.listCards(type: CardType.formula);
    expect(before.first.id, newest);

    final int oldest = before.last.id!;
    await repo.setPinned(oldest, true);
    final after = await repo.listCards(type: CardType.formula);
    expect(after.first.id, oldest);
    expect(after[1].id, newest);
  });

  test('更新卡片会覆盖标题、注释、图片和科目', () async {
    final int id = await addCard(title: '旧标题', createdAt: 5);
    final StudyCard? card = await repo.getCard(id);
    final subjects = await repo.listSubjects();

    await repo.updateCard(
      card!.copyWith(
        title: '新标题',
        content: '新注释',
        subjectId: subjects.last.id,
        images: <String>['a.jpg'],
      ),
    );

    final StudyCard? updated = await repo.getCard(id);
    expect(updated!.title, '新标题');
    expect(updated.content, '新注释');
    expect(updated.subjectId, subjects.last.id);
    expect(updated.images, <String>['a.jpg']);
  });

  test('copyWith 能把科目显式改回未分类', () async {
    final subjects = await repo.listSubjects();
    final int id = await addCard(title: '有科目', subjectId: subjects.first.id);
    final card = (await repo.getCard(id))!;
    await repo.updateCard(card.copyWith(subjectId: null));
    expect((await repo.getCard(id))!.subjectId, isNull);
  });

  test('软删除后进回收站，恢复后回到列表', () async {
    final List<StudyCard> cards =
        await repo.listCards(type: CardType.formula);
    final int target = cards.first.id!;

    await repo.moveToTrash(target);
    expect(
      (await repo.listCards(type: CardType.formula)).length,
      cards.length - 1,
    );
    expect((await repo.listCards(trashed: true)).length, 1);

    await repo.restoreFromTrash(target);
    expect((await repo.listCards(trashed: true)), isEmpty);
    expect((await repo.listCards(type: CardType.formula)).length, cards.length);
  });

  test('彻底删除会把图片文件一起清掉', () async {
    final File source = File(p.join(tempDir.path, 'source.jpg'))
      ..writeAsBytesSync(<int>[1, 2, 3]);
    final String name = await images.import(source.path);
    final int id = await addCard(title: '带图的卡', imageNames: <String>[name]);

    expect(await images.fileOf(name).exists(), isTrue);
    await repo.moveToTrash(id);
    await repo.deleteForever(id);

    expect(await repo.getCard(id), isNull);
    expect(await images.fileOf(name).exists(), isFalse);
  });

  test('回收站超过 30 天才清理，29 天不动', () async {
    final cards = await repo.listCards(type: CardType.formula);
    final int expired = cards[0].id!;
    final int alive = cards[1].id!;
    await repo.moveToTrash(expired);
    await repo.moveToTrash(alive);

    final DateTime now = DateTime.now();
    final db = await database.open();
    await db.update(
      'cards',
      <String, Object?>{
        'deleted_at':
            now.subtract(const Duration(days: 31)).millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[expired],
    );
    await db.update(
      'cards',
      <String, Object?>{
        'deleted_at':
            now.subtract(const Duration(days: 29)).millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[alive],
    );

    expect(await repo.purgeExpired(now: now), 1);
    final List<StudyCard> left = await repo.listCards(trashed: true);
    expect(left.length, 1);
    expect(left.first.id, alive);
  });

  test('删除科目后卡片变成未分类，卡片本身还在', () async {
    final subjects = await repo.listSubjects();
    final yunchou = subjects.firstWhere((s) => s.name == '运筹');

    expect(await repo.countCardsInSubject(yunchou.id), 1);
    expect(await repo.deleteSubject(yunchou.id), 1);

    expect((await repo.listSubjects()).length, 4);
    final uncategorized = await repo.listCards(
      type: CardType.formula,
      subject: const SubjectFilter.uncategorized(),
    );
    expect(uncategorized.length, 1);
    expect(uncategorized.first.title, '单纯形法判别准则');
  });

  test('科目可以改名和重排', () async {
    final subjects = await repo.listSubjects();
    await repo.renameSubject(subjects.first.id, '运筹学');
    expect((await repo.listSubjects()).first.name, '运筹学');

    final reversed = subjects.reversed
        .map((s) => s.id)
        .toList(growable: false);
    await repo.reorderSubjects(reversed);
    expect(
      (await repo.listSubjects()).map((s) => s.id).toList(),
      reversed,
    );
  });

  test('按类型统计数量时不含回收站', () async {
    expect((await repo.countByType())[CardType.formula], 3);
    final cards = await repo.listCards(type: CardType.formula);
    await repo.moveToTrash(cards.first.id!);
    expect((await repo.countByType())[CardType.formula], 2);
  });

  test('灵感卡和公式卡互不串台', () async {
    await addCard(type: CardType.idea, title: null, content: '一条灵感');
    await addCard(type: CardType.idea, title: null, content: '又一条灵感');

    final ideas = await repo.listCards(type: CardType.idea);
    expect(ideas.length, 2);
    expect(ideas.every((StudyCard c) => c.type == CardType.idea), isTrue);

    // 预置的 3 条示例卡都是公式，不该被灵感数进去。
    final formulas = await repo.listCards(type: CardType.formula);
    expect(formulas.length, 3);
  });

  test('listTags 去重、按用得多的排前面，且不算回收站里的卡', () async {
    await addCard(
      type: CardType.idea,
      content: 'a',
      tags: <String>['运筹', '易错'],
    );
    await addCard(
      type: CardType.idea,
      content: 'b',
      tags: <String>['运筹'],
    );
    await addCard(
      type: CardType.idea,
      content: 'c',
      tags: <String>['运筹', '灵光一闪'],
    );
    // 公式卡上的标签不该出现在灵感记录的候选里。
    await addCard(tags: <String>['不属于灵感']);

    expect(
      await repo.listTags(type: CardType.idea),
      // 「运筹」用了 3 次排最前；剩下两个都只用过 1 次，按名字排。
      <String>['运筹', '易错', '灵光一闪'],
    );

    // 把唯一带「易错」的那张丢进回收站，标签就该跟着消失。
    final List<StudyCard> ideas = await repo.listCards(type: CardType.idea);
    final StudyCard withEasy =
        ideas.firstWhere((StudyCard c) => c.tags.contains('易错'));
    await repo.moveToTrash(withEasy.id!);
    expect(await repo.listTags(type: CardType.idea), <String>['运筹', '灵光一闪']);
  });

  test('按标签筛选：某个标签 / 没有标签 / 全部', () async {
    await addCard(type: CardType.idea, content: '带标签的', tags: <String>['运筹']);
    await addCard(type: CardType.idea, content: '没标签的');

    final List<StudyCard> byTag = await repo.listCards(
      type: CardType.idea,
      tag: const TagFilter.one('运筹'),
    );
    expect(byTag.length, 1);
    expect(byTag.first.content, '带标签的');

    final List<StudyCard> untagged = await repo.listCards(
      type: CardType.idea,
      tag: const TagFilter.untagged(),
    );
    expect(untagged.length, 1);
    expect(untagged.first.content, '没标签的');

    expect((await repo.listCards(type: CardType.idea)).length, 2);
  });

  test('搜索能找到标签', () async {
    await addCard(type: CardType.idea, content: '与标签无关的正文', tags: <String>['灵光一闪']);

    final List<StudyCard> hit =
        await repo.listCards(type: CardType.idea, keyword: '灵光');
    expect(hit.length, 1);
    expect(hit.first.content, '与标签无关的正文');
  });

  // ------------------------------------------------------------ 记忆卡复习

  /// 记忆卡专用的便捷建卡：题目/答案 + 复习状态。
  Future<int> addMemoryCard({
    String? title = '题目',
    String? content = '答案',
    int? subjectId,
    int? reviewedAt,
    int forgotCount = 0,
    int createdAt = 1,
  }) {
    return repo.insertCard(
      StudyCard(
        type: CardType.memory,
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

  /// 今天 0 点。复习的「到期」是按天算的，测试里也得用同一把尺子。
  int todayStart(DateTime now) =>
      DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;

  test('复习队列只收没复习过、或上次复习在昨天之前的卡', () async {
    final DateTime now = DateTime.now();
    final int never = await addMemoryCard(title: '从没复习过');
    final int longAgo = await addMemoryCard(
      title: '昨天之前看过',
      reviewedAt: todayStart(now) - 1000,
    );
    final int doneToday = await addMemoryCard(
      title: '今天刚看过',
      reviewedAt: todayStart(now) + 1000,
    );

    final List<StudyCard> due =
        await repo.listDueCards(type: CardType.memory, limit: 10, now: now);
    expect(
      due.map((StudyCard c) => c.id).toList(),
      <int>[never, longAgo],
    );
    expect(due.map((StudyCard c) => c.id), isNot(contains(doneToday)));
    expect(await repo.countDueCards(type: CardType.memory, now: now), 2);
  });

  test('复习队列排序：忘得多的在前，同样次数里最久没看的在前', () async {
    final DateTime now = DateTime.now();
    final int today = todayStart(now);
    final int often = await addMemoryCard(
      title: '老忘的题',
      forgotCount: 3,
      reviewedAt: today - 5000,
      createdAt: 1,
    );
    final int never = await addMemoryCard(
      title: '从没看过的题',
      createdAt: 2,
    );
    final int longAgo = await addMemoryCard(
      title: '很久没看的题',
      reviewedAt: today - 90000,
      createdAt: 3,
    );
    final int recent = await addMemoryCard(
      title: '前两天刚看过的题',
      reviewedAt: today - 100,
      createdAt: 4,
    );

    final List<StudyCard> due =
        await repo.listDueCards(type: CardType.memory, limit: 10, now: now);
    expect(
      due.map((StudyCard c) => c.id).toList(),
      <int>[often, never, longAgo, recent],
    );
  });

  test('一次只取一批：limit 生效，总数照数不误', () async {
    for (int i = 0; i < 12; i++) {
      await addMemoryCard(title: '第 $i 张', createdAt: i);
    }

    final List<StudyCard> batch =
        await repo.listDueCards(type: CardType.memory, limit: 10, now: DateTime.now());
    expect(batch.length, 10);
    expect(await repo.countDueCards(type: CardType.memory, now: DateTime.now()), 12);
  });

  test('进了回收站的卡不进复习队列', () async {
    final int id = await addMemoryCard(title: '要删掉的题');
    await repo.moveToTrash(id);

    expect(await repo.countDueCards(type: CardType.memory, now: DateTime.now()), 0);
  });

  test('忘了：次数 +1，reviewed_at 不动，所以今天还留在队列里', () async {
    final int id = await addMemoryCard(title: '总忘的题', createdAt: 7);

    await repo.markForgotten(id);

    final StudyCard after = (await repo.getCard(id))!;
    expect(after.forgotCount, 1);
    expect(after.reviewedAt, isNull);
    // 复习不是编辑，updated_at 不能被刷掉。
    expect(after.updatedAt, 7);
    expect(await repo.countDueCards(type: CardType.memory, now: DateTime.now()), 1);
  });

  test('记得：把 reviewed_at 推到现在，今天不再出现', () async {
    final int id = await addMemoryCard(title: '记住的题', createdAt: 7);
    final DateTime now = DateTime.now();

    await repo.markRemembered(id, now: now);

    final StudyCard after = (await repo.getCard(id))!;
    expect(after.reviewedAt, now.millisecondsSinceEpoch);
    expect(after.forgotCount, 0);
    expect(after.updatedAt, 7);
    expect(await repo.countDueCards(type: CardType.memory, now: now), 0);
  });

  test('复习队列跟着科目筛选走', () async {
    final subjects = await repo.listSubjects();
    await addMemoryCard(title: '有科目的题', subjectId: subjects.first.id);
    await addMemoryCard(title: '没科目的题');
    final DateTime now = DateTime.now();

    expect(
      await repo.countDueCards(
        type: CardType.memory,
        subject: SubjectFilter.one(subjects.first.id),
        now: now,
      ),
      1,
    );
    expect(
      await repo.countDueCards(
        type: CardType.memory,
        subject: const SubjectFilter.uncategorized(),
        now: now,
      ),
      1,
    );
    expect(await repo.countDueCards(type: CardType.memory, now: now), 2);
  });

  test('复习队列按类型隔离：记忆卡和错题各查各的', () async {
    await addMemoryCard(title: '一张记忆卡');
    await repo.insertCard(
      StudyCard(
        type: CardType.mistake,
        title: '一道错题',
        createdAt: 5,
        updatedAt: 5,
      ),
    );
    final DateTime now = DateTime.now();

    expect(await repo.countDueCards(type: CardType.memory, now: now), 1);
    expect(await repo.countDueCards(type: CardType.mistake, now: now), 1);

    final List<StudyCard> mistakes =
        await repo.listDueCards(type: CardType.mistake, limit: 10, now: now);
    expect(mistakes.single.title, '一道错题');
  });

  // ---------------------------------------------------------- 问题收集箱

  test('待解决的数量：只数没答案的，不算回收站，也不算别的类型', () async {
    await repo.insertCard(
      StudyCard(
        type: CardType.question,
        title: '还没问到答案的',
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    await repo.insertCard(
      StudyCard(
        type: CardType.question,
        title: '已经有答案的',
        content: '答案是先造人工变量',
        createdAt: 2,
        updatedAt: 2,
      ),
    );
    final int trashed = await repo.insertCard(
      StudyCard(
        type: CardType.question,
        title: '丢进回收站的',
        createdAt: 3,
        updatedAt: 3,
      ),
    );
    await repo.moveToTrash(trashed);
    // 别的类型不能算进问题的账里。
    await repo.insertCard(
      StudyCard(
        type: CardType.formula,
        title: '一张没注释的公式',
        createdAt: 4,
        updatedAt: 4,
      ),
    );

    expect(await repo.countPendingCards(type: CardType.question), 1);
  });

  test('hasContent：没写、空串、纯空格都算没内容', () {
    StudyCard withContent(String? content) => StudyCard(
          type: CardType.question,
          content: content,
          createdAt: 1,
          updatedAt: 1,
        );

    expect(withContent(null).hasContent, isFalse);
    expect(withContent('').hasContent, isFalse);
    expect(withContent('   \n  ').hasContent, isFalse);
    expect(withContent(' 有答案 ').hasContent, isTrue);
  });
}
