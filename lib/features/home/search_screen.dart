import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_globals.dart';
import '../../models/study_card.dart';
import '../../theme/app_theme.dart';
import '../../widgets/card_tile.dart';
import '../../widgets/empty_hint.dart';
import '../formula/card_detail_screen.dart';

/// 跨全部卡片类型的全局搜索。结果按功能分组。
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  String _query = '';
  List<MapEntry<String, List<StudyCard>>> _groups =
      const <MapEntry<String, List<StudyCard>>>[];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _run(value),
    );
  }

  Future<void> _run(String query) async {
    final String trimmed = query.trim();
    final List<MapEntry<String, List<StudyCard>>> groups =
        <MapEntry<String, List<StudyCard>>>[];

    if (trimmed.isNotEmpty) {
      for (final String type in CardType.all) {
        final List<StudyCard> list =
            await cardRepository.listCards(type: type, keyword: trimmed);
        if (list.isNotEmpty) {
          groups.add(MapEntry<String, List<StudyCard>>(type, list));
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _query = trimmed;
      _groups = groups;
    });
  }

  Future<void> _openCard(StudyCard card) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => CardDetailScreen(cardId: card.id!),
      ),
    );
    await _run(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: AppText.body.copyWith(color: p.text),
          cursorColor: p.primary,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: '搜公式、灵感、错题…',
            hintStyle: AppText.body.copyWith(color: p.textTertiary),
          ),
          onChanged: _onChanged,
          onSubmitted: _run,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty) {
      return const EmptyHint(icon: Icons.search, text: '输入关键词开始搜索');
    }
    if (_groups.isEmpty) {
      return const EmptyHint(icon: Icons.search_off, text: '没找到相关内容');
    }

    final List<Widget> children = <Widget>[];
    for (int g = 0; g < _groups.length; g++) {
      final MapEntry<String, List<StudyCard>> group = _groups[g];
      children.add(_GroupHeader(title: group.key, count: group.value.length));
      for (int i = 0; i < group.value.length; i++) {
        final StudyCard card = group.value[i];
        children.add(
          CardTile(
            key: ValueKey<String>('${group.key}-${card.id}'),
            card: card,
            subtitleOverride: _subtitleOf(card),
            onTap: () => _openCard(card),
          ),
        );
        if (i != group.value.length - 1) {
          children.add(const CardListDivider());
        }
      }
      if (g != _groups.length - 1) {
        children.add(const SizedBox(height: AppSpace.lg));
      }
    }

    return ListView(
      padding: const EdgeInsets.only(
        top: AppSpace.md,
        bottom: AppSpace.xl,
      ),
      children: children,
    );
  }

  /// 搜索结果的第二行优先显示科目标签，比注释更有辨识度。
  String? _subtitleOf(StudyCard card) {
    final String subject = subjectCache.labelOf(card);
    return subject.isEmpty ? null : subject;
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.count});

  final String title;
  final int count;

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
      child: Text(
        '$title · $count',
        style: AppText.caption.copyWith(
          color: p.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
