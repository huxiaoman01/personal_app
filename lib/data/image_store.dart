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

  /// 导入备份包时用：把内存里的一段图片字节写进私有目录，返回文件名。
  ///
  /// 名字沿用包里那份（人一眼能看出是哪张图），万一本机已经有了就依次试
  /// `名字_1`、`名字_2`……绝不覆盖本机已有的文件。
  Future<String> writeBytes(String suggestedName, List<int> bytes) async {
    final String name = await _availableName(suggestedName);
    await File(p.join(directory.path, name)).writeAsBytes(bytes);
    return name;
  }

  Future<String> _availableName(String suggestedName) async {
    if (!await fileOf(suggestedName).exists()) return suggestedName;
    final String ext = p.extension(suggestedName);
    final String base = p.basenameWithoutExtension(suggestedName);
    for (int i = 1; i < 1000; i++) {
      final String candidate = '${base}_$i$ext';
      if (!await fileOf(candidate).exists()) return candidate;
    }
    // 同名文件堆到几百个说明另有蹊跷，退回一个必然不冲突的随机名字。
    return '${DateTime.now().microsecondsSinceEpoch}_$suggestedName';
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
