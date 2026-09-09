# -*- coding: utf-8 -*-
"""
Orbit·轨道 —— .shortcut 文件签名器（免 macOS）
=================================================
背景: iOS 15 起，iPhone 只接受带 Apple CMS 数字签名的 .shortcut 文件，
直接导入未签名文件会提示「不支持导入未签名的快捷指令文件」。
官方签名命令 shortcuts sign 仅 macOS 且需登录 iCloud；本脚本借助
RoutineHub 社区维护的 HubSign 服务完成签名（协议同 wynx1123/shortcut-signer，MIT）。

用法:
  python sign_shortcut.py                     # 签名 build_shortcut.py 的产物
  python sign_shortcut.py 输入.shortcut -o 输出.shortcut

失败排查:
  - HTTP 403 + Cloudflare 拦截页 → 本机 IP 被 RoutineHub 的防火墙拦截
    (国内网络常见)。此时改用 GitHub Actions 云端签名:
    .github/workflows/sign-shortcut.yml (美国机房 IP)，或按说明书手动搭建。
  - 403 但返回 JSON → HubSign 可能已要求 RoutineHub 会员，同样走上面两条路。
"""

import argparse
import json
import plistlib
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

HERE = Path(__file__).parent
HUBSIGN_URL = "https://hubsign.routinehub.services/sign"
HEADERS = {
    "Content-Type": "application/json",
    "User-Agent": "cherri/1.0",
    "Origin": "https://routinehub.co",
    "Referer": "https://routinehub.co/",
}


def sign_file(input_path: Path, output_path: Path, name: str) -> None:
    raw = input_path.read_bytes()
    if raw[:6] != b"bplist" and raw[:5] != b"<?xml":
        sys.exit(f"!! 无法识别 {input_path.name} 的 plist 格式")
    xml = plistlib.dumps(plistlib.loads(raw), fmt=plistlib.FMT_XML).decode("utf-8")
    payload = json.dumps({"shortcutName": name, "shortcut": xml}).encode()

    print(f"→ 上传 {len(payload) // 1024} KB 到 HubSign 签名服务 …")
    req = Request(HUBSIGN_URL, data=payload, headers=HEADERS, method="POST")
    try:
        with urlopen(req, timeout=60) as resp:
            data = resp.read()
    except HTTPError as e:
        body = e.read()[:200].decode("utf-8", "ignore")
        if (e.headers.get("server", "").lower() == "cloudflare"
                or "cloudflare" in body.lower()
                or "attention required" in body.lower()):
            sys.exit("!! 本机 IP 被 RoutineHub 的 Cloudflare 防火墙拦截。"
                     "请改用 GitHub Actions 云端签名"
                     "(.github/workflows/sign-shortcut.yml)，"
                     "或按《使用说明书》方式 C 手动搭建。")
        sys.exit(f"!! HubSign 拒绝了请求 (HTTP {e.code}): {body[:200]}")
    except URLError as e:
        sys.exit(f"!! 无法连接 HubSign: {e.reason}")

    if data[:4] != b"AEA1":
        sys.exit(f"!! 服务返回了意外的数据 (前4字节 {data[:4].hex()})，"
                 "可能临时不可用，请稍后再试")

    output_path.write_bytes(data)
    print(f"OK 已签名 → {output_path} ({len(data) // 1024} KB)")
    print("   传到 iPhone (微信文件传输助手/隔空投送/iCloud盘 皆可)，")
    print("   在「文件」App 里点开它 → 添加快捷指令。")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Orbit 快捷指令签名器")
    ap.add_argument("input", nargs="?",
                    default=str(HERE / "Orbit轨道日程助手.shortcut"))
    ap.add_argument("-o", "--output",
                    default=str(HERE / "Orbit轨道日程助手-已签名.shortcut"))
    ap.add_argument("-n", "--name", default="Orbit轨道日程助手")
    args = ap.parse_args()
    sign_file(Path(args.input), Path(args.output), args.name)
