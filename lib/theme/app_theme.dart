import 'package:flutter/material.dart';

/// 设计 token。
///
/// 规范见 IDEA.md 第 2 节：间距只能用 [AppSpace] 里的五档，圆角只能用
/// [AppRadius]，颜色一律从 [AppPalette] 取，不要在任何页面里写死色值。

/// 颜色随深浅色切换。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.divider,
    required this.iconBlock,
    required this.decor,
    required this.primary,
    required this.onPrimary,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
  });

  /// 页面背景。
  final Color bg;

  /// 浮层、弹窗、输入框底色。
  final Color surface;

  /// 分隔线。
  final Color divider;

  /// 功能入口、缩略图占位块的底色。
  final Color iconBlock;

  /// 列表页背景上那三个装饰图案的线条色。
  ///
  /// 素材本身是纯白 + alpha，颜色完全由这里决定（见
  /// [AppBackground]）。色值里已经带了很低的透明度——它就是要「淡」，
  /// 浓了会跟列表内容抢注意力。要调深浅只改这里的 alpha。
  final Color decor;

  /// 主色，只用于选中态、FAB、关键按钮、置顶标记。
  final Color primary;

  /// 主色之上的文字与图标颜色。
  final Color onPrimary;

  /// 正文。
  final Color text;

  /// 次级文字：注释、日期、数量。
  final Color textSecondary;

  /// 三级文字：更弱的提示。
  final Color textTertiary;

  static const AppPalette light = AppPalette(
    bg: Color(0xFFFDF8EF),
    surface: Color(0xFFFFFFFF),
    divider: Color(0xFFF0E8DA),
    iconBlock: Color(0xFFF5EDDD),
    decor: Color(0x38B5834A),
    primary: Color(0xFFB5834A),
    onPrimary: Color(0xFFFFFFFF),
    text: Color(0xFF3A3226),
    textSecondary: Color(0xFF8A7B68),
    textTertiary: Color(0xFFA89A85),
  );

  static const AppPalette dark = AppPalette(
    bg: Color(0xFF0F1B2D),
    surface: Color(0xFF16253B),
    divider: Color(0xFF1E2E45),
    iconBlock: Color(0xFF1B2C44),
    decor: Color(0x296E9BD1),
    primary: Color(0xFF6E9BD1),
    onPrimary: Color(0xFF0F1B2D),
    text: Color(0xFFE6EDF6),
    textSecondary: Color(0xFF93A3B8),
    textTertiary: Color(0xFF6B7C92),
  );

  @override
  AppPalette copyWith({
    Color? bg,
    Color? surface,
    Color? divider,
    Color? iconBlock,
    Color? decor,
    Color? primary,
    Color? onPrimary,
    Color? text,
    Color? textSecondary,
    Color? textTertiary,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      divider: divider ?? this.divider,
      iconBlock: iconBlock ?? this.iconBlock,
      decor: decor ?? this.decor,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      iconBlock: Color.lerp(iconBlock, other.iconBlock, t)!,
      decor: Color.lerp(decor, other.decor, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      text: Color.lerp(text, other.text, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
    );
  }
}

/// 间距只有这五档。
abstract final class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

/// 圆角。
abstract final class AppRadius {
  static const double card = 12;
  static const double thumb = 10;
  static const double iconBlock = 12;
  static const double pill = 999;
}

/// 固定的尺寸。
abstract final class AppSize {
  static const double pagePadding = AppSpace.lg;
  static const double rowHeight = 64;
  static const double subjectRowHeight = 56;

  /// 首页功能入口行的高度：96 = 上下各 16 内边距 + 64 的配图。
  static const double hubRowHeight = 96;
  static const double thumb = 48;
  static const double hubThumb = 64;
  static const double iconBlock = 44;
  static const double searchHeight = 44;
  static const double fab = 56;

  /// 列表分隔线的左边缩进：页边距 + 缩略图 + 间距。
  static const double dividerIndent =
      pagePadding + thumb + AppSpace.md;
}

/// 字号与行高。中文行高一律不小于 1.5。
abstract final class AppText {
  static const TextStyle detailTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static const TextStyle pageTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static const TextStyle listTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.6,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  static const TextStyle badge = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
}

/// 读取当前配色。写法：`context.palette.primary`
extension AppPaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

/// [fontFamily] 平时留空，用系统默认中文字体。
/// golden 测试会传一个在测试环境里手动加载的字体——Flutter 测试环境
/// 不带中文字体，不指定的话所有汉字会渲染成方块。
ThemeData buildAppTheme(Brightness brightness, {String? fontFamily}) {
  final AppPalette p =
      brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;

  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: p.primary,
    brightness: brightness,
  ).copyWith(
    primary: p.primary,
    onPrimary: p.onPrimary,
    surface: p.bg,
    onSurface: p.text,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    extensions: <ThemeExtension<dynamic>>[p],
    splashFactory: InkRipple.splashFactory,

    // 零阴影：所有 elevation 一律为 0，靠留白和分隔线分层。
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: AppSpace.lg,
      // 这里必须显式带上 fontFamily：AppBar 的标题样式不走默认文字样式，
      // 漏了它的话，指定了字体族时偏偏只有标题不跟着变。
      titleTextStyle: AppText.pageTitle.copyWith(
        color: p.text,
        fontFamily: fontFamily,
      ),
      iconTheme: IconThemeData(color: p.text, size: 24),
    ),
    dividerTheme: DividerThemeData(
      color: p.divider,
      thickness: 1,
      space: 1,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.primary,
      foregroundColor: p.onPrimary,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      titleTextStyle: AppText.listTitle.copyWith(color: p.text),
      contentTextStyle: AppText.body.copyWith(color: p.textSecondary),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.text,
      contentTextStyle: AppText.caption.copyWith(color: p.bg),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: p.text,
      iconColor: p.textSecondary,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.primary,
      selectionHandleColor: p.primary,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary),
    textTheme: TextTheme(
      titleLarge: AppText.detailTitle.copyWith(color: p.text),
      titleMedium: AppText.pageTitle.copyWith(color: p.text),
      bodyLarge: AppText.body.copyWith(color: p.text),
      bodyMedium: AppText.body.copyWith(color: p.text),
      bodySmall: AppText.caption.copyWith(color: p.textSecondary),
      labelSmall: AppText.badge.copyWith(color: p.textTertiary),
    ),
  );
}
