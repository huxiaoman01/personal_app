import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_globals.dart';
import '../../data/card_repository.dart';
import '../../models/study_card.dart';
import '../../models/subject.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_background.dart';
import '../../widgets/add_star.dart';
import '../../widgets/card_tile.dart';
import '../../widgets/empty_hint.dart';
import '../../widgets/filter_pill.dart';
import '../../widgets/sheet_action.dart';
import '../formula/card_detail_screen.dart';
import '../subjects/subject_manage_screen.dart';
import 'card_edit_screen.dart';
import 'card_feature.dart';
import 'card_review_screen.dart';

/// 通用卡片库：一个功能自己的卡片列表 + 今天该复习的那一批。
///
/// 记忆卡片和错题本共用这一页，差别全在 [feature] 里（标题、空态、次数说法）。
/// 记忆卡那会儿是写死「记忆」的，错题本接进来时把它参数化了，一处改动两边生效。
class CardLibraryScreen extends StatefulWidget {
  const CardLibraryScreen({super.key, required this.feature});

  final CardFeature feature;

  @override
  State<CardLibraryScreen> createState() => _CardLibraryScreenState();
}

class _CardLibraryScreenState extends State<CardLibraryScreen> {
  List<Subject> _subjects = const <Subject>[];
  SubjectFilter _filter = const SubjectFilter.all();
  List<StudyCard> _cards = const <StudyCard>[];

  /// 当前筛选下今天该复习的张数，0 的时候复习条整条藏起来。
  int _dueCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<Subject> subjects = await subjectCache.load(force: true);
    final List<StudyCard> cards = await cardRepository.listCards(
      type: widget.feature.type,
      subject: _filter,
    );
    final int due = await cardRepository.countDueCards(
      type: widget.feature.type,
      subject: _filter,
      now: DateTime.now(),
    );
    if (!mounted) return;
    setState(() {
      _subjects = subjects;
      _cards = cards;
      _dueCount = due;
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
            CardEditScreen(type: widget.feature.type),
      ),
    );
    if (saved ?? false) await _reload();
  }

  Future<void> _openDetail(StudyCard card) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => CardDetailScreen(cardId: card.id!),
      ),
    );
    await _reload();
  }

  /// 复习也跟着筛选走：筛了 408 就只刷 408 的卡。
  Future<void> _startReview() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => CardReviewScreen(
          feature: widget.feature,
          subject: _filter,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _showCardMenu(StudyCard card) async {
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
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

  /// 列表第二行：科目 + 忘了几次（错题本是错了几次），一眼看出哪几张最该看。
  String _subtitleOf(StudyCard card) {
    final String subject = subjectCache.labelOf(card);
    if (card.forgotCount == 0) return '$subject · 还没复习';
    return '$subject · ${widget.feature.reviewedWord} ${card.forgotCount} 次';
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;

    return Scaffold(
      appBar: AppBar(title: Text(widget.feature.title)),
      floatingActionButton: FloatingActionButton(
        onPressed: _createCard,
        tooltip: '新增${widget.feature.editVerb}',
        // 「＋」是那颗星星，见 widgets/add_star.dart。
        child: const AddStar(size: AppSize.iconBlock),
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
          if (_dueCount > 0)
            _ReviewBar(dueCount: _dueCount, onStart: _startReview),
          // 背景图案只铺在列表这块：标题栏、科目筛选条和复习条保持干净。
          Expanded(child: AppBackground(child: _buildList())),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_cards.isEmpty) {
      if (_filter.key != 'all') {
        return EmptyHint(
          icon: Icons.filter_alt_off_outlined,
          text: widget.feature.emptyFilteredText,
        );
      }
      return EmptyHint(
        icon: widget.feature.icon,
        text: widget.feature.emptyText,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: AppSpace.sm, bottom: 96),
      itemCount: _cards.length,
      separatorBuilder: (BuildContext _, int _) => const CardListDivider(),
      itemBuilder: (BuildContext context, int index) {
        final StudyCard card = _cards[index];
        return CardTile(
          card: card,
          subtitleOverride: _subtitleOf(card),
          onTap: () => _openDetail(card),
          onLongPress: () => _showCardMenu(card),
        );
      },
    );
  }
}

/// 列表顶部那条复习入口：左边说清楚今天做几张，右边一颗「开始复习」。
class _ReviewBar extends StatelessWidget {
  const _ReviewBar({required this.dueCount, required this.onStart});

  final int dueCount;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    // 待复习的卡比一批还多时才说「先做 10 张」，不然就是「就这几张」。
    final bool moreThanOneBatch = dueCount > CardReviewScreen.batchSize;
    final int thisBatch =
        moreThanOneBatch ? CardReviewScreen.batchSize : dueCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSize.pagePadding,
        AppSpace.md,
        AppSize.pagePadding,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
        decoration: BoxDecoration(
          color: p.iconBlock,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '今天先做 $thisBatch 张',
                    style: AppText.listTitle.copyWith(color: p.text),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    // 一批装得下就不必再报一次总数，那是同一句话说了两遍。
                    moreThanOneBatch ? '还有 $dueCount 张待复习' : '一次就能刷完',
                    style: AppText.caption.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.md),
            InkWell(
              onTap: onStart,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                // 可点区域不能小于 44，这里正好 44。
                height: AppSize.iconBlock,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                decoration: BoxDecoration(
                  color: p.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Center(
                  child: Text(
                    '开始复习',
                    style: AppText.caption.copyWith(
                      color: p.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
