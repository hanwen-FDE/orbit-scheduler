# Orbit・轨道 App Store 冲刺上架计划（2026-09）

> 编制日期：2026-09-14（周一）｜目标：**9 月 20 日（周日）过审上线，用户可在 App Store 搜索下载**
> 账号状态：Apple 个人开发者账号（$99/年）审核中（个人账号通常 24–48 小时通过）
> 关联文档：`APPSTORE_RELEASE_PLAN.md`（六阶段闸门总计划，本文件是其阶段 1–4 的压缩执行版）、`docs/ORBIT_LATEST_DEBUG_REPORT_2026-09-13.md`（P0 缺陷详情）、`docs/ORBIT_MARKET_AND_ACCOUNT_STRATEGY.md`（商业化与账号策略）

---

## 0. 一页结论

- **主线**：9/17（周四）前完成 P0 修复 + 商店素材，最晚 9/18 提审，争取 9/20 过审上线。首发地区 = **全球（不含中国大陆）**。
- **并行线**：**今天就启动工信部 App 备案**（不等 App 完成、不等账号通过），预计 10 月上中旬拿到备案号后，在 App Store Connect 填号、单独开放中国区。两条线互不耽误。
- **今天最重要的一件事**：定稿 **App 名称 + Bundle ID**——备案和上架共用这两个信息，备案后再改很麻烦，牵一发动全身。

---

## 1. 备案问题解答（回应提问：什么时候能备案？要等 App 做完吗？）

**不用等 App 开发完成，也不等苹果账号通过，今天就能提交。**
备案审的是"谁（主体）+ 用什么域名/服务器 + 提供什么服务（App 信息）"，不审 App 代码本身。

需要提前准备的 4 样东西：

1. **主体资料**：个人备案 = 本人身份证 + 人脸核验。⚠️ 备案主体姓名必须与 Apple 个人开发者账号是**同一个人**（Apple 校验备案号时会核对主体一致）。
2. **已完成实名认证的域名**：域名实名信息也应是本人。你已有域名 ✅，需核验实名主体是否为本人。
3. **云厂商备案服务码**：只有国内云厂商（阿里云/腾讯云/华为云等）的服务器/主机能生成，一般要求包年包月（如阿里云 ECS ≥3 个月、轻量应用服务器）。⚠️ 若云资源在境外厂商（AWS 海外、Vultr 等），无法用于备案，需另购国内轻量服务器（约 ¥100/年）。
4. **App 基本信息**：App 名称、平台 iOS、**Bundle ID**、用途说明、权限使用说明。日程工具**不涉及**新闻/出版/教育/医疗等前置审批，如实填写即可。

**唯一的前置依赖：App 名称和 Bundle ID 必须先定稿**，因为备案信息要与之后 App Store 上架信息保持一致，备案通过后再变更很麻烦。

流程与时长：

```
今天提交 → 云厂商初审（1–2 天）→ 通信管理局审核（法定最长 20 个工作日，实际常见 3–10 个工作日）→ 获得备案号
```

**结论**：9/20 前拿到备案号基本不可能 ⇒ 9/20 首发**只能选全球（不含中国大陆）**；备案下来后在 App Store Connect 填备案号并勾选中国大陆。中国区预计 **10 月上中旬**可开放。

---

## 2. 冲刺总时间轴

| 日期 | 主线（上架） | 并行线（备案） |
|---|---|---|
| 9/14 周一（今天） | 定稿 App 名称 + Bundle ID；修 P0；隐私政策/支持页上线；商店文案初稿 | 发起 App 备案（材料 + 人脸 + 提交） |
| 9/15 周二 | 账号应通过（24–48h）→ 证书 + ASC 建号 + 首个签名构建 | 云厂商初审 |
| 9/16 周三 | 签名构建 → TestFlight/真机回归 P0；截图终版；ASC 填写完成 | 管局审核中 |
| 9/17 周四 | **提审（目标日）**，选自动发布 | 管局审核中 |
| 9/18 周五 | 缓冲：回归出问题则修复重传，最晚今天提审 | 管局审核中 |
| 9/19–20 周末 | 盯审核状态；过审自动发布 → 可搜索 | — |
| 9/21 之后 | 若被拒：修复 + Resolution Center 回复 + 重提（每轮约 24h） | 拿备案号 → ASC 填号 → 开放中国大陆 |

> ⏰ **为什么 9/17 提审**：9/20 是周日，苹果审核周末变慢；约 90% 的审核在 24–48h 内完成。周四提审 + 一次过审 = 9/19–20 上线，周五留作缓冲。

---

