import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../app_globals.dart';
import '../../models/study_card.dart';
import '../../models/subject.dart';
import '../../theme/app_theme.dart';
import '../../widgets/add_star.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/sheet_action.dart';
import '../../widgets/tag_chip.dart';
import '../../widgets/tag_editor.dart';

/// 新增 / 编辑一张卡片。
///
/// 六种功能共用这一个页面——它们本来就是同一张卡片的不同视图，
/// 差别只在显示哪几个字段：
///   公式 = 图片 → 标题 → 注释 → 科目
///   灵感 = 图片 → 标题 → 正文 → 标签
///   记忆 = 图片 → 题目 → 答案 → 科目
///   错题 = 图片 → 标题 → 我当时错在哪 → 科目
///   问题 = 图片 → 问题 → 答案 → 科目
class CardEditScreen extends StatefulWidget {
  const CardEditScreen({super.key, required this.type, this.card});

  /// 卡片类型。新增时由调用方给；编辑已有卡片时传 `card.type`。
  final String type;

  /// null 表示新增。
  final StudyCard? card;

  @override
  State<CardEditScreen> createState() => _CardEditScreenState();
}

class _CardEditScreenState extends State<CardEditScreen> {
  late final TextEditingController _title =
      TextEditingController(text: widget.card?.title ?? '');
  late final TextEditingController _content =
      TextEditingController(text: widget.card?.content ?? '');
  late final List<String> _images =
      List<String>.of(widget.card?.images ?? const <String>[]);
  late final List<String> _originalImages =
      List<String>.of(widget.card?.images ?? const <String>[]);
  late final List<String> _tags =
      List<String>.of(widget.card?.tags ?? const <String>[]);
  late int? _subjectId = widget.card?.subjectId;

  final ImagePicker _picker = ImagePicker();

  List<Subject> _subjects = const <Subject>[];

  /// 这个功能下用过的标签，用来在对话框里一键复用。
  List<String> _knownTags = const <String>[];

  bool _saving = false;
  bool _dirty = false;

  bool get _isNew => widget.card == null;

  /// 灵感有标题，但是选填——想快速记一句时可以不写，
  /// 列表里就退化成用正文首行当标题（老灵感都是这样）。
  bool get _isIdea => widget.type == CardType.idea;

  /// 记忆卡的题目存在 title 里，答案存在 content 里（没有单独的 answer 字段）。
  bool get _isMemory => widget.type == CardType.memory;

  /// 错题的标题存在 title 里，「我当时错在哪」存在 content 里
  /// （设计稿里的 my_mistake 字段和 answer 一样，实际没建）。
  bool get _isMistake => widget.type == CardType.mistake;

  /// 问题存在 title 里，答案存在 content 里。答案空着就是「待解决」。
  bool get _isQuestion => widget.type == CardType.question;

