import '../models/study_card.dart';
import '../models/subject.dart';
import 'card_repository.dart';

/// 科目列表在多个页面都要用，缓存一份，避免每次都查库。
class SubjectCache {
  SubjectCache(this._repository);

  final CardRepository _repository;

  List<Subject> _items = const <Subject>[];
  bool _loaded = false;

  List<Subject> get items => _items;

  Future<List<Subject>> load({bool force = false}) async {
    if (_loaded && !force) return _items;
    _items = await _repository.listSubjects();
    _loaded = true;
    return _items;
  }

  Subject? byId(int? id) {
    if (id == null) return null;
    for (final Subject s in _items) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 卡片所属科目的名字，没归类就是「未分类」。
  String labelOf(StudyCard card) => byId(card.subjectId)?.name ?? '未分类';
}
