import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 图片仓库：独占 app 私有目录下的 `images/`。
///
/// 数据库里只存文件名，真实路径运行时解析——这样重装、换目录都不会失效。
class ImageStore {
  ImageStore(this.directory);

  final Directory directory;

  /// app 启动时按真实的私有目录建一个。
  static Future<ImageStore> forApp() async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(p.join(base.path, 'images'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return ImageStore(dir);
  }

  File fileOf(String name) => File(p.join(directory.path, name));

  /// 把拍照或相册选出来的图片复制进私有目录，返回新文件名。
  Future<String> import(String sourcePath) async {
    final String rawExt = p.extension(sourcePath).toLowerCase();
    final String ext = rawExt.isEmpty || rawExt.length > 5 ? '.jpg' : rawExt;
    final int salt = Random().nextInt(1 << 30);
    final String name =
        '${DateTime.now().microsecondsSinceEpoch}_${salt.toRadixString(16)}$ext';
    await File(sourcePath).copy(p.join(directory.path, name));
    return name;
  }

  Future<void> deleteAll(Iterable<String> names) async {
    for (final String name in names) {
      final File file = fileOf(name);
      if (!await file.exists()) continue;
      try {
        await file.delete();
      } on FileSystemException {
        // 删不掉就算了，别让清理流程中断。
      }
    }
  }
}
