import 'package:sqflite/sqflite.dart';

import '../models/study_card.dart';
import '../models/subject.dart';
import 'app_database.dart';
import 'image_store.dart';

/// 科目筛选的三种状态：全部 / 某个科目 / 未分类。
class SubjectFilter {
  const SubjectFilter.all()
      : subjectId = null,
        isUncategorized = false;

  const SubjectFilter.uncategorized()
      : subjectId = null,
        isUncategorized = true;

  const SubjectFilter.one(int id)
      : subjectId = id,
        isUncategorized = false;

  final int? subjectId;
  final bool isUncategorized;

  String get key {
    if (isUncategorized) return 'none';
    final int? id = subjectId;
    return id == null ? 'all' : 'id:$id';
  }
}

/// 所有数据访问都走这里，页面不直接碰 SQL。
class CardRepository {
  CardRepository(this._database, this._images);

  final AppDatabase _database;
  final ImageStore _images;

  /// 回收站保留天数。
  static const int trashRetentionDays = 30;

  Future<Database> get _db => _database.open();

  // ---------------------------------------------------------------- 卡片

  Future<int> insertCard(StudyCard card) async {
    final Database db = await _db;
    final Map<String, Object?> values = card.toMap()..remove('id');
    return db.insert('cards', values);
  }

  Future<void> updateCard(StudyCard card) async {
    final Database db = await _db;
    final Map<String, Object?> values = card.toMap()..remove('id');
    await db.update(
      'cards',
      values,
      where: 'id = ?',
      whereArgs: <Object?>[card.id],
    );
  }

  Future<StudyCard?> getCard(int id) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'cards',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return StudyCard.fromMap(rows.first);
  }

  Future<void> setPinned(int id, bool pinned) async {
    final Database db = await _db;
    await db.update(
      'cards',
      <String, Object?>{
        'pinned': pinned ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 列表查询。置顶在前，其余按创建时间倒序。
  Future<List<StudyCard>> listCards({
    String? type,
    SubjectFilter subject = const SubjectFilter.all(),
    String keyword = '',
    bool trashed = false,
  }) async {
    final Database db = await _db;
    final StringBuffer sql = StringBuffer(
      'SELECT c.* FROM cards c '
      'LEFT JOIN subjects s ON s.id = c.subject_id WHERE ',
    );
    final List<Object?> args = <Object?>[];

    sql.write(trashed ? 'c.deleted_at IS NOT NULL' : 'c.deleted_at IS NULL');

    if (type != null) {
      sql.write(' AND c.type = ?');
      args.add(type);
    }
    if (subject.isUncategorized) {
      sql.write(' AND c.subject_id IS NULL');
    } else if (subject.subjectId != null) {
      sql.write(' AND c.subject_id = ?');
      args.add(subject.subjectId);
    }

    final String trimmed = keyword.trim();
    if (trimmed.isNotEmpty) {
      sql.write(' AND (c.title LIKE ? OR c.content LIKE ? OR s.name LIKE ?)');
      final String like = '%$trimmed%';
      args.addAll(<Object?>[like, like, like]);
    }

    sql.write(
      trashed
          ? ' ORDER BY c.deleted_at DESC'
          : ' ORDER BY c.pinned DESC, c.created_at DESC',
    );

    final List<Map<String, Object?>> rows =
        await db.rawQuery(sql.toString(), args);
    return rows.map(StudyCard.fromMap).toList(growable: false);
  }

  /// 首页统计：每种类型各有多少张（不含回收站）。
  Future<Map<String, int>> countByType() async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT type, COUNT(*) AS n FROM cards '
      'WHERE deleted_at IS NULL GROUP BY type',
    );
    return <String, int>{
      for (final Map<String, Object?> row in rows)
        row['type']! as String: (row['n'] as int?) ?? 0,
    };
  }

  /// 导出用：所有未删除的卡片。
  Future<List<StudyCard>> listCardsForExport() =>
      listCards(subject: const SubjectFilter.all());

  // -------------------------------------------------------------- 回收站

  Future<void> moveToTrash(int id) async {
    final Database db = await _db;
    await db.update(
      'cards',
      <String, Object?>{'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> restoreFromTrash(int id) async {
    final Database db = await _db;
    await db.update(
      'cards',
      <String, Object?>{'deleted_at': null},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 彻底删除：连图片文件一起清掉。
  Future<void> deleteForever(int id) async {
    final Database db = await _db;
    final StudyCard? card = await getCard(id);
    if (card == null) return;
    await db.delete('cards', where: 'id = ?', whereArgs: <Object?>[id]);
    await _images.deleteAll(card.images);
  }

  Future<void> emptyTrash() async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'cards',
      where: 'deleted_at IS NOT NULL',
    );
    for (final Map<String, Object?> row in rows) {
      await _images.deleteAll(StudyCard.fromMap(row).images);
    }
    await db.delete('cards', where: 'deleted_at IS NOT NULL');
  }

  /// 清掉超过保留期的回收站记录，返回清理条数。
  /// [now] 显式传入，方便单测卡边界。
  Future<int> purgeExpired({required DateTime now}) async {
    final Database db = await _db;
    final int cutoff = now
        .subtract(const Duration(days: trashRetentionDays))
        .millisecondsSinceEpoch;
    final List<Map<String, Object?>> rows = await db.query(
      'cards',
      where: 'deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: <Object?>[cutoff],
    );
    for (final Map<String, Object?> row in rows) {
      final StudyCard card = StudyCard.fromMap(row);
      await _images.deleteAll(card.images);
      await db.delete('cards', where: 'id = ?', whereArgs: <Object?>[card.id]);
    }
    return rows.length;
  }

  // ---------------------------------------------------------------- 科目

  Future<List<Subject>> listSubjects() async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'subjects',
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(Subject.fromMap).toList(growable: false);
  }

  Future<int> addSubject(String name) async {
    final Database db = await _db;
    final List<Map<String, Object?>> maxRow = await db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) AS m FROM subjects',
    );
    final int next = ((maxRow.first['m'] as int?) ?? -1) + 1;
    return db.insert(
      'subjects',
      <String, Object?>{'name': name, 'sort_order': next},
    );
  }

  Future<void> renameSubject(int id, String name) async {
    final Database db = await _db;
    await db.update(
      'subjects',
      <String, Object?>{'name': name},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 删除科目：把它的卡片变成未分类，再删掉科目本身。返回受影响的卡片数。
  Future<int> deleteSubject(int id) async {
    final int affected = await countCardsInSubject(id);
    final Database db = await _db;
    await db.transaction((Transaction txn) async {
      await txn.update(
        'cards',
        <String, Object?>{'subject_id': null},
        where: 'subject_id = ?',
        whereArgs: <Object?>[id],
      );
      await txn.delete('subjects', where: 'id = ?', whereArgs: <Object?>[id]);
    });
    return affected;
  }

  Future<int> countCardsInSubject(int id) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM cards '
      'WHERE subject_id = ? AND deleted_at IS NULL',
      <Object?>[id],
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  /// 按传入的 id 顺序重排科目。
  Future<void> reorderSubjects(List<int> orderedIds) async {
    final Database db = await _db;
    await db.transaction((Transaction txn) async {
      for (int i = 0; i < orderedIds.length; i++) {
        await txn.update(
          'subjects',
          <String, Object?>{'sort_order': i},
          where: 'id = ?',
          whereArgs: <Object?>[orderedIds[i]],
        );
      }
    });
  }
}
