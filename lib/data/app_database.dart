import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 建库、建表、首次种子数据。
///
/// 测试时可以传 [path]（用内存库）和 [databaseFactoryOverride]。
class AppDatabase {
  AppDatabase({this.path, this.databaseFactoryOverride});

  static const String fileName = 'baibaoxiang.db';
  static const int schemaVersion = 1;

  /// 首次启动种入的科目。
  static const List<String> seedSubjects = <String>[
    '运筹',
    '高数',
    '线代',
    '数据库',
    '408',
  ];

  final String? path;
  final DatabaseFactory? databaseFactoryOverride;

  Database? _db;

  Future<Database> open() async {
    final Database? cached = _db;
    if (cached != null) return cached;

    final DatabaseFactory factory = databaseFactoryOverride ?? databaseFactory;
    final String dbPath =
        path ?? p.join(await factory.getDatabasesPath(), fileName);

    final Database db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: _onCreate,
        onConfigure: (Database db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
    _db = db;
    return db;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE subjects (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT NOT NULL UNIQUE,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE cards (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        type         TEXT NOT NULL,
        subject_id   INTEGER,
        title        TEXT,
        content      TEXT,
        images       TEXT,
        tags         TEXT,
        pinned       INTEGER NOT NULL DEFAULT 0,
        created_at   INTEGER NOT NULL,
        updated_at   INTEGER NOT NULL,
        reviewed_at  INTEGER,
        forgot_count INTEGER NOT NULL DEFAULT 0,
        deleted_at   INTEGER
      )
    ''');

    await db.execute('CREATE INDEX idx_cards_type ON cards(type)');
    await db.execute('CREATE INDEX idx_cards_subject ON cards(subject_id)');
    await db.execute('CREATE INDEX idx_cards_deleted ON cards(deleted_at)');

    await _seed(db);
  }

  /// 种入科目和 3 条示例卡，免得第一次打开页面空荡荡。
  Future<void> _seed(Database db) async {
    final int now = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < seedSubjects.length; i++) {
      await db.insert('subjects', <String, Object?>{
        'name': seedSubjects[i],
        'sort_order': i,
      });
    }

    final List<Map<String, Object?>> rows = await db.query(
      'subjects',
      columns: <String>['id', 'name'],
    );
    final Map<String, int> ids = <String, int>{
      for (final Map<String, Object?> row in rows)
        row['name']! as String: row['id']! as int,
    };

    const List<List<String>> samples = <List<String>>[
      <String>[
        '运筹',
        '单纯形法判别准则',
        '检验数 σⱼ ≤ 0 时达到最优解；若某个 σⱼ > 0 且该列系数全 ≤ 0，则问题无界。'
            '入基选最大正检验数，出基按 θ 最小比值规则。',
      ],
      <String>[
        '线代',
        '矩阵求逆',
        '用增广矩阵 (A | E) 做初等行变换，把左边化成单位阵，右边就是 A⁻¹；'
            '只有 |A| ≠ 0 时逆矩阵才存在。',
      ],
      <String>[
        '408',
        '补码转换',
        '求负数补码：符号位不变、数值位取反再加 1；或者直接按 2ⁿ + x 计算。'
            '8 位下 −128 的补码是 1000 0000。',
      ],
    ];

    for (int i = 0; i < samples.length; i++) {
      await db.insert('cards', <String, Object?>{
        'type': '公式',
        'subject_id': ids[samples[i][0]],
        'title': samples[i][1],
        'content': samples[i][2],
        'images': '[]',
        'tags': '[]',
        'pinned': 0,
        'created_at': now + i,
        'updated_at': now + i,
        'reviewed_at': null,
        'forgot_count': 0,
        'deleted_at': null,
      });
    }
  }
}
