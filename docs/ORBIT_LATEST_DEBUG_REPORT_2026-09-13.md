> **历史快照（2026-09-13）**：本报告基于云端积分接入前的代码基线。当前发布口径、后端与积分架构以 `README.md`、`docs/ORBIT_FEATURE_AND_AI_ARCHITECTURE.md` 和 `docs/ORBIT_APPSTORE_METADATA.md` 为准。

# Orbit 最新版静态调试审查报告

审查日期：2026-09-13  
审查对象：`codex/test` 最后一版  
审查提交：`ebe6ec3125491bbae5a752390e882e32a81d05bf`  
审查方式：源码静态审查、Xcode 工程配置审查、GitHub Actions 与产物核验；本轮未修改 App 源码。

## 一、结论先行

最后一版已经恢复到“可以编译并生成测试包”的状态，但还不能作为稳定测试版或 App Store 候选版。

- GitHub Actions 第 21 次运行成功：`build-ipa` 与 `build-simulator` 两个任务均通过。
- 最新 IPA 产物已经生成，名称为 `ScheduleAssistant-ipa`，对应提交就是 `ebe6ec3`。
- 对话重新进入后滚动到最后一条消息的逻辑已经加入，原先“回到最初消息”的问题大概率已修复。
- API 错误提示已开始区分无网络、超时、401/403、429、服务端错误和模型返回异常，比旧版明显完善。
- 右上角旧“日程”入口已经改成通知铃铛；“今天页、对话页、通知中心、教学、语音、图片、循环日程、冲突建议、小组件、快捷指令”都有了实际代码。

但当前至少有 4 个发布阻断项、8 个高优先级功能缺陷。最严重的不是界面，而是数据安全：从“今天”页修改一个已有循环日程，可能清空该次事件的循环信息和额外提醒；部分日历写入失败也会被界面显示成成功。

因此建议：暂时不要合并到 `main`，也不要用真实重要日程做测试。先修复本报告的 P0，再下载新 IPA 进行真机回归。

## 二、构建与测试包状态

### 已确认

