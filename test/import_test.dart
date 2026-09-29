import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:baibaoxiang/data/app_database.dart';
import 'package:baibaoxiang/data/card_repository.dart';
import 'package:baibaoxiang/data/export_service.dart';
import 'package:baibaoxiang/data/image_store.dart';
import 'package:baibaoxiang/data/import_service.dart';
import 'package:baibaoxiang/models/study_card.dart';
import 'package:baibaoxiang/models/subject.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 导入这条链路：导出包 → 解包校验 → 图片落盘 → 事务写库。
///
/// 重点盯两件事：**合并不能弄丢本机已有的数据**，**覆盖要连旧图片一起清掉**。
void main() {
  late Directory tempDir;
  late AppDatabase database;
  late ImageStore images;
  late CardRepository repo;
  late ExportService exporter;
  late ImportService importer;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('baibaoxiang_import');
    database = AppDatabase(
      path: inMemoryDatabasePath,
      databaseFactoryOverride: databaseFactoryFfi,
    );
    images = ImageStore(tempDir);
    repo = CardRepository(database, images);
    exporter = ExportService(repo, images);
    importer = ImportService(repo, images);
    await database.open();
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 清空卡片和科目，从一张白纸开始（建库时种进来的示例数据也一并清掉）。
  Future<void> wipe() async {
    final db = await database.open();
    await db.delete('cards');
    await db.delete('subjects');
  }

  /// 造一张假图片丢进私有目录，返回它的文件名。
  Future<String> addImage(String fileName) async {
    final File source = File(p.join(tempDir.path, fileName))
      ..writeAsBytesSync(<int>[1, 2, 3, 4]);
    return images.import(source.path);
  }

  /// 造一份「另一台手机」的备份：一个科目、两张卡片（一张带图、一张是带标题的灵感）。
  Future<Uint8List> buildBackup() async {
    await wipe();
    final int subjectId = await repo.addSubject('运筹');
    final String imageName = await addImage('shot.jpg');
    await repo.insertCard(
      StudyCard(
        type: CardType.formula,
        subjectId: subjectId,
        title: '对偶单纯形法',
        content: '先从负检验数入基',
        images: <String>[imageName],
        createdAt: 10,
        updatedAt: 10,
      ),
    );
    await repo.insertCard(
      StudyCard(
        type: CardType.idea,
        title: '图论复习顺序',
        content: '先过一遍最短路，再看生成树',
        createdAt: 20,
        updatedAt: 20,
      ),
    );
    return exporter.buildZip(now: DateTime(2026, 9, 29, 10));
  }

  /// 换掉包里的 data.json，用来伪造「以后版本才有的数据」。
  Uint8List rewriteJson(
    Uint8List bytes,
    void Function(Map<String, Object?> payload) change,
  ) {
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final Archive out = Archive();
    for (final ArchiveFile file in archive.files) {
      final Uint8List content = file.content;
      if (file.name == ImportService.jsonFileName) {
        final Map<String, Object?> payload =
            jsonDecode(utf8.decode(content)) as Map<String, Object?>;
        change(payload);
        final List<int> encoded = utf8.encode(jsonEncode(payload));
        out.addFile(ArchiveFile(file.name, encoded.length, encoded));
      } else {
        out.addFile(ArchiveFile(file.name, content.length, content));
      }
    }
    return Uint8List.fromList(ZipEncoder().encode(out));
  }

  /// 去掉包里的 images/，用来伪造「图片丢了」。
  Uint8List dropImages(Uint8List bytes) {
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final Archive out = Archive();
    for (final ArchiveFile file in archive.files) {
      if (file.name.startsWith('${ImportService.imagesFolder}/')) continue;
      final Uint8List content = file.content;
      out.addFile(ArchiveFile(file.name, content.length, content));
    }
    return Uint8List.fromList(ZipEncoder().encode(out));
  }

  /// 取出 data.json 里的卡片，去掉 id / 科目 id / 图片名这三样导入后必然
  /// 会变的字段，用来比「数据内容本身」有没有变。
  List<Map<String, Object?>> cardContents(Uint8List zip) {
    final Archive archive = ZipDecoder().decodeBytes(zip);
    final ArchiveFile json = archive.files
        .firstWhere((ArchiveFile f) => f.name == ImportService.jsonFileName);
    final Map<String, Object?> payload =
        jsonDecode(utf8.decode(json.content)) as Map<String, Object?>;
    final List<Map<String, Object?>> cards =
        (payload['cards']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map((Map<String, Object?> card) => <String, Object?>{
                  for (final MapEntry<String, Object?> entry in card.entries)
                    if (entry.key != 'id' &&
                        entry.key != 'subjectId' &&
                        entry.key != 'images')
                      entry.key: entry.value,
                })
            .toList();
    cards.sort((Map<String, Object?> a, Map<String, Object?> b) =>
        (a['createdAt']! as int).compareTo(b['createdAt']! as int));
    return cards;
  }

  test('导入前先看清包里有什么，且一个字都不写进库', () async {
    final Uint8List bytes = await buildBackup();
    await wipe();

    final ImportPreview preview = await importer.inspect(bytes);

    expect(preview.cardCount, 2);
    expect(preview.subjectCount, 1);
    expect(preview.imageCount, 1);
    expect(preview.countByType[CardType.idea], 1);
    expect(preview.exportedAtText, '2026-09-29 10:00');
    expect(await repo.listCardsForExport(), isEmpty);
  });

  test('导进空库：卡片、科目和图片都回来了', () async {
    final Uint8List bytes = await buildBackup();
    await wipe();

    final ImportResult result = await importer.run(bytes, mode: ImportMode.merge);

    expect(result.cardsImported, 2);
    expect(result.subjectsCreated, 1);
    expect(result.imagesImported, 1);
    expect(result.warnings, isEmpty);

    final List<StudyCard> cards = await repo.listCardsForExport();
    expect(cards.length, 2);
    final StudyCard formula =
        cards.firstWhere((StudyCard c) => c.type == CardType.formula);
    expect(formula.title, '对偶单纯形法');
    expect(formula.content, '先从负检验数入基');
    expect(formula.images.length, 1);
    // 图片按包里的名字落回私有目录，卡片指向的就是那个文件。
    expect(images.fileOf(formula.images.first).existsSync(), isTrue);

    final List<Subject> subjects = await repo.listSubjects();
    expect(subjects.single.name, '运筹');
    expect(formula.subjectId, subjects.single.id);
  });

  test('合并导入：本机数据一条不丢，同名科目不会重复', () async {
    final Uint8List bytes = await buildBackup();

    // 目标手机上已经有一条自己的数据，科目名还正好和包里那个重名。
    await wipe();
    final int mine = await repo.addSubject('运筹');
    await repo.insertCard(
      StudyCard(
        type: CardType.formula,
        subjectId: mine,
        title: '本机就有的公式',
        createdAt: 99,
        updatedAt: 99,
      ),
    );

    final ImportResult result = await importer.run(bytes, mode: ImportMode.merge);

    expect(result.cardsImported, 2);
    expect(result.subjectsCreated, 0, reason: '「运筹」已经存在，不该再建一个');
    final List<StudyCard> cards = await repo.listCardsForExport();
    expect(cards.length, 3);
    expect(cards.where((StudyCard c) => c.title == '本机就有的公式').length, 1);
    expect((await repo.listSubjects()).length, 1);
  });

  test('覆盖导入：旧卡片和旧图片一起消失', () async {
    final Uint8List bytes = await buildBackup();

    await wipe();
    final int mine = await repo.addSubject('高数');
    final String oldImage = await addImage('old.jpg');
    await repo.insertCard(
      StudyCard(
        type: CardType.formula,
        subjectId: mine,
        title: '要被覆盖掉的卡',
        images: <String>[oldImage],
        createdAt: 99,
        updatedAt: 99,
      ),
    );

    final ImportResult result =
        await importer.run(bytes, mode: ImportMode.replace);

    expect(result.cardsImported, 2);
    final List<StudyCard> cards = await repo.listCardsForExport();
    expect(cards.length, 2);
    expect(cards.any((StudyCard c) => c.title == '要被覆盖掉的卡'), isFalse);
    expect(images.fileOf(oldImage).existsSync(), isFalse, reason: '旧图片要跟着删');
    expect((await repo.listSubjects()).single.name, '运筹');
  });

  test('不是备份包就明说，且不动库里的数据', () async {
    await expectLater(
      importer.inspect(Uint8List.fromList(<int>[1, 2, 3, 4])),
      throwsA(isA<ImportException>()),
    );

    final Archive archive = Archive()
      ..addFile(ArchiveFile('readme.txt', 5, utf8.encode('hello')));
    final Uint8List noJson =
        Uint8List.fromList(ZipEncoder().encode(archive));
    await expectLater(
      importer.run(noJson, mode: ImportMode.merge),
      throwsA(isA<ImportException>()),
    );

    // 建库时种的三条示例公式还在，说明上面两次失败没写进去任何东西。
    expect((await repo.listCardsForExport()).length, 3);
  });

  test('包里的图片丢了：卡片照常导入，只提示一句', () async {
    final Uint8List bytes = await buildBackup();
    final Uint8List noImages = dropImages(bytes);
    await wipe();

    final ImportResult result =
        await importer.run(noImages, mode: ImportMode.merge);

    expect(result.cardsImported, 2);
    expect(result.imagesImported, 0);
    expect(result.warnings, isNotEmpty);
    final StudyCard formula = (await repo.listCardsForExport())
        .firstWhere((StudyCard c) => c.type == CardType.formula);
    expect(formula.images, isEmpty);
  });

  test('包里出现这个版本还不认识的功能：跳过那几条，其余照常导入', () async {
    final Uint8List bytes = await buildBackup();
    final Uint8List withUnknown =
        rewriteJson(bytes, (Map<String, Object?> payload) {
      (payload['cards']! as List<Object?>).add(<String, Object?>{
        'type': '考点',
        'title': '以后才有的功能',
        'createdAt': 30,
        'updatedAt': 30,
      });
    });
    await wipe();

    final ImportResult result =
        await importer.run(withUnknown, mode: ImportMode.merge);

    expect(result.cardsImported, 2);
    expect(result.warnings, isNotEmpty);
    expect(
      (await repo.listCardsForExport())
          .any((StudyCard c) => c.type == '考点'),
      isFalse,
    );
  });

  test('数据版本比本机新：拒绝导入，并说清楚原因', () async {
    final Uint8List bytes = await buildBackup();
    final Uint8List tooNew = rewriteJson(bytes, (Map<String, Object?> payload) {
      payload['schemaVersion'] = 2;
    });

    await expectLater(
      importer.run(tooNew, mode: ImportMode.merge),
      throwsA(
        isA<ImportException>().having(
          (ImportException e) => e.message,
          'message',
          contains('更新版本'),
        ),
      ),
    );
  });

  test('改名前导出的老备份还能导进来', () async {
    final Uint8List bytes = await buildBackup();
    // 伪造一份 v0.6 那会儿的备份：data.json 里写的还是老名字。
    final Uint8List old = rewriteJson(bytes, (Map<String, Object?> payload) {
      payload['app'] = '万能百宝箱';
    });
    await wipe();

    final ImportResult result = await importer.run(old, mode: ImportMode.merge);

    expect(result.cardsImported, 2);
    expect(result.warnings, isEmpty);
  });

  test('别人家的备份包还是会被拒', () async {
    final Uint8List bytes = await buildBackup();
    final Uint8List alien =
        rewriteJson(bytes, (Map<String, Object?> payload) {
      payload['app'] = '别人的备份';
    });

    await expectLater(
      importer.run(alien, mode: ImportMode.merge),
      throwsA(isA<ImportException>()),
    );
  });

  test('导出 → 导入 → 再导出：卡片内容一模一样', () async {
    final Uint8List first = await buildBackup();
    await wipe();

    await importer.run(first, mode: ImportMode.merge);
    final Uint8List second =
        await exporter.buildZip(now: DateTime(2026, 9, 29, 10));

    expect(cardContents(second), cardContents(first));
  });
}
