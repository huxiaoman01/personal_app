import 'package:flutter/material.dart';

import '../../app_globals.dart';
import '../../models/study_card.dart';
import '../../theme/app_theme.dart';
import '../export/export_sheet.dart';
import '../formula/formula_list_screen.dart';
import '../placeholder/placeholder_screen.dart';
import '../trash/trash_screen.dart';
import 'search_screen.dart';

/// 首页六宫格的一项。
class _HubEntry {
  const _HubEntry({
    required this.label,
    required this.icon,
    required this.ready,
    this.type,
  });

  final String label;
  final IconData icon;

  /// v0 只有公式手册能点开。
  final bool ready;

  /// 对应的卡片类型；考点大纲不是卡片，所以是 null。
  final String? type;
}

const List<_HubEntry> _entries = <_HubEntry>[
  _HubEntry(
    label: '公式手册',
    icon: Icons.functions,
    ready: true,
    type: CardType.formula,
  ),
  _HubEntry(
    label: '灵感记录',
    icon: Icons.lightbulb_outline,
    ready: false,
    type: CardType.idea,
  ),
  _HubEntry(
    label: '记忆卡片',
    icon: Icons.style_outlined,
    ready: false,
    type: CardType.memory,
  ),
  _HubEntry(
    label: '错题本',
    icon: Icons.error_outline,
    ready: false,
    type: CardType.mistake,
  ),
  _HubEntry(
    label: '问题收集箱',
    icon: Icons.help_outline,
    ready: false,
    type: CardType.question,
  ),
  _HubEntry(
    label: '考点大纲',
    icon: Icons.check_circle_outline,
    ready: false,
  ),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, int> _counts = const <String, int>{};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final Map<String, int> counts = await cardRepository.countByType();
    if (!mounted) return;
    setState(() => _counts = counts);
  }

  Future<void> _openEntry(_HubEntry entry) async {
    if (!entry.ready) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext _) =>
              PlaceholderScreen(title: entry.label),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const FormulaListScreen(),
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
                    onTrash: _openTrash,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppSize.pagePadding,
                  0,
                  AppSize.pagePadding,
                  AppSpace.xl,
                ),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 104,
                  crossAxisSpacing: AppSpace.lg,
                  mainAxisSpacing: 20,
                ),
                itemCount: _entries.length,
                itemBuilder: (BuildContext context, int index) {
                  final _HubEntry entry = _entries[index];
                  return _HubCard(
                    entry: entry,
                    count: entry.type == null ? null : (_counts[entry.type] ?? 0),
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
                '搜公式、灵感、错题…',
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
  const _MoreButton({required this.onExport, required this.onTrash});

  final VoidCallback onExport;
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

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.entry,
    required this.count,
    required this.onTap,
  });

  final _HubEntry entry;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final int? n = count;

    return Opacity(
      opacity: entry.ready ? 1 : 0.4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        overlayColor: WidgetStatePropertyAll<Color>(
          p.primary.withValues(alpha: 0.08),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: AppSize.iconBlock,
              height: AppSize.iconBlock,
              decoration: BoxDecoration(
                color: p.iconBlock,
                borderRadius: BorderRadius.circular(AppRadius.iconBlock),
              ),
              child: Icon(entry.icon, size: 22, color: p.primary),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              entry.label,
              style: AppText.listTitle.copyWith(color: p.text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              n == null ? '待开发' : '$n 张',
              style: AppText.badge.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
