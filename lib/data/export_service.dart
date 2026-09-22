import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';

import '../models/study_card.dart';
import '../models/subject.dart';
import 'card_repository.dart';
import 'image_store.dart';

/// 导出 Markdown + 图片 zip。给定同样的数据，输出是确定的，方便单测。
class ExportService {
  ExportService(this._repository, this._images);

  final CardRepository _repository;
  final ImageStore _images;

  static const String markdownFileName = '公式手册.md';
  static const String jsonFileName = 'data.json';
  static const String imagesFolder = 'images';

  String zipFileName(DateTime now) =>
      '万能百宝箱_公式手册_${DateFormat('yyyyMMdd').format(now)}.zip';

  Future<Uint8List> buildZip({required DateTime now}) async {
    final List<StudyCard> cards = await _repository.listCardsForExport();
    final List<Subject> subjects = await _repository.listSubjects();

    final Archive archive = Archive()
      ..addFile(_textFile(
        markdownFileName,
        buildMarkdown(cards: cards, subjects: subjects, now: now),
      ))
      ..addFile(_textFile(
        jsonFileName,
        buildJson(cards: cards, subjects: subjects, now: now),
      ));

    final Set<String> seen = <String>{};
    for (final StudyCard card in cards) {
      for (final String name in card.images) {
        if (!seen.add(name)) continue;
        final file = _images.fileOf(name);
        if (!await file.exists()) continue;
        final Uint8List bytes = await file.readAsBytes();
        archive.addFile(
          ArchiveFile('$imagesFolder/$name', bytes.length, bytes),
        );
      }
    }

    final List<int> encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  String buildMarkdown({
    required List<StudyCard> cards,
    required List<Subject> subjects,
    required DateTime now,
  }) {
    final String stamp = DateFormat('yyyy-MM-dd HH:mm').format(now);
    final StringBuffer out = StringBuffer()
      ..writeln('# 公式手册')
      ..writeln()
      ..writeln('> 导出时间：$stamp　共 ${cards.length} 条')
      ..writeln();

    for (final _SubjectGroup group in _groupBySubject(cards, subjects)) {
      if (group.cards.isEmpty) continue;
      out
        ..writeln('## ${group.name}')
        ..writeln();
      for (final StudyCard card in group.cards) {
        out
          ..writeln('### ${card.displayTitle}')
          ..writeln();
        for (int i = 0; i < card.images.length; i++) {
          out
            ..writeln('![图${i + 1}]($imagesFolder/${card.images[i]})')
            ..writeln();
        }
        final String content = (card.content ?? '').trim();
        if (content.isNotEmpty) {
          out
            ..writeln(content)
            ..writeln();
        }
        out
          ..writeln('---')
          ..writeln();
      }
    }
    return out.toString();
  }

  String buildJson({
    required List<StudyCard> cards,
    required List<Subject> subjects,
    required DateTime now,
  }) {
    final Map<String, Object?> payload = <String, Object?>{
      'app': '万能百宝箱',
      'schemaVersion': 1,
      'exportedAt': now.millisecondsSinceEpoch,
      'exportedAtText': DateFormat('yyyy-MM-dd HH:mm').format(now),
      'subjects': <Map<String, Object?>>[
        for (final Subject s in subjects)
          <String, Object?>{
            'id': s.id,
            'name': s.name,
            'sortOrder': s.sortOrder,
          },
      ],
      'cards': <Map<String, Object?>>[
        for (final StudyCard c in cards)
          <String, Object?>{
            'id': c.id,
            'type': c.type,
            'subjectId': c.subjectId,
            'title': c.title,
            'content': c.content,
            'images': c.images,
            'tags': c.tags,
            'pinned': c.pinned,
            'createdAt': c.createdAt,
            'updatedAt': c.updatedAt,
            'reviewedAt': c.reviewedAt,
            'forgotCount': c.forgotCount,
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// 按科目分组，顺序跟科目排序一致，「未分类」排最后。
  List<_SubjectGroup> _groupBySubject(
    List<StudyCard> cards,
    List<Subject> subjects,
  ) {
    return <_SubjectGroup>[
      for (final Subject s in subjects)
        _SubjectGroup(s.name, <StudyCard>[
          for (final StudyCard c in cards)
            if (c.subjectId == s.id) c,
        ]),
      _SubjectGroup('未分类', <StudyCard>[
        for (final StudyCard c in cards)
          if (c.subjectId == null) c,
      ]),
    ];
  }

  ArchiveFile _textFile(String name, String content) {
    final List<int> bytes = utf8.encode(content);
    return ArchiveFile(name, bytes.length, bytes);
  }
}

class _SubjectGroup {
  const _SubjectGroup(this.name, this.cards);

  final String name;
  final List<StudyCard> cards;
}
