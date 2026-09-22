import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_globals.dart';
import '../../models/study_card.dart';
import '../../models/subject.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sheet_action.dart';

/// 新增 / 编辑一张公式卡。
///
/// 字段顺序按方案：图片区 → 标题 → 注释 → 科目。
class CardEditScreen extends StatefulWidget {
  const CardEditScreen({super.key, this.card});

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
  late int? _subjectId = widget.card?.subjectId;

  final ImagePicker _picker = ImagePicker();

  List<Subject> _subjects = const <Subject>[];
  bool _saving = false;
  bool _dirty = false;

  bool get _isNew => widget.card == null;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    final List<Subject> subjects = await subjectCache.load();
    if (!mounted) return;
    setState(() => _subjects = subjects);
  }

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少写个标题，或者放一张图')),
      );
      return;
    }

    setState(() => _saving = true);
    final int now = DateTime.now().millisecondsSinceEpoch;

    if (_isNew) {
      await cardRepository.insertCard(
        StudyCard(
          type: CardType.formula,
          subjectId: _subjectId,
          title: title.isEmpty ? null : title,
          content: content.isEmpty ? null : content,
          images: _images,
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
          title: Text(_isNew ? '新增公式' : '编辑公式'),
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
            _ImageGrid(
              images: _images,
              onAdd: _showAddImageSheet,
              onRemove: _removeImage,
            ),
            const SizedBox(height: AppSpace.xl),
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
          ],
        ),
      ),
    );
  }
}

class _ImageGrid extends StatelessWidget {
  const _ImageGrid({
    required this.images,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> images;
  final VoidCallback onAdd;
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
                child: Icon(Icons.add, size: 24, color: p.textTertiary),
              ),
            ),
          );
        }
        final int imageIndex = index - 1;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ClipRRect(
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
