import 'package:flutter/material.dart';

import '../../app_globals.dart';
import '../../data/card_repository.dart';
import '../../models/study_card.dart';
import '../../theme/app_theme.dart';
import '../../widgets/card_tile.dart';
import '../../widgets/empty_hint.dart';
import '../../widgets/sheet_action.dart';

/// 最近删除。软删除的卡片在这里放 30 天，之后自动清掉。
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<StudyCard> _cards = const <StudyCard>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<StudyCard> cards =
        await cardRepository.listCards(trashed: true);
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _loading = false;
    });
  }

  int _daysLeft(StudyCard card) {
    final int deletedAt = card.deletedAt ?? 0;
    final DateTime deleted = DateTime.fromMillisecondsSinceEpoch(deletedAt);
    final int passed = DateTime.now().difference(deleted).inDays;
    final int left = CardRepository.trashRetentionDays - passed;
    return left < 0 ? 0 : left;
  }

  Future<void> _showMenu(StudyCard card) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SheetAction(
              icon: Icons.restore,
              label: '恢复',
              onTap: () => Navigator.of(sheet).pop('restore'),
            ),
            SheetAction(
              icon: Icons.delete_forever_outlined,
              label: '彻底删除',
              onTap: () => Navigator.of(sheet).pop('purge'),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );
    if (action == 'restore') {
      await cardRepository.restoreFromTrash(card.id!);
      await _reload();
    } else if (action == 'purge') {
      await cardRepository.deleteForever(card.id!);
      await _reload();
    }
  }

  Future<void> _emptyAll() async {
    final AppPalette p = context.palette;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: const Text('清空最近删除？'),
        content: const Text('这些卡片会被彻底删掉，图片也一起，没法恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(
              '取消',
              style: AppText.body.copyWith(color: p.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(
              '清空',
              style: AppText.body.copyWith(color: p.primary),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await cardRepository.emptyTrash();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;

    return Scaffold(
      appBar: AppBar(
        title: const Text('最近删除'),
        actions: <Widget>[
          if (_cards.isNotEmpty)
            TextButton(
              onPressed: _emptyAll,
              child: Text(
                '清空',
                style: AppText.body.copyWith(color: p.primary),
              ),
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
    if (_cards.isEmpty) {
      return const EmptyHint(icon: Icons.delete_outline, text: '最近删除是空的');
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xl),
      itemCount: _cards.length,
      separatorBuilder: (BuildContext _, int _) => const CardListDivider(),
      itemBuilder: (BuildContext context, int index) {
        final StudyCard card = _cards[index];
        return CardTile(
          card: card,
          subtitleOverride: '还有 ${_daysLeft(card)} 天',
          onTap: () => _showMenu(card),
        );
      },
    );
  }
}
