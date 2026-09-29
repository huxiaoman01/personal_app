import 'package:flutter/material.dart';

import '../../app_globals.dart';
import '../../data/card_repository.dart';
import '../../models/study_card.dart';
import '../../theme/app_theme.dart';
import '../../widgets/card_tile.dart';
import '../../widgets/empty_hint.dart';
import '../../widgets/image_viewer.dart';
import 'card_feature.dart';

/// 通用复习页：一次一小批，遮住背面 → 点开 → 两个按钮判定。
///
/// 「今天 / 明天」只有两级，没有遗忘曲线：
///   点右边（记得 / 做对了）→ reviewed_at 推到现在，今天不再出现，明天重新到期
///   点左边（忘了 / 又错了）→ 只把次数 +1，今天还留在队列里
/// 所以刷完一批再点「再来 10 张」，刚判过左边的那几张会排在最前面。
///
/// 记忆卡片和错题本共用这一页，字从 [feature] 取。
class CardReviewScreen extends StatefulWidget {
  const CardReviewScreen({
    super.key,
    required this.feature,
    this.subject = const SubjectFilter.all(),
  });

  final CardFeature feature;

  /// 只复习这个筛选下的卡片，跟列表页顶部的筛选条保持一致。
  final SubjectFilter subject;

  /// 一批多少张。不让待复习列表无限膨胀，全靠这个数字。
  static const int batchSize = 10;

  @override
  State<CardReviewScreen> createState() => _CardReviewScreenState();
}

class _CardReviewScreenState extends State<CardReviewScreen> {
  List<StudyCard> _batch = const <StudyCard>[];

  /// 当前是这一批的第几张，等于批次长度时就表示这批做完了。
  int _index = 0;

  /// 背面是不是已经翻开。
  bool _revealed = false;

  bool _loading = true;

  /// 进来的时候队列本来就是空的，和「这批做完了」是两回事。
  bool _queueEmpty = false;

  /// 防止手快连点两下，同一张卡被判定两次。
  bool _answering = false;

  @override
  void initState() {
    super.initState();
    _loadBatch();
  }

  Future<void> _loadBatch() async {
    final List<StudyCard> cards = await cardRepository.listDueCards(
      type: widget.feature.type,
      subject: widget.subject,
      limit: CardReviewScreen.batchSize,
      now: DateTime.now(),
    );
    if (!mounted) return;
    setState(() {
      _batch = cards;
      _index = 0;
      _revealed = false;
      _queueEmpty = cards.isEmpty;
      _loading = false;
    });
  }

  Future<void> _answer({required bool remembered}) async {
    if (_answering) return;
    _answering = true;

    final StudyCard card = _batch[_index];
    if (remembered) {
      await cardRepository.markRemembered(card.id!, now: DateTime.now());
    } else {
      await cardRepository.markForgotten(card.id!);
    }

    _answering = false;
    if (!mounted) return;
    setState(() {
      _index++;
      _revealed = false;
    });
  }

  void _reveal() {
    if (_revealed) return;
    setState(() => _revealed = true);
  }

