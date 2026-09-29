import 'package:flutter/material.dart';

import '../../app_globals.dart';
import '../../models/study_card.dart';
import '../../theme/app_theme.dart';
import '../export/export_sheet.dart';
import '../export/import_sheet.dart';
import '../formula/formula_list_screen.dart';
import '../idea/idea_list_screen.dart';
import '../card/card_feature.dart';
import '../card/card_library_screen.dart';
import '../placeholder/placeholder_screen.dart';
import '../question/question_list_screen.dart';
import '../trash/trash_screen.dart';
import 'search_screen.dart';

/// 首页的一个功能入口。
///
/// 定义成公开常量（而不是文件私有的）是为了让测试能直接检查它——
/// 六个入口、配图路径、描述文案都能被测试守住。
class HubEntry {
  const HubEntry({
    required this.label,
    required this.description,
    required this.asset,
    required this.ready,
    this.type,
  });

  final String label;

  /// 第二行的说明文字。
  final String description;

  /// 右侧配图，透明 PNG。
  final String asset;

  /// 已经做完、能点开的功能。没做完的点进去是占位页。
  final bool ready;

  /// 对应的卡片类型；考点大纲不是卡片，所以是 null。
  final String? type;
}

/// 顺序就是首页从上到下的顺序，右侧配图也按这个顺序。
const List<HubEntry> kHubEntries = <HubEntry>[
  HubEntry(
    label: '公式手册',
    description: '各科常忘公式，拍照存下来随时查',
    asset: 'assets/hub/hub_1.png',
    ready: true,
    type: CardType.formula,
  ),
  HubEntry(
    label: '灵感记录',
    description: '想到就写，自动记时间，可打标签',
    asset: 'assets/hub/hub_2.png',
    ready: true,
    type: CardType.idea,
  ),
  HubEntry(
    label: '记忆卡片',
    description: '导入简答题，今天明天简单复习',
    asset: 'assets/hub/hub_3.png',
    ready: true,
    type: CardType.memory,
  ),
  HubEntry(
    label: '错题本',
    description: '记下做错的题和错在哪一步',
    asset: 'assets/hub/hub_4.png',
    ready: true,
    type: CardType.mistake,
  ),
  HubEntry(
    label: '问题收集箱',
    description: '不会的先记下，问完再回填答案',
    asset: 'assets/hub/hub_5.png',
    ready: true,
    type: CardType.question,
  ),
  HubEntry(
    label: '考点大纲',
    description: '大纲知识点打勾，看掌握进度',
    asset: 'assets/hub/hub_6.png',
    ready: false,
  ),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 每种类型各有多少张。
  Map<String, int> _counts = const <String, int>{};

  /// 还没有答案的问题有几条。
  ///
  /// 首页别的数字都是「这个功能里一共多少条」，只有问题收集箱要的是
  /// 「还欠着几条」——那才是这个数字存在的意义。
  int _pendingQuestions = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    // 两个统计一起发出去：都是读同一张表，没有先后关系，串着等只是白等一轮。
    final Future<Map<String, int>> counts =
        cardRepository.countByType();
    final Future<int> pending =
        cardRepository.countPendingCards(type: CardType.question);
    final Map<String, int> byType = await counts;
    final int pendingQuestions = await pending;
    if (!mounted) return;
    setState(() {
      _counts = byType;
      _pendingQuestions = pendingQuestions;
    });
  }

  /// 已经做完的入口按类型分发到各自的列表页；没做完的先给占位页。
  Widget _pageFor(HubEntry entry) {
    if (!entry.ready) {
      return PlaceholderScreen(title: entry.label);
    }
    if (entry.type == CardType.idea) return const IdeaListScreen();
    if (entry.type == CardType.question) return const QuestionListScreen();
    // 记忆卡和错题本共用同一个卡片库页面，按类型查配置就行。
    final CardFeature? feature = cardFeatureOf(entry.type);
    if (feature != null) return CardLibraryScreen(feature: feature);
    return const FormulaListScreen();
  }

  /// 入口右边那个数字。考点大纲不是卡片，所以是 null（显示「待开发」）。
  int? _countFor(HubEntry entry) {
    if (entry.type == null) return null;
    if (entry.type == CardType.question) return _pendingQuestions;
    return _counts[entry.type] ?? 0;
  }

  Future<void> _openEntry(HubEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => _pageFor(entry),
      ),
    );
    await _reload();
  }

  Future<void> _openSearch() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext _) => const SearchScreen()),
    );
  }

  Future<void> _openTrash() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext _) => const TrashScreen()),
    );
    await _reload();
  }

  /// 导入成功会让各个入口的数字全变，所以拿返回值决定要不要重算一遍。
  Future<void> _openImport() async {
    final bool imported = await showImportSheet(context);
    if (imported) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSize.pagePadding,
                AppSpace.md,
                AppSize.pagePadding,
                0,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(child: _SearchEntry(onTap: _openSearch)),
                  const SizedBox(width: AppSpace.xl),
                  _MoreButton(
                    onExport: () => showExportSheet(context),
                    onImport: _openImport,
                    onTrash: _openTrash,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSize.pagePadding,
                  0,
                  AppSize.pagePadding,
                  AppSpace.xl,
                ),
                itemCount: kHubEntries.length,
                separatorBuilder: (BuildContext _, int _) =>
                    const SizedBox(height: AppSpace.md),
                itemBuilder: (BuildContext context, int index) {
                  final HubEntry entry = kHubEntries[index];
                  return _HubRow(
                    entry: entry,
                    count: _countFor(entry),
                    onTap: () => _openEntry(entry),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部搜索入口。点了才跳搜索页，本身不接收输入。
class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        height: AppSize.searchHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        decoration: BoxDecoration(
          color: p.iconBlock,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.search, size: 18, color: p.textTertiary),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                '搜公式、灵感、记忆…',
                style: AppText.caption.copyWith(color: p.textTertiary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({
    required this.onExport,
    required this.onImport,
    required this.onTrash,
  });

  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback onTrash;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return SizedBox(
      width: AppSize.iconBlock,
      height: AppSize.iconBlock,
      child: PopupMenuButton<String>(
        tooltip: '更多',
        icon: Icon(Icons.more_horiz, color: p.textSecondary),
        color: p.surface,
        elevation: 0,
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        onSelected: (String value) {
          if (value == 'export') onExport();
          if (value == 'import') onImport();
          if (value == 'trash') onTrash();
        },
        itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'export',
            child: Text(
              '导出全部数据',
              style: AppText.body.copyWith(color: p.text),
            ),
          ),
          PopupMenuItem<String>(
            value: 'import',
            child: Text(
              '导入数据',
              style: AppText.body.copyWith(color: p.text),
            ),
          ),
          PopupMenuItem<String>(
            value: 'trash',
            child: Text(
              '最近删除',
              style: AppText.body.copyWith(color: p.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一个整宽的功能按钮：左边名称 + 描述，右边角色贴纸。
class _HubRow extends StatelessWidget {
  const _HubRow({
    required this.entry,
    required this.count,
    required this.onTap,
  });

  final HubEntry entry;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final int? n = count;
    final BorderRadius radius = BorderRadius.circular(AppRadius.card);

    return Opacity(
      opacity: entry.ready ? 1 : 0.4,
      child: Material(
        color: p.iconBlock,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          overlayColor: WidgetStatePropertyAll<Color>(
            p.primary.withValues(alpha: 0.08),
          ),
          child: SizedBox(
            height: AppSize.hubRowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                entry.label,
                                style:
                                    AppText.listTitle.copyWith(color: p.text),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppSpace.sm),
                            Text(
                              n == null ? '待开发' : '$n',
                              style: AppText.badge.copyWith(
                                color: p.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          entry.description,
                          style: AppText.caption.copyWith(
                            color: p.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Image.asset(
                    entry.asset,
                    width: AppSize.hubThumb,
                    height: AppSize.hubThumb,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
