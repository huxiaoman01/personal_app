import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';

import '../models/study_card.dart';
import '../models/subject.dart';
import 'card_repository.dart';
import 'image_store.dart';

/// 导入方式。
enum ImportMode {
  /// 追加：现有数据一条不动，包里的卡片作为新卡插进来。
  merge,

  /// 覆盖：先清空现有卡片、科目和图片，再整包灌进去。
  replace,
}

/// 备份包的摘要——动手之前先让用户看一眼「包里有什么」。
class ImportPreview {
  const ImportPreview({
    required this.cardCount,
    required this.subjectCount,
    required this.imageCount,
    required this.exportedAt,
    required this.countByType,
  });

  final int cardCount;
  final int subjectCount;
  final int imageCount;

  /// 导出时间。老包可能没写这一项，那就是 null。
  final DateTime? exportedAt;

  /// 每种功能各多少条。
  final Map<String, int> countByType;

  String get exportedAtText => exportedAt == null
      ? '未知'
      : DateFormat('yyyy-MM-dd HH:mm').format(exportedAt!);
}

/// 导入结果。
class ImportResult {
  const ImportResult({
    required this.cardsImported,
    required this.subjectsCreated,
    required this.imagesImported,
    required this.warnings,
  });

  final int cardsImported;
  final int subjectsCreated;
  final int imagesImported;

  /// 「导进去了但有点小毛病」的地方，一条一句人话（缺图、不认识的功能）。
  final List<String> warnings;
}

/// 备份包本身有问题时抛这个，[message] 是能直接给用户看的一句话。
class ImportException implements Exception {
  ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 把导出的 zip 读回这台手机。
///
/// 顺序是刻意安排的：解包校验 → 图片先落盘 → 再在一个事务里写库 →
/// 事务成功之后才删旧图片。任何一步出岔子都会把刚落盘的图片删掉、库里回滚，
/// 宁可一条都没导进来，也不留半份数据。
class ImportService {
  ImportService(this._repository, this._images);

  final CardRepository _repository;
  final ImageStore _images;

  /// 认得的 `data.json` 版本号。比这个高说明包来自更新版本的 app，
  /// 那里面长什么样现在还不知道，别硬导。
  static const int supportedSchemaVersion = 1;

  static const String jsonFileName = 'data.json';
  static const String imagesFolder = 'images';

  /// 先看一眼包里有什么，不写任何数据。
  Future<ImportPreview> inspect(Uint8List bytes) async {
    final _Payload payload = _read(bytes);
    return ImportPreview(
      cardCount: payload.cards.length,
      subjectCount: payload.subjects.length,
      imageCount: payload.imageNames.length,
      exportedAt: payload.exportedAt,
      countByType: payload.countByType,
    );
  }

  /// 真正开始导入。
  Future<ImportResult> run(Uint8List bytes, {required ImportMode mode}) async {
    final _Payload payload = _read(bytes);
    final List<String> warnings = <String>[];

    // 覆盖模式要删的旧图片：先从库里把名字记下来，等数据库写成功才真删。
    final Set<String> oldImages = <String>{};
    if (mode == ImportMode.replace) {
      for (final StudyCard card in await _repository.listCardsForExport()) {
        oldImages.addAll(card.images);
      }
      // 回收站里的卡片不在导出列表里，但它们的图片还躺在私有目录。
      for (final StudyCard card in await _repository.listCards(trashed: true)) {
        oldImages.addAll(card.images);
      }
    }

    final List<String> written = <String>[];
    try {
      // 1) 图片先落盘。
      final Map<String, String> renamed = <String, String>{};
      final List<StudyCard> cards = <StudyCard>[];
      for (final StudyCard card in payload.cards) {
        if (!CardType.all.contains(card.type)) {
          warnings.add('有 ${card.type} 类型的卡片这个版本还不认识，已经跳过');
          continue;
        }
        final List<String> names = <String>[];
        for (final String oldName in card.images) {
          final Uint8List? data = payload.images[oldName];
          if (data == null) {
            warnings.add('有 1 张图片没在包里找到，对应的卡片少了那张图');
            continue;
          }
          // 同一张图被多张卡片引用时只落盘一次，省得多出一堆重复文件。
          String? newName = renamed[oldName];
          if (newName == null) {
            newName = await _images.writeBytes(oldName, data);
            renamed[oldName] = newName;
            written.add(newName);
          }
          names.add(newName);
        }
        cards.add(card.copyWith(images: names));
      }

      // 2) 写库。事务在 importPayload 里面，失败会整体回滚。
      final ({int subjectsCreated, int cardsImported}) result =
          await _repository.importPayload(
        subjects: payload.subjects,
        cards: cards,
        replace: mode == ImportMode.replace,
      );

      // 3) 数据已经稳了，覆盖模式这时候才清旧图。
      if (mode == ImportMode.replace) {
        await _images.deleteAll(oldImages);
      }

      return ImportResult(
        cardsImported: result.cardsImported,
        subjectsCreated: result.subjectsCreated,
        imagesImported: written.length,
        warnings: warnings,
      );
    } catch (_) {
      // 收拾掉刚落盘的图片，再把错误抛给界面去说明白。
      await _images.deleteAll(written);
      rethrow;
    }
  }

