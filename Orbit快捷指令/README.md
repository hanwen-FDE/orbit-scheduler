# 🪐 Orbit快捷指令

**Orbit·轨道 日程助手** 的 iOS 快捷指令版 —— 不侧载、不越狱、不装 App，
一条 iCloud 链接点开即用，AI 把自然语言变成系统日历日程。

> 把主项目（`../ScheduleAssistant`，SwiftUI App 版）的核心能力移植到了「快捷指令」里：
> 文字 / 语音 / 图片三种输入 · 批量识别 · 多模型（任意 OpenAI 兼容接口）· 自动写入系统日历。
> 侧载门槛太高时，就用这一版。

## 📂 文件清单

| 文件 | 说明 |
|---|---|
| **[使用说明书.html](使用说明书.html)** | ⭐ 图文并茂的完整文档（图片内嵌，双击打开，可直接转发） |
| [使用说明书.md](使用说明书.md) | 同内容的 Markdown 源 |
| **Orbit轨道日程助手.shortcut** | 快捷指令工程文件（90 动作完整版，未签名） |
| **Orbit轨道日程助手-已签名.shortcut** | 签名产物（可直接导入 iPhone；由 `sign_shortcut.py` 或 Actions 生成） |
| [sign_shortcut.py](sign_shortcut.py) | 签名器：借 RoutineHub 的 HubSign 服务给 .shortcut 加 Apple 签名（免 macOS） |
| [../.github/workflows/sign-shortcut.yml](../.github/workflows/sign-shortcut.yml) | GitHub Actions 云端签名（本地网络被 Cloudflare 拦截时用它，美国机房 IP 代签） |
| [源码速览.md](源码速览.md) | 90 个动作的人类可读清单（对照排错 / 进阶改装） |
| [build_shortcut.py](build_shortcut.py) | 快捷指令生成器（含结构自校验），改动后重跑即可重新生成 |
| [make_docs_images.py](make_docs_images.py) | 说明书全部配图的绘制脚本 |
| [make_docs_html.py](make_docs_html.py) | md → 自包含 html 转换脚本 |
| images/ | 配图源文件（banner / 原理 / 配置 / 安装 / 效果 / 分享，共 6 张） |

## 🚀 快速开始

1. **读文档**：打开 `使用说明书.html`（10 分钟装好 + 配好）
2. **领密钥**：[open.bigmodel.cn](https://open.bigmodel.cn) 免费领一枚智谱 API Key
3. **装**：说明书第三节三选一 —— 已签名文件（推荐）/ iCloud 链接 / 手动搭建

## 🔏 关于「不支持导入未签名的快捷指令文件」

iOS 15 起，iPhone 强制要求 .shortcut 文件带 Apple CMS 数字签名，未签名文件一律
无法直接导入（「允许不受信任的快捷指令」开关也只对 iCloud 链接生效）。分发路径：

```
方式A(推荐): 推送到 GitHub → Actions「Sign iOS Shortcut」→ 下载 Artifacts
             → 得到已签名 .shortcut → 微信/QQ 发到手机 → 文件App点开导入
   （本地网络可达 RoutineHub 时，也可 python sign_shortcut.py 直接签）
方式B: 任意一台 iPhone 装好后 → 清空密钥 → 长按 → 分享 → iCloud链接
       → 之后所有人点链接即装
方式C: 保底 —— 照说明书附录A手动搭建（无网络依赖）
```

⚠️ 分发前务必把「API密钥」换回占位文字 `请把这一行替换成你的API密钥`。

## 🔧 维护

```bash
python build_shortcut.py     # 改完动作/提示词后重新生成 .shortcut（含自动校验）
python sign_shortcut.py      # 本地签名（网络可达 RoutineHub 时）
python make_docs_images.py   # 改配图
python make_docs_html.py     # md 改完转 html
```

所有可自定义项（API 地址 / 密钥 / 模型 / 目标日历 / 提前提醒分钟）都集中在
快捷指令最上方的「配置」字典里——终端用户无需理解后面 90 个动作。

<p align="center"><sub>Orbit·轨道 —— All your plans run on time orbit. 🪐</sub></p>
