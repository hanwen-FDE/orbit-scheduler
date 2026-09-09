# -*- coding: utf-8 -*-
"""
Orbit·轨道 快捷指令版 —— 说明文档配图生成器
运行: python make_docs_images.py  → 在 images/ 下产出 6 张 PNG
"""
import random
import re
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = Path(__file__).parent
OUT = HERE / "images"
OUT.mkdir(exist_ok=True)

# ---------------- 设计系统 ----------------
INK = (45, 49, 89)        # 深空墨蓝(标题)
MUTED = (122, 128, 156)   # 次要文字
PAGE = (246, 247, 251)    # 页面底
CARD = (255, 255, 255)
BORDER = (228, 231, 240)
VIOLET = (108, 92, 231)   # 主色
VIOLET_SOFT = (237, 233, 254)
TEAL = (0, 184, 169)
TEAL_SOFT = (222, 245, 243)
ORANGE = (245, 166, 35)
ORANGE_SOFT = (253, 240, 222)
BLUE = (64, 120, 242)
BLUE_SOFT = (230, 239, 254)
DEEP1 = (23, 26, 56)      # 横幅渐变
DEEP2 = (62, 66, 126)

FZ = r"C:/Windows/Fonts/msyh.ttc"
FZ_B = r"C:/Windows/Fonts/msyhbd.ttc"
FZ_MO = r"C:/Windows/Fonts/seguiemj.ttf"

_cache = {}


def F(size, bold=False, emoji=False):
    key = (size, bold, emoji)
    if key not in _cache:
        path = FZ_MO if emoji else (FZ_B if bold else FZ)
        _cache[key] = ImageFont.truetype(path, size)
    return _cache[key]


def color_emoji_ok():
    try:
        im = Image.new("RGB", (40, 40), "white")
        d = ImageDraw.Draw(im)
        d.text((4, 4), "🦷", font=F(28, emoji=True), embedded_color=True)
        return True
    except Exception:
        return False


EMOJI_COLOR = color_emoji_ok()


def emojitext(d, xy, s, size, fill=None):
    """画 emoji; 彩色失败则退回单色描边。"""
    try:
        d.text(xy, s, font=F(size, emoji=True),
               embedded_color=True if EMOJI_COLOR else None,
               fill=None if EMOJI_COLOR else (fill or INK))
    except Exception:
        d.text(xy, s, font=F(size, emoji=True), fill=fill or INK)


def text_w(d, s, size, bold=False, emoji=False):
    return d.textlength(s, font=F(size, bold, emoji))


EMOJI_LEAD = re.compile(
    "^[\U0001F000-\U0001FAFF\u2600-\u27BF\u2B00-\u2BFF\uFE0F\u200D]+")


def etext(d, x, y, s, size, fill=None, bold=False):
    """开头的 emoji 用彩色 emoji 字体, 其余用微软雅黑。"""
    m = EMOJI_LEAD.match(s)
    if m:
        pre = m.group(0)
        emojitext(d, (x, y), pre, size)
        x += text_w(d, pre, size, emoji=True) + 8
        s = s[m.end():]
    d.text((x, y), s, font=F(size, bold), fill=fill or INK)


def wrap(d, s, size, max_w, bold=False):
    """按像素宽度把长句折行。"""
    lines, cur = [], ""
    for ch in s:
        if d.textlength(cur + ch, font=F(size, bold)) > max_w and cur:
            lines.append(cur)
            cur = ch
        else:
            cur += ch
    if cur:
        lines.append(cur)
    return lines


def new_canvas(w, h, bg=PAGE):
    im = Image.new("RGB", (w, h), bg)
    return im, ImageDraw.Draw(im)


def card(d, box, fill=CARD, radius=22, border=BORDER, bw=2):
    d.rounded_rectangle(box, radius=radius, fill=fill, outline=border, width=bw)