## 3. 阶段 A：账号等待期任务（现在就开始，四轨并行）

标注说明：🤖 = 可交给 AI（ZCode）代做；👤 = 必须本人操作。

### A1 代码轨（✅ 2026-09-14 已由 AI 执行完毕，待推送 GitHub 触发 CI 验证编译）

- [x] 👤+🤖 **定稿正式 Bundle ID**：✅ 2026-09-14 定稿 **`com.itransstudio.orbit`**（itransstudio.com 域名倒序；小组件 `com.itransstudio.orbit.OrbitWidget`）——工程 pbxproj 已替换，备案表与 ASC 照抄此串。早前临时用的 `com.hanwenfde.orbitscheduler` 已废弃（App 备案未提交前完成切换，零成本）。
- [x] 🤖 **修复 P0-1：循环日程编辑可能丢失数据**：快照层的 `alarmOffsets`/`recurrence` 往返映射在工作区已存在；本次补齐了循环日程编辑时的「只改这一次 / 改这一次及后续」范围选择（EKEventEditor），不再默认改掉整个系列。
- [x] 🤖 **修复 P0-2：日历写入失败被显示为成功**：`CalendarService` 全部写操作（create/update/delete/setReminder/moveToCalendar）改为返回 `Result`，明确区分"原事件不存在 / 只读日历 / 保存失败"；`updateEvent` 不再在找不到原事件时静默重建（杜绝重复日程）；`ChatStore` 全部 7 处调用点改为成功才更新卡片，失败统一走"通知中心 + 对话提示"；今天页删除/编辑失败会弹窗告知。
- [x] 🤖 **建立 PrivacyInfo.xcprivacy 隐私清单**：主 App（声明 UserDefaults CA92.1 + BYOK 数据送第三方 LLM 的 OtherUserContent 披露）与小组件（零数据声明）各一份，均已接入 pbxproj 资源阶段。
- [x] 🤖 **补 entitlements 文件**：`ScheduleAssistant/ScheduleAssistant.entitlements` 启用 WeatherKit（小组件为零数据快速入口，无需 entitlements；App Group/Keychain 共享经核查暂不需要——小组件不读任何共享数据）。
- [x] 🤖 **Info.plist 权限文案复核**：7 个权限键文案已存在且如实描述用途，无需改动；已加 `ITSAppUsesNonExemptEncryption = NO`（仅标准 HTTPS，免出口合规审查）。中英双语本地化列为上线后 P2。
- [x] 🤖 **CI 签名改造**：`build.yml` 新增 `build-signed` job——手动触发并勾选 `signed` 时走 App Store Connect API Key 自动签名（自动注册 App ID 含 WeatherKit、分发证书、描述文件）、导出 app-store-connect IPA 并上传 TestFlight；未配置 Secrets 会明确报错。默认 push 仍走原无签名侧载路线，互不影响。**账号通过后需配置 4 个 Secrets：`ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8`（base64）/ `ASC_TEAM_ID`。**

### A2 素材轨（🤖 部分 2026-09-14 已完成，产出见 `website/` 与 `docs/ORBIT_APPSTORE_METADATA.md`、`docs/ORBIT_IMMUTABLE_INFO_CHECKLIST.md`）

- [x] 👤 **App 名称定稿 + 查重** ✅ 2026-09-14 定稿：**商店名 `Orbit`，中文语境"轨道"，品类"效率·日程助手"**；查重结论与备案名（Orbit）见 METADATA 文档 §1；App 内品牌标已由"Orbit 轨迹"改为"Orbit 轨道"（Models.swift），README 标题同步统一
- [x] 🤖 **隐私政策页**：`website/privacy.html` 已完成（中英双语；云端积分数据流、无追踪、权限用途表、BYOK 高级可选项；支持邮箱 `service.orbit@iChatStudio.com`）——部署指南见 `website/README.md`
- [x] 🤖 **支持页**：`website/support.html` 已完成（3 分钟上手步骤、Orbit 账号与积分说明、权限用途、常见故障排查、联系方式卡片）
- [x] 🤖 **商店文案**：`docs/ORBIT_APPSTORE_METADATA.md` §2–§5（副标题 19/30 字符、关键词 77/100 字符、完整描述、What's New，均按限制备好可直接粘贴）+ §8 ASC 字段速填表 + §9 隐私标签勾选对照
- [ ] 👤+🤖 **截图**（iPhone 专用 App 只需 6.9" 一套：1320×2868，3–8 张）：拍摄脚本已列于 METADATA 文档 §7（8 张画面与顺序）⏳ 待拍摄；iPhone 16 Pro Max 真机直接截屏即是该分辨率
- [ ] 👤 **审核测试账号**：⏳ 在正式后端创建独立审核账号并预置积分；真实凭证只填 App Store Connect，不提交 Git 仓库
- [x] 🤖 **审核备注草稿**：METADATA 文档 §6（审核账号占位 + 云端积分测试路径 + 可选 BYOK 说明）
- [ ] 👤 **网站上线**：`website/` 三页上传到你已有域名（三种部署方式见 `website/README.md`），上线后把 https URL 回填 METADATA §8；AI 无法代替部署（无服务器凭证）

