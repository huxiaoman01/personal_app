import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:baibaoxiang/app_identity.dart';
import 'package:baibaoxiang/data/app_database.dart';
import 'package:baibaoxiang/data/card_repository.dart';
import 'package:baibaoxiang/data/export_service.dart';
import 'package:baibaoxiang/data/image_store.dart';
import 'package:baibaoxiang/models/study_card.dart';
import 'package:baibaoxiang/models/subject.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
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

  /// 某一种类型的卡片——导出现在按功能分文件，测试也得按类型取。
  Future<List<StudyCard>> cardsOfType(String type) async {
    final List<StudyCard> all = await repo.listCardsForExport();
    return all.where((StudyCard c) => c.type == type).toList();
  }

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

    final String markdown = exportService.buildFormulaMarkdown(
      cards: await cardsOfType(CardType.formula),
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

    final String markdown = exportService.buildFormulaMarkdown(
      cards: await cardsOfType(CardType.formula),
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

    expect(names, contains(ExportService.formulaMarkdownFileName));
    expect(names, contains(ExportService.ideaMarkdownFileName));
    expect(names, contains(ExportService.memoryMarkdownFileName));
    expect(names, contains(ExportService.mistakeMarkdownFileName));
    expect(names, contains(ExportService.questionMarkdownFileName));
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

    expect(payload['app'], AppIdentity.backupId);
    expect(payload['app'], '可可嫑记');
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
      '可可嫑记_20260922.zip',
    );
    // 筛过东西的包带「部分」两个字，一眼能区分。
    expect(
      exportService.zipFileName(DateTime(2026, 9, 22), partial: true),
      '可可嫑记_部分_20260922.zip',
    );
  });

  test('灵感记录 Markdown：有标题用标题，没标题才用创建时间', () async {
    await repo.insertCard(
      StudyCard(
        type: CardType.idea,
        content: '先写的',
        tags: <String>['运筹', '易错'],
        createdAt: 100,
        updatedAt: 100,
      ),
    );
    final int pinnedId = await repo.insertCard(
      StudyCard(
        type: CardType.idea,
        content: '后写的',
        createdAt: 200,
        updatedAt: 200,
      ),
    );
    await repo.setPinned(pinnedId, true);
    await repo.insertCard(
      StudyCard(
        type: CardType.idea,
        title: '图论复习顺序',
        content: '先过一遍最短路，再看生成树',
        createdAt: 300,
        updatedAt: 300,
      ),
    );

    final String markdown = exportService.buildIdeaMarkdown(
      cards: await cardsOfType(CardType.idea),
      now: DateTime(2026, 9, 22, 9),
    );

    expect(markdown, startsWith('# 灵感记录'));
    expect(markdown, contains('共 3 条'));
    expect(markdown, contains('标签：运筹、易错'));
    // 没标题的（含所有老灵感）小标题仍然用创建时间，置顶的标一下。
    final String stamp = DateFormat('yyyy-MM-dd HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(200),
    );
    expect(markdown, contains('### $stamp（置顶）'));
    expect(markdown, contains('后写的'));
    // 有标题就拿标题当小标题，时间挪到下面一行小字里，正文不再重复一遍。
    expect(markdown, contains('### 图论复习顺序'));
    final String titledStamp = DateFormat('yyyy-MM-dd HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(300),
    );
    expect(markdown, contains('> $titledStamp'));
    // 灵感不绑科目，所以一个 ## 分节都不该有。
    expect(markdown, isNot(contains('\n## ')));
  });

  test('记忆卡片 Markdown：按科目分节，题目做小标题，答案是正文', () async {
    final subjects = await repo.listSubjects();
    final Subject yunchou = subjects.firstWhere((s) => s.name == '运筹');
    await repo.insertCard(
      StudyCard(
        type: CardType.memory,
        subjectId: yunchou.id,
        title: '单纯形法的判别准则是什么？',
        content: '检验数 σj ≤ 0 时达到最优解。',
        forgotCount: 2,
        createdAt: 50,
        updatedAt: 50,
      ),
    );

    final String markdown = exportService.buildNotebookMarkdown(
      heading: '记忆卡片',
      cards: await cardsOfType(CardType.memory),
      subjects: subjects,
      now: DateTime(2026, 9, 23, 10),
    );

    expect(markdown, startsWith('# 记忆卡片'));
    expect(markdown, contains('共 1 条'));
    expect(markdown, contains('## 运筹'));
    expect(markdown, contains('### 单纯形法的判别准则是什么？'));
    expect(markdown, contains('检验数 σj ≤ 0 时达到最优解。'));
  });

  test('错题本 Markdown：同一个方法，标题和正文换成错题的说法', () async {
    final subjects = await repo.listSubjects();
    final Subject yunchou = subjects.firstWhere((s) => s.name == '运筹');
    await repo.insertCard(
      StudyCard(
        type: CardType.mistake,
        subjectId: yunchou.id,
        title: '对偶单纯形法那题',
        content: '符号搞反了，应该先看检验数',
        forgotCount: 1,
        createdAt: 60,
        updatedAt: 60,
      ),
    );

    final String markdown = exportService.buildNotebookMarkdown(
      heading: '错题本',
      cards: await cardsOfType(CardType.mistake),
      subjects: subjects,
      now: DateTime(2026, 9, 23, 10),
    );

    expect(markdown, startsWith('# 错题本'));
    expect(markdown, contains('共 1 条'));
    expect(markdown, contains('## 运筹'));
    expect(markdown, contains('### 对偶单纯形法那题'));
    expect(markdown, contains('符号搞反了，应该先看检验数'));
  });

  test('问题收集箱 Markdown：还没答案的标成待解决', () async {
    final subjects = await repo.listSubjects();
    final Subject yunchou = subjects.firstWhere((s) => s.name == '运筹');
    await repo.insertCard(
      StudyCard(
        type: CardType.question,
        subjectId: yunchou.id,
        title: '为什么要有人工变量',
        createdAt: 70,
        updatedAt: 70,
      ),
    );
    await repo.insertCard(
      StudyCard(
        type: CardType.question,
        title: '单纯形法和两阶段法的关系',
        content: '两阶段法先造人工变量凑初始基',
        createdAt: 71,
        updatedAt: 71,
      ),
    );

    final String markdown = exportService.buildQuestionMarkdown(
      cards: await cardsOfType(CardType.question),
      subjects: subjects,
      now: DateTime(2026, 9, 23, 10),
    );

    expect(markdown, startsWith('# 问题收集箱'));
    expect(markdown, contains('共 2 条'));
    expect(markdown, contains('## 运筹'));
    expect(markdown, contains('### 为什么要有人工变量（待解决）'));
    expect(markdown, contains('### 单纯形法和两阶段法的关系'));
    expect(markdown, contains('两阶段法先造人工变量凑初始基'));
  });

  // ---------------------------------------------------------------- 挑选导出

  /// 导出包里都有哪些文件。
  List<String> zipFileNames(Uint8List bytes) => ZipDecoder()
      .decodeBytes(bytes)
      .files
      .map((ArchiveFile f) => f.name)
      .toList();

  /// data.json 里那些卡片的标题。
  List<String> titlesIn(Uint8List bytes) {
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final ArchiveFile json = archive.files
        .firstWhere((ArchiveFile f) => f.name == ExportService.jsonFileName);
    final Map<String, Object?> payload =
        jsonDecode(utf8.decode(json.content)) as Map<String, Object?>;
    return (payload['cards']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map((Map<String, Object?> c) => c['title']! as String)
        .toList();
  }

  test('只挑一个功能导出：别的功能一个字都不出', () async {
    final subjects = await repo.listSubjects();
    await repo.insertCard(
      StudyCard(
        type: CardType.idea,
        title: '只要这条灵感',
        createdAt: 500,
        updatedAt: 500,
      ),
    );
    await repo.insertCard(
      StudyCard(
        type: CardType.formula,
        subjectId: subjects.first.id,
        title: '不该出现的公式',
        createdAt: 501,
        updatedAt: 501,
      ),
    );

    final Uint8List bytes = await exportService.buildZip(
      now: DateTime(2026, 9, 29),
      selection: const ExportSelection(
        types: <String>{CardType.idea},
        subjectIds: <int?>{null},
      ),
    );

    final List<String> names = zipFileNames(bytes);
    expect(names, contains(ExportService.ideaMarkdownFileName));
    expect(names, isNot(contains(ExportService.formulaMarkdownFileName)));
    expect(titlesIn(bytes), <String>['只要这条灵感']);
    // data.json 永远在——它是给导入用的，缺了这份备份就白做了。
    expect(names, contains(ExportService.jsonFileName));
  });

  test('只挑一个科目导出，未分类那一项包含所有灵感', () async {
    final subjects = await repo.listSubjects();
    final Subject yunchou = subjects.firstWhere((s) => s.name == '运筹');
    await repo.insertCard(
      StudyCard(
        type: CardType.formula,
        subjectId: yunchou.id,
        title: '只属于运筹的公式',
        createdAt: 600,
        updatedAt: 600,
      ),
    );
    await repo.insertCard(
      StudyCard(
        type: CardType.idea,
        title: '没有科目的灵感',
        createdAt: 601,
        updatedAt: 601,
      ),
    );

    // 只勾「运筹」：建库时种进来的线代、408 那两条要筛掉，灵感也要筛掉。
    final Uint8List onlyYunchou = await exportService.buildZip(
      now: DateTime(2026, 9, 29),
      selection: ExportSelection(
        types: CardType.all.toSet(),
        subjectIds: <int?>{yunchou.id},
      ),
    );
    final List<String> yunchouTitles = titlesIn(onlyYunchou);
    expect(yunchouTitles, contains('只属于运筹的公式'));
    expect(yunchouTitles, contains('单纯形法判别准则'));
    expect(yunchouTitles, isNot(contains('矩阵求逆')));
    expect(yunchouTitles, isNot(contains('补码转换')));
    expect(yunchouTitles, isNot(contains('没有科目的灵感')));

    // 只勾「未分类」：灵感归在这一项里，所以它在。
    final Uint8List onlyUncategorized = await exportService.buildZip(
      now: DateTime(2026, 9, 29),
      selection: ExportSelection(
        types: CardType.all.toSet(),
        subjectIds: const <int?>{null},
      ),
    );
    expect(titlesIn(onlyUncategorized), <String>['没有科目的灵感']);
  });

  test('什么都不筛时，导出内容和以前一模一样', () async {
    final Uint8List bytes =
        await exportService.buildZip(now: DateTime(2026, 9, 29));

    expect(
      zipFileNames(bytes),
      containsAll(<String>[
        ExportService.formulaMarkdownFileName,
        ExportService.ideaMarkdownFileName,
        ExportService.memoryMarkdownFileName,
        ExportService.mistakeMarkdownFileName,
        ExportService.questionMarkdownFileName,
        ExportService.jsonFileName,
      ]),
    );
    // 建库时种的三条示例公式，一条不少。
    expect(titlesIn(bytes).length, 3);
  });
}
