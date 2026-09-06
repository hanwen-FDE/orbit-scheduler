# Orbit・轨道

**All your plans run on time orbit.**
**所有计划，运行于时间轨道。**

[中文](#中文) ｜ [English](#english)

---

## 中文

Orbit（轨道）是一款 iOS 原生 AI 日程助手。名字取自拉丁语 *orbita*——天体绕行的路径：它把日程、计划视作在时间维度上运行的事物，AI 将零散、模糊的想法安置到时间的轨道上有序运转，帮你建立时间秩序。

### 它能做什么

- **三种输入**：文字 / 语音（实时转写）/ 图片（课程表、会议通知截图）
- **AI 识别**：调用云端大模型（智谱 GLM / OpenAI / 任意 OpenAI 兼容接口），把自然语言解析为结构化日程
- **批量录入**：多行日程一次粘贴逐项识别；整场会议（名称+起止时间）一键成项
- **自动写入系统日历**：复用 iPhone 自带日历，不另造日历 UI
- **日程卡片**：聊天式中管理——改时间、换日历、设提醒（准时/提前5~120分钟/1天）、删除
- **6 色图标**：App 内一键切换

### 如何安装（侧载，无需 Mac）

1. **开启开发者模式**：电脑安装 [iMazing](https://imazing.com)（3.4+）→ iPhone 连线 → 「启用开发者模式」→ 手机 *设置 → 隐私与安全性 → 开发者模式* → 打开并重启（只需一次）
2. **下载 IPA**：本仓库 *Actions* → 最新成功运行 → Artifacts → 下载 `ScheduleAssistant-ipa` → 解压出 `ScheduleAssistant.ipa`（存放路径建议纯英文）
3. **侧载安装**：电脑安装 [Sideloadly](https://sideloadly.io)（v0.60+）→ iPhone 连线 → 拖入 IPA → Apple Account 填你的 Apple ID → 密码填 **Apple ID 主密码**（开了两步验证的账号不能用 App 专用密码；弹出验证码时输入 iPhone 上显示的 6 位码）→ Start
4. **信任证书**：手机 *设置 → 通用 → VPN与设备管理* → 信任你的 Apple ID → 打开 Orbit
5. **首次配置**：App 内左上角头像 → AI 识别（API）→ 填入大模型 API Key（推荐智谱 [open.bigmodel.cn](https://open.bigmodel.cn)）→ 测试连接

> 免费签名有效期 7 天，到期后重复第 3 步重装即可，数据不丢。详细排障见 `docs/开发报告.html`。

### 技术栈

SwiftUI（iOS 18+）· EventKit · Speech · PhotosUI · 多 LLM Provider 架构 · GitHub Actions 云构建

---

## English

Orbit is a native iOS AI scheduling assistant. The name comes from Latin *orbita* — the path of a celestial body: plans are things running along the dimension of time, and Orbit uses AI to place scattered, fuzzy ideas onto orderly time orbits.

### What it does

- **Three inputs**: text / voice (live transcription) / images (class schedules, meeting notices)
- **AI parsing**: cloud LLMs (Zhipu GLM / OpenAI / any OpenAI-compatible endpoint) turn natural language into structured calendar events
- **Batch input**: paste multi-line schedules and get one card per line; a whole conference (name + time range) becomes a single event
- **Writes to the system calendar**: reuses the iPhone Calendar app instead of building another calendar UI
- **Event cards**: edit time, switch calendars, set alarms (on-time / 5–120 min / 1 day before), delete — all in a chat-style flow
- **6 icon color themes** switchable in-app

### How to install (sideloading, no Mac needed)

1. **Enable Developer Mode**: install [iMazing](https://imazing.com) (3.4+) on your PC → connect iPhone → *Enable Developer Mode* → on the phone: *Settings → Privacy & Security → Developer Mode* → toggle on & restart (one-time)
2. **Get the IPA**: this repo → *Actions* → latest successful run → Artifacts → download `ScheduleAssistant-ipa` → unzip to get `ScheduleAssistant.ipa`
3. **Sideload**: install [Sideloadly](https://sideloadly.io) (v0.60+) → connect iPhone → drop the IPA in → sign in with your Apple ID and your **main Apple ID password** (app-specific passwords do NOT work with free accounts; enter the 6-digit 2FA code when prompted) → Start
4. **Trust the profile**: *Settings → General → VPN & Device Management* → trust your Apple ID → launch Orbit
5. **First-run setup**: avatar (top-left) → AI API → paste your LLM API key (Zhipu recommended: [open.bigmodel.cn](https://open.bigmodel.cn)) → Test Connection

> Free signing lasts 7 days; repeat step 3 to re-sign. Data is preserved. Full troubleshooting guide: `docs/开发报告.html`.

### Tech stack

SwiftUI (iOS 18+) · EventKit · Speech · PhotosUI · multi-LLM provider architecture · GitHub Actions cloud builds

---

<p align="center"><sub>Orbit・轨道 ｜ All your plans run on time orbit.</sub></p>