  String get _screenTitle {
    final String action = _isNew ? '新增' : '编辑';
    if (_isIdea) return '$action灵感';
    if (_isMemory) return '$action记忆卡';
    if (_isMistake) return '$action错题';
    if (_isQuestion) return '$action问题';
    return '$action公式';
  }

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    final List<Subject> subjects = await subjectCache.load();
    final List<String> tags =
        await cardRepository.listTags(type: widget.type);
    if (!mounted) return;
    setState(() {
      _subjects = subjects;
      _knownTags = tags;
    });
  }

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ---------------------------------------------------------------- 图片

  Future<void> _showAddImageSheet() async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SheetAction(
              icon: Icons.photo_camera_outlined,
              label: '拍照',
              onTap: () => Navigator.of(sheet).pop('camera'),
            ),
            SheetAction(
              icon: Icons.photo_library_outlined,
              label: '从相册选',
              onTap: () => Navigator.of(sheet).pop('gallery'),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );
    if (action == 'camera') await _pickCamera();
    if (action == 'gallery') await _pickGallery();
  }

  /// 图片长边压到 2400、质量 88，再复制进私有目录。
  static const double _maxImageSide = 2400;
  static const int _imageQuality = 88;

  Future<void> _pickCamera() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: _maxImageSide,
      imageQuality: _imageQuality,
    );
    if (file == null) return;
    await _importFiles(<XFile>[file]);
  }

  Future<void> _pickGallery() async {
    final List<XFile> files = await _picker.pickMultiImage(
      maxWidth: _maxImageSide,
      imageQuality: _imageQuality,
    );
    if (files.isEmpty) return;
    await _importFiles(files);
  }

  Future<void> _importFiles(List<XFile> files) async {
    for (final XFile file in files) {
      final String name = await imageStore.import(file.path);
      _images.add(name);
    }
    if (!mounted) return;
    setState(() {});
    _markDirty();
  }

  Future<void> _removeImage(int index) async {
    final String name = _images[index];
    _images.removeAt(index);
    setState(() {});
    _markDirty();
    // 编辑已有卡片时删掉的图不再属于任何地方，直接清掉，免得留孤儿文件。
    if (!_originalImages.contains(name)) {
      await imageStore.deleteAll(<String>[name]);
    }
  }

  Future<void> _previewImage(int index) {
    return openImageViewer(context, names: _images, initialIndex: index);
  }

  // ---------------------------------------------------------------- 标签

  Future<void> _addTag() async {
    if (_tags.length >= kTagMaxCount) {
      _toast('一条灵感最多 $kTagMaxCount 个标签');
      return;
    }
    final String? name = await showTagEditor(context, suggestions: _knownTags);
    if (name == null || !mounted) return;
    if (_tags.contains(name)) {
      _toast('已经有这个标签了');
      return;
    }
    setState(() => _tags.add(name));
    _markDirty();
  }

  // ------------------------------------------------------------------ 保存

  Future<bool> _confirmDiscard() async {
    final AppPalette p = context.palette;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: const Text('放弃这次修改？'),
        content: const Text('改动还没保存。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(
              '继续编辑',
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

  Future<void> _save() async {
    final String title = _title.text.trim();
    final String content = _content.text.trim();

    if (title.isEmpty && content.isEmpty && _images.isEmpty) {
      if (_isIdea) {
        _toast('写点什么，或者放一张图');
      } else if (_isMemory) {
        _toast('至少写个题目，或者放一张图');
      } else if (_isMistake) {
        _toast('至少写个标题，或者拍一张题');
      } else if (_isQuestion) {
        _toast('至少写个问题，或者拍一张');
      } else {
        _toast('至少写个标题，或者放一张图');
      }
      return;
    }

    setState(() => _saving = true);
    final int now = DateTime.now().millisecondsSinceEpoch;

    if (_isNew) {
      await cardRepository.insertCard(
        StudyCard(
          type: widget.type,
          subjectId: _subjectId,
          // 标题空着就存 null。灵感也能填标题，但选填——没填的（含所有
          // 老灵感）列表里退化成用正文首行当标题。
          title: title.isEmpty ? null : title,
          content: content.isEmpty ? null : content,
          images: _images,
          tags: _tags,
          createdAt: now,
          updatedAt: now,
        ),
      );
    } else {
      await cardRepository.updateCard(
        widget.card!.copyWith(
          subjectId: _subjectId,
          title: title.isEmpty ? null : title,
          content: content.isEmpty ? null : content,
          images: _images,
          tags: _tags,
          updatedAt: now,
        ),
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final NavigatorState navigator = Navigator.of(context);
        final bool discard = await _confirmDiscard();
        if (!discard || !mounted) return;
        navigator.pop(false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_screenTitle),
          actions: <Widget>[
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(
                '保存',
                style: AppText.body.copyWith(
                  color: _saving ? p.textTertiary : p.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSize.pagePadding,
            AppSpace.lg,
            AppSize.pagePadding,
            AppSpace.xl,
          ),
          children: <Widget>[
            // 灵感没有详情页，点开就是这一页——所以时间得显示在这里，
            // 不然一条老灵感点进来完全看不出是什么时候写的。
            if (_isIdea && !_isNew) ...<Widget>[
              _CreatedStamp(
                createdAt: widget.card!.createdAt,
                updatedAt: widget.card!.updatedAt,
              ),
              const SizedBox(height: AppSpace.lg),
            ],
            _ImageGrid(
              images: _images,
              onAdd: _showAddImageSheet,
              onPreview: _previewImage,
              onRemove: _removeImage,
            ),
            const SizedBox(height: AppSpace.xl),
            if (_isIdea)
              ..._buildIdeaFields()
            else if (_isMemory)
              ..._buildMemoryFields()
            else if (_isMistake)
              ..._buildMistakeFields()
            else if (_isQuestion)
              ..._buildQuestionFields()
            else
              ..._buildFormulaFields(),
          ],
        ),
      ),
    );
  }

  /// 公式：标题 + 注释 + 科目。
  List<Widget> _buildFormulaFields() {
    return <Widget>[
      _LabeledField(
        label: '标题',
        controller: _title,
        hint: '比如：单纯形法判别准则',
        textStyle: AppText.listTitle,
        onChanged: _markDirty,
      ),
      const SizedBox(height: AppSpace.lg),
      _LabeledField(
        label: '注释',
        controller: _content,
        hint: '用一句人话写下最容易忘的地方',
        textStyle: AppText.body,
        minLines: 3,
        maxLines: 8,
        onChanged: _markDirty,
      ),
      const SizedBox(height: AppSpace.lg),
      _SubjectPicker(
        subjects: _subjects,
        selectedId: _subjectId,
        onChanged: (int? id) {
          setState(() => _subjectId = id);
          _markDirty();
        },
      ),
    ];
  }

  /// 灵感：标题 + 正文 + 标签。不绑科目。
  List<Widget> _buildIdeaFields() {
    return <Widget>[
      _LabeledField(
        label: '标题',
        controller: _title,
        hint: '一句话说清这条是啥，可不填',
        textStyle: AppText.listTitle,
        onChanged: _markDirty,
      ),
      const SizedBox(height: AppSpace.lg),
      _LabeledField(
        label: '正文',
        controller: _content,
        hint: '想到什么就写什么，不用讲究',
        textStyle: AppText.body,
        minLines: 5,
        maxLines: 12,
        onChanged: _markDirty,
      ),
      const SizedBox(height: AppSpace.lg),
      _TagField(
        tags: _tags,
        onAdd: _addTag,
        onRemove: (String tag) {
          setState(() => _tags.remove(tag));
          _markDirty();
        },
      ),
    ];
  }

  /// 记忆卡：题目 + 答案 + 科目。题目要能写一整句问句，所以给两行起。
  List<Widget> _buildMemoryFields() {
    return <Widget>[
      _LabeledField(
        label: '题目',
        controller: _title,
        hint: '比如：单纯形法的判别准则是什么？',
        textStyle: AppText.listTitle,
        minLines: 2,
        maxLines: 4,
        onChanged: _markDirty,
      ),
      const SizedBox(height: AppSpace.lg),
      _LabeledField(
        label: '答案',
        controller: _content,
        hint: '用一句人话写下你要记住的东西',
        textStyle: AppText.body,
        minLines: 4,
        maxLines: 10,
        onChanged: _markDirty,
      ),
      const SizedBox(height: AppSpace.lg),
      _SubjectPicker(
        subjects: _subjects,
        selectedId: _subjectId,
        onChanged: (int? id) {
          setState(() => _subjectId = id);
          _markDirty();
        },
      ),
    ];
  }

  /// 错题：标题 + 我当时错在哪 + 科目。
  /// 题目本身拍照片就行——手机上打数学公式太痛苦，图片区在最上面。
  List<Widget> _buildMistakeFields() {
    return <Widget>[
      _LabeledField(
        label: '标题',
        controller: _title,
        hint: '比如：对偶单纯形法那题又算错符号',
        textStyle: AppText.listTitle,
        onChanged: _markDirty,
      ),
      const SizedBox(height: AppSpace.lg),
      _LabeledField(
        label: '我当时错在哪',
        controller: _content,
        hint: '错在哪一步、当时怎么想的，写下来最有用',
        textStyle: AppText.body,
        minLines: 4,
        maxLines: 10,
        onChanged: _markDirty,
      ),
      const SizedBox(height: AppSpace.lg),
      _SubjectPicker(
        subjects: _subjects,
        selectedId: _subjectId,
        onChanged: (int? id) {
          setState(() => _subjectId = id);
          _markDirty();
        },
      ),
    ];
  }

  /// 问题：问题 + 答案 + 科目。答案可以先空着——那正是「待解决」的意思。
  List<Widget> _buildQuestionFields() {
    return <Widget>[
      _LabeledField(
        label: '问题',
        controller: _title,
        hint: '比如：为什么单纯形法要用人工变量？',
        textStyle: AppText.listTitle,
        minLines: 2,
        maxLines: 4,
        onChanged: _markDirty,
      ),
      const SizedBox(height: AppSpace.lg),
      _LabeledField(
        label: '答案',
        controller: _content,
        hint: '问到了就回填，先空着也行',
        textStyle: AppText.body,
        minLines: 4,
        maxLines: 10,
        onChanged: _markDirty,
      ),
      const SizedBox(height: AppSpace.lg),
      _SubjectPicker(
        subjects: _subjects,
        selectedId: _subjectId,
        onChanged: (int? id) {
          setState(() => _subjectId = id);
          _markDirty();
        },
      ),
    ];
  }
}

/// 编辑已有灵感时显示的一行时间。
class _CreatedStamp extends StatelessWidget {
  const _CreatedStamp({required this.createdAt, required this.updatedAt});

  final int createdAt;
  final int updatedAt;

  /// 一分钟以内不算「修改过」——刚存完又补了两个字，不值得单独标一行。
  static const int _editedThreshold = 60 * 1000;

  static String _format(int milliseconds) => DateFormat('yyyy-MM-dd HH:mm')
      .format(DateTime.fromMillisecondsSinceEpoch(milliseconds));

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final bool edited = updatedAt - createdAt > _editedThreshold;
    // 两个时间点分两行写。「创建于…… 改于……」并排时几乎顶满一行，
    // 换台窄一点的手机就会折行，不如一开始就分好。
    final String text = edited
        ? '创建于 ${_format(createdAt)}\n改于 ${_format(updatedAt)}'
        : '创建于 ${_format(createdAt)}';

    return Text(text, style: AppText.caption.copyWith(color: p.textSecondary));
  }
}

class _ImageGrid extends StatelessWidget {
  const _ImageGrid({
    required this.images,
    required this.onAdd,
    required this.onPreview,
    required this.onRemove,
  });

  final List<String> images;
  final VoidCallback onAdd;
  final ValueChanged<int> onPreview;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppSpace.sm,
        mainAxisSpacing: AppSpace.sm,
      ),
      itemCount: images.length + 1,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(AppRadius.thumb),
            child: CustomPaint(
              painter: _DashedBorderPainter(
                color: p.textTertiary,
                radius: AppRadius.thumb,
              ),
              child: Center(
                // 这一格也是「＋」，跟着换成星星。
                child: const AddStar(size: 32),
              ),
            ),
          );
        }
        final int imageIndex = index - 1;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 点缩略图能全屏放大——不然存进来的图就白存了。
            GestureDetector(
              onTap: () => onPreview(imageIndex),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.thumb),
                child: Image.file(
                  imageStore.fileOf(images[imageIndex]),
                  fit: BoxFit.cover,
                  errorBuilder: (
                    BuildContext _,
                    Object _,
                    StackTrace? _,
                  ) =>
                      Container(
                    color: p.iconBlock,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: p.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () => onRemove(imageIndex),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: p.text.withValues(alpha: 0.6),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(AppRadius.thumb),
                      topRight: Radius.circular(AppRadius.thumb),
                    ),
                  ),
                  child: Icon(Icons.close, size: 14, color: p.bg),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.textStyle,
    required this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final TextStyle textStyle;
  final VoidCallback onChanged;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: AppText.badge.copyWith(color: p.textSecondary)),
        const SizedBox(height: AppSpace.sm),
        TextField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          style: textStyle.copyWith(color: p.text),
          cursorColor: p.primary,
          onChanged: (String _) => onChanged(),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: textStyle.copyWith(color: p.textTertiary),
            contentPadding: const EdgeInsets.only(bottom: AppSpace.sm),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: p.divider),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: p.primary),
            ),
          ),
        ),
      ],
    );
  }
}

