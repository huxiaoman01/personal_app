import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_globals.dart';
import '../../app_identity.dart';
import '../../data/export_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sheet_action.dart';

/// 导出入口：先弹交付方式（分享出去 / 存到手机），再打包 zip。
///
/// 「分享出去」走系统分享面板，「存到手机」走 SAF 保存对话框——
/// 两条路都不需要存储权限。
///
/// [selection] 是要导出哪些东西；null 表示全都导（从「导出数据」页进来时
/// 会把用户勾好的那份传过来）。
Future<void> showExportSheet(
  BuildContext context, {
  ExportSelection? selection,
}) async {
  final String? action = await showModalBottomSheet<String>(
    context: context,
    builder: (BuildContext sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SheetAction(
            icon: Icons.ios_share,
            label: '分享出去',
            onTap: () => Navigator.of(sheet).pop('share'),
          ),
          SheetAction(
            icon: Icons.download_outlined,
            label: '存到手机',
            onTap: () => Navigator.of(sheet).pop('save'),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  await _run(context, share: action == 'share', selection: selection);
}

Future<void> _run(
  BuildContext context, {
  required bool share,
  ExportSelection? selection,
}) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(
      content: Text('正在打包…'),
      duration: Duration(seconds: 30),
    ),
  );

  try {
    final ExportService service = ExportService(cardRepository, imageStore);
    final DateTime now = DateTime.now();
    final Uint8List bytes =
        await service.buildZip(now: now, selection: selection);
    final String fileName =
        service.zipFileName(now, partial: selection != null);

    messenger.hideCurrentSnackBar();

    if (share) {
      final Directory tmp = await getTemporaryDirectory();
      final File file = File(p.join(tmp.path, fileName));
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path)],
          text: '${AppIdentity.displayName}导出',
        ),
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('已经交给系统分享')),
      );
      return;
    }

    final Uri? saved = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/zip',
      dialogTitle: '保存到手机',
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(saved == null ? '已取消' : '已保存到 ${saved.path}'),
      ),
    );
  } on Exception catch (error) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('导出失败：$error')));
  }
}
