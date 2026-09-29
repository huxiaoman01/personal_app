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

  /// 每个功能出自己的一份 Markdown，以后做完一个新功能就多一个文件。
  static const String formulaMarkdownFileName = '公式手册.md';
  static const String ideaMarkdownFileName = '灵感记录.md';
  static const String memoryMarkdownFileName = '记忆卡片.md';
  static const String mistakeMarkdownFileName = '错题本.md';
  static const String questionMarkdownFileName = '问题收集箱.md';
  static const String jsonFileName = 'data.json';
  static const String imagesFolder = 'images';

  String zipFileName(DateTime now) =>
      '万能百宝箱_${DateFormat('yyyyMMdd').format(now)}.zip';

  Future<Uint8List> buildZip({required DateTime now}) async {
    final List<StudyCard> cards = await _repository.listCardsForExport();
    final List<Subject> subjects = await _repository.listSubjects();

    final Archive archive = Archive()
      ..addFile(_textFile(
        formulaMarkdownFileName,
        buildFormulaMarkdown(
          cards: _ofType(cards, CardType.formula),
          subjects: subjects,
          now: now,
        ),
      ))
      ..addFile(_textFile(
        ideaMarkdownFileName,
        buildIdeaMarkdown(
          cards: _ofType(cards, CardType.idea),
          now: now,
        ),
      ))
      ..addFile(_textFile(
        memoryMarkdownFileName,
        buildNotebookMarkdown(
          heading: '记忆卡片',
          cards: _ofType(cards, CardType.memory),
          subjects: subjects,
          now: now,
        ),
      ))
      ..addFile(_textFile(
        mistakeMarkdownFileName,
        buildNotebookMarkdown(
          heading: '错题本',
          cards: _ofType(cards, CardType.mistake),
          subjects: subjects,
          now: now,
        ),
      ))
      ..addFile(_textFile(
        questionMarkdownFileName,
        buildQuestionMarkdown(
          cards: _ofType(cards, CardType.question),
          subjects: subjects,
          now: now,
        ),
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

  /// 公式手册的 Markdown：按科目分节，顺序跟科目排序一致。
  String buildFormulaMarkdown({
    required List<StudyCard> cards,
    required List<Subject> subjects,
    required DateTime now,
  }) {
    final StringBuffer out = _header('公式手册', cards.length, now);

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

  /// 灵感记录的 Markdown：不分节，先置顶、再按创建时间倒序。
  ///
  /// 标题是选填的：填了就拿它当小标题，时间挪到下面一行小字；
  /// 没填的（含所有老灵感）仍然拿创建时间当小标题——总不能拿正文首行
  /// 当标题，那句话在正文里会再出现一遍。
  String buildIdeaMarkdown({
    required List<StudyCard> cards,
    required DateTime now,
  }) {
    final StringBuffer out = _header('灵感记录', cards.length, now);

    for (final StudyCard card in cards) {
      final String stamp = DateFormat('yyyy-MM-dd HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch(card.createdAt),
      );
      final String title = (card.title ?? '').trim();
      final String mark = card.pinned ? '（置顶）' : '';
      if (title.isEmpty) {
        out
          ..writeln('### $stamp$mark')
          ..writeln();
      } else {
        out
          ..writeln('### $title$mark')
          ..writeln()
          ..writeln('> $stamp')
          ..writeln();
      }

      if (card.tags.isNotEmpty) {
        out
          ..writeln('标签：${card.tags.join('、')}')
          ..writeln();
      }
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
    return out.toString();
  }

  /// 「卡片库 + 复习」这两个功能的 Markdown：和公式手册一样按科目分节，
  /// 标题做小标题（背的时候正好用），下面就是正文
  /// ——记忆卡片的正文是答案，错题本的正文是「我当时错在哪」。
  String buildNotebookMarkdown({
    required String heading,
    required List<StudyCard> cards,
    required List<Subject> subjects,
    required DateTime now,
  }) {
    final StringBuffer out = _header(heading, cards.length, now);

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

  /// 问题收集箱的 Markdown：按科目分节，问题做小标题，答案是正文。
  /// 还没答案的那条在标题后面标一句「（待解决）」，导出去也一眼看得出来。
  String buildQuestionMarkdown({
    required List<StudyCard> cards,
    required List<Subject> subjects,
    required DateTime now,
  }) {
    final StringBuffer out = _header('问题收集箱', cards.length, now);

    for (final _SubjectGroup group in _groupBySubject(cards, subjects)) {
      if (group.cards.isEmpty) continue;
      out
        ..writeln('## ${group.name}')
        ..writeln();
      for (final StudyCard card in group.cards) {
        final String mark = card.hasContent ? '' : '（待解决）';
        out
          ..writeln('### ${card.displayTitle}$mark')
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

  /// 每个功能一份 Markdown 的开头部分，几处共用。
  StringBuffer _header(String title, int count, DateTime now) {
    final String stamp = DateFormat('yyyy-MM-dd HH:mm').format(now);
    return StringBuffer()
      ..writeln('# $title')
      ..writeln()
      ..writeln('> 导出时间：$stamp　共 $count 条')
      ..writeln();
  }

  List<StudyCard> _ofType(List<StudyCard> cards, String type) =>
      cards.where((StudyCard c) => c.type == type).toList(growable: false);

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