/// 标签区：已经选的标签 + 一颗「加标签」。
class _TagField extends StatelessWidget {
  const _TagField({
    required this.tags,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> tags;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('标签', style: AppText.badge.copyWith(color: p.textSecondary)),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: <Widget>[
            for (final String tag in tags)
              TagChip(label: tag, onDeleted: () => onRemove(tag)),
            InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md,
                  vertical: AppSpace.xs,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: p.divider),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const AddStar(size: 18),
                    const SizedBox(width: AppSpace.xs),
                    Text(
                      '加标签',
                      style: AppText.caption.copyWith(color: p.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SubjectPicker extends StatelessWidget {
  const _SubjectPicker({
    required this.subjects,
    required this.selectedId,
    required this.onChanged,
  });

  final List<Subject> subjects;
  final int? selectedId;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final List<({int? id, String label})> options =
        <({int? id, String label})>[
      (id: null, label: '未分类'),
      for (final Subject s in subjects) (id: s.id, label: s.name),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('科目', style: AppText.badge.copyWith(color: p.textSecondary)),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: <Widget>[
            for (final ({int? id, String label}) option in options)
              InkWell(
                onTap: () => onChanged(option.id),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.sm,
                  ),
                  decoration: BoxDecoration(
                    color: selectedId == option.id
                        ? p.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: selectedId == option.id ? p.primary : p.divider,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    option.label,
                    style: AppText.caption.copyWith(
                      color: selectedId == option.id ? p.onPrimary : p.text,
                      fontWeight: selectedId == option.id
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 虚线边框，用在「加图片」那一格。
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ),
      );

    const double dash = 4;
    const double gap = 4;
    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double end =
            (distance + dash) > metric.length ? metric.length : distance + dash;
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
