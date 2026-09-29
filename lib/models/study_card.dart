import 'dart:convert';

/// 卡片类型。v0 只实现「公式」，其余几个值先占着，数据模型不用再改。
abstract final class CardType {
  static const String formula = '公式';
  static const String idea = '灵感';
  static const String memory = '记忆';
  static const String mistake = '错题';
  static const String question = '问题';

  /// 首页六宫格和搜索分组的展示顺序。
  static const List<String> all = <String>[
    formula,
    idea,
    memory,
    mistake,
    question,
  ];
}

const Object _unset = Object();

/// 一张卡片。公式手册只是它的一个视图。
class StudyCard {
  const StudyCard({
    this.id,
    required this.type,
    this.subjectId,
    this.title,
    this.content,
    this.images = const <String>[],
    this.tags = const <String>[],
    this.pinned = false,
    required this.createdAt,
    required this.updatedAt,
    this.reviewedAt,
    this.forgotCount = 0,
    this.deletedAt,
  });

  final int? id;
  final String type;

  /// null 表示未分类。
  final int? subjectId;
  final String? title;
  final String? content;

  /// 只存文件名，实际路径由 ImageStore 在运行时解析。
  final List<String> images;
  final List<String> tags;
  final bool pinned;
  final int createdAt;
  final int updatedAt;
  final int? reviewedAt;
  final int forgotCount;

  /// null 表示正常；非 null 表示在回收站里，值是删除时间。
  final int? deletedAt;

  bool get isDeleted => deletedAt != null;

  /// 正文 / 答案里有没有真东西。
  ///
  /// 「问题收集箱」靠它派生状态：没答案就是待解决，回填了答案就是已解决。
  /// 只打了空格和换行的算没写——不然一条空卡会莫名其妙变成「已解决」。
  bool get hasContent => (content ?? '').trim().isNotEmpty;

  /// 列表里显示的标题：没标题就退到注释首行。
  String get displayTitle {
    final String t = (title ?? '').trim();
    if (t.isNotEmpty) return t;
    final String c = (content ?? '').trim();
    if (c.isEmpty) return '（无标题）';
    final int br = c.indexOf('\n');
    return br == -1 ? c : c.substring(0, br);
  }

  /// 列表第二行。标题已经用掉了就把注释整体作为副标题。
  String get displaySubtitle {
    final String c = (content ?? '').replaceAll('\n', ' ').trim();
    if (c.isEmpty) return '';
    if ((title ?? '').trim().isEmpty) return '';
    return c;
  }

  factory StudyCard.fromMap(Map<String, Object?> map) => StudyCard(
        id: map['id'] as int?,
        type: map['type']! as String,
        subjectId: map['subject_id'] as int?,
        title: map['title'] as String?,
        content: map['content'] as String?,
        images: _decodeList(map['images']),
        tags: _decodeList(map['tags']),
        pinned: ((map['pinned'] as int?) ?? 0) != 0,
        createdAt: (map['created_at'] as int?) ?? 0,
        updatedAt: (map['updated_at'] as int?) ?? 0,
        reviewedAt: map['reviewed_at'] as int?,
        forgotCount: (map['forgot_count'] as int?) ?? 0,
        deletedAt: map['deleted_at'] as int?,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'type': type,
        'subject_id': subjectId,
        'title': title,
        'content': content,
        'images': jsonEncode(images),
        'tags': jsonEncode(tags),
        'pinned': pinned ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'reviewed_at': reviewedAt,
        'forgot_count': forgotCount,
        'deleted_at': deletedAt,
      };

  StudyCard copyWith({
    int? id,
    String? type,
    Object? subjectId = _unset,
    Object? title = _unset,
    Object? content = _unset,
    List<String>? images,
    List<String>? tags,
    bool? pinned,
    int? createdAt,
    int? updatedAt,
    Object? reviewedAt = _unset,
    int? forgotCount,
    Object? deletedAt = _unset,
  }) {
    return StudyCard(
      id: id ?? this.id,
      type: type ?? this.type,
      subjectId:
          identical(subjectId, _unset) ? this.subjectId : subjectId as int?,
      title: identical(title, _unset) ? this.title : title as String?,
      content: identical(content, _unset) ? this.content : content as String?,
      images: images ?? this.images,
      tags: tags ?? this.tags,
      pinned: pinned ?? this.pinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reviewedAt:
          identical(reviewedAt, _unset) ? this.reviewedAt : reviewedAt as int?,
      forgotCount: forgotCount ?? this.forgotCount,
      deletedAt:
          identical(deletedAt, _unset) ? this.deletedAt : deletedAt as int?,
    );
  }

  static List<String> _decodeList(Object? raw) {
    if (raw is! String || raw.isEmpty) return const <String>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
    } on FormatException {
      // 数据坏了就当空列表，不要让整个列表页崩掉。
    }
    return const <String>[];
  }
}
