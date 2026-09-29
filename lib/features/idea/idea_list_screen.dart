import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_globals.dart';
import '../../data/card_repository.dart';
import '../../models/study_card.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_background.dart';
import '../../widgets/add_star.dart';
import '../../widgets/card_tile.dart';
import '../../widgets/empty_hint.dart';
import '../../widgets/filter_pill.dart';
import '../../widgets/sheet_action.dart';
import '../card/card_edit_screen.dart';

/// 灵感记录：一条按天排的时间线，右下角 + 号新建。
///
/// 和公式手册是同一套路子：先看列表，点 + 再写。写的那一页是共用的
/// 卡片编辑页，所以新建时也能直接拍照配图。
class IdeaListScreen extends StatefulWidget {
  const IdeaListScreen({super.key});

  @override
  State<IdeaListScreen> createState() => _IdeaListScreenState();
}

class _IdeaListScreenState extends State<IdeaListScreen> {
  /// 用过的标签，既是筛选条的候选，也是标签对话框里的建议。
  List<String> _knownTags = const <String>[];
  TagFilter _filter = const TagFilter.all();
  List<StudyCard> _cards = const <StudyCard>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<String> tags = await cardRepository.listTags(
      type: CardType.idea,
    );
    // 正在筛的那个标签要是已经没人用了，就退回「全部」，不然列表会一直空着。
    final String? current = _filter.tag;
    if (current != null && !tags.contains(current)) {
      _filter = const TagFilter.all();
    }
    final List<StudyCard> cards = await cardRepository.listCards(
      type: CardType.idea,
      tag: _filter,
    );
    if (!mounted) return;
    setState(() {
      _knownTags = tags;
      _cards = cards;
      _loading = false;
    });
  }

  void _selectFilter(TagFilter filter) {
    setState(() => _filter = filter);
    _reload();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ------------------------------------------------------------ 新建 / 打开

  Future<void> _createCard() async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) =>
            const CardEditScreen(type: CardType.idea),
      ),
    );
    if (saved ?? false) await _reload();
  }

  Future<void> _openCard(StudyCard card) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) =>
            CardEditScreen(type: CardType.idea, card: card),
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
      _toast('已移入最近删除，30 天内可以恢复');
    }
  }

  // -------------------------------------------------------------- 时间线

  /// 列表第二行：有标签就显示标签，没有就显示正文。
  ///
  /// 没标题的老灵感是个例外：它的正文首行已经被拿去当标题了（见
  /// [StudyCard.displayTitle]），所以副标题得从第二行接着显示，
  /// 不然同一句话会在同一行里出现两遍。
  String? _subtitleOf(StudyCard card) {
    if (card.tags.isNotEmpty) {
      return card.tags.map((String t) => '#$t').join('  ');
    }
    final String content = (card.content ?? '').trim();
    if (content.isEmpty) return null;
    if ((card.title ?? '').trim().isNotEmpty) {
      return content.replaceAll('\n', ' ').trim();
    }
    final List<String> lines = content.split('\n');
    if (lines.length < 2) return null;
    final String rest = lines.skip(1).join(' ').trim();
    return rest.isEmpty ? null : rest;
  }

  /// 按天切段。置顶的单独放最前面一段，不打断下面的时间线。
  List<_DaySection> _groupByDay(List<StudyCard> cards) {
    final List<_DaySection> sections = <_DaySection>[];

    final List<StudyCard> pinned =
        cards.where((StudyCard c) => c.pinned).toList(growable: false);
    if (pinned.isNotEmpty) {
      sections.add(_DaySection('置顶', isPinned: true, cards: pinned));
    }

    for (final StudyCard card in cards) {
      if (card.pinned) continue;
      final String label = _dayLabel(card.createdAt);
      // 卡片本身已经按时间倒序排好，所以同一天的必然挨在一起，
      // 只要跟上一段比一下名字就知道要不要新开一段。
      if (sections.isEmpty || sections.last.title != label) {
        sections.add(_DaySection(label, isPinned: false, cards: <StudyCard>[]));
      }
      sections.last.cards.add(card);
    }
    return sections;
  }

  String _dayLabel(int milliseconds) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final DateTime date = DateTime(day.year, day.month, day.day);
    final int passed = today.difference(date).inDays;

    if (passed == 0) return '今天';
    if (passed == 1) return '昨天';
    if (date.year == today.year) return '${date.month}月${date.day}日';
    return '${date.year}年${date.month}月${date.day}日';
  }

  // ------------------------------------------------------------------ 界面

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('灵感记录')),
      floatingActionButton: FloatingActionButton(
        onPressed: _createCard,
        tooltip: '写灵感',
        // 「＋」是那颗星星，见 widgets/add_star.dart。
        child: const AddStar(size: AppSize.iconBlock),
      ),
      body: Column(
        children: <Widget>[
          // 一个标签都没用过的时候，筛选条藏起来，页面更干净。
          if (_knownTags.isNotEmpty) ...<Widget>[
            _buildFilterBar(),
            const Divider(height: 1, thickness: 1),
          ],
          // 背景图案只铺在列表这块：标题栏和筛选条保持干净。
          Expanded(child: AppBackground(child: _buildTimeline())),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSize.pagePadding),
        children: <Widget>[
          FilterPill(
            label: '全部',
            selected: _filter.key == 'all',
            onTap: () => _selectFilter(const TagFilter.all()),
          ),
          for (final String tag in _knownTags)
            FilterPill(
              label: tag,
              selected: _filter.key == 'tag:$tag',
              onTap: () => _selectFilter(TagFilter.one(tag)),
            ),
          FilterPill(
            label: '无标签',
            selected: _filter.key == 'none',
            onTap: () => _selectFilter(const TagFilter.untagged()),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
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
        return const EmptyHint(
          icon: Icons.filter_alt_off_outlined,
          text: '这个筛选下还没有灵感',
        );
      }
      return const EmptyHint(
        icon: Icons.lightbulb_outline,
        text: '还没有灵感\n点右下角 + 写下第一条',
      );
    }

    final List<_DaySection> sections = _groupByDay(_cards);
    final List<Widget> children = <Widget>[];
    for (int s = 0; s < sections.length; s++) {
      final _DaySection section = sections[s];
      children.add(
        _SectionHeader(title: section.title, isPinned: section.isPinned),
      );
      for (int i = 0; i < section.cards.length; i++) {
        final StudyCard card = section.cards[i];
        children.add(
          CardTile(
            key: ValueKey<int>(card.id!),
            card: card,
            subtitleOverride: _subtitleOf(card),
            onTap: () => _openCard(card),
            onLongPress: () => _showCardMenu(card),
          ),
        );
        if (i != section.cards.length - 1) {
          children.add(const CardListDivider());
        }
      }
      if (s != sections.length - 1) {
        children.add(const SizedBox(height: AppSpace.lg));
      }
    }

    return ListView(
      // 底部留出 FAB 的位置，免得最后一个卡片被按钮压住。
      padding: const EdgeInsets.only(bottom: 96),
      children: children,
    );
  }
}

/// 时间线里的一段：要么是「置顶」，要么是一天。
class _DaySection {
  _DaySection(this.title, {required this.isPinned, required this.cards});

  final String title;
  final bool isPinned;
  final List<StudyCard> cards;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.isPinned});

  final String title;
  final bool isPinned;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSize.pagePadding,
        AppSpace.md,
        AppSize.pagePadding,
        AppSpace.sm,
      ),
      child: Row(
        children: <Widget>[
          if (isPinned) ...<Widget>[
            Icon(Icons.push_pin, size: 14, color: p.primary),
            const SizedBox(width: AppSpace.xs),
          ],
          Text(
            title,
            style: AppText.caption.copyWith(
              color: p.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