### A3 账号/合规轨

- [ ] 👤 **每天检查账号状态**：developer.apple.com 登录看 Membership 是否 Active；注册超 48 小时未过 → 联系苹果（developer.apple.com/contact/，选 Membership and Account）；确认两步验证手机可用
- [ ] 👤 **备案启动（今天）**：核验域名实名主体 = 本人 → 云厂商备案控制台申领备案服务码 → 提交 App 备案（材料见 §1）→ 记录备案订单号备查

### A4 测试轨

- [ ] 👤 侧载最新构建，按 `APPSTORE_RELEASE_PLAN.md` 测试矩阵跑**压缩版核心路径**：文字/语音/图片建日程 → 写入 → 编辑 → 删除；**循环日程重点测**（P0-1 相关）
- [ ] 👤 快捷指令版继续收集周围用户反馈（上架前唯一的真实用户信号来源）

---

## 4. 阶段 B：账号通过后 24–48 小时（黄金窗口）

按顺序执行，每步完成勾掉：

- [ ] 👤 登录 developer.apple.com：同意弹出协议，进入 Certificates, Identifiers & Profiles 确认可用
- [ ] 👤 **App Store Connect 创建 API Key**（用户与访问 → 集成 → App Store Connect API，Team Key，Admin 权限）：得到 Key ID / Issuer ID / .p8 文件
- [ ] 👤 GitHub 仓库 Secrets 配置：`ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8`（base64）
- [ ] 🤖 **正式签名构建（无 Mac 方案，推荐自动签名）**：改造 `build.yml`，核心命令：

  ```bash
  xcodebuild -scheme ScheduleAssistant \
    -destination 'generic/platform=iOS' \
    -allowProvisioningUpdates \
    -authenticationKeyPath AuthKey.p8 \
    -authenticationKeyID $ASC_KEY_ID \
    -authenticationKeyIssuerID $ASC_ISSUER_ID \
    -archivePath build/Orbit.xcarchive archive
  # 导出 IPA 后上传：
  xcrun altool --upload-app --type ios -f Orbit.ipa \
    --apiKey $ASC_KEY_ID --apiIssuer $ASC_ISSUER_ID
  ```

  Xcode 会自动注册 App ID（含 WeatherKit capability）、生成分发证书与描述文件并完成签名。备选方案 B：fastlane match（首次生成证书/描述文件后存入 Secrets 复用，更可控）
- [ ] 👤 **App Store Connect 创建 App**：名称（已定稿）、主要语言、正式 Bundle ID、SKU（如 `orbit-001`）；**销售范围选全球后手动取消中国大陆**（等备案）
- [ ] 👤 首个签名构建上传 → **TestFlight 内部测试**（无需 Beta 审核，构建处理约 15–30 分钟）→ 真机安装回归 4 个 P0 修复点
- [ ] 👤 顺手事项：ASC 税务/银行表单首发免费版**不阻塞可缓填**，但建议 10 月前补齐，避免以后加订阅时卡住

---

## 5. 阶段 C：提审（目标 9/17，最晚 9/18）

- [ ] ASC 版本页填写完整：截图、描述、关键词、副标题、支持 URL、隐私政策 URL、年龄分级（4+：无用户生成内容、无赌博等）、版权、出口合规（标准 HTTPS exempt）
- [ ] **App 隐私标签**（Privacy → 营养标签）如实勾选：日历、提醒事项、位置（精确度：粗略；用途：App 功能）、语音/图片/日程文本 → 发送至用户配置的第三方（智谱/OpenAI 兼容）；**不收集**到自有服务器、无追踪、不与身份关联
- [ ] 审核备注粘贴演示 Key + 分步演示说明；联系方式留邮箱
- [ ] 发布方式选**自动发布**（过审即上商店，赶 9/20 必选）
- [ ] 提交审核（ASC 会显示预计时长，通常 24 小时内）
- [ ] 🤖 **一次过审要点**：审核员能在 3 分钟内跑通核心闭环（备注第一行写"请先在设置中填入演示 Key"）；界面无占位内容、无崩溃、无死胡同空状态；权限弹窗文案与实际用途一致；商店截图与实际界面一致（避免 2.3.3）

