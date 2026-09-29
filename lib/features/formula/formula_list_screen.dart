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
import 'card_detail_screen.dart';

/// 公式手册主列表：科目筛选条 + 一行一张的卡片列表。
class FormulaListScreen extends StatefulWidget {
  const FormulaListScreen({super.key});

  @override
  State<FormulaListScreen> createState() => _FormulaListScreenState();
}

class _FormulaListScreenState extends State<FormulaListScreen> {
  List<Subject> _subjects = const <Subject>[];
  SubjectFilter _filter = const SubjectFilter.all();
  List<StudyCard> _cards = const <StudyCard>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<Subject> subjects = await subjectCache.load(force: true);
    final List<StudyCard> cards = await cardRepository.listCards(
      type: CardType.formula,
      subject: _filter,
    );
    if (!mounted) return;
    setState(() {
      _subjects = subjects;
      _cards = cards;
      _loading = false;
    });
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

  Future<void> _openDetail(StudyCard card) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => CardDetailScreen(cardId: card.id!),
      ),
    );
    await _reload();
  }

  Future<void> _createCard() async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) =>
            const CardEditScreen(type: CardType.formula),
      ),
    );
    if (saved ?? false) await _reload();
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

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('公式手册')),
      floatingActionButton: FloatingActionButton(
        onPressed: _createCard,
        tooltip: '新增公式',
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
                        onTap: () {
                          setState(() => _filter = const SubjectFilter.all());
                          _reload();
                        },
                      ),
                      for (final Subject s in _subjects)
                        FilterPill(
                          label: s.name,
                          selected: _filter.key == 'id:${s.id}',
                          onTap: () {
                            setState(
                              () => _filter = SubjectFilter.one(s.id),
                            );
                            _reload();
                          },
                        ),
                      FilterPill(
                        label: '未分类',
                        selected: _filter.key == 'none',
                        onTap: () {
                          setState(
                            () => _filter = const SubjectFilter.uncategorized(),
                          );
                          _reload();
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 44,
                  height: 44,
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
      return const EmptyHint(
        icon: Icons.functions,
        text: '还没有公式\n点右下角 + 拍下第一张',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: _cards.length,
      separatorBuilder: (BuildContext _, int _) => const CardListDivider(),
      itemBuilder: (BuildContext context, int index) {
        final StudyCard card = _cards[index];
        return CardTile(
          card: card,
          subtitleOverride: card.displaySubtitle.isEmpty
              ? subjectCache.labelOf(card)
              : card.displaySubtitle,
          onTap: () => _openDetail(card),
          onLongPress: () => _showCardMenu(card),
        );
      },
    );
  }
}