def chip(d, x, y, s, size=24, fg=VIOLET, bg=VIOLET_SOFT, bold=False, pad=14):
    w = text_w(d, s, size, bold)
    h = size + 18
    d.rounded_rectangle((x, y, x + w + pad * 2, y + h), radius=h // 2, fill=bg)
    d.text((x + pad, y + 8), s, font=F(size, bold), fill=fg)
    return w + pad * 2


def title_block(d, x, y, title, sub=None):
    d.text((x, y), title, font=F(46, True), fill=INK)
    if sub:
        d.text((x, y + 62), sub, font=F(26), fill=MUTED)


def arrow_h(d, x1, x2, y, color=VIOLET, w=5):
    d.line((x1, y, x2 - 16, y), fill=color, width=w)
    d.polygon([(x2, y), (x2 - 22, y - 13), (x2 - 22, y + 13)], fill=color)


def arrow_v(d, x, y1, y2, color=VIOLET, w=5):
    d.line((x, y1, x, y2 - 16), fill=color, width=w)
    d.polygon([(x, y2), (x - 13, y2 - 22), (x + 13, y2 - 22)], fill=color)


def footer(d, w, h, s):
    d.text((w // 2 - text_w(d, s, 22) / 2, h - 56), s, font=F(22), fill=MUTED)


def save(im, name):
    im.save(OUT / name)
    print("OK", name)


# ======================================================================
# 1. banner —— 品牌横幅
# ======================================================================
def banner():
    W, H = 1600, 640
    im = Image.new("RGB", (W, H), DEEP1)
    d = ImageDraw.Draw(im)
    for y in range(H):  # 垂直渐变
        t = y / H
        c = tuple(int(DEEP1[i] + (DEEP2[i] - DEEP1[i]) * t) for i in range(3))
        d.line((0, y, W, y), fill=c)
    rnd = random.Random(42)
    for _ in range(130):  # 星星
        x, y = rnd.randrange(W), rnd.randrange(H)
        r = rnd.choice([1, 1, 2, 2, 3])
        a = rnd.randrange(90, 220)
        d.ellipse((x - r, y - r, x + r, y + r), fill=(a, a + 8, min(255, a + 30)))
    # 轨道
    cx, cy = 1180, 300
    for rx, ry, w, col in [(300, 120, 3, (140, 148, 210)),
                           (380, 160, 2, (100, 108, 175)),
                           (240, 95, 2, (120, 128, 190))]:
        d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), outline=col, width=w)
    d.ellipse((cx - 46, cy - 46, cx + 46, cy + 46), fill=VIOLET)   # 行星
    d.ellipse((cx - 18, cy - 30, cx + 2, cy - 10), fill=(160, 150, 240))
    d.ellipse((cx + 300 - 14, cy - 60 - 14, cx + 300 + 14, cy - 60 + 14),
              fill=(255, 214, 102))                                  # 轨道上的小星
    # 文案
    d.text((110, 150), "Orbit · 轨道", font=F(96, True), fill=(255, 255, 255))
    d.text((116, 280), "AI 日程助手｜iOS 快捷指令版", font=F(40),
           fill=(205, 210, 245))
    x = 116
    for s in ["⌨️ 文字", "🎙️ 语音", "📷️ 图片", "📋 批量识别", "📅 写入系统日历", "🧩 多模型可选"]:
        w = text_w(d, s[2:], 26) + 74
        d.rounded_rectangle((x, 370, x + w, 424), radius=27,
                            outline=(120, 128, 190), width=2)
        emojitext(d, (x + 16, 378), s[:2], 26)
        d.text((x + 54, 380), s[2:], font=F(26), fill=(225, 228, 250))
        x += w + 16
    d.text((116, 500), "已签名文件直达 / iCloud 链接分享，点开即用。",
           font=F(28), fill=(255, 214, 102))
    save(im, "banner.png")


# ======================================================================
# 2. flow —— 工作原理
# ======================================================================
def flow():
    W, H = 1600, 980
    im, d = new_canvas(W, H)
    title_block(d, 90, 70, "工作原理：三步上轨",
                "你说人话，AI 排期，日程自动进入 iPhone 系统日历")
    boxes = [
        ("📝", "① 你说人话", ["⌨️ 打字 / 粘贴", "🎙️ 语音听写", "📷 课表·通知截图"],
         "支持一次粘贴多行", VIOLET, VIOLET_SOFT),
        ("⚙️", "② Orbit 快捷指令", ["自动带上当前时间", "拼装 JSON 请求", "直连你填的 API"],
         "无需安装任何 App", BLUE, BLUE_SOFT),
        ("🧠", "③ 大模型解析", ["自然语言 → 结构化", "标题/时间/地点/备注", "自动配 emoji"],
         "严格 JSON 输出", ORANGE, ORANGE_SOFT),
        ("📅", "④ 写入系统日历", ["自动创建日程", "自动设置提醒", "可指定目标日历"],
         "复用 iPhone 日历", TEAL, TEAL_SOFT),
    ]
    bw, bh, gap, top = 320, 460, 66, 240
    x0 = (W - bw * 4 - gap * 3) // 2
    for i, (emo, t, items, note, cmain, csoft) in enumerate(boxes):
        x = x0 + i * (bw + gap)
        y = top
        card(d, (x, y, x + bw, y + bh))
        d.rounded_rectangle((x + 30, y + 34, x + 102, y + 106), radius=18,
                            fill=csoft)
        emojitext(d, (x + 46, y + 48), emo, 42)
        d.text((x + 118, y + 52), t, font=F(30, True), fill=INK)
        yy = y + 140
        for it in items:
            d.ellipse((x + 36, yy + 12, x + 46, yy + 22), fill=cmain)
            etext(d, x + 62, yy, it, 24, INK)
            yy += 48
        d.rounded_rectangle((x + 28, y + bh - 88, x + bw - 28, y + bh - 30),
                            radius=14, fill=csoft)
        tw = text_w(d, note, 23)
        d.text((x + (bw - tw) / 2, y + bh - 76), note, font=F(23), fill=cmain)
        if i < 3:
            arrow_h(d, x + bw + 8, x + bw + gap - 8, y + bh // 2)
    footer(d, W, H, "全程为「本机 ⇄ 你的大模型 API」直连，不经过任何第三方服务器")
    save(im, "flow.png")


# ======================================================================
# 3. config —— 配置字典
# ======================================================================
def config():
    W, H = 1500, 1120
    im, d = new_canvas(W, H)
    title_block(d, 80, 60, "唯一要改的地方：配置字典",
                "长按快捷指令 →「编辑」→ 展开最上方的「字典」动作，像填表格一样改")
    # 左侧: 字典编辑器卡片
    cx0, cy0, cw, ch = 80, 220, 760, 820
    card(d, (cx0, cy0, cx0 + cw, cy0 + ch))
    d.rounded_rectangle((cx0, cy0, cx0 + cw, cy0 + 66), radius=22,
                        fill=(58, 62, 110))
    d.rectangle((cx0, cy0 + 40, cx0 + cw, cy0 + 66), fill=(58, 62, 110))
    d.text((cx0 + 28, cy0 + 16), "字典 · 配置", font=F(28, True),
           fill=(255, 255, 255))
    rows = [
        ("API地址", "https://open.bigmodel.cn/api/paas/v4", "换服务商就改这行", VIOLET),
        ("API密钥", "请把这一行替换成你的API密钥", "必填！去服务商官网申请", ORANGE),
        ("模型", "glm-4v-plus", "任意 OpenAI 兼容模型", BLUE),
        ("目标日历", "（留空 = 默认日历）", "想写进特定日历就填名字", TEAL),
        ("提前提醒分钟", "15", "改成 0 = 开始时提醒", TEAL),
    ]
    yy = cy0 + 100
    for key, val, note, c in rows:
        d.rounded_rectangle((cx0 + 26, yy, cx0 + 250, yy + 56), radius=12,
                            fill=(244, 245, 250))
        d.text((cx0 + 44, yy + 13), key, font=F(25, True), fill=INK)
        vw = max(370, text_w(d, val, 23) + 30)
        d.rounded_rectangle((cx0 + 264, yy, cx0 + 264 + vw, yy + 56),
                            radius=12, fill=(250, 251, 254),
                            outline=BORDER, width=1)
        d.text((cx0 + 280, yy + 13), val, font=F(23), fill=MUTED)
        yy += 72
        d.text((cx0 + 264, yy - 8), "↳ " + note, font=F(21), fill=c)
        yy += 44
    # 右侧: 服务商预设
    px, pw = 890, 540
    py, ph = 220, 560
    card(d, (px, py, px + pw, py + ph))
    d.text((px + 30, py + 26), "常见服务商预设", font=F(30, True), fill=INK)
    d.text((px + 30, py + 70), "API地址 填 Base URL，模型填右列：", font=F(22), fill=MUTED)
    providers = [
        ("智谱 GLM（默认）", "glm-4v-plus", "支持图片识别", True),
        ("DeepSeek", "deepseek-chat", "便宜好用", False),
        ("Kimi 月之暗面", "kimi-latest", "长文本见长", False),
        ("OpenAI", "gpt-4o", "支持图片识别", True),
        ("阿里通义千问", "qwen-vl-plus", "支持图片识别", True),
    ]
    yy = py + 116
    for name, model, note, vision in providers:
        d.rounded_rectangle((px + 26, yy, px + pw - 26, yy + 76),
                            radius=14, fill=(248, 249, 253))
        d.text((px + 46, yy + 12), name, font=F(24, True), fill=INK)
        d.text((px + 46, yy + 42), model, font=F(22), fill=VIOLET)
        tag = "📷 图片" if vision else "⌨️ 文字"
        tw = text_w(d, tag[2:], 20) + 24 + 36
        d.rounded_rectangle((px + pw - 56 - tw, yy + 14, px + pw - 56, yy + 48),
                            radius=16, fill=(237, 240, 250))
        emojitext(d, (px + pw - 56 - tw + 10, yy + 21), tag[:2], 20)
        d.text((px + pw - 56 - tw + 42, yy + 21), tag[2:], font=F(20), fill=MUTED)
        d.text((px + pw - 56 - text_w(d, note, 20) - 20, yy + 48 - 8),
               note, font=F(20), fill=MUTED)
        yy += 88
    footer(d, W, H, "改完点右上角 ✕ 保存即可，随时可以再改")
    save(im, "config.png")


# ======================================================================
# 4. install —— 两种安装方式
# ======================================================================
def phone_frame(d, x, y, w, h, title):
    """画一个 iPhone 线框, 返回内容区"""
    d.rounded_rectangle((x, y, x + w, y + h), radius=36, fill=CARD,
                        outline=INK, width=4)
    d.rounded_rectangle((x + w / 2 - 60, y + 12, x + w / 2 + 60, y + 26),
                        radius=8, fill=INK)  # 灵动岛
    d.text((x + w / 2 - text_w(d, title, 20) / 2, y + 40), title,
           font=F(20, True), fill=INK)
    return (x + 18, y + 74, x + w - 18, y + h - 18)


def install():
    W, H = 1600, 1080
    im, d = new_canvas(W, H)
    title_block(d, 80, 60, "三种安装方式",
                "推荐 A；装好任意一种后，都能用 B 的 iCloud 链接分发")
    bw, gap, top, bh = 460, 50, 230, 760
    x0 = (W - bw * 3 - gap * 2) // 2
    heads = [
        ("方式 A · 已签名文件（推荐）", VIOLET),
        ("方式 B · iCloud 链接", BLUE),
        ("方式 C · 手动搭建（保底）", TEAL),
    ]
    steps_all = [
        ["GitHub 仓库 → Actions → Sign iOS Shortcut → Run",
         "跑完下载 Artifacts，解压出「已签名」.shortcut",
         "微信 / QQ / 邮件 把文件发到 iPhone",
         "「文件」App 点开 → 添加快捷指令 ✅"],
        ["自己先装好（方式 A 或 C）",
         "⚠️ 把「API密钥」换回占位文字",
         "长按 Orbit → 分享 → iCloud 链接",
         "朋友点开链接 → 添加，填自己的密钥"],
        ["新建一个空白快捷指令",
         "照《附录 A》30 步表格逐步添加动作",
         "顶部放「字典」动作并填好配置",
         "跑一次，日程进日历 ✅"],
    ]
    notes = ["海外机房代签，不受本地网络限制",
             "分享给朋友最顺滑，一代链接人人可装",
             "约 10 分钟，无任何网络依赖"]
    for i in range(3):
        x = x0 + i * (bw + gap)
        card(d, (x, top, x + bw, top + bh))
        hc = heads[i][1]
        d.rounded_rectangle((x, top, x + bw, top + 66), radius=22, fill=hc)
        d.rectangle((x, top + 44, x + bw, top + 66), fill=hc)
        d.text((x + 22, top + 16), heads[i][0], font=F(25, True),
               fill=(255, 255, 255))
        yy = top + 92
        for j, s in enumerate(steps_all[i], 1):
            d.ellipse((x + 22, yy, x + 54, yy + 32), fill=(244, 245, 250))
            d.text((x + 36 if j < 10 else x + 32, yy + 4), str(j),
                   font=F(19, True), fill=hc)
            lines = wrap(d, s, 21, bw - 96)
            d.multiline_text((x + 68, yy + 2), "\n".join(lines), font=F(21),
                             fill=INK, spacing=8)
            yy += 34 + len(lines) * 30
        d.rounded_rectangle((x + 22, top + bh - 96, x + bw - 22, top + bh - 34),
                            radius=12, fill=(244, 245, 250))
        emojitext(d, (x + 36, top + bh - 82), "💡", 22)
        d.text((x + 68, top + bh - 80), notes[i], font=F(20), fill=MUTED)
    # 中部: 报错警示条 (对应 iPhone 的未签名拦截提示)
    wx0, wy, ww, wh = 80, top + bh + 26, W - 160, 74
    d.rounded_rectangle((wx0, wy, wx0 + ww, wy + wh), radius=16,
                        fill=ORANGE_SOFT)
    emojitext(d, (wx0 + 22, wy + 18), "⚠️", 36)
    d.text((wx0 + 74, wy + 14),
           "双击 .shortcut 提示「不支持导入未签名的快捷指令文件」？",
           font=F(24, True), fill=(170, 105, 15))
    d.text((wx0 + 74, wy + 46),
           "这是 iOS 15 起的强制签名要求，所有第三方快捷指令都一样——上方任一方式都能解决。",
           font=F(20), fill=(150, 100, 30))
    footer(d, W, H, "A、C 装好后都能生成 iCloud 链接（方式 B），一份链接分享给所有人")
    save(im, "install.png")


# ======================================================================
# 5. demo —— 使用效果
# ======================================================================
def demo():
    W, H = 1500, 1210
    im, d = new_canvas(W, H)
    title_block(d, 80, 56, "使用效果：一次输入，日程成串",
                "像发微信一样描述计划，剩下的交给轨道")
    # 用户气泡
    msg = "下周五下午3点牙医复诊，记得提前半小时出发；\n10月1日到7日国庆假期；\n11月2日 9:00-11:30 国际会议中心开母胎医学论坛"
    bx0, by0 = 80, 200
    d.rounded_rectangle((bx0, by0, bx0 + 1030, by0 + 200), radius=24,
                        fill=(238, 240, 248))
    d.polygon([(bx0 + 26, by0 + 200), (bx0 + 6, by0 + 224), (bx0 + 60, by0 + 200)],
              fill=(238, 240, 248))
    etext(d, bx0 + 30, by0 + 24, "📨 你输入的原文", 21, MUTED, True)
    d.multiline_text((bx0 + 30, by0 + 62), msg, font=F(25), fill=INK,
                     spacing=14)
    # 处理 chip
    cy = by0 + 250
    d.rounded_rectangle((bx0 + 8, cy, bx0 + 480, cy + 56), radius=28,
                        fill=ORANGE_SOFT)
    emojitext(d, (bx0 + 26, cy + 12), "🧠", 28)
    d.text((bx0 + 66, cy + 13), "glm-4v-plus 正在识别…", font=F(24),
           fill=(190, 120, 20))
    arrow_v(d, bx0 + 60, cy + 66, cy + 116)
    # 结果卡
    rx0, ry0, rw, rh = 80, 430, 1340, 620
    card(d, (rx0, ry0, rx0 + rw, ry0 + rh))
    d.rounded_rectangle((rx0 + 24, ry0 + 24, rx0 + 640, ry0 + 84),
                        radius=16, fill=TEAL_SOFT)
    emojitext(d, (rx0 + 44, ry0 + 36), "✅", 30)
    d.text((rx0 + 86, ry0 + 38), "已写入 3 个日程到系统日历", font=F(27, True),
           fill=(0, 140, 129))
    events = [
        ("🦷", "牙医复诊", "9月18日 周五 15:00 – 16:00", "提醒：提前 15 分钟", VIOLET),
        ("🇨🇳", "国庆假期", "10月1日 – 10月7日 全天", "自动推算年份 2026", ORANGE),
        ("🏛️", "母胎医学论坛", "11月2日 09:00 – 11:30 · 国际会议中心", "地点和备注一并写入", TEAL),
    ]
    yy = ry0 + 116
    for emo, t, t2, t3, c in events:
        d.rounded_rectangle((rx0 + 24, yy, rx0 + rw - 24, yy + 128),
                            radius=18, fill=(248, 249, 253))
        d.rectangle((rx0 + 24, yy + 18, rx0 + 30, yy + 110), fill=c)
        emojitext(d, (rx0 + 52, yy + 34), emo, 44)
        d.text((rx0 + 120, yy + 22), t, font=F(29, True), fill=INK)
        d.text((rx0 + 120, yy + 66), t2, font=F(24), fill=MUTED)
        tw = text_w(d, t3, 20)
        d.text((rx0 + rw - 44 - tw, yy + 28), t3, font=F(20), fill=c)
        yy += 146
    d.text((rx0 + 24, ry0 + rh - 58),
           "AI 自动推算年份与星期、补全时长、配上 emoji，并逐项写入系统日历。",
           font=F(23), fill=MUTED)
    footer(d, W, H, "示例基于 2026年9月9日 运行 · 「下周五」被正确解析为 9月18日")
    save(im, "demo.png")


# ======================================================================
# 6. share —— 一键分享
# ======================================================================
def share():
    W, H = 1600, 880
    im, d = new_canvas(W, H)
    title_block(d, 80, 56, "一键分享给朋友", "你自己先跑通一次，然后人人都能一键安装")
    steps = [
        ("🛠️", "自己先装好", "按方式 A/B 安装并填好密钥，跑通一次"),
        ("🔗", "长按 → 分享", "快捷指令列表里长按 →「分享」→「iCloud 链接」"),
        ("📋", "复制链接", "系统自动上传签名，生成 icloud.com 短链"),
        ("🎉", "朋友点开即用", "点链接 →「添加快捷指令」→ 填自己的密钥"),
    ]
    bw, gap, top, bh = 340, 62, 220, 400
    x0 = (W - bw * 4 - gap * 3) // 2
    for i, (emo, t, s) in enumerate(steps):
        x = x0 + i * (bw + gap)
        card(d, (x, top, x + bw, top + bh))
        d.rounded_rectangle((x + 30, top + 30, x + 102, top + 102), radius=18,
                            fill=VIOLET_SOFT)
        emojitext(d, (x + 46, top + 44), emo, 40)
        d.text((x + 118, top + 52), f"STEP {i+1}", font=F(22, True), fill=VIOLET)
        d.text((x + 30, top + 126), t, font=F(29, True), fill=INK)
        lines = wrap(d, s, 23, bw - 60)
        d.multiline_text((x + 30, top + 176), "\n".join(lines), font=F(23),
                         fill=MUTED, spacing=10)
        if i < 3:
            arrow_h(d, x + bw + 8, x + bw + gap - 8, top + bh // 2)
    # 警示条
    wx0, wy, ww, wh = 150, 680, W - 300, 108
    d.rounded_rectangle((wx0, wy, wx0 + ww, wy + wh), radius=20,
                        fill=ORANGE_SOFT)
    emojitext(d, (wx0 + 28, wy + 30), "⚠️", 40)
    d.text((wx0 + 90, wy + 22), "分享前，把「API密钥」换回占位文字！",
           font=F(27, True), fill=(170, 105, 15))
    d.text((wx0 + 90, wy + 64), "iCloud 链接分享的是整个快捷指令，密钥会被一起带出去 —— 先替换成「请把这一行替换成你的API密钥」再生成链接。",
           font=F(22), fill=(150, 100, 30))
    save(im, "share.png")


if __name__ == "__main__":
    banner()
    flow()
    config()
    install()
    demo()
    share()
    print("全部配图生成完毕 →", OUT)
