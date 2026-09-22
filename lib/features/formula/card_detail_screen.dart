import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_globals.dart';
import '../../models/study_card.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_hint.dart';
import '../../widgets/sheet_action.dart';
import 'card_edit_screen.dart';

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
        builder: (BuildContext _) => CardEditScreen(card: card),
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => _FullscreenImages(
          names: card.images,
          initialIndex: initialIndex,
        ),
      ),
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

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      children: <Widget>[
        if (card.images.isNotEmpty) ...<Widget>[
          _ImagePager(
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
                '$subject · $created',
                style: AppText.badge.copyWith(color: p.textTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ImagePager extends StatelessWidget {
  const _ImagePager({
    required this.names,
    required this.page,
    required this.onPageChanged,
    required this.onTap,
  });

  final List<String> names;
  final int page;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Column(
      children: <Widget>[
        SizedBox(
          height: 280,
          child: PageView.builder(
            itemCount: names.length,
            onPageChanged: onPageChanged,
            itemBuilder: (BuildContext context, int index) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSize.pagePadding,
                ),
                child: GestureDetector(
                  onTap: () => onTap(index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: Container(
                      color: p.iconBlock,
                      alignment: Alignment.center,
                      child: Image.file(
                        imageStore.fileOf(names[index]),
                        fit: BoxFit.contain,
                        errorBuilder: (
                          BuildContext _,
                          Object _,
                          StackTrace? _,
                        ) =>
                            Icon(
                          Icons.broken_image_outlined,
                          size: 32,
                          color: p.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (names.length > 1) ...<Widget>[
          const SizedBox(height: AppSpace.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (int i = 0; i < names.length; i++)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == page ? p.primary : p.divider,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 全屏看图：左右滑动 + 双指缩放。
class _FullscreenImages extends StatefulWidget {
  const _FullscreenImages({required this.names, required this.initialIndex});

  final List<String> names;
  final int initialIndex;

  @override
  State<_FullscreenImages> createState() => _FullscreenImagesState();
}

class _FullscreenImagesState extends State<_FullscreenImages> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _page = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 看图页用接近纯黑的深蓝，不参与 app 大面的浅色底。
    const Color viewerBg = Color(0xFF0A1220);
    return Scaffold(
      backgroundColor: viewerBg,
      appBar: AppBar(
        backgroundColor: viewerBg,
        foregroundColor: Colors.white,
        title: Text(
          '${_page + 1} / ${widget.names.length}',
          style: AppText.caption.copyWith(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.names.length,
        onPageChanged: (int i) => setState(() => _page = i),
        itemBuilder: (BuildContext context, int index) {
          return InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: Image.file(
                imageStore.fileOf(widget.names[index]),
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}
