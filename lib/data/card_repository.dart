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

/// 标签筛选的三种状态：全部 / 某个标签 / 没有标签。
///
/// 和 [SubjectFilter] 长得一样，因为用法一样——都是给列表页上面的筛选条用。
class TagFilter {
  const TagFilter.all()
      : tag = null,
        isUntagged = false;

  const TagFilter.untagged()
      : tag = null,
        isUntagged = true;

  const TagFilter.one(String name)
      : tag = name,
        isUntagged = false;

  final String? tag;
  final bool isUntagged;

  String get key {
    if (isUntagged) return 'none';
    final String? t = tag;
    return t == null ? 'all' : 'tag:$t';
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
  ///
  /// [tag] 的筛选是在 Dart 里做的，没写进 SQL——标签存在 JSON 字符串里，
  /// 而 minSdk 24 的系统 SQLite 没有 JSON1 扩展，SQL 里解析不了它。
  /// 个人几千张卡的量级，多遍历一遍完全无感。
  Future<List<StudyCard>> listCards({
    String? type,
    SubjectFilter subject = const SubjectFilter.all(),
    TagFilter tag = const TagFilter.all(),
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
      sql.write(
        ' AND (c.title LIKE ? OR c.content LIKE ? OR s.name LIKE ? '
        'OR c.tags LIKE ?)',
      );
      final String like = '%$trimmed%';
      args.addAll(<Object?>[like, like, like, like]);
    }

    sql.write(
      trashed
          ? ' ORDER BY c.deleted_at DESC'
          : ' ORDER BY c.pinned DESC, c.created_at DESC',
    );

    final List<Map<String, Object?>> rows =
        await db.rawQuery(sql.toString(), args);
    final List<StudyCard> cards =
        rows.map(StudyCard.fromMap).toList(growable: false);

    if (tag.isUntagged) {
      return cards
          .where((StudyCard c) => c.tags.isEmpty)
          .toList(growable: false);
    }
    final String? wanted = tag.tag;
    if (wanted == null) return cards;
    return cards
        .where((StudyCard c) => c.tags.contains(wanted))
        .toList(growable: false);
  }

  /// 某个功能下用过的全部标签，用得多的排在前面。
  ///
  /// 标签没有独立的表，只存在卡片的 `tags` 字段里，所以这里是把现有卡片
  /// 读出来在 Dart 里数一遍。回收站里的卡片不算数——不然一个标签删干净了
  /// 还会赖在筛选条上。
  Future<List<String>> listTags({required String type}) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'cards',
      where: 'type = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[type],
    );

