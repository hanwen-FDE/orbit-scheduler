# -*- coding: utf-8 -*-
"""生成 Orbit 图标 v2：白底 + 斜向渐变单环（无星球无小球），6 色系
参考设计几何：环中心≈画面中心，长轴倾角≈43°，环体超出画面被裁边，
环体渐变沿垂直方向（上深下亮）。"""
from PIL import Image
import json, os, math

ROOT = os.path.join(os.path.dirname(__file__), "ScheduleAssistant")

# 每色系: (名称, 上端色, 下端色)
DESIGNS = {
    "Classic":     ((18, 46, 92), (57, 190, 214)),    # 星轨蓝（默认，参考原版）
    "OrbitViolet": ((76, 29, 149), (167, 139, 250)),  # 紫罗兰
    "OrbitGreen":  ((5, 95, 70), (52, 212, 153)),     # 青碧
    "OrbitOrange": ((146, 64, 14), (251, 146, 60)),   # 曙光
    "OrbitPink":   ((131, 36, 90), (244, 114, 182)),  # 桃粉
    "OrbitMono":   ((22, 30, 46), (148, 163, 184)),   # 月岩
}

TILT_DEG = -43.0        # 长轴倾角（度，顺时针为正 → 这里取逆时针 43°，与参考一致取负）
A_OUTER  = 0.72         # 外长半轴 / 画面宽
B_OUTER  = 0.30         # 外短半轴 / 画面宽（环呈扁椭圆）
STROKE   = 0.085        # 环线宽 / 画面宽
BG       = (253, 252, 251)

def draw_icon(size, top, bottom):
    ss = 4  # 超采样抗锯齿
    S = size * ss
    img = Image.new("RGB", (S, S), BG)
    px = img.load()
    cx = cy = S / 2
    a = A_OUTER * S          # 长半轴（倾斜方向）
    b = B_OUTER * S          # 短半轴
    w = STROKE * S           # 线宽
    th = math.radians(TILT_DEG)
    ct, st = math.cos(th), math.sin(th)
    # 椭圆中心线上的点参数 t∈[0,2π)：(a cos t, b sin t) 旋转 th
    steps = 2200
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ex, ey = a * math.cos(t), b * math.sin(t)
        rx = cx + ex * ct - ey * st
        ry = cy + ex * st + ey * ct
        # 该点的渐变色：按画面 y 位置从上(深)到下(亮)
        tt = min(max((ry / S), 0.0), 1.0)
        col = tuple(int(top[k] + (bottom[k] - top[k]) * tt) for k in range(3))
        r = w / 2
        x0, x1 = int(rx - r), int(rx + r) + 1
        y0, y1 = int(ry - r), int(ry + r) + 1
        for x in range(max(0, x0), min(S, x1)):
            for y in range(max(0, y0), min(S, y1)):
                if (x - rx) ** 2 + (y - ry) ** 2 <= r * r:
                    px[x, y] = col
    return img.resize((size, size), Image.LANCZOS)

# 1) 默认 AppIcon（星轨蓝，1024）
os.makedirs(os.path.join(ROOT, "Assets.xcassets", "AppIcon.appiconset"), exist_ok=True)
draw_icon(1024, *DESIGNS["Classic"]).save(
    os.path.join(ROOT, "Assets.xcassets", "AppIcon.appiconset", "icon1024.png"))

# 2) 抽屉预览（imageset，120）
for name, (top, bottom) in DESIGNS.items():
    set_name = "IconClassic" if name == "Classic" else name
    d = os.path.join(ROOT, "Assets.xcassets", set_name + ".imageset")
    os.makedirs(d, exist_ok=True)
    draw_icon(120, top, bottom).save(os.path.join(d, set_name + ".png"))
    json.dump({"images": [{"filename": set_name + ".png", "idiom": "universal", "scale": "1x"}],
               "info": {"author": "xcode", "version": 1}},
              open(os.path.join(d, "Contents.json"), "w"), indent=2)

# 3) 备选图标（bundle 资源，120 + 180）
alt_dir = os.path.join(ROOT, "AlternateIcons")
os.makedirs(alt_dir, exist_ok=True)
for name, (top, bottom) in DESIGNS.items():
    if name == "Classic":
        continue
    draw_icon(120, top, bottom).save(os.path.join(alt_dir, name + ".png"))
    draw_icon(180, top, bottom).save(os.path.join(alt_dir, name + "@3x.png"))

# 4) catalog 骨架 json
json.dump({"info": {"author": "xcode", "version": 1}},
          open(os.path.join(ROOT, "Assets.xcassets", "Contents.json"), "w"), indent=2)
json.dump({"images": [{"filename": "icon1024.png", "idiom": "universal",
                        "platform": "ios", "size": "1024x1024"}],
           "info": {"author": "xcode", "version": 1}},
          open(os.path.join(ROOT, "Assets.xcassets", "AppIcon.appiconset", "Contents.json"), "w"), indent=2)

print("icons v2 done")
