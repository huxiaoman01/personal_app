import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app_globals.dart';
import '../../data/import_service.dart';
import '../../theme/app_theme.dart';

/// 导入入口：选 zip → 看摘要 → 选合并还是清空 → 执行 → 报结果。
///
/// 返回 true 表示确实写进去了，首页拿到就该刷新一下各个入口的数字。
///
/// 这几步的先后顺序是有讲究的：先只读地把包看一遍（[ImportService.inspect]），
/// 让用户在动手之前就知道「包里有多少东西」，再问怎么导。
Future<bool> showImportSheet(BuildContext context) async {
  final Uint8List? bytes = await _pickZip(context);
  if (bytes == null || !context.mounted) return false;

  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final ImportService service = ImportService(cardRepository, imageStore);

  messenger.showSnackBar(
    const SnackBar(
      content: Text('正在读取备份包…'),
      duration: Duration(seconds: 30),
    ),
  );

  final ImportPreview preview;
  try {
    preview = await service.inspect(bytes);
  } on ImportException catch (error) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
    return false;
  } catch (error) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('读取失败：$error')));
    return false;
  }
  messenger.hideCurrentSnackBar();
  if (!context.mounted) return false;

  final ImportMode? mode = await _askMode(context, preview);
  if (mode == null || !context.mounted) return false;

  // 清空是唯一会丢数据的操作，必须再问一次。
  if (mode == ImportMode.replace) {
    final bool ok = await _confirmReplace(context);
    if (!ok || !context.mounted) return false;
  }

  messenger.showSnackBar(
    const SnackBar(
      content: Text('正在导入，图片多的时候要等一会儿…'),
      duration: Duration(seconds: 30),
    ),
  );

  try {
    final ImportResult result = await service.run(bytes, mode: mode);
    messenger.hideCurrentSnackBar();
    if (!context.mounted) return true;
    await _showResult(context, result);
    return true;
  } on ImportException catch (error) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
    return false;
  } catch (error) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('导入失败：$error')));
    return false;
  }
}

/// 选一个 .zip。优先读文件路径，拿不到路径才退回内存里的字节。
///
/// 备份包里可能塞了几十兆照片，能走路径就别整包读进内存。
Future<Uint8List?> _pickZip(BuildContext context) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final PlatformFile? picked;
  try {
    picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['zip'],
      dialogTitle: '选择备份包',
    );
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('打开文件选择器失败：$error')));
    return null;
  }
  if (picked == null) return null;

  try {
    final String? path = picked.path;
    if (path != null) return await File(path).readAsBytes();
    return await picked.readAsBytes();
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('读不到这个文件：$error')));
    return null;
  }
}

/// 摘要确认框：先让用户看清包里有什么，再选怎么导。
Future<ImportMode?> _askMode(BuildContext context, ImportPreview preview) {
  final AppPalette p = context.palette;
  return showDialog<ImportMode>(
    context: context,
    builder: (BuildContext dialog) => AlertDialog(
      title: const Text('导入这份备份？'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '导出于 ${preview.exportedAtText}',
              style: AppText.body.copyWith(color: p.text),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              '${preview.cardCount} 张卡片 · ${preview.subjectCount} 个科目'
              ' · ${preview.imageCount} 张图片',
              style: AppText.body.copyWith(color: p.text),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              '合并导入：新卡片追加进来，同名科目自动复用，手机上现有的数据'
              '一条都不动。同一份包导入两次会出现两份卡片。',
              style: AppText.caption.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              '清空后导入：先删掉手机上现有的全部卡片和图片，换成包里的内容。',
              style: AppText.caption.copyWith(color: p.textSecondary),
            ),
          ],
        ),
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
          onPressed: () => Navigator.of(dialog).pop(ImportMode.replace),
          child: Text(
            '清空后导入',
            style: AppText.body.copyWith(color: p.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(ImportMode.merge),
          child: Text(
            '合并导入',
            style: AppText.body.copyWith(
              color: p.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

Future<bool> _confirmReplace(BuildContext context) async {
  final AppPalette p = context.palette;
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialog) => AlertDialog(
      title: const Text('确定清空现有数据？'),
      content: const Text(
        '手机上现有的全部卡片、图片和科目都会被删掉，换成备份包里的内容。'
        '这一步没法撤销。',
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
            '确认清空',
            style: AppText.body.copyWith(
              color: p.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
  return ok ?? false;
}

Future<void> _showResult(BuildContext context, ImportResult result) {
  final AppPalette p = context.palette;
  // 提示最多列 5 条：真出了十几条问题，对话框会被顶得老高，反而看不清。
  final List<String> shown = result.warnings.take(5).toList(growable: false);
  final int rest = result.warnings.length - shown.length;

  return showDialog<void>(
    context: context,
    builder: (BuildContext dialog) => AlertDialog(
      title: const Text('导入完成'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${result.cardsImported} 张卡片，${result.imagesImported} 张图片',
              style: AppText.body.copyWith(color: p.text),
            ),
            if (result.subjectsCreated > 0)
              Text(
                '新增 ${result.subjectsCreated} 个科目',
                style: AppText.body.copyWith(color: p.text),
              ),
            for (final String warning in shown) ...<Widget>[
              const SizedBox(height: AppSpace.sm),
              Text(
                warning,
                style: AppText.caption.copyWith(color: p.textSecondary),
              ),
            ],
            if (rest > 0) ...<Widget>[
              const SizedBox(height: AppSpace.sm),
              Text(
                '还有 $rest 条类似提示',
                style: AppText.caption.copyWith(color: p.textTertiary),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(),
          child: Text(
            '知道了',
            style: AppText.body.copyWith(
              color: p.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
