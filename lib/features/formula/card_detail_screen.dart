import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_globals.dart';
import '../../models/study_card.dart';
import '../../theme/app_theme.dart';
import '../../widgets/card_image_pager.dart';
import '../../widgets/empty_hint.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/sheet_action.dart';
import '../card/card_edit_screen.dart';
import '../card/card_feature.dart';

/// 卡片详情：大图 + 标题 + 注释 + 元信息。
class CardDetailScreen extends StatefulWidget {
  const CardDetailScreen({super.key, required this.cardId});

  final int cardId;

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  StudyCard? _card;
  bool _loading = true;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final StudyCard? card = await cardRepository.getCard(widget.cardId);
    if (!mounted) return;
    setState(() {
      _card = card;
      _loading = false;
    });
  }

  Future<void> _togglePin() async {
    final StudyCard? card = _card;
    if (card == null) return;
    await cardRepository.setPinned(card.id!, !card.pinned);
    await _load();
  }

  Future<void> _edit() async {
    final StudyCard? card = _card;
    if (card == null) return;
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext _) =>
            CardEditScreen(type: card.type, card: card),
      ),
    );
    if (saved ?? false) await _load();
  }

  Future<void> _delete() async {
    final StudyCard? card = _card;
    if (card == null) return;
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
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
    if (action != 'delete') return;
    await cardRepository.moveToTrash(card.id!);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已移入最近删除，30 天内可以恢复')),
    );
  }

  Future<void> _openFullscreen(int initialIndex) async {
    final StudyCard? card = _card;
    if (card == null) return;
    await openImageViewer(
      context,
      names: card.images,
      initialIndex: initialIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final StudyCard? card = _card;

    return Scaffold(
      appBar: AppBar(
        actions: <Widget>[
          IconButton(
            tooltip: (card?.pinned ?? false) ? '取消置顶' : '置顶',
            onPressed: card == null ? null : _togglePin,
            icon: Icon(
              (card?.pinned ?? false) ? Icons.push_pin : Icons.push_pin_outlined,
              color: (card?.pinned ?? false) ? p.primary : p.textSecondary,
            ),
          ),
          IconButton(
            tooltip: '编辑',
            onPressed: card == null ? null : _edit,
            icon: Icon(Icons.edit_outlined, color: p.textSecondary),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: card == null ? null : _delete,
            icon: Icon(Icons.delete_outline, color: p.textSecondary),
          ),
          const SizedBox(width: AppSpace.sm),
        ],
      ),
      body: _buildBody(),
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
    final StudyCard? card = _card;
    if (card == null) {
      return const EmptyHint(icon: Icons.error_outline, text: '这张卡片已经不在了');
    }

    final AppPalette p = context.palette;
    final String created =
        DateFormat('yyyy-MM-dd').format(
      DateTime.fromMillisecondsSinceEpoch(card.createdAt),
    );
    final String subject = subjectCache.labelOf(card);
    final String content = (card.content ?? '').trim();
    // 靠复习的功能（记忆卡、错题本）多显示一行次数——复习就是按它排序的。
    final CardFeature? feature = cardFeatureOf(card.type);
    final String meta;
    if (feature == null) {
      meta = '$subject · $created';
    } else if (card.forgotCount == 0) {
      meta = '$subject · 还没复习 · $created';
    } else {
      meta =
          '$subject · ${feature.reviewedWord} ${card.forgotCount} 次 · $created';
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      children: <Widget>[
        if (card.images.isNotEmpty) ...<Widget>[
          CardImagePager(
            names: card.images,
            page: _page,
            onPageChanged: (int i) => setState(() => _page = i),
            onTap: _openFullscreen,
          ),
          const SizedBox(height: AppSpace.xl),
        ] else
          const SizedBox(height: AppSpace.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSize.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                card.displayTitle,
                style: AppText.detailTitle.copyWith(color: p.text),
              ),
              if (content.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpace.md),
                Text(content, style: AppText.body.copyWith(color: p.text)),
              ],
              const SizedBox(height: AppSpace.lg),
              const Divider(height: 1, thickness: 1),
              const SizedBox(height: AppSpace.md),
              Text(
                meta,
                style: AppText.badge.copyWith(color: p.textTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
