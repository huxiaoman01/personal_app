import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_globals.dart';
import '../../data/card_repository.dart';
import '../../models/study_card.dart';
import '../../models/subject.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_background.dart';
import '../../widgets/card_tile.dart';
import '../../widgets/empty_hint.dart';
import '../../widgets/filter_pill.dart';
import '../../widgets/sheet_action.dart';
import '../card/card_edit_screen.dart';
import '../subjects/subject_manage_screen.dart';
import 'question_detail_screen.dart';

/// 问题收集箱：待解决的和已经问出答案的，分成两摊。
///
/// 和记忆卡、错题本最大的不同是「状态」：这里没有复习流，
/// **答案留空 = 待解决，回填了答案 = 已解决**——状态是从正文派生的，
/// 没有单独的字段，所以回填完自动就归到下面那一摊里去了。
class QuestionListScreen extends StatefulWidget {
  const QuestionListScreen({super.key});

  @override
  State<QuestionListScreen> createState() => _QuestionListScreenState();
}

class _QuestionListScreenState extends State<QuestionListScreen> {
  List<Subject> _subjects = const <Subject>[];
  SubjectFilter _filter = const SubjectFilter.all();

  /// 待解决：置顶优先，其余按记下来的时间倒序（就是 listCards 的默认顺序）。
  List<StudyCard> _pending = const <StudyCard>[];

  /// 已解决：最近解决的排前面，这一摊不看置顶。
  List<StudyCard> _solved = const <StudyCard>[];

  /// 归档那一摊默认收起来，免得翻了半屏才看到待解决的下一条。
  bool _showSolved = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<Subject> subjects = await subjectCache.load(force: true);
    final List<StudyCard> cards = await cardRepository.listCards(
      type: CardType.question,
      subject: _filter,
    );

    final List<StudyCard> pending = cards
        .where((StudyCard c) => !c.hasContent)
        .toList(growable: false);
    final List<StudyCard> solved = cards
        .where((StudyCard c) => c.hasContent)
        .toList();
    // 回填答案会更新 updated_at，所以它就是「什么时候解决的」。
    solved.sort((StudyCard a, StudyCard b) => b.updatedAt.compareTo(a.updatedAt));