  Future<void> _openImage(StudyCard card, int index) {
    return openImageViewer(
      context,
      names: card.images,
      initialIndex: index,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('复习'),
        actions: <Widget>[
          if (!_loading && !_queueEmpty && _index < _batch.length)
            Center(
              child: Text(
                '第 ${_index + 1} / ${_batch.length} 张',
                style: AppText.badge.copyWith(
                  color: context.palette.textSecondary,
                ),
              ),
            ),
          const SizedBox(width: AppSpace.lg),
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
    if (_queueEmpty) {
      return EmptyHint(
        icon: widget.feature.icon,
        text: '今天没有要复习的卡片',
      );
    }
    if (_index >= _batch.length) {
      return _FinishedView(
        count: _batch.length,
        onAgain: _loadBatch,
        onBack: () => Navigator.of(context).pop(),
      );
    }

    final StudyCard card = _batch[_index];
    return Column(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSize.pagePadding,
              AppSpace.sm,
              AppSize.pagePadding,
              AppSpace.sm,
            ),
            // 换下一张时整块淡出淡入：200ms，不做弹跳缩放。
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _buildCardFace(card, key: ValueKey<int>(card.id!)),
            ),
          ),
        ),
        _buildActions(),
      ],
    );
  }

  /// 卡面：撑满中间整块地方（一张卡就该占住视线），内容多了才滚动。
  Widget _buildCardFace(StudyCard card, {required Key key}) {
    final AppPalette p = context.palette;
    final String back = (card.content ?? '').trim();

    return GestureDetector(
      key: key,
      // 点卡片任意位置都算「我看到了，翻背面」，不用去戳某个小按钮。
      behavior: HitTestBehavior.opaque,
      onTap: _reveal,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: p.iconBlock,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            // 内容短的时候靠 ConstrainedBox 撑满，让正面的字落在中间而不是贴着顶。
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - AppSpace.lg * 2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (card.images.isNotEmpty) ...<Widget>[
                      Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.sm,
                        children: <Widget>[
                          for (int i = 0; i < card.images.length; i++)
                            GestureDetector(
                              onTap: () => _openImage(card, i),
                              child: CardThumb(name: card.images[i]),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.md),
                    ],
                    Text(
                      card.displayTitle,
                      style: AppText.detailTitle.copyWith(color: p.text),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _revealed
                          ? Column(
                              key: const ValueKey<String>('back'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const SizedBox(height: AppSpace.lg),
                                // 卡面底色是 iconBlock，比 palette.divider 还要浅一点，
                                // 直接用它画线几乎看不见，所以从三级文字取色再压淡。
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: p.textTertiary.withValues(alpha: 0.3),
                                ),
                                const SizedBox(height: AppSpace.lg),
                                Text(
                                  back.isEmpty
                                      ? widget.feature.emptyFlipText
                                      : back,
                                  style: AppText.body.copyWith(color: p.text),
                                ),
                              ],
                            )
                          : Padding(
                              padding: const EdgeInsets.only(top: AppSpace.lg),
                              child: Text(
                                widget.feature.revealHint,
                                key: const ValueKey<String>('hint'),
                                style: AppText.caption
                                    .copyWith(color: p.textTertiary),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSize.pagePadding,
        AppSpace.sm,
        AppSize.pagePadding,
        AppSpace.lg,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _ReviewButton(
              label: widget.feature.forgotLabel,
              filled: false,
              onTap: () => _answer(remembered: false),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: _ReviewButton(
              label: widget.feature.rememberedLabel,
              filled: true,
              onTap: () => _answer(remembered: true),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部两个判定按钮：左边描边，右边用主色实心。
class _ReviewButton extends StatelessWidget {
  const _ReviewButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final BorderRadius radius = BorderRadius.circular(AppRadius.card);

    return Material(
      color: filled ? p.primary : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: filled ? null : Border.all(color: p.divider),
            borderRadius: radius,
          ),
          child: Text(
            label,
            style: AppText.body.copyWith(
              color: filled ? p.onPrimary : p.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// 一批刷完的样子：说一句、给一次「再来 10 张」、也给一条退路。
class _FinishedView extends StatelessWidget {
  const _FinishedView({
    required this.count,
    required this.onAgain,
    required this.onBack,
  });

  final int count;
  final VoidCallback onAgain;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final BorderRadius radius = BorderRadius.circular(AppRadius.pill);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.check_circle_outline, size: 40, color: p.textTertiary),
            const SizedBox(height: AppSpace.md),
            Text(
              '今天这 $count 张看完了',
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppSpace.xl),
            SizedBox(
              width: 176,
              child: Material(
                color: p.primary,
                borderRadius: radius,
                child: InkWell(
                  onTap: onAgain,
                  borderRadius: radius,
                  child: SizedBox(
                    height: AppSize.iconBlock,
                    child: Center(
                      child: Text(
                        '再来 10 张',
                        style: AppText.body.copyWith(
                          color: p.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            SizedBox(
              width: 176,
              child: Material(
                color: Colors.transparent,
                borderRadius: radius,
                child: InkWell(
                  onTap: onBack,
                  borderRadius: radius,
                  child: Container(
                    height: AppSize.iconBlock,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: p.divider),
                      borderRadius: radius,
                    ),
                    child: Text(
                      '回卡片库',
                      style: AppText.body.copyWith(color: p.textSecondary),
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
