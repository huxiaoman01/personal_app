#!/usr/bin/env python3
"""把源图处理成 app 用的素材。

一共三件事：
  1. 黑底的角色图 → 透明 PNG（首页六个入口右边那六张贴纸）
  2. 拍立得截图 → app 图标（含自适应图标的前景层）
  3. 米黄底的手绘线稿 → 「纯白 + alpha」的装饰图（列表页背景，见 lib/widgets/app_background.dart）

这是**一次性**脚本：源图不进货，跑完把 assets/ 下的产物提交即可。
源图在本机上的绝对路径属于私人信息，不进版本库，所以一律从命令行参数或
环境变量拿：

    python tools/prepare_assets.py --source-dir D:\\素材\\2026-09

    set BAIBAOXIANG_SOURCE_DIR=D:\\素材\\2026-09
    python tools/prepare_assets.py

    python tools/prepare_assets.py --threshold 30   # 头发被抠掉时把阈值调低
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
HUB_DIR = ROOT / "assets" / "hub"
ICON_DIR = ROOT / "assets" / "icon"
DECOR_DIR = ROOT / "assets" / "decor"

# 源图目录：环境变量给个默认值，命令行 --source-dir 优先级更高。
DEFAULT_SOURCE_DIR = os.environ.get("BAIBAOXIANG_SOURCE_DIR", r"C:\path\to\sources")

# 六张选项图的文件名，顺序就是首页六个按钮的顺序。
HUB_SOURCE_NAMES = [
    "c7e902525729583c358e96abadfa9490.jpg",
    "376b68aaf90fc6e9c6a9939d1ecd1074.jpg",
    "7896328882fc6b754c2a91436b7baf8f.jpg",
    "ab4e48c96345403f604204764c337350.jpg",
    "d82f41dbc53331c10fe6ab65b3c26b4f.jpg",
    "ea2906d86f57ad81671501dc5abcb4c3.jpg",
]

# 拍立得那张图标源图，和装饰线稿，同样放在源图目录里。
ICON_SOURCE_NAME = "app_icon_source.jpg"
DECOR_SOURCE_NAME = "decor_source.png"

# 拍立得白框里面的画（实测值）。
ICON_INNER_BOX = (224, 200, 808, 730)  # left, top, right, bottom -> 584 x 530

# floodfill 用的标记色。选洋红是因为这些图里不会出现这个颜色。
MARKER = (255, 0, 255)

HUB_SIZE = 256
ICON_SIZE = 1024

# 装饰线稿：三块图案在原图里的位置（左, 上, 右, 下），实测值。
# 原图 1600x2848 三块纵向排开，右下角还有一行「豆包AI生成」水印——
# 最后一刀切在 y=2677，正好把它排除在外。
DECOR_BOXES = [
    (415, 175, 1336, 919),  # 圆脑袋 + 放射线
    (477, 1015, 1161, 1790),  # >_< 表情脸
    (457, 1859, 1222, 2677),  # 放大镜里的小脸
]

DECOR_SIZE = 512

# 线条最暗处实测约 170（源图是手绘粗线，不是纯黑），亮度低于它就算完全不透明。
DECOR_INK_LUM = 175

# 背景亮度要按「大多数像素有多亮」来定，不能取最大值——纸上那些比别处亮
# 一丁点的像素会把整幅背景算成半透明，贴到页面上就是一块淡淡的方块。
# 留出这一段死区，把背景和线条之间那一层噪点直接压成透明。
DECOR_BG_PERCENTILE = 0.95
DECOR_BG_DEAD = 10


def strip_black_background(img: Image.Image, threshold: int) -> Image.Image:
    """从四个角灌水，把与边缘连通的近黑区域变透明。

    只处理「和边界连得上」的黑，所以角色内部的黑色描边、深色头发都留着。
    """
    rgb = img.convert("RGB")
    width, height = rgb.size
    work = rgb.copy()

    seeds = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
    for seed in seeds:
        r, g, b = work.getpixel(seed)
        if r < threshold and g < threshold and b < threshold:
            ImageDraw.floodfill(work, seed, MARKER, thresh=threshold)

    # 用「和标记色完全相同」来生成遮罩，比逐像素遍历快得多。
    marker_layer = Image.new("RGB", (width, height), MARKER)
    is_background = ImageChops.difference(work, marker_layer).convert("L").point(
        lambda v: 255 if v == 0 else 0
    )

    rgba = rgb.convert("RGBA")
    rgba.putalpha(is_background.point(lambda v: 0 if v == 255 else 255))
    return rgba


def _find_opaque_seed(alpha: Image.Image) -> tuple[int, int] | None:
    """从图片正中心向外一圈圈找，返回第一个不透明像素。

    角色一定占着中间位置，水印则缩在角落，所以这样找种子很稳。
    """
    width, height = alpha.size
    cx, cy = width // 2, height // 2
    limit = max(width, height) // 2

    for radius in range(0, limit + 1, 4):
        for offset in range(-radius, radius + 1, 4):
            for x, y in (
                (cx + offset, cy - radius),
                (cx + offset, cy + radius),
                (cx - radius, cy + offset),
                (cx + radius, cy + offset),
            ):
                if 0 <= x < width and 0 <= y < height and alpha.getpixel((x, y)) > 200:
                    return x, y
    return None


def keep_main_subject(rgba: Image.Image) -> Image.Image:
    """只保留最大的一块连通区域，把角落的水印和零星噪点去掉。

    水印是浮在黑底上的浅色小块，抠完背景后它就成了一座孤岛——
    和角色不连通，所以只留角色那一块即可。
    """
    alpha = rgba.getchannel("A")
    seed = _find_opaque_seed(alpha)
    if seed is None:
        return rgba

    marked = alpha.copy()
    ImageDraw.floodfill(marked, seed, 128, thresh=0)
    kept = marked.point(lambda v: 255 if v == 128 else 0)

    result = rgba.copy()
    result.putalpha(kept)
    return result


def normalize_square(img: Image.Image, size: int, margin_ratio: float = 0.06) -> Image.Image:
    """按不透明区域裁掉空白，再补成正方形并统一尺寸。

    六张图必须做这一步：源图里角色大小差很多，不统一的话列表里高低不齐。
    """
    bbox = img.getbbox()
    if bbox is None:
        raise ValueError("整张图都是透明的，抠图阈值可能太高了")
    cropped = img.crop(bbox)

    side = max(cropped.size)
    canvas_side = round(side * (1 + margin_ratio * 2))
    canvas = Image.new("RGBA", (canvas_side, canvas_side), (0, 0, 0, 0))
    canvas.paste(
        cropped,
        ((canvas_side - cropped.width) // 2, (canvas_side - cropped.height) // 2),
        cropped,
    )
    return canvas.resize((size, size), Image.LANCZOS)


def build_app_icon(source: Image.Image) -> tuple[Image.Image, Image.Image]:
    """返回 (完整图标, 自适应图标前景)。"""
    inner = source.convert("RGB").crop(ICON_INNER_BOX)

    # 内画是 584x530（略扁）。取居中的最大正方形，不做补边——
    # 试过把顶行拉长补到 584 高，会在顶部留下一排竖条纹，很难看。
    # 居中裁只损失左右各 27px，角色和花都在。
    side = inner.height
    left = (inner.width - side) // 2
    square = inner.crop((left, 0, left + side, side))

    icon = square.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS)

    # 自适应图标的前景层：整块图缩到 66% 居中，四周留透明，
    # 保证在圆形/方形遮罩下都不会被切掉。
    visible = round(ICON_SIZE * 0.66)
    scaled = icon.resize((visible, visible), Image.LANCZOS)

    mask = Image.new("L", (visible, visible), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, visible - 1, visible - 1),
        radius=round(visible * 0.12),
        fill=255,
    )

    foreground = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    offset = (ICON_SIZE - visible) // 2
    foreground.paste(scaled.convert("RGBA"), (offset, offset), mask)

    return icon, foreground


def build_decor(source: Image.Image) -> list[Image.Image]:
    """把米黄底上的手绘线稿抠成「纯白 + alpha」的装饰图。

    颜色故意不烤进图片：Flutter 那边用 `Image.asset(color: ..., colorBlendMode:
    srcIn)` 上色，深浅两套主题各配一个颜色（见 AppPalette.decor）。
    这样同一张图在米黄底和深蓝底上都不会显得脏。
    """
    gray = source.convert("L")
    layers: list[Image.Image] = []
    for box in DECOR_BOXES:
        crop = gray.crop(box)
        opaque_from = _background_luminance(crop) - DECOR_BG_DEAD
        span = max(opaque_from - DECOR_INK_LUM, 1)
        alpha = crop.point(
            lambda v: 0
            if v >= opaque_from
            else min(255, round((opaque_from - v) * 255 / span))
        )
        layer = Image.new("RGBA", crop.size, (255, 255, 255, 0))
        layer.putalpha(alpha)
        layers.append(normalize_square(layer, DECOR_SIZE, margin_ratio=0.08))
    return layers


def _background_luminance(gray: Image.Image) -> int:
    """一块图里绝大多数像素都是纸，取 95 分位当背景亮度。

    不用最大值：纸面本身有细微的明暗，最亮那几个像素会把背景算高，
    整幅背景就都成了半透明。
    """
    histogram = gray.histogram()
    target = gray.size[0] * gray.size[1] * DECOR_BG_PERCENTILE
    running = 0
    for value, count in enumerate(histogram):
        running += count
        if running >= target:
            return value
    return 255


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source-dir",
        default=DEFAULT_SOURCE_DIR,
        help="放源图的目录（六张入口图、图标源图、装饰线稿都在里面）",
    )
    parser.add_argument(
        "--decor-source",
        default=None,
        help=f"单独指定装饰线稿的路径，默认是 <source-dir>/{DECOR_SOURCE_NAME}",
    )
    parser.add_argument(
        "--threshold",
        type=int,
        default=45,
        help="判定「近黑」的阈值，默认 45。角色深色部分被误删就调小。",
    )
    args = parser.parse_args()

    source_dir = Path(args.source_dir)
    hub_sources = [source_dir / name for name in HUB_SOURCE_NAMES]
    icon_source = source_dir / ICON_SOURCE_NAME
    decor_source = (
        Path(args.decor_source)
        if args.decor_source
        else source_dir / DECOR_SOURCE_NAME
    )

    missing = [p for p in hub_sources + [icon_source, decor_source] if not p.exists()]
    if missing:
        for path in missing:
            print(f"找不到源文件: {path}", file=sys.stderr)
        print(
            "\n用 --source-dir 指定源图目录，或先设好环境变量 "
            "BAIBAOXIANG_SOURCE_DIR。",
            file=sys.stderr,
        )
        return 1

    HUB_DIR.mkdir(parents=True, exist_ok=True)
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    DECOR_DIR.mkdir(parents=True, exist_ok=True)

    for index, source_path in enumerate(hub_sources, start=1):
        with Image.open(source_path) as raw:
            cut = strip_black_background(raw, args.threshold)
        out = normalize_square(keep_main_subject(cut), HUB_SIZE)
        target = HUB_DIR / f"hub_{index}.png"
        out.save(target)
        histogram = out.getchannel("A").histogram()
        opaque = sum(histogram[129:])
        print(
            f"hub_{index}.png  {out.size[0]}x{out.size[1]}"
            f"  不透明像素 {opaque / (HUB_SIZE ** 2):.0%}"
        )

    with Image.open(icon_source) as raw:
        icon, foreground = build_app_icon(raw)
    icon.save(ICON_DIR / "app_icon.png")
    foreground.save(ICON_DIR / "app_icon_foreground.png")
    print(f"app_icon.png  {icon.size[0]}x{icon.size[1]}")
    print(f"app_icon_foreground.png  {foreground.size[0]}x{foreground.size[1]}")

    with Image.open(decor_source) as raw:
        decor = build_decor(raw)
    for index, image in enumerate(decor, start=1):
        image.save(DECOR_DIR / f"decor_{index}.png")
        histogram = image.getchannel("A").histogram()
        opaque = sum(histogram[129:])
        print(
            f"decor_{index}.png  {image.size[0]}x{image.size[1]}"
            f"  有效线稿 {opaque / (DECOR_SIZE ** 2):.1%}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