    if (!mounted) return;
    setState(() {
      _subjects = subjects;
      _pending = pending;
      _solved = solved;
      _loading = false;
    });
  }

  void _selectFilter(SubjectFilter filter) {
    setState(() => _filter = filter);
    _reload();
  }

  /// 删掉的科目如果正在被筛选，就退回「全部」。
  Future<void> _openSubjectManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const SubjectManageScreen(),
      ),
    );
    final bool stillThere = _filter.subjectId == null ||
        _subjects.any((Subject s) => s.id == _filter.subjectId);
    if (!stillThere) {
      _filter = const SubjectFilter.all();
    }
    await _reload();
  }

  Future<void> _createCard() async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) =>
            const CardEditScreen(type: CardType.question),
      ),
    );
    if (saved ?? false) await _reload();
  }

  Future<void> _openDetail(StudyCard card) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => QuestionDetailScreen(cardId: card.id!),
      ),
    );
    await _reload();
  }

  /// 已解决的那些不再给「置顶」——置顶在这里没有任何作用，只会让人困惑。
  Future<void> _showCardMenu(StudyCard card, {required bool solved}) async {
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!solved)
              SheetAction(
                icon: card.pinned ? Icons.push_pin_outlined : Icons.push_pin,
                label: card.pinned ? '取消置顶' : '置顶',
                onTap: () => Navigator.of(sheet).pop('pin'),
              ),
            SheetAction(
              icon: Icons.delete_outline,
              label: '删除',
              onTap: () => Navigator.of(sheet).pop('delete'),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );

    if (action == 'pin') {
      await cardRepository.setPinned(card.id!, !card.pinned);
      await _reload();
    } else if (action == 'delete') {
      await cardRepository.moveToTrash(card.id!);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已移入最近删除，30 天内可以恢复')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('问题收集箱')),
      floatingActionButton: FloatingActionButton(
        onPressed: _createCard,
        tooltip: '新增问题',
        child: const Icon(Icons.add, size: 26),
      ),
      body: Column(
        children: <Widget>[
          SizedBox(
            height: 52,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSize.pagePadding,
                    ),
                    children: <Widget>[
                      FilterPill(
                        label: '全部',
                        selected: _filter.key == 'all',
                        onTap: () => _selectFilter(const SubjectFilter.all()),
                      ),
                      for (final Subject s in _subjects)
                        FilterPill(
                          label: s.name,
                          selected: _filter.key == 'id:${s.id}',
                          onTap: () => _selectFilter(SubjectFilter.one(s.id)),
                        ),
                      FilterPill(
                        label: '未分类',
                        selected: _filter.key == 'none',
                        onTap: () =>
                            _selectFilter(const SubjectFilter.uncategorized()),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: AppSize.iconBlock,
                  height: AppSize.iconBlock,
                  child: IconButton(
                    tooltip: '编辑科目',
                    iconSize: 20,
                    onPressed: _openSubjectManager,
                    icon: Icon(Icons.edit_outlined, color: p.textSecondary),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
          // 背景图案只铺在列表这块：标题栏和科目筛选条保持干净。
          Expanded(child: AppBackground(child: _buildBody())),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_pending.isEmpty && _solved.isEmpty) {
      if (_filter.key != 'all') {
        return const EmptyHint(
          icon: Icons.filter_alt_off_outlined,
          text: '这个筛选下还没有问题',
        );
      }
      return const EmptyHint(
        icon: Icons.help_outline,
        text: '还没有问题\n点右下角 + 记第一条',
      );
    }

    final List<Widget> children = <Widget>[];

    if (_pending.isEmpty) {
      // 全都问完了，但下面还压着归档区，所以只给一句轻的提示。
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSize.pagePadding,
            AppSpace.xl,
            AppSize.pagePadding,
            AppSpace.md,
          ),
          child: Text(
            '没有待解决的问题了',
            style: AppText.caption.copyWith(color: context.palette.textTertiary),
          ),
        ),
      );
    } else {
      children.add(const SizedBox(height: AppSpace.sm));
      for (int i = 0; i < _pending.length; i++) {
        final StudyCard card = _pending[i];
        children.add(
          CardTile(
            key: ValueKey<int>(card.id!),
            card: card,
            subtitleOverride: subjectCache.labelOf(card),
            trailing: const _StatusBadge(label: '待解决', highlight: true),
            onTap: () => _openDetail(card),
            onLongPress: () => _showCardMenu(card, solved: false),
          ),
        );
        if (i != _pending.length - 1) children.add(const CardListDivider());
      }
    }

    if (_solved.isNotEmpty) {
      children
        ..add(const SizedBox(height: AppSpace.lg))
        ..add(
          _ArchiveHeader(
            count: _solved.length,
            expanded: _showSolved,
            onTap: () => setState(() => _showSolved = !_showSolved),
          ),
        );
      if (_showSolved) {
        for (int i = 0; i < _solved.length; i++) {
          final StudyCard card = _solved[i];
          children.add(
            CardTile(
              key: ValueKey<int>(card.id!),
              card: card,
              subtitleOverride: subjectCache.labelOf(card),
              trailing: const _StatusBadge(label: '已解决', highlight: false),
              onTap: () => _openDetail(card),
              onLongPress: () => _showCardMenu(card, solved: true),
            ),
          );
          if (i != _solved.length - 1) children.add(const CardListDivider());
        }
      }
    }

    return ListView(
      // 底部留出 FAB 的位置，免得最后一行被按钮压住。
      padding: const EdgeInsets.only(bottom: 96),
      children: children,
    );
  }
}

/// 列表右边那颗状态角标：待解决 / 已解决。
///
/// 不上主色——主色留给置顶、FAB 和关键按钮，这种天天见的标记用描边就够安静。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.highlight});

  final String label;

  /// 待解决的那颗字重一点：它是唯一还需要动手的。
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xs / 2,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: p.divider),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppText.badge.copyWith(
          color: highlight ? p.textSecondary : p.textTertiary,
        ),
      ),
    );
  }
}

/// 归档那一行的标题，点一下展开 / 收起。
class _ArchiveHeader extends StatelessWidget {
  const _ArchiveHeader({
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSize.pagePadding,
          vertical: AppSpace.md,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: p.textTertiary,
            ),
            const SizedBox(width: AppSpace.xs),
            Text(
              '已解决的 $count 条',
              style: AppText.caption.copyWith(
                color: p.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
