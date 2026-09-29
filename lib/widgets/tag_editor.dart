import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'tag_chip.dart';

/// 一个标签最长多少个字。
const int kTagMaxLength = 12;

/// 一条灵感最多挂几个标签。数量不设上限的话，筛选条会被撑成一堵墙。
const int kTagMaxCount = 8;

/// 添加标签的小对话框：输入框 + 「用过的标签」。
///
/// 点历史标签直接用它，不用重新敲一遍；也可以输入一个新标签。
/// 返回选中的标签名（已经 trim 过），取消时返回 null。
Future<String?> showTagEditor(
  BuildContext context, {
  required List<String> suggestions,
}) async {
  final TextEditingController controller = TextEditingController();
  final AppPalette p = context.palette;

  final String? result = await showDialog<String>(
    context: context,
    builder: (BuildContext dialog) => AlertDialog(
      title: const Text('添加标签'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: controller,
            autofocus: true,
            style: AppText.body.copyWith(color: p.text),
            cursorColor: p.primary,
            // 直接限制输入长度，比输完再报错友好。
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(kTagMaxLength),
            ],
            decoration: InputDecoration(
              hintText: '比如：易错点',
              hintStyle: AppText.body.copyWith(color: p.textTertiary),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: p.divider),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: p.primary),
              ),
            ),
            onSubmitted: (String value) => Navigator.of(dialog).pop(value),
          ),
          if (suggestions.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpace.xl),
            Text(
              '用过的标签',
              style: AppText.badge.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: <Widget>[
                for (final String tag in suggestions)
                  TagChip(
                    label: tag,
                    onTap: () => Navigator.of(dialog).pop(tag),
                  ),
              ],
            ),
          ],
        ],
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
          onPressed: () => Navigator.of(dialog).pop(controller.text),
          child: Text(
            '添加',
            style: AppText.body.copyWith(color: p.primary),
          ),
        ),
      ],
    ),
  );

  controller.dispose();

  final String name = (result ?? '').trim();
  return name.isEmpty ? null : name;
}
