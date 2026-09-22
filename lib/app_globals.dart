import 'data/card_repository.dart';
import 'data/image_store.dart';
import 'data/subject_cache.dart';

/// 全局单例。个人自用的小 app，用一个 late final 变量比引状态管理框架
/// 更省事，main() 里初始化一次即可。
late final ImageStore imageStore;
late final CardRepository cardRepository;
late final SubjectCache subjectCache;
