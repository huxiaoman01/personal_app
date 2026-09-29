import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../theme/app_theme.dart';

/// 打开全屏看图。
///
/// 公式详情页点大图、灵感编辑页点缩略图，走的都是这里，
/// 保证「点图片能放大」这件事在两处的手感一样。
Future<void> openImageViewer(
  BuildContext context, {
  required List<String> names,
  int initialIndex = 0,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (BuildContext _) => ImageViewer(
        names: names,
        initialIndex: initialIndex,
      ),
    ),
  );
}

/// 全屏看图：左右滑动翻页 + 双指缩放。
class ImageViewer extends StatefulWidget {
  const ImageViewer({
    super.key,
    required this.names,
    this.initialIndex = 0,
  });

  final List<String> names;
  final int initialIndex;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  /// 看图页用接近纯黑的深蓝，不参与 app 大面的浅色底——
  /// 这是全屏看图页唯一的例外。
  static const Color _viewerBg = Color(0xFF0A1220);

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
    return Scaffold(
      backgroundColor: _viewerBg,
      appBar: AppBar(
        backgroundColor: _viewerBg,
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