- 分支：`codex/test`
- 本地 HEAD 与远端 `origin/codex/test` 一致：`ebe6ec3`
- GitHub Actions 运行：[Build iOS App #21](https://github.com/hanwen-FDE/orbit-scheduler/actions/runs/34726920693)
- 真机任务：成功
- 模拟器任务：成功
- 最新 IPA artifact：`ScheduleAssistant-ipa`
- artifact 创建时间：2026-09-13 00:02 UTC
- artifact SHA-256：`521c142c77ac6c8e41a68f28bb731667c0a8ccf5a0395190a085a77f207f4ffc`

### 特别提醒

工作区根目录现有的 `ScheduleAssistant.ipa` 修改时间是 2026-06-09，明显不是本次最新版，不应再安装它。最新版应从上面的 Actions #21 页面底部 Artifacts 下载。

当前工作流只做“编译和打包”，没有 XCTest、UI Test 或自动化功能测试。因此绿色对勾只能证明项目可编译，不能证明简报、日历写入、通知、WeatherKit、语音或 API 在真机上正确工作。

## 三、你之前反馈的几个问题，最新版的真实状态

### 1. 打开 App 为什么没有简报

不是因为今天没有日程。即使今天是空日程，代码也会生成“今天日历还没有安排……”的简报文字。

真正原因是：App 默认先打开“今天”页，而生成简报的代码只放在 `ChatView.onAppear` 中。用户只是打开 App、停留在今天页时，简报根本不会生成；必须再点右下角对话气泡进入对话页才会执行。

证据：

- 根视图默认加载 `TodayScheduleView`，对话页是 `fullScreenCover`：`ScheduleAssistant/Sources/ScheduleAssistantApp.swift:33-40`
- 简报刷新只在对话页执行：`ScheduleAssistant/Sources/ChatView.swift:69-82,352-359`
- 空日程也有明确简报文案：`ScheduleAssistant/Sources/DailyBriefing.swift:124-132`

结论：这个问题仍未真正修复。

### 2. 天气为什么经常看不到

当前有两层问题：

1. `briefing.refresh()` 发起异步定位和 WeatherKit 请求后，代码固定只等 0.25 秒就写入简报。网络或定位通常不可能稳定在 0.25 秒内完成，所以简报很容易先写成“天气暂时无法获取”，天气回来后又没有自动更新这条消息。
2. 工程没有启用 WeatherKit capability，也没有 entitlement 文件；测试工作流还明确传入 `CODE_SIGN_ENTITLEMENTS=""`。因此当前 Sideloadly 测试包无法正常携带 WeatherKit entitlement，真机天气极可能持续失败。

证据：

- 固定等待 0.25 秒：`ScheduleAssistant/Sources/ChatView.swift:352-357`
- WeatherKit 请求异步返回：`ScheduleAssistant/Sources/DailyBriefing.swift:90-111`
- CI 主动清空 entitlement：`.github/workflows/build.yml:23-34`
- 项目中不存在 `.entitlements` 文件，也未发现 `com.apple.developer.weatherkit`。

Apple 官方要求在 Xcode/App ID 中启用 WeatherKit capability，并由签名写入 `com.apple.developer.weatherkit` entitlement：[WeatherKit Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.weatherkit)。此外，展示 Apple Weather 数据还需要天气来源归属及法律链接，当前界面也没有这部分：[Get Started with WeatherKit](https://developer.apple.com/weatherkit/)。

结论：天气功能目前不能算完成。

### 3. 退出后再进入，是否回到最后一段对话

已加入三处滚动到底部：首次布局、消息数量变化、App 回到前台。对于原先反馈的“重新进入跳到最初对话”，代码层面已经针对性修复。

证据：`ScheduleAssistant/Sources/ChatView.swift:91-131`

剩余体验问题：只要消息数量变化，页面都会强制滚到底部；用户正在翻看旧记录时，如果后台产生新消息，也会被拉回底部。建议后续增加“用户是否接近底部”的判断及“回到最新”按钮。

### 4. API 测试成功，但实际识别偶尔报网络/API 设置错误

已有进步：连接测试现在使用和正式识别相同的 endpoint、请求结构及 JSON 解码，并且正式错误文案不再把所有故障都归因于 API Key。

不过仍有两个明确缺陷：

- 切换 AI 服务商时，`ProviderConfigView` 的 `@State` 只在 `onAppear` 读取，视图没有按 provider ID 重建。SwiftUI 可能沿用上一个服务商的 Key、地址和模型，随后把旧状态保存到新服务商，造成“看起来测试过，实际请求却用了另一套配置”。位置：`ScheduleAssistant/Sources/SettingsView.swift:4-54,84-91`。
- `supportsImage` 只被声明，从未在发送图片前校验。DeepSeek、Kimi 被标记为不支持图片，但照片/相机入口仍然照常发送 `image_url`，实际请求会失败。位置：`ScheduleAssistant/Sources/LLMProvider.swift:11-14,257-272` 与 `ScheduleAssistant/Sources/ChatStore.swift:75-80`。

结论：原故障的提示已改善，但配置切换与图片能力判断还需要修复。

## 四、功能完成度对照

| 需求点 | 最新状态 | 审查结论 |
|---|---|---|
| 当天任务/日程列表 | 已实现 | 默认首页直接读取 Apple 日历，可前后翻天、编辑和删除 |
| 对话页面 | 已实现 | 但作为全屏弹层，不是与“今天”并列的底部 Tab |
| 右上角通知入口 | 已实现 | 已替换旧日程入口；内部删除与跳转仍有缺陷 |
| 对话卡片删除 | 已实现 | 长按后滑动、二次确认；底层删除失败会被误显示为成功 |
| 修改日程与目标日历 | 基本实现 | 全局可选默认日历，详情可移动日历；错误反馈不完整 |
| 冲突识别与重排建议 | 基本实现 | 有重叠检测、建议时间、采用及忽略；算法仍较粗糙 |
| 循环事件 | 已实现一部分 | 对话卡片可编辑循环；今天页编辑存在破坏循环数据风险 |
| 与系统提醒事项串联 | 已实现一部分 | 可手动同步/取消同步；不是自动双向同步 |
| 独立“习惯”入口移除 | 表面完成 | 新 UI 没有入口，但模型、服务、卡片及旧页面代码仍保留 |
| 每日晨报 | 部分实现 | 有对话卡片和本地通知，但触发时机、天气更新、跳转未闭环 |
| 每日晚报 | 部分实现 | 只有打开对话且已过时间时生成，不能后台自动生成正文 |
| 固定时间设置 | 与原要求不一致 | 当前改为“起床后 N 分钟/睡前 N 分钟”，设置页不能直接选固定时刻 |
| 无日程也显示简报 | 文案支持 | 但只有进入对话页才触发，所以打开 App 仍可能看不到 |
| 首次使用教学 | 部分实现 | 7 页静态教学已完成；没有语音样例演练、视频动画、小组件/快捷指令实操 |
| 语音输入 | 基本实现 | 有实时转写和时长；错误不显示、录音不保留、按钮结构有问题 |
| 图片/拍照识别 | 基本实现 | 支持相册和相机；未根据模型能力禁用或切换方案 |
| 桌面小组件 | 基础版完成 | 目前只是快速打开对话，不展示今日日程，也没有 App Group 数据共享 |
| 系统快捷指令 | 基础版完成 | 已注册“快速记录”“查看今日日程”两个 AppIntent |
| 电话提醒 | 未实现 | 当前只有日历提醒及提醒事项同步 |
| 协作/共享 | 未实现 | 当前没有邀请、共享日历、参与人或协调流程 |
| 隐藏 API Key 的会员后端 | 未实现 | 当前仅 BYOK：用户自己填写各服务商 API Key |

## 五、P0：必须优先修复的阻断问题

### P0-01 “今天”页编辑可能破坏循环规则和提醒

`TodayScheduleView.snapshot(of:)` 只保留第一个 alarm，完全没有把 `EKEvent.recurrenceRules` 转换到 `EventSnapshot.recurrence`。用户在今天页只改一个标题，保存时 `CalendarService.apply` 会先清空全部 alarms，再用这份缺失数据清空 recurrenceRules。

证据：

- 丢失循环规则、只取第一个提醒：`ScheduleAssistant/Sources/ScheduleListView.swift:371-385`
- 保存使用这份不完整快照：`ScheduleAssistant/Sources/ScheduleListView.swift:437-444`
- 底层明确清空 alarms 和 recurrenceRules：`ScheduleAssistant/Sources/CalendarService.swift:214-227`

风险：用户原本“每周一”并设置了两个提醒，进入 Orbit 今天页改标题后，可能变成单次例外、丢失额外提醒，属于真实用户数据破坏。

修复原则：今天页应直接在原 `EKEvent` 上只改用户实际编辑的字段，或者完整往返映射所有循环及 alarms；循环事件必须先询问“仅本次 / 本次及以后 / 全部”。

### P0-02 日历写入失败被吞掉，界面可能谎报成功

`updateEvent`、`deleteEvent` 和 `setReminder` 多处使用 `try?`，不把失败返回给上层。ChatStore 随后仍然更新卡片为“已修改/已删除/已开启提醒”。如果事件 ID 失效，`updateEvent` 还会静默重新创建一条事件，可能制造重复日程。

证据：`ScheduleAssistant/Sources/CalendarService.swift:62-92`、`ScheduleAssistant/Sources/ChatStore.swift:398-469`

修复原则：所有 CRUD 返回 `Result` 或抛出明确错误；只有系统保存成功后才更新聊天卡片；“原事件找不到”必须提示用户，禁止自动新建。

### P0-03 WeatherKit 能力和测试签名缺失

工程只导入了 WeatherKit，没有 capability/entitlement；CI 又清空 entitlement。侧载包即使可以安装，也不能据此验证天气功能。正式版还缺 Apple Weather attribution。

修复原则：开发者账号开通后，为正式 Bundle ID 和 App ID 启用 WeatherKit；添加 entitlements；为测试构建保留正确签名能力；界面加入 Apple Weather 归属与法律链接。侧载临时阶段可改用无需 Apple entitlement 的天气后端，或明确关闭天气入口。

### P0-04 目前不是 App Store 可上传身份

- 主 App Bundle ID 仍是 `com.example.scheduleassistant`
- Widget ID 仍是 `com.example.scheduleassistant.OrbitWidget`
- `DEVELOPMENT_TEAM` 为空
- 没有正式签名、App Store provisioning、WeatherKit capability
- 没有 `PrivacyInfo.xcprivacy`

证据：`ScheduleAssistant.xcodeproj/project.pbxproj:353-448`

项目大量直接使用 `UserDefaults`。Apple 要求使用 Required Reason API 的 App 在隐私清单中声明原因；缺失时 App Store Connect 不接受上传。官方说明：[Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) 与 [TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)。

## 六、P1：高优先级功能缺陷

### P1-01 通知子页删除会删错记录

子页显示的是经过筛选的 `items`，但 `.onDelete` 把子页 offset 直接传给完整 `store.items` 删除。比如“简报”子页第 1 条可能对应总列表第 5 条，左滑删除却会删总列表第 1 条。

证据：`ScheduleAssistant/Sources/ScheduleListView.swift:93-98,150-190`

应按通知 UUID 删除，而不是按筛选数组的 offset 删除；子页也应实时从 store 按 kind 计算，不能接收一次性的数组快照。

### P1-02 简报没有真正按时间生成

晨报生成函数没有判断当前是否已到设定时间；只要当天第一次进入 Chat，就会立即创建“今日早报”，即使是凌晨或下午。反过来，到设定时间时如果 App 没进入 Chat，只会出现一条通用系统通知，不会在对话中生成内容。

此外，本地通知没有携带 deep link/userInfo，点击通知只会打开默认“今天”页，仍不会直接看到简报。

修复原则：建立根级 `BriefingCoordinator`；App 启动和回前台都检查是否到期；通知点击路由到对应简报；天气先显示加载态，异步返回后更新同一条消息；无日程也必须生成。若产品坚持 iOS 后台限制，应把文案写成“到点提醒打开，打开后生成”，不要写成“自动推送到对话”。

### P1-03 简报设置与系统通知不同步

晨报/晚报 Toggle 只写 UserDefaults：关闭开关不会调用 scheduler 的 `disable()`；修改起床、睡觉或偏移也不会自动重新安排通知，必须用户另点“设置推送提醒”。首次教学结束时又无条件同时安排晨报和晚报，即使用户在教学中关闭了其中一个。

证据：`ScheduleAssistant/Sources/SideDrawerView.swift:137-218`、`ScheduleAssistant/Sources/UsageGuideView.swift:159-219`、`ScheduleAssistant/Sources/DailyBriefing.swift:147-221`

### P1-04 清空对话与异步 AI 请求存在崩溃风险

AI 请求以数组下标 `thinkingIndex` 和 `targetIndex` 记录目标消息。请求等待期间，如果用户在设置中执行“删除当前对话”，数组会被替换；请求返回后继续访问旧下标，可能数组越界崩溃。

证据：`ScheduleAssistant/Sources/ChatStore.swift:104-220,590-592`

修复原则：用消息 UUID 查找，不保存数组下标；清空对话时取消全部正在进行的 Task；为每个请求维护独立状态。

### P1-05 服务商切换可能串 Key/地址/模型

`ProviderConfigView` 的输入内容是本地 `@State`，只在 `onAppear` 加载。Picker 改变 provider 后没有 `.id(provider.id)` 或 `onChange` 重新加载，容易把上一家的状态显示或保存到下一家。

修复原则：给配置视图加稳定 provider identity，切换前保存旧 provider，切换后加载新 provider，并为每家单独显示测试状态。

### P1-06 语音交互仍不稳

- 一个外层“开始/停止录音” Button 的 label 内又嵌套了“垃圾桶” Button，属于嵌套交互控件，点击命中和无障碍行为不可靠：`ScheduleAssistant/Sources/ChatView.swift:180-225`。
- `SpeechService.errorMessage` 从未在 ChatView 展示；麦克风或语音权限被拒、识别器失败时，用户看到的是“点了没反应”：`ScheduleAssistant/Sources/SpeechService.swift:20-77`。
- 只保存转写文字，不保存录音文件；转写为空时整次输入直接消失，也不能重新转写。
- 注释写“本地中文识别”，代码却把 `requiresOnDeviceRecognition` 设为 false，并不能保证本地处理：`ScheduleAssistant/Sources/SpeechService.swift:38-49`。

### P1-07 对话修正会改变时长，也无法取消循环

用户只修改开始时间而模型没返回结束时间时，代码保留旧的绝对结束时刻，而不是保留原时长。例如 09:00–11:00 改到 10:00，可能变成 10:00–11:00；改到 16:00 时又会回退成固定 1 小时。

同时，`parsed.recurrence ?? original.recurrence` 让“取消重复”无法生效；删除地点和备注也有相同的 nil 合并问题。

证据：`ScheduleAssistant/Sources/ChatStore.swift:192-209`

### P1-08 自动写入与确认原则尚未统一

最新版在 AI 识别完成后立即把所有事件写入 Apple 日历，只有写入失败才显示“确认添加”。这与此前确认的“先生成可核对卡片，用户确认后写入”不一致，也放大了图片误识别和重试重复写入的风险。

证据：`ScheduleAssistant/Sources/ChatStore.swift:121-154,350-354`

这是产品决策而不只是代码错误，需要你最终二选一：

- 安全模式：默认预览确认，适合第一版和图片批量识别；
- 快速模式：高置信单条可自动写入，低置信、多条、冲突、图片必须确认。

我更建议第二种“分级确认”，兼顾 Toki 式速度和 Orbit 的可靠定位。

## 七、P2：需要随后完善的问题

1. 两个主页面目前不是并列 Tab，而是“今天首页 + 右下角气泡 + 全屏对话”。如果要严格执行已确认方案，应恢复底部“今天 / 对话”双入口。
2. 独立习惯虽然没有新入口，但 `HabitSnapshot`、`HabitDetailSheet`、`HabitCardView`、`createHabit` 仍在正式 target 中，旧数据仍会显示习惯卡；应完成迁移后删除。
3. 通知中心所谓“提醒”其实是“已添加到日历”的操作记录，不是提醒真正触发的历史，命名会误导用户。
4. 简报通知没有 `relatedMessageId`，无法从通知中心跳到相应简报；子页的 dismiss 也可能只返回上一层，而不是关闭整个通知 sheet。
5. `DailyBriefingCard` 和 `ensureDailyBriefing` 均没有调用者，存在两套简报逻辑并行、以后行为继续分叉的风险。
6. `upsertDailyBriefing` 没有加入已经写好的 `encouragement` 文案，所以对话简报缺少你要求的“加油/问好”结尾。
7. “读取哪些日历”全部关闭会自动等同全部开启，用户无法选择不读取任何日历；保存的日历 ID 全部失效时也会回退读取全部，逻辑和隐私预期不清晰。
8. 冲突检测忽略所有全天事件，会漏掉“全天出差、全天培训、休假”等真实阻塞；建议时间使用所有日历，而冲突列表使用用户选择的日历，两者范围不一致。
9. 建议时间只使用起床/睡觉的小时，忽略分钟；只从原时刻向后推，不搜索同日更早的空档，也没有通勤/缓冲时间。
10. Today 页切到明天或后天且为空时，仍显示“今天暂无安排”。
11. 重试按钮会永远留在旧错误消息上，重复点击会重新解析并可能再次写入同一日程；缺少幂等键和重复检测。
12. 对话 JSON 解码失败时直接回到欢迎消息，没有备份、迁移或损坏提示；版本升级可能让用户误以为历史被清空。
13. 小组件目前只是打开 App 的快捷入口，还没有用户期待的今日日程摘要或教学动画。
14. iOS 最低版本设为 18.0，发布前应根据目标用户覆盖率决定是否降低；这不是编译错误，但会直接限制可安装用户。

## 八、建议修复顺序

### 第一阶段：先保证不破坏用户数据

1. 修复 Today 编辑的循环和 alarms 丢失。
2. 所有 EventKit 写、改、删返回明确成功/失败。
3. 禁止 update 找不到原事件时自动 create。
4. 修复通知筛选列表删错项目。
5. 将异步 AI 操作从数组下标改为 UUID，并支持取消。

完成标准：对 1 次日程、循环日程、全天日程、多个提醒、只读日历、事件被系统删除等情况都不会误报成功或破坏字段。

### 第二阶段：闭环每日简报和天气

1. 把简报协调器提升到根视图，不依赖先打开 Chat。
2. 明确采用“固定时刻”还是“起床/睡觉相对时间”，只保留一套设置模型；目前遗留的 `morningBriefingHour/minute` 已经完全没有被使用。
3. 开关、时间变化与系统通知自动同步；关闭必须取消通知。
4. 通知点击直达当天简报。
5. 天气异步完成后更新同一条简报；加入加载、拒绝定位、无网络、WeatherKit 不可用状态。
6. 配置 WeatherKit entitlement 和天气归属。

### 第三阶段：稳定 AI、多模态和语音

1. 修复服务商切换状态串线。
2. 根据 `supportsImage` 禁用图片或自动提示切换到多模态模型。
3. 语音按钮拆成同级控件，展示权限/识别错误，保留临时录音直到发送成功。
4. 修正“接续修改”的时长与可清空字段语义。
5. 增加幂等写入、防重复及低置信确认。

### 第四阶段：完成信息架构和教学

1. 由你确认最终导航：底部双 Tab，还是今天页 + 对话气泡；不要同时在文案里说“切换到对话”却没有 Tab。
2. 清理独立习惯遗留代码和旧数据迁移。
3. 首次教学增加真实的语音示例、图片示例、第一条试运行、小组件和快捷指令步骤。
4. 将通知中心语义改为“提醒 / 简报 / 冲突与失败”，并保证每条可追溯到相应卡片。

### 第五阶段：App Store 工程化

1. 正式 Bundle ID、Team、签名、Widget ID 与 capabilities。
2. PrivacyInfo.xcprivacy、隐私政策、API/图片/语音/位置数据流披露。
3. 增加 Unit Test、UI Test 和至少一套 mock EventKit/LLM 测试。
4. TestFlight 内测后再准备截图、描述、审核备注和正式提交。

## 九、下一轮真机测试清单

### 日历数据安全

- 新建单次事件、全天事件、每周事件、工作日事件。
- 每种事件分别配置 0、1、2 个系统提醒。
- 在 Orbit 今天页只改标题，确认循环和所有提醒没有变化。
- 删除“仅本次”和“本次及以后”，核对 Apple 日历结果。
- 在 Apple 日历先删掉事件，再回 Orbit 修改，确认不会偷偷新建重复项。
- 使用只读订阅日历，确认 Orbit 不会显示假成功。

### 简报与天气

- 今天 0 项、1 项、多项日程都能生成晨报。
- 到点前、到点后、App 完全关闭、App 在今天页、App 在对话页分别测试。
- 开关关闭后检查系统待处理通知确实消失。
- 修改起床时间后检查通知自动更新。
- 定位首次询问、拒绝、稍后开启、无网络、慢网络分别测试。
- 点击系统晨报通知应直接看到对应简报，而不是只打开今天页。

### API 与输入

- 每个服务商分别保存、切换、退出设置、重新进入，确认 Key 不串线。
- DeepSeek/Kimi 下选择图片，应明确阻止或提示，不应直接发出必然失败的请求。
- 测试无网络、DNS 错误、超时、401、402、429、5xx、模型非 JSON。
- 连续快速发送两条消息，然后清空对话，确认不崩溃。
- 成功重试后再次点击旧“重试”，确认不会重复写日历。
- 拒绝麦克风和语音权限时必须有可见提示及“前往设置”。

### 导航与通知

- 退出重进后停在最后一段对话。
- 阅读旧消息时新消息不应强制打断，提供“回到最新”。
- 在“通知”和“简报”子页分别删除第 1、2 条，确认删的是所选 UUID。
- 点击冲突、失败、提醒、简报四类记录，核对跳转目标。
- 小组件和两个快捷指令从冷启动、后台、前台三种状态打开正确页面。

## 十、当前建议

现在可以下载最新 IPA 做“界面走查”，但不适合用真实工作日历做破坏性测试。建议先在 iPhone 的 Apple 日历中新建一个专用测试日历，例如“Orbit 测试”，把它设为 Orbit 默认日历，并只放可删除的测试事件。

本轮最合理的下一步不是继续加新功能，而是先完成第一阶段的 5 个数据安全修复，再构建新的 IPA。之后再集中验证晨报和天气，否则现在收集到的真机反馈会被底层错误干扰。
