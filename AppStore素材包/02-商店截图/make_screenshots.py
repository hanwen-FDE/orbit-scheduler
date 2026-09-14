# -*- coding: utf-8 -*-
"""把 iPhone 真机原始截屏合成为 App Store 商店截图（6.9 英寸，1320x2868）。

用法：
  1. 把真机截屏放入同目录下的「原始截图」文件夹，按编号命名：01.png、02.png …
  2. 在本目录运行：  python make_screenshots.py
  3. 成品输出到「成品」文件夹（原始截图缺失时，输出占位预览到「成品预览」，
     并不会写入「成品」，避免占位图被误上传）。

设计：白底 + 顶部轨道环标志与一句文案（与 App 图标同一视觉体系），
下方为带圆角与投影的截图卡片。每张图的文案在下方 SHOTS 中修改。
"""
import os
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

BASE = os.path.dirname(os.path.abspath(__file__))
RAW_DIR = os.path.join(BASE, "原始截图")
OUT_DIR = os.path.join(BASE, "成品")
PREVIEW_DIR = os.path.join(BASE, "成品预览")

W, H = 1320, 2868                 # 6.9" iPhone 16 Pro Max 竖屏
BG = (253, 252, 251)              # 与 App 图标同底色
INK = (24, 32, 46)                # 主文字色（月岩深色）
BRAND_INK = (58, 86, 122)         # 品牌名色（轨道蓝）
SUB_INK = (70, 77, 92)            # 副文字色
PLACEHOLDER_BG = (236, 234, 230)

# 每张截图：(编号, 主文案, 副文案)。文案必须与画面内容一致（审核要求真实）。
SHOTS = [
    ("01", "一句话，写进日历",   "“下周三下午4点开课题会”，AI 识别后写入系统日历"),
    ("02", "课程表，拍张照",     "截图批量识别，一行一条日程"),
    ("03", "改时间、设循环、定提醒", "日程卡片上一站完成"),
    ("04", "今天，一目了然",     "时间轴查看全天安排"),
    ("05", "冲突了？给出空档建议", "是否采纳，由你决定"),
    ("06", "按住说话，松手成日程", "实时转写，解放双手"),
    ("07", "每天一份晨间简报",   "今日安排 + 本地天气 + 一句问候"),
    ("08", "桌面一键记录",       "小组件 + 快捷指令 + 6 色图标"),
]

FONT_DIR = r"C:\Windows\Fonts"


def load_font(size, bold=False):
    for name in (["msyhbd.ttc", "msyh.ttc"] if bold else ["msyh.ttc", "simhei.ttf"]):
        p = os.path.join(FONT_DIR, name)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def draw_ring(size):
    """画一枚轨道环标志：斜向渐变单环，视觉与 App 图标一致。"""
    ss = 4  # 超采样抗锯齿
    S = size * ss
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px = img.load()
    top, bottom = (18, 46, 92), (57, 190, 214)   # 星轨蓝渐变
    a, b, w = 0.40 * S, 0.165 * S, 0.062 * S     # 长/短半轴、线宽（相对环画布）
    th = math.radians(-43.0)
    ct, st = math.cos(th), math.sin(th)
    cx = cy = S / 2
    steps = 1600
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ex, ey = a * math.cos(t), b * math.sin(t)
        rx = cx + ex * ct - ey * st
        ry = cy + ex * st + ey * ct
        tt = min(max(ry / S, 0.0), 1.0)
        col = tuple(int(top[k] + (bottom[k] - top[k]) * tt) for k in range(3))
        r = w / 2
        for x in range(max(0, int(rx - r)), min(S, int(rx + r) + 1)):
            for y in range(max(0, int(ry - r)), min(S, int(ry + r) + 1)):
                if (x - rx) ** 2 + (y - ry) ** 2 <= r * r:
                    px[x, y] = col + (255,)
    return img.resize((size, size), Image.LANCZOS)


def text_center(draw, y, s, f, fill):
    x0, _, x1, _ = draw.textbbox((0, 0), s, font=f)
    draw.text(((W - (x1 - x0)) / 2 - x0, y), s, font=f, fill=fill)


def fit_into(img, box_w, box_h):
    """等比缩放到目标框内。"""
    scale = min(box_w / img.width, box_h / img.height)
    return img.resize((round(img.width * scale), round(img.height * scale)),
                      Image.LANCZOS)


def make_one(shot, raw_path):
    no, headline, sub = shot
    canvas = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(canvas)

    # ---- 顶部文案区 ----
    y = 100
    ring = draw_ring(112)
    canvas.paste(ring, ((W - ring.width) // 2, y), ring)
    y += ring.height + 38
    text_center(draw, y, "Orbit · 轨道", load_font(46, bold=True), BRAND_INK)
    y += 64
    text_center(draw, y, headline, load_font(92, bold=True), INK)
    y += 128
    text_center(draw, y, sub, load_font(46), SUB_INK)
    y += 74

    # ---- 截图卡片区 ----
    bottom_pad = 84
    box_w, box_h = W - 120, H - y - bottom_pad
    radius = 44

    if raw_path and os.path.exists(raw_path):
        card = fit_into(Image.open(raw_path).convert("RGB"), box_w, box_h)
        out_path = os.path.join(OUT_DIR, no + ".png")
    else:
        card_w = min(box_w, round(box_h * 1320 / 2868))
        card = Image.new("RGB", (card_w, box_h), PLACEHOLDER_BG)
        d = ImageDraw.Draw(card)
        f1, f2 = load_font(52, bold=True), load_font(42)
        d.text(((card_w - d.textbbox((0, 0), "待放入原始截图", font=f1)[2]) / 2,
                box_h / 2 - 96), "待放入原始截图", font=f1, fill=(150, 155, 165))
        note = f"{no}.png · {headline}"
        d.text(((card_w - d.textbbox((0, 0), note, font=f2)[2]) / 2,
                box_h / 2 + 4), note, font=f2, fill=(150, 155, 165))
        out_path = os.path.join(PREVIEW_DIR, no + ".png")

    cx, cy = (W - card.width) // 2, y + (box_h - card.height) // 2

    # 投影 + 圆角裁剪
    mask = Image.new("L", card.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, card.width, card.height],
                                           radius=radius, fill=255)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [cx - 8, cy + 14, cx + card.width + 8, cy + card.height + 34],
        radius=radius + 8, fill=(20, 26, 40, 95))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB")
    canvas.paste(card, (cx, cy), mask)
    canvas.save(out_path, "PNG")
    return out_path


def main():
    os.makedirs(RAW_DIR, exist_ok=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    missing = []
    for shot in SHOTS:
        raw = os.path.join(RAW_DIR, shot[0] + ".png")
        if not os.path.exists(raw):
            missing.append(shot[0])
        p = make_one(shot, raw)
        print("已生成", p)
    if missing:
        print("\n⚠ 缺少原始截图：", "、".join(missing),
              "\n  本次输出为占位预览（成品预览文件夹），「成品」文件夹未改动。")
    else:
        print("\n✅ 全部合成完成，请上传「成品」文件夹内的 8 张图。")


if __name__ == "__main__":
    main()
