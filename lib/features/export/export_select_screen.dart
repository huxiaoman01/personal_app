import 'package:flutter/material.dart';

import '../../app_globals.dart';
import '../../data/export_service.dart';
import '../../models/study_card.dart';
import '../../models/subject.dart';
import '../../theme/app_theme.dart';
import 'export_sheet.dart';

/// 导出前先挑一下要导什么：哪些功能、哪些科目。
///
/// 卡片入选的条件是「功能被选中 **且** 科目被选中」。灵感不绑科目，
/// 所以它和没归类的卡片一起算在「未分类」那一项里——界面上写了这句说明，
/// 不然用户会以为灵感没导出来是 bug。
class ExportSelectScreen extends StatefulWidget {
  const ExportSelectScreen({super.key});

  @override
  State<ExportSelectScreen> createState() => _ExportSelectScreenState();
}

class _ExportSelectScreenState extends State<ExportSelectScreen> {
  /// 全部未删除的卡片，读一次，勾选时在内存里筛。
  List<StudyCard> _cards = const <StudyCard>[];
  List<Subject> _subjects = const <Subject>[];
  bool _loading = true;

  /// 默认全选：进来什么都不用动，点「导出」就和以前一模一样。
  Set<String> _types = CardType.all.toSet();
  Set<int?> _subjectIds = <int?>{null};

  /// 功能入口的显示名。顺序就是首页那个顺序。
  static const List<({String type, String label})> _typeOptions =
      <({String type, String label})>[
    (type: CardType.formula, label: '公式手册'),
    (type: CardType.idea, label: '灵感记录'),
    (type: CardType.memory, label: '记忆卡片'),
    (type: CardType.mistake, label: '错题本'),
    (type: CardType.question, label: '问题收集箱'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<StudyCard> cards = await cardRepository.listCardsForExport();
    final List<Subject> subjects = await subjectCache.load(force: true);
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _subjects = subjects;
      // 科目默认也全选（含未分类）。
      _subjectIds = <int?>{
        null,
        for (final Subject s in subjects) s.id,
      };
      _loading = false;
    });
  }

  ExportSelection get _selection =>
      ExportSelection(types: _types, subjectIds: _subjectIds);

  List<StudyCard> get _picked =>
      _cards.where(_selection.includes).toList(growable: false);

  /// 图片按文件名去重——同一张图被几张卡片引用只算一次，和打包时一致。
  int get _imageCount {
    final Set<String> names = <String>{};
    for (final StudyCard card in _picked) {
      names.addAll(card.images);
    }
    return names.length;
  }

  /// 是不是「什么都没筛」，只用来决定文件名带不带「部分」两个字。
  bool get _isFull {
    final bool allTypes = _types.length == CardType.all.length;
    final bool allSubjects = _subjectIds.length == _subjects.length + 1;
    return allTypes && allSubjects;
  }

  void _toggleType(String type) {
    setState(() {
      if (!_types.remove(type)) _types.add(type);
    });
  }

  void _toggleSubject(int? id) {
    setState(() {
      if (!_subjectIds.remove(id)) _subjectIds.add(id);
    });
  }

  void _toggleAllTypes() {
    setState(() {
      _types = _types.length == CardType.all.length
          ? <String>{}
          : CardType.all.toSet();
    });
  }

  void _toggleAllSubjects() {
    setState(() {
      _subjectIds = _subjectIds.length == _subjects.length + 1
          ? <int?>{}
          : <int?>{
              null,
              for (final Subject s in _subjects) s.id,
            };
    });
  }

  Future<void> _export() async {
    await showExportSheet(
      context,
      selection: _isFull ? null : _selection,
    );
    if (!mounted) return;
    // 分享面板/保存对话框关掉之后就退回首页，不用再手动返回一次。
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('导出数据')),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: AppSpace.lg),
                    children: <Widget>[
                      _SectionHeader(
                        title: '导出哪些功能',
                        actionLabel:
                            _types.length == CardType.all.length ? '全不选' : '全选',
                        onAction: _toggleAllTypes,
                      ),
                      for (final ({String type, String label}) option
                          in _typeOptions)
                        _PickRow(
                          label: option.label,
                          selected: _types.contains(option.type),
                          onTap: () => _toggleType(option.type),
                        ),
                      const SizedBox(height: AppSpace.lg),
                      _SectionHeader(
                        title: '导出哪些科目',
                        actionLabel: _subjectIds.length == _subjects.length + 1
                            ? '全不选'
                            : '全选',
                        onAction: _toggleAllSubjects,
                      ),
                      for (final Subject subject in _subjects)
                        _PickRow(
                          label: subject.name,
                          selected: _subjectIds.contains(subject.id),
                          onTap: () => _toggleSubject(subject.id),
                        ),
                      _PickRow(
                        label: '未分类',
                        note: '含所有灵感',
                        selected: _subjectIds.contains(null),
                        onTap: () => _toggleSubject(null),
                      ),
                    ],
                  ),
                ),
                _buildBottomBar(p),
              ],
            ),
    );
  }

  Widget _buildBottomBar(AppPalette p) {
    final int count = _picked.length;
    final bool enabled = count > 0;
    final BorderRadius radius = BorderRadius.circular(AppRadius.pill);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSize.pagePadding,
        AppSpace.md,
        AppSize.pagePadding,
        AppSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            enabled
                ? '将导出 $count 张卡片 · $_imageCount 张图片'
                : '至少选一个功能或科目',
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(
              color: enabled ? p.textSecondary : p.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Material(
            color: enabled ? p.primary : p.iconBlock,
            borderRadius: radius,
            child: InkWell(
              onTap: enabled ? _export : null,
              borderRadius: radius,
              child: SizedBox(
                height: AppSize.iconBlock,
                child: Center(
                  child: Text(
                    '导出',
                    style: AppText.body.copyWith(
                      color: enabled ? p.onPrimary : p.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分组标题 + 右边一个「全选 / 全不选」。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSize.pagePadding,
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: AppText.badge.copyWith(color: p.textSecondary),
            ),
          ),
          TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel,
              style: AppText.caption.copyWith(color: p.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一行可选中的东西：左边名字，右边一个圆圈或对勾。
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.note,
  });

  final String label;

  /// 跟在名字后面的小字，比如「含所有灵感」。
  final String? note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final String? noteText = note;

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: AppSize.subjectRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSize.pagePadding,
          ),
          child: Row(
            children: <Widget>[
              Text(label, style: AppText.body.copyWith(color: p.text)),
              if (noteText != null) ...<Widget>[
                const SizedBox(width: AppSpace.sm),
                Text(
                  noteText,
                  style: AppText.caption.copyWith(color: p.textTertiary),
                ),
              ],
              const Spacer(),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: selected ? p.primary : p.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