    final Map<String, int> counts = <String, int>{};
    for (final Map<String, Object?> row in rows) {
      for (final String tag in StudyCard.fromMap(row).tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }

    final List<String> names = counts.keys.toList();
    names.sort((String a, String b) {
      final int byCount = counts[b]!.compareTo(counts[a]!);
      if (byCount != 0) return byCount;
      return a.compareTo(b);
    });
    return names;
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

  /// 还没处理完的卡片数（正文是空的），问题收集箱的「待解决」就是它。
  ///
  /// 和标签筛选一样在 Dart 里数：判据只有 [StudyCard.hasContent] 一处，
  /// 不会出现 SQL 里写一套、页面里又写一套、时间长了慢慢跑偏的情况。
  Future<int> countPendingCards({required String type}) async {
    final List<StudyCard> cards = await listCards(type: type);
    return cards.where((StudyCard c) => !c.hasContent).length;
  }

  /// 导出用：所有未删除的卡片。
  Future<List<StudyCard>> listCardsForExport() =>
      listCards(subject: const SubjectFilter.all());

  // ---------------------------------------------------------------- 复习

  /// 复习队列共用的筛选条件：「今天该看的卡」。
  ///
  /// 到期 = 从没复习过（`reviewed_at` 为空），或上次复习早于今天 0 点。
  /// 点过「记得」的卡 `reviewed_at` 就是刚才，今天不再出现、明天又到期；
  /// 点「忘了」的卡不动 `reviewed_at`，所以今天还留在队列里。
  ///
  /// 这里是刻意「按天」而不是「按小时」算的：用户要的是今天 / 明天，
  /// 不需要精确到秒的排期。
  ({String where, List<Object?> args}) _dueFilter({
    required String type,
    required SubjectFilter subject,
    required DateTime now,
  }) {
    final int todayStart =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final StringBuffer where = StringBuffer(
      'deleted_at IS NULL AND type = ? '
      'AND (reviewed_at IS NULL OR reviewed_at < ?)',
    );
    final List<Object?> args = <Object?>[type, todayStart];

    if (subject.isUncategorized) {
      where.write(' AND subject_id IS NULL');
    } else if (subject.subjectId != null) {
      where.write(' AND subject_id = ?');
      args.add(subject.subjectId);
    }
    return (where: where.toString(), args: args);
  }

  /// 今天该复习的卡片，忘得多的先看、同样次数里最久没碰的先看。
  ///
  /// [limit] 就是「今天只做 10 张」的那个 10——个人自用不需要排期算法，
  /// 一次给一小批，刷完了想接着刷再取一批就行。
  Future<List<StudyCard>> listDueCards({
    required String type,
    SubjectFilter subject = const SubjectFilter.all(),
    required int limit,
    required DateTime now,
  }) async {
    final Database db = await _db;
    final ({String where, List<Object?> args}) filter =
        _dueFilter(type: type, subject: subject, now: now);
    final List<Map<String, Object?>> rows = await db.query(
      'cards',
      where: filter.where,
      whereArgs: filter.args,
      // reviewed_at 为空表示从没复习过，当成 0 排在「复习过但很早」的前面。
      orderBy: 'forgot_count DESC, COALESCE(reviewed_at, 0) ASC, '
          'created_at DESC',
      limit: limit,
    );
    return rows.map(StudyCard.fromMap).toList(growable: false);
  }

  /// 今天该复习的卡片总数，给列表页顶部那句「还有 N 张待复习」用。
  Future<int> countDueCards({
    required String type,
    SubjectFilter subject = const SubjectFilter.all(),
    required DateTime now,
  }) async {
    final Database db = await _db;
    final ({String where, List<Object?> args}) filter =
        _dueFilter(type: type, subject: subject, now: now);
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM cards WHERE ${filter.where}',
      filter.args,
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  /// 「记得」：把 reviewed_at 推到现在，今天不再出现。
  ///
  /// 故意不碰 `updated_at`——复习不是编辑，别让「改于」时间被复习刷掉。
  Future<void> markRemembered(int id, {required DateTime now}) async {
    final Database db = await _db;
    await db.update(
      'cards',
      <String, Object?>{'reviewed_at': now.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 「忘了」：忘的次数 +1，reviewed_at 不动，所以今天还会再见到它。
  Future<void> markForgotten(int id) async {
    final Database db = await _db;
    // 用 SQL 自己加，省得先读出来再写回去，两步之间万一有别的写入就丢了。
    await db.rawUpdate(
      'UPDATE cards SET forgot_count = forgot_count + 1 WHERE id = ?',
      <Object?>[id],
    );
  }

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

  // ---------------------------------------------------------------- 导入

  /// 把一份导入包写进库里，整个动作在一个事务里完成。
  ///
  /// 包里那些 id 是**导出那台手机**上的编号，直接拿来用会和本机已有数据
  /// 撞车，所以一律丢掉重发；卡片靠「科目名字」找回自己的科目。
  /// [replace] 为 true 时先清空现有卡片和科目（图片文件由调用方负责清理，
  /// 而且必须等这个方法成功返回之后再删——否则导入失败就白删了）。
  Future<({int subjectsCreated, int cardsImported})> importPayload({
    required List<Subject> subjects,
    required List<StudyCard> cards,
    required bool replace,
  }) async {
    final Database db = await _db;

    // 导出机上的科目 id → 科目名。卡片挂着的是旧 id，靠这张表换成新 id。
    final Map<int, String> namesByOldId = <int, String>{
      for (final Subject s in subjects) s.id: s.name,
    };

    int created = 0;

    await db.transaction((Transaction txn) async {
      if (replace) {
        await txn.delete('cards');
        await txn.delete('subjects');
      }

      // 现有科目按名字索引：重名的直接复用，不会导出一堆「运筹(2)」。
      final List<Map<String, Object?>> rows = await txn.query(
        'subjects',
        columns: <String>['id', 'name'],
      );
      final Map<String, int> idsByName = <String, int>{
        for (final Map<String, Object?> row in rows)
          row['name']! as String: row['id']! as int,
      };

      for (final Subject s in subjects) {
        if (idsByName.containsKey(s.name)) continue;
        idsByName[s.name] = await txn.insert('subjects', <String, Object?>{
          'name': s.name,
          'sort_order': s.sortOrder,
        });
        created++;
      }

      for (final StudyCard card in cards) {
        final String? subjectName = namesByOldId[card.subjectId];
        final int? subjectId =
            subjectName == null ? null : idsByName[subjectName];
        final Map<String, Object?> values = card
            .copyWith(subjectId: subjectId, deletedAt: null)
            .toMap()
          ..remove('id');
        await txn.insert('cards', values);
      }
    });

    return (subjectsCreated: created, cardsImported: cards.length);
  }
}
