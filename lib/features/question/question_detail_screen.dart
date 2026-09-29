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

/// 问题详情：问题 + 一个能直接写的答案框。
///
/// 「回填答案」不该再跳一层页面，所以答案区就是这个页面上的输入框：
/// 写完点「保存答案」，这条问题就从待解决变成已解决；把答案清空再保存，
/// 它就退回待解决——不用另做一个「标记为未解决」的按钮。
class QuestionDetailScreen extends StatefulWidget {
  const QuestionDetailScreen({super.key, required this.cardId});

  final int cardId;

  @override
  State<QuestionDetailScreen> createState() => _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends State<QuestionDetailScreen> {
  final TextEditingController _answer = TextEditingController();

  StudyCard? _card;
  bool _loading = true;
  int _page = 0;

  /// 答案框改了但还没保存。返回时要靠它决定弹不弹确认。
  bool _dirty = false;

  bool _saving = false;

  /// 进来的时候这条是不是已经解决了，保存后用它判断状态有没有变。
  bool _wasSolved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final StudyCard? card = await cardRepository.getCard(widget.cardId);
    if (!mounted) return;
    setState(() {
      _card = card;
      // 这里用直接赋值而不是 controller 的监听，所以不会把「载入」当成「改动」。
      _answer.text = card?.content ?? '';
      _dirty = false;
      _wasSolved = card?.hasContent ?? false;
      _loading = false;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _saveAnswer() async {
    final StudyCard? card = _card;
    if (card == null) return;
    final String answer = _answer.text.trim();

    setState(() => _saving = true);
    await cardRepository.updateCard(
      card.copyWith(
        // 空白答案就当没写，这样「清空 = 回到待解决」才成立。
        content: answer.isEmpty ? null : answer,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    final bool nowSolved = answer.isNotEmpty;
    final bool statusChanged = nowSolved != _wasSolved;
    await _load();
    if (!mounted) return;
    setState(() => _saving = false);
    // 只有状态真的变了才提示一句，平常改几个字不用打扰。
    if (statusChanged) {
      _toast(nowSolved ? '已解决' : '已回到待解决');
    }
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
    _toast('已移入最近删除，30 天内可以恢复');
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

  Future<bool> _confirmDiscard() async {
    final AppPalette p = context.palette;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: const Text('放弃这次修改？'),
        content: const Text('答案还没保存。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(
              '继续写',
              style: AppText.body.copyWith(color: p.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(
              '放弃',
              style: AppText.body.copyWith(color: p.primary),
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final StudyCard? card = _card;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final NavigatorState navigator = Navigator.of(context);
        final bool discard = await _confirmDiscard();
        if (!discard || !mounted) return;
        navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          actions: <Widget>[
            IconButton(
              tooltip: (card?.pinned ?? false) ? '取消置顶' : '置顶',
              onPressed: card == null ? null : _togglePin,
              icon: Icon(
                (card?.pinned ?? false)
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
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
    final StudyCard? card = _card;
    if (card == null) {
      return const EmptyHint(icon: Icons.error_outline, text: '这个问题已经不在了');
    }

    final AppPalette p = context.palette;
    final String created = DateFormat('yyyy-MM-dd').format(
      DateTime.fromMillisecondsSinceEpoch(card.createdAt),
    );
    final String subject = subjectCache.labelOf(card);
    final String status = card.hasContent ? '已解决' : '待解决';

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
              const SizedBox(height: AppSpace.md),
              Text(
                '$subject · $status · $created',
                style: AppText.badge.copyWith(color: p.textTertiary),
              ),
              const SizedBox(height: AppSpace.lg),
              const Divider(height: 1, thickness: 1),
              const SizedBox(height: AppSpace.lg),
              Text('答案', style: AppText.badge.copyWith(color: p.textSecondary)),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _answer,
                minLines: 4,
                maxLines: 12,
                style: AppText.body.copyWith(color: p.text),
                cursorColor: p.primary,
                onChanged: (String _) {
                  if (_dirty) return;
                  setState(() => _dirty = true);
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '问到了就写在这里；写完自动变成已解决',
                  hintStyle: AppText.body.copyWith(color: p.textTertiary),
                  contentPadding: const EdgeInsets.only(bottom: AppSpace.sm),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: p.divider),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: p.primary),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              _SaveButton(
                enabled: _dirty && !_saving,
                onTap: _saveAnswer,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 「保存答案」：没改动的时候是灰的，改了就变成主色实心。
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final BorderRadius radius = BorderRadius.circular(AppRadius.card);

    return Material(
      color: enabled ? p.primary : p.iconBlock,
      borderRadius: radius,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: radius,
        child: SizedBox(
          height: AppSize.iconBlock,
          child: Center(
            child: Text(
              '保存答案',
              style: AppText.body.copyWith(
                color: enabled ? p.onPrimary : p.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
