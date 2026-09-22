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
    String title = '临时卡',
    String? content,
    int? subjectId,
    List<String> imageNames = const <String>[],
    int createdAt = 1,
  }) {
    return repo.insertCard(
      StudyCard(
        type: CardType.formula,
        subjectId: subjectId,
        title: title,
        content: content,
        images: imageNames,
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
}
