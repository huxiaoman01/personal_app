import 'package:flutter/material.dart';

import '../../app_globals.dart';
import '../../models/subject.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_hint.dart';

/// 科目管理：拖动排序、改名、删除。删除时把卡片转成「未分类」。
class SubjectManageScreen extends StatefulWidget {
  const SubjectManageScreen({super.key});

  @override
  State<SubjectManageScreen> createState() => _SubjectManageScreenState();
}

class _SubjectManageScreenState extends State<SubjectManageScreen> {
  List<Subject> _subjects = const <Subject>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<Subject> subjects = await subjectCache.load(force: true);
    if (!mounted) return;
    setState(() {
      _subjects = subjects;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final String? name = await _askName(title: '添加科目');
    if (name == null || name.isEmpty) return;
    try {
      await cardRepository.addSubject(name);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个科目已经存在了')),
      );
      return;
    }
    await _reload();
  }

  Future<void> _rename(Subject subject) async {
    final String? name = await _askName(title: '重命名科目', initial: subject.name);
    if (name == null || name.isEmpty || name == subject.name) return;
    try {
      await cardRepository.renameSubject(subject.id, name);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个科目已经存在了')),
      );
      return;
    }
    await _reload();
  }

  Future<void> _delete(Subject subject) async {
    final int count = await cardRepository.countCardsInSubject(subject.id);
    if (!mounted) return;

    final AppPalette p = context.palette;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: Text('删除「${subject.name}」？'),
        content: Text(
          count == 0
              ? '这个科目下还没有卡片。'
              : '删除后，这 $count 张卡片会变成「未分类」，卡片本身不会丢。',
        ),
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
              '删除',
              style: AppText.body.copyWith(color: p.primary),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await cardRepository.deleteSubject(subject.id);
    await _reload();
  }

  Future<String?> _askName({required String title, String initial = ''}) async {
    final TextEditingController controller =
        TextEditingController(text: initial);
    final AppPalette p = context.palette;
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppText.body.copyWith(color: p.text),
          cursorColor: p.primary,
          decoration: InputDecoration(
            hintText: '比如：运筹',
            hintStyle: AppText.body.copyWith(color: p.textTertiary),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: p.divider),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: p.primary),
            ),
          ),
          onSubmitted: (String value) =>
              Navigator.of(dialog).pop(value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: Text(
              '取消',
              style: AppText.body.copyWith(color: p.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialog).pop(controller.text.trim()),
            child: Text(
              '确定',
              style: AppText.body.copyWith(color: p.primary),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _persistOrder() async {
    await cardRepository.reorderSubjects(
      _subjects.map((Subject s) => s.id).toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('科目管理')),
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
                  child: _subjects.isEmpty
                      ? const EmptyHint(
                          icon: Icons.label_outline,
                          text: '还没有科目，点下面添加一个',
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.only(bottom: AppSpace.lg),
                          itemCount: _subjects.length,
                          onReorderItem: (int oldIndex, int newIndex) {
                            setState(() {
                              final Subject moved =
                                  _subjects.removeAt(oldIndex);
                              _subjects.insert(newIndex, moved);
                            });
                            _persistOrder();
                          },
                          itemBuilder: (BuildContext context, int index) {
                            final Subject subject = _subjects[index];
                            return SizedBox(
                              key: ValueKey<int>(subject.id),
                              height: AppSize.subjectRowHeight,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSize.pagePadding,
                                ),
                                child: Row(
                                  children: <Widget>[
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Icon(
                                        Icons.drag_handle,
                                        color: p.textTertiary,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpace.md),
                                    Expanded(
                                      child: Text(
                                        subject.name,
                                        style: AppText.body.copyWith(
                                          color: p.text,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: IconButton(
                                        tooltip: '重命名',
                                        iconSize: 20,
                                        onPressed: () => _rename(subject),
                                        icon: Icon(
                                          Icons.edit_outlined,
                                          color: p.textSecondary,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: IconButton(
                                        tooltip: '删除',
                                        iconSize: 20,
                                        onPressed: () => _delete(subject),
                                        icon: Icon(
                                          Icons.delete_outline,
                                          color: p.textSecondary,
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
                const Divider(height: 1, thickness: 1),
                SafeArea(
                  top: false,
                  child: TextButton.icon(
                    onPressed: _add,
                    icon: Icon(Icons.add, size: 20, color: p.primary),
                    label: Text(
                      '添加科目',
                      style: AppText.body.copyWith(color: p.primary),
                    ),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
