/// 科目标签。全局共用，公式手册和以后的考点大纲读的是同一批。
class Subject {
  const Subject({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  final int id;
  final String name;
  final int sortOrder;

  factory Subject.fromMap(Map<String, Object?> map) => Subject(
        id: map['id']! as int,
        name: map['name']! as String,
        sortOrder: (map['sort_order'] as int?) ?? 0,
      );
}