  // ------------------------------------------------------------ 解包与校验

  /// 解包并把所有「这个文件不对」一次性判掉。
  _Payload _read(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw ImportException('这个文件不是压缩包，或者已经损坏了');
    }

    final ArchiveFile? jsonFile = _fileNamed(archive, jsonFileName);
    if (jsonFile == null) {
      throw ImportException('包里没有 $jsonFileName，看起来不是万能百宝箱的备份');
    }

    final Map<String, Object?> payload;
    try {
      payload = jsonDecode(utf8.decode(jsonFile.content)) as Map<String, Object?>;
    } catch (_) {
      throw ImportException('$jsonFileName 读不出来，这个包可能传坏了');
    }

    if (payload['app'] != '万能百宝箱') {
      throw ImportException('这个压缩包不是万能百宝箱导出的');
    }
    final int version = (payload['schemaVersion'] as int?) ?? 1;
    if (version > supportedSchemaVersion) {
      throw ImportException(
        '这份备份来自更新版本的 app（数据版本 $version），先升级 app 再导入',
      );
    }

    final List<Subject> subjects = <Subject>[];
    for (final Object? raw in _asList(payload['subjects'])) {
      if (raw is! Map<String, Object?>) continue;
      final String name = (raw['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      subjects.add(Subject(
        // id 只是「导出机上的编号」，本机不用它，但得保证列表内唯一，
        // 所以没写 id 的时候就按顺序补一个。
        id: (raw['id'] as int?) ?? subjects.length,
        name: name,
        sortOrder: (raw['sortOrder'] as int?) ?? subjects.length,
      ));
    }

    final List<StudyCard> cards = <StudyCard>[];
    final Map<String, int> countByType = <String, int>{};
    for (final Object? raw in _asList(payload['cards'])) {
      if (raw is! Map<String, Object?>) continue;
      final String type = raw['type'] as String? ?? '';
      countByType[type] = (countByType[type] ?? 0) + 1;
      cards.add(StudyCard(
        type: type,
        subjectId: raw['subjectId'] as int?,
        title: raw['title'] as String?,
        content: raw['content'] as String?,
        images: _asStringList(raw['images']),
        tags: _asStringList(raw['tags']),
        pinned: (raw['pinned'] as bool?) ?? false,
        createdAt: (raw['createdAt'] as int?) ?? 0,
        updatedAt: (raw['updatedAt'] as int?) ?? 0,
        reviewedAt: raw['reviewedAt'] as int?,
        forgotCount: (raw['forgotCount'] as int?) ?? 0,
      ));
    }

    final Map<String, Uint8List> images = <String, Uint8List>{};
    for (final ArchiveFile file in archive.files) {
      if (!file.name.startsWith('$imagesFolder/')) continue;
      final String name = file.name.substring(imagesFolder.length + 1);
      if (name.isEmpty || name.endsWith('/')) continue;
      images[name] = file.content;
    }

    final int? exportedAt = payload['exportedAt'] as int?;
    return _Payload(
      subjects: subjects,
      cards: cards,
      images: images,
      countByType: countByType,
      exportedAt: exportedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(exportedAt),
    );
  }

  ArchiveFile? _fileNamed(Archive archive, String name) {
    for (final ArchiveFile file in archive.files) {
      if (file.name == name) return file;
    }
    return null;
  }

  List<Object?> _asList(Object? raw) =>
      raw is List ? raw.cast<Object?>() : const <Object?>[];

  List<String> _asStringList(Object? raw) => raw is List
      ? raw.whereType<String>().toList(growable: false)
      : const <String>[];
}

/// zip 解出来的原始内容，[import] 之前先在这里躺着，不动数据库。
class _Payload {
  const _Payload({
    required this.subjects,
    required this.cards,
    required this.images,
    required this.countByType,
    required this.exportedAt,
  });

  final List<Subject> subjects;
  final List<StudyCard> cards;

  /// 包里的图片：文件名 → 字节。
  final Map<String, Uint8List> images;
  final Map<String, int> countByType;
  final DateTime? exportedAt;

  Iterable<String> get imageNames => images.keys;
}