---

## 6. 9/20 后：中国区开放流程（备案下来时执行）

1. 👤 云厂商控制台查收**备案号**（格式如 `京ICP备2026XXXXXX号-XX`）
2. 👤 ASC → App Store 页签 → App 信息 → **ICP 备案号**字段填入
3. 👤 定价与销售范围 → 勾选**中国大陆** → 保存（修改销售区域一般即时生效、无需重新提审；Apple 会校验备案号真实性与主体一致性）
4. 🤖（可选）更新中国区搜索关键词与描述

---

## 7. 风险与预案

| 风险 | 概率 | 预案 |
|---|---|---|
| 账号审核拖延 | 中 | 超 48h 联系苹果（个人账号偶有 3–7 天）；A 轨全部任务不受影响，照常推进 |
| 审核被拒：2.1 完整性（审核员无 Key 用不了 AI） | 中高 | 备注提供演示 Key + 详细分步说明是唯一解；被拒后 24h 内修复重提 |
| 审核被拒：5.1 隐私（日程文本送第三方 LLM） | 中 | 隐私政策 + 隐私标签如实声明"发送至用户自行配置的 LLM 服务商"；App 内首次使用时给出提示文案 |
| 审核被拒：4.2 最小功能 | 低 | AI 解析 + 日历写入 + 语音 + 图片 + 小组件，功能密度足够；保证演示路径完整 |
| App 名称被占用 | 高 | 今天查重定稿并备 3 个候选；若备案后改名，云初审阶段可撤回修改 |
| 备案被驳回 | 中 | 常见原因：用途描述过简、权限说明缺失——按"AI 日程工具：读取系统日历、语音转文字、识别课程表图片并生成日程"如实详写；驳回可修改后重提 |
| P0 修复延期 | 中 | 9/16 晚设检查点：P0-1/P0-2 未修复完 → 提审顺延至 9/18；仍不行则接受 9/21–22 上线，保素材质量不动摇 |
| 9/20 仍未过审 | 中 | 降级口径：9/20 前处于"已提交审核"状态；过审当日自动发布即可被搜索 |

---

## 8. 总检查清单（按天打印）

**今天 9/14（周一）必办 👤**
- [x] 定稿 App 名称 → ✅ **Orbit**（中文"轨道"，品类"效率·日程助手"），备案名同名，详见 METADATA §1
- [x] 定稿 Bundle ID → ✅ **com.itransstudio.orbit**（域名倒序，工程已落地；早前 GitHub 版已废弃）
- [ ] 发起 App 备案：域名实名核验 → 备案服务码 → 身份证人脸 → App 信息 → 提交
- [ ] 检查苹果账号审核状态
- [x] 把 A1 代码轨交给 AI 开工：P0-1、P0-2、隐私清单、entitlements、Info.plist 文案、CI 改造 → ✅ 全部完成
- [x] 把 A2 素材轨交给 AI 开工：隐私政策页、支持页、商店文案、审核备注 → ✅ 完成（website/ 三页 + METADATA 文档，占位符全部填好）；剩余 👤：名称定稿、演示 Key、截图、网站上传（文件已就绪直接传）
- [ ] 👤 **推送代码到 GitHub（codex/test 分支）触发 Actions 第 22 次构建，确认编译通过**（本机无 git 命令，需你推送或用其他工具同步）

**9/15（周二，账号过审日）**
- [ ] 同意协议 + 创建 ASC API Key + 配置 GitHub Secrets
- [ ] ASC 创建 App（全球不含中国大陆）
- [ ] 首个正式签名构建上传

**9/16（周三）**
- [ ] 真机 / TestFlight 内部回归：4 个 P0 全绿
- [ ] 截图、文案、隐私标签全部就位

**9/17（周四）**
- [ ] 提审（自动发布 + 演示 Key 备注）

**9/18–20（周五–周日）**
- [ ] 盯审核状态；被拒则当天修复、回复、重提
- [ ] 过审 → 商店可搜可下载 🎉

**拿到备案号后（预计 10 月上中旬）**
- [ ] ASC 填备案号 → 勾选中国大陆 → 中国区可下载

---

*本文件是 `APPSTORE_RELEASE_PLAN.md` 六阶段计划在"9/20 硬期限"约束下的压缩执行版；原计划的完整测试矩阵与阶段 5（产品网站/开发者文档）在上线后继续推进。*
