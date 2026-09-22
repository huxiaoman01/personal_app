import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:baibaoxiang/data/app_database.dart';
import 'package:baibaoxiang/data/card_repository.dart';
import 'package:baibaoxiang/data/export_service.dart';
import 'package:baibaoxiang/data/image_store.dart';
import 'package:baibaoxiang/models/study_card.dart';
import 'package:baibaoxiang/models/subject.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late ImageStore images;
  late CardRepository repo;
  late ExportService exportService;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('baibaoxiang_export');
    database = AppDatabase(
      path: inMemoryDatabasePath,
      databaseFactoryOverride: databaseFactoryFfi,
    );
    images = ImageStore(tempDir);
    repo = CardRepository(database, images);
    exportService = ExportService(repo, images);
    await database.open();
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('Markdown 按科目分节，含标题、注释和图片引用', () async {
    final File source = File(p.join(tempDir.path, 'shot.jpg'))
      ..writeAsBytesSync(<int>[1, 2, 3, 4]);
    final String imageName = await images.import(source.path);

    final subjects = await repo.listSubjects();
    final yunchou = subjects.firstWhere((s) => s.name == '运筹');
    await repo.insertCard(
      StudyCard(
        type: CardType.formula,
        subjectId: yunchou.id,
        title: '对偶单纯形法',
        content: '先从负检验数入基',
        images: <String>[imageName],
        createdAt: 10,
        updatedAt: 10,
      ),
    );

    final String markdown = exportService.buildMarkdown(
      cards: await repo.listCardsForExport(),
      subjects: subjects,
      now: DateTime(2026, 9, 22, 21, 5),
    );

    expect(markdown, startsWith('# 公式手册'));
    expect(markdown, contains('导出时间：2026-09-22 21:05'));
    expect(markdown, contains('共 4 条'));
    expect(markdown, contains('## 运筹'));
    expect(markdown, contains('### 对偶单纯形法'));
    expect(markdown, contains('先从负检验数入基'));
    expect(markdown, contains('![图1](images/$imageName)'));
  });

  test('没有标题的卡片用注释首行当标题', () async {
    final marks = await repo.listSubjects();
    await repo.insertCard(
      StudyCard(
        type: CardType.formula,
        subjectId: marks.first.id,
        content: '第一行内容\n第二行内容',
        createdAt: 20,
        updatedAt: 20,
      ),
    );

    final String markdown = exportService.buildMarkdown(
      cards: await repo.listCardsForExport(),
      subjects: marks,
      now: DateTime(2026, 9, 22),
    );
    expect(markdown, contains('### 第一行内容'));
    expect(markdown, isNot(contains('### 第二行内容')));
  });

  test('zip 里有 Markdown、data.json 和图片文件', () async {
    final File source = File(p.join(tempDir.path, 'page.jpg'))
      ..writeAsBytesSync(<int>[9, 8, 7]);
    final String imageName = await images.import(source.path);

    final subjects = await repo.listSubjects();
    await repo.insertCard(
      StudyCard(
        type: CardType.formula,
        subjectId: subjects.first.id,
        title: '带图的卡',
        images: <String>[imageName],
        createdAt: 30,
        updatedAt: 30,
      ),
    );

    final bytes = await exportService.buildZip(now: DateTime(2026, 9, 22));
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final List<String> names =
        archive.files.map((ArchiveFile f) => f.name).toList();

    expect(names, contains(ExportService.markdownFileName));
    expect(names, contains(ExportService.jsonFileName));
    expect(names, contains('images/$imageName'));
  });

  test('data.json 保留全部字段，供以后做导入', () async {
    final subjects = await repo.listSubjects();
    final Subject yunchou = subjects.firstWhere((s) => s.name == '运筹');
    await repo.insertCard(
      StudyCard(
        type: CardType.formula,
        subjectId: yunchou.id,
        title: 'JSON 卡',
        content: '注释',
        createdAt: 40,
        updatedAt: 40,
      ),
    );

    final String raw = exportService.buildJson(
      cards: await repo.listCardsForExport(),
      subjects: subjects,
      now: DateTime(2026, 9, 22, 8, 30),
    );
    final Map<String, Object?> payload =
        jsonDecode(raw) as Map<String, Object?>;

    expect(payload['app'], '万能百宝箱');
    expect(payload['schemaVersion'], 1);
    expect(payload['exportedAtText'], '2026-09-22 08:30');
    expect((payload['subjects']! as List<Object?>).length, 5);

    final cards = payload['cards']! as List<Object?>;
    final jsonCard = cards
        .cast<Map<String, Object?>>()
        .firstWhere((c) => c['title'] == 'JSON 卡');
    expect(jsonCard['type'], CardType.formula);
    expect(jsonCard['subjectId'], yunchou.id);
    expect(jsonCard['content'], '注释');
    expect(jsonCard['pinned'], isFalse);
    expect(jsonCard['forgotCount'], 0);
  });

  test('导出文件名带日期', () {
    expect(
      exportService.zipFileName(DateTime(2026, 9, 22)),
      '万能百宝箱_公式手册_20260922.zip',
    );
  });
}
