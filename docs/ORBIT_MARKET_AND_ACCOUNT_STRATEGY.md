# Orbit 竞品、商业化与开发者账号策略

## 结论先行

1. **可以先用个人 Apple Developer Program 账号发布 Orbit。**这很适合目前没有公司的早期验证阶段；代价是 App Store 会把你的**法定个人姓名**显示为开发者/卖家，而不是 “Orbit”。会员费目前为每年 99 美元或当地等值货币。[^1]
2. **以后可以变成公司主体。**Apple 允许申请把个人会员更新为组织会员；也允许把已发布的 App 转移到另一个 App Store Connect 账号/组织。后者可保留 Bundle ID、评分和用户更新，但有资格条件及订阅、TestFlight、签名资料的迁移工作。[^2][^3]
3. **不要为了“像日历 App”而先造一套自己的日历数据库。**Orbit 当前最合理的定位是“把零散输入可靠地写进用户已在用的 Apple 日历”的 AI 入口层；Apple 日历仍是事实数据源。只有当未来需要跨平台账户、协作权限、团队排班或自有数据分析时，才考虑自建云端日历层。
4. **仅有“文字/语音/图片转日程”不足以形成差异化。**Toki 和 SmoreAI 都已公开主打这些能力。Orbit 必须把差异建立在：多条复杂输入的高保真拆分、可核对的写入预览、正确路由到用户指定日历、可撤销/可追溯修改，以及“数据仍留在用户系统日历”上。
5. **公开版不应把“让普通用户自己填 API Key”作为核心体验。**它适合内部测试和早期技术用户，但不适合验证面向普通消费者的产品。推荐路径是：TestFlight 阶段允许 BYOK；公开版默认提供少量托管 AI 额度；付费订阅/点数由 Orbit 服务端授权。App 内解锁 AI 功能必须按 Apple 的规则使用 In-App Purchase（IAP）。[^4]

## 研究范围与读取方式

本报告基于截至 2026-09-13 可访问的官方 App Store 页面、产品网站、Apple 开发者文档，以及 Orbit 当前仓库源码。以下标记用于区分证据强度：

- **已公开**：产品官网、App Store 页面或 Apple 文档明确写出。
- **当前代码**：从 Orbit 仓库现状确认；不等于已在 App Store 发布。
- **建议**：本报告的产品判断和推荐，并非竞品已实现的事实。
- “已验证的商店地区”仅表示成功访问到该地区的产品页，**不等同于完整的全球发行地区清单**；完整可售地区只有开发者在 App Store Connect 后台能确认。

## 四个产品的基本资料

| 产品 | App Store 展示主体/性质 | 公司与所在地 | 已验证的发行或可用地区 | 平台与系统门槛 | 当前商业状态 |
| --- | --- | --- | --- | --- | --- |
| Apple 日历 | Apple 原生系统 App，不是可单独购买的第三方 App Store 商品页 | Apple Inc.；美国加州 Cupertino。[^5] | 随 iOS/iPadOS/macOS 提供，不以单一第三方 App 商品页统计地区 | Apple 设备系统自带 | 免费，未见日历 App 本身的订阅/IAP |
| Toki: AI Scheduling & Tasks（原 Dola） | Orion Arm Pte. Ltd；公司主体 | App Store 与条款均写明 Orion Arm Pte. Ltd。公开企业目录将该 Pte. Ltd. 列为新加坡实体；其公开条款未给出注册地地址，因此“新加坡”标为中等置信度。[^6][^7] | 美国、英国、澳门产品页可验证；不据此声称完整全球覆盖。[^6][^8] | iPhone、iPad、Apple Watch；美国页显示 iOS/iPadOS 16.4+、watchOS 10+，也支持 Apple Silicon Mac 与 Vision。[^9] | 免费下载 + 订阅 + 可消费 Credits |
| SmoreAI | Beijing Shuangsheng Technology Co., Ltd / 北京双生科技有限公司；公司主体 | 中国北京。中国区产品页列出统一社会信用代码 91110105MAEB4G534G，隐私政策也以该公司为主体。[^10][^11] | 中国大陆、台湾产品页可验证；不据此声称完整全球覆盖。[^10][^12] | iPhone、iPad、Apple Silicon Mac、Vision；中国页显示 iOS/iPadOS 17+。[^10] | 免费下载 + Pro 月/年订阅 |
| Orbit | 尚未上架；计划以个人账号发布 | 尚无 App Store 卖家主体。若个人加入，卖家名会是你的法定姓名；若组织加入，才显示组织法定名称。[^1] | 尚无 | 当前 Xcode 项目目标为 iOS 18；仅 GitHub Actions 侧载构建流程 | 尚未售卖；目前为用户自带 API Key（BYOK）模式 |

### 对“个人注册还是公司注册”的直接回答

Apple 将个人/独资经营者与组织分开处理：个人发布时显示个人法定姓名；组织发布时显示组织法定实体名称，且组织需要 D-U-N-S Number、可公开访问且与组织关联的网站、以及可代表组织签约的人。[^1]

因此，对 Orbit 的建议是：

- **现在没有公司且想尽快验证产品：个人注册，合理。**不要因为尚无公司而停住产品测试。
- **如果你不希望真实姓名出现在公开商品页、预计 3–6 个月内就会成立公司、或一开始就要招人/融资/签商业合同：先成立公司再以组织账号上架，后续摩擦最小。**
- 不要把“Orbit”填为个人姓名的替代品；Apple 明确要求个人使用法定姓名。[^1]

## 功能对照：谁解决什么问题

“✔”表示公开材料或当前代码明确支持；“部分”表示有相近功能但路径不同；“未见公开证据/未实现”不等于产品永远没有，只表示本次可核实材料没有证明。

| 能力 | Apple 日历 | Toki | SmoreAI | Orbit 当前代码 |
| --- | --- | --- | --- | --- |
| 原生日/周/月日历界面 | ✔ | ✔ | ✔（公开更新说明含完整月视图） | **未实现**；目前是聊天流和日程卡片 |
| 手动新建、编辑、删除事件 | ✔ | ✔ | ✔ | ✔ |
| 文字自然语言转日程 | Siri 指令/建议，非聊天式批量解析 | ✔ | ✔ | ✔，需用户 API Key |
| 语音输入 | Siri 语音指令 | ✔ | ✔ | ✔，Apple Speech 转写后交 LLM |
| 图片/截图识别日程 | 未见 Apple 日历原生入口 | ✔，公开页写 screenshot/photo | ✔ | ✔，相册与相机图片交 LLM |
| 邮件内容输入 | Siri 可建议 Mail 中的事件 | ✔，公开页写 email | 未见公开证据 | 未实现 |
| 一次处理多条/复杂日程 | 以手工添加、复制为主 | ✔，公开主打 brain dump 转计划 | ✔，公开主打批量增改取消/复制 | ✔，多行输入可解析多个事件 |
| 写入 Apple 系统日历 | ✔，它本身就是系统日历 | ✔，公开称可同步 Apple/Google/Outlook | ✔，公开称与系统/Apple 日历双向同步 | ✔，EventKit 创建、更新、删除已有日历内事件 |
| 多账户/多日历 | ✔，iCloud、Google、Exchange、Yahoo、CalDAV 等 | ✔，公开称 Apple/Google/Outlook；免费最多同步 3 个，付费最多 5 个 | 已公开 Apple 系统日历同步；其他账户未确认 | ✔，列出可写系统日历，可设默认目标日历 |
| 日程路由到指定日历 | ✔，新建时选择/默认日历 | 公开材料表明多日历同步，细节未核实 | 公开材料表明分组与系统日历同步 | ✔，卡片可移动到另一个日历，也可设置未来默认日历 |
| 冲突识别与建议重排 | 交通/出发时间提醒，非 AI 重排 | ✔ | 未见公开证据 | 未实现 |
| 循环事件、习惯或持续提醒 | ✔，可重复事件/提醒 | ✔，公开称 recurring reminders | ✔，公开称持续提醒、习惯打卡 | **未实现循环规则**；当前仅单事件提醒 |
| 电话提醒 | 普通系统通知 | ✔，公开称可电话提醒 | 未见公开证据 | 未实现 |
| 待办、笔记、习惯 | 日历事件为主；提醒事项是独立 App | ✔，公开称 to-do list | ✔，任务、笔记、打卡 | 未实现独立待办/笔记模型 |
| 日程洞察、复盘、日报 | 未见原生日历分析 | 有偏好记忆、视觉日程等公开描述 | ✔，标签、每日总结、复盘为主打 | 未实现 |
| 主动触发、预约协调 | 未见 | ✔，Triggers、booking、会议协调 | 未见公开证据 | 未实现 |
| 协作、邀请、共享日历 | ✔，iCloud 共享及事件邀请 | 未见完整公开权限模型 | 未见完整公开权限模型 | 未实现 |
| 小组件、桌面/锁屏入口 | 系统日历小组件生态 | 未在本次公开资料中确认 | 未在本次公开资料中确认 | 未实现；仓库有独立快捷指令产物，但尚非 App 内完整设置流程 |
| API Key / 模型选择 | 不适用 | 对用户隐藏 | 对用户隐藏 | ✔，智谱/OpenAI/任意 OpenAI 兼容接口 |
| 账号、后端额度、订阅权益 | Apple Account/系统服务 | ✔ | ✔ | **未实现** |

Apple 日历本身已经覆盖手动事件、提醒、地图/交通出发时间、多账户、邀请、附件和共享日历；它还可从 Mail、信息和 Safari 中通过 Siri 提议事件。[^13][^14][^15] 因此，Orbit 不能把“能建日程”当作卖点。

### Toki 的实际定位

Toki 的公开描述已把自己从“AI 建日程”拓展为全栈计划助手：文本、语音、截图、图片和邮件输入；多日历汇集；一次性/循环提醒；电话提醒；待办；冲突处理；偏好记忆；Trigger 和预约协调。[^6][^16] 它更像一个主动式日程代理，而不只是 Apple 日历的输入插件。

### SmoreAI 的实际定位

SmoreAI 公开定位更偏中文生活管理：图片、语音、文字输入，批量新建/修改/取消，系统日历双向同步，持续提醒、笔记、习惯打卡、标签、每日总结与“复盘”。[^10][^12] 它的壁垒不只是识别，而是“把日程、提醒、笔记和回顾做成一个生活记录系统”。

### Orbit 当前真实位置

Orbit 目前不是 Toki 或 SmoreAI 的功能对等替代品，而是一个已经可用的 **AI 输入 + 系统日历写入原型**：

- 文字、实时语音转写、相册/相机图片；
- 智谱 GLM、OpenAI 和自定义 OpenAI 兼容服务；
- LLM 解析为结构化事件并批量创建；
- 修改时间/内容、目标日历、提醒和删除；
- 没有自己的日历视图、账户体系、服务端、额度、订阅、循环事件、日程洞察、主动代理或完整上手引导。

上述当前状态来自 [README](../README.md)、[LLMProvider.swift](../ScheduleAssistant/Sources/LLMProvider.swift)、[CalendarService.swift](../ScheduleAssistant/Sources/CalendarService.swift) 与 [ParsedEvent.swift](../ScheduleAssistant/Sources/ParsedEvent.swift)。

## 订阅、价格与权益对照

价格必须按同一商店地区看。Toki 下表为美国区公开价格，SmoreAI 为中国大陆区公开价格；它们不应按某个临时汇率直接得出“谁更便宜”。

| 产品 | 免费层 | 已公开付费层与价格 | 已公开权益边界 | 需要注意的未知项 |
| --- | --- | --- | --- | --- |
| Apple 日历 | 完整原生基础日历能力 | 无日历 App 本身的订阅/IAP | 无 AI 配额售卖 | 这是 Orbit 的免费替代基线 |
| Toki（美国区） | 最多同步 3 个日历；低频基础 AI 配额 | Plus：$3.99/月、$35.90/年；Super：$9.99/月、$83.90/年；5,000 Credits $0.99；10,000 Credits $1.59。[^9][^16] | 公开价格页描述付费层为更多 AI 能力、最多 5 个日历、偏好记忆、智能排程和冲突处理；首购用户可获 7 天试用。[^16] | Credits 与具体一次模型调用之间的换算规则未在公开页中明确；不要自行假定 |
| SmoreAI（中国大陆区） | 可免费下载，免费额度的细则未公开 | Pro 月费 ¥9.90；Pro 年费 ¥108。[^10] | 会员协议概括为 AI 增强、更高额度、更快响应、优先服务、个性化分析，实际权益以 App 内页面为准。[^17] | 公开协议未披露每月次数、图片成本或具体功能门槛 |
| Orbit（建议，尚未上线） | 15 个 Orbit 点/月；让用户可真实体验文字、语音、图片和一次小批量处理 | Plus：¥12/月或 ¥108/年；Pro：¥28/月或 ¥228/年；可选点数包 | 见下一节的点数定义和路线 | 价格上线前必须以真实模型成本、留存和试用转化验证，而非照抄竞品 |

### 建议的 Orbit 付费阶梯

先把一个模糊的“次数”定义为用户能理解、后台能控成本的 **Orbit 点**，而不是承诺“无限 AI”。例如：

| 层级 | 建议售价 | 每月点数 | 核心权益 | 目的 |
| --- | --- | ---: | --- | --- |
| Free | ¥0 | 15 | 文字/语音建日程 1 点；图片 3 点；小批量 4 点；系统日历写入和确认卡片不限次 | 让用户先感受 Orbit 与普通日历不同的“采集→确认→入库”体验 |
| Orbit Plus | ¥12/月或 ¥108/年 | 150 | 多模态、较大批量、历史偏好、日历路由模板、标准速度；首购 7 天试用 | 覆盖高频个人用户，不把基础体验拆得太碎 |
| Orbit Pro | ¥28/月或 ¥228/年 | 500 | Plus 全部权益；复杂图片/多日程批量、每周规划与复盘、优先模型队列、未来高级自动化 | 面向重度用户；只在这些真实能力做出后再售卖 |
| 点数包 | 例：50 点 ¥6；250 点 ¥22 | 不过期 | 给偶发图片/大批量用户补量 | 作为订阅的补充而不是逼迫续订 |

建议权重应以实际单位经济模型调整：纯文本/语音解析成本低，可以 1 点；图片、复杂批量、长上下文和复盘成本高，使用更多点。任何通过 IAP 售卖的可消费点数不应过期，且要有恢复/账本机制。Apple 对用 IAP 解锁 App 内数字功能、订阅和虚拟点数有明确要求。[^4]

**不要让免费层退化成 Apple 日历的残缺版。**免费层也要让用户用到图片/语音/批量和清晰的确认卡片；付费差异应是处理量、复杂度、速度、偏好和自动化深度，而不是把“能否保存一个日程”本身收费。

## Orbit 应该如何拉开差距

### 不建议作为差异点的东西

- “可以用文字建日程”：Apple 的 Siri、Toki 和 SmoreAI 都已覆盖。
- “可以语音/图片识别”：Toki 与 SmoreAI 都在公开页主打。
- “有一个漂亮日历月视图”：Apple、Toki、SmoreAI 都已有，且这是开发量很大的红海能力。
- “做一个更泛化的 AI 助理”：Toki 已在主动代理和预约协调上先行，SmoreAI 也已覆盖生活记录和复盘。

### 推荐定位：日历原生的“可信采集层”

把 Orbit 定义为：

> **把一句话、一段语音、一张截图或一堆零散事项，变成“可核对、可编辑、写入正确系统日历”的可靠日程。**

这不是“再做一个日历”，而是“让用户已有的 Apple 日历更容易被正确使用”。要成立，产品必须把以下能力做到比竞品更可信：

1. **先预览、后写入。**每个识别结果都显示标题、时间、时区、地点、提醒、目标日历和置信度；用户一次确认或单项修正，而不是 AI 静默修改真实日程。
2. **批量高保真。**课程表、会议截图、值班表、旅行行程、聊天记录中的多条事项要可拆分、标注来源、发现冲突，并支持“只导入我勾选的几条”。
3. **日历路由。**“工作”“个人”“家庭”“某个共享日历”不是仅在设置里选择一次，而是在每次复杂输入里可以明确指定和学习偏好。
4. **可撤销与可追溯。**显示“Orbit 改了什么”；一键撤销；用户在 Apple 日历中移动或删除事件后，Orbit 不应悄悄重新创建旧事件。
5. **本地优先的信任叙事。**日历仍由 EventKit/Apple 日历保存；Orbit 不另建一个锁定用户的数据孤岛。云端仅处理当次用户授权发送给模型的内容，并清楚说明保存期限与用途。

在这条路线下，最适合先验证的细分场景是**截图/照片中的复杂日程批量导入**与**中文口语中的准确时间、提醒和目标日历识别**。它们与 Orbit 当前代码能力连续，也比先做“通用生活超级 App”现实。具体人群仍要通过访谈选择，例如学生课表、轮班/值班人群、家庭照护者或会议密集的知识工作者；不要同时服务所有人。

### 自建日历的判断门槛

当前结论：**先不建。**自建日历会带来同步冲突、重复事件、离线、时区、邀请/共享、删除传播、iCloud/Google/Exchange 连接器和隐私责任，极易挤占 AI 体验的开发时间。

只有下面至少两项同时成立时再评估：

- 需要 Android/Web/Windows 跨端且用户希望 Orbit 成为唯一数据源；
- 需要团队协作、权限、排班、资源预约；
- 需要自有日历维度上的历史分析，且用户明确授权保存；
- 系统日历 API 无法满足关键工作流。

即使未来建立“Orbit 日历”，也建议创建一个可见的 `Orbit` 系统日历本并与 Apple 日历同步，而不是把用户数据困在 App 内；首次启用须明确征得同意。

## BYOK、会员和后端：推荐的实现顺序

### 结论

可以先 BYOK，但**只把它当作测试工具，不当作最终消费产品**。BYOK 会让每位普通用户都要理解模型、注册供应商、充值、复制密钥和排查报错；这会掩盖 Orbit 自身的真实留存和付费意愿。

推荐分三步：

1. **内部侧载/TestFlight：保留 BYOK。**这是最低现金成本的研发验证方式。API Key 必须放在 iOS Keychain，不应继续放在 `UserDefaults`。
2. **公开 MVP：默认托管 AI 试用额度。**用户无需 API Key；App 通过 Orbit 后端调用模型，后台按匿名安装 ID 或账户跟踪点数与滥用。用户完成首个“照片/语音→确认卡片→系统日历”的闭环后，再展示 Plus 试用。
3. **稳定后：IAP 订阅 + 点数包 + 可选高级 BYOK。**服务端验证 StoreKit 交易和订阅状态，再决定用户是否有额度。Apple 的示例也说明，订阅服务应依据验证后的交易/服务器通知判定服务权益。[^18]

BYOK 若最终保留，应是“高级用户自己的模型选择”，而非绕过 Orbit 付费功能的隐藏购买通道；产品页、付款页和 App Review 说明必须清楚区分。若用户付款来解锁 Orbit 内的 AI 能力，应走 IAP。[^4]

### 需要的最小后端边界

- 登录或匿名设备身份；
- `entitlement`：当前订阅、到期时间、已购点数；
- `usage ledger`：每次请求的点数、模型、耗时、错误、幂等请求 ID；
- 模型代理：不把 Orbit 自己的供应商 Key 放进 App；
- App Store Server Notifications 与交易验证；
- 速率限制、内容/图片大小限制和审计日志；
- 明确的隐私政策、删除入口和客服渠道。

这套后端不是“以后再补的小功能”，而是托管 AI 订阅真正能成立的最小基础设施。

## 个人账号以后变公司：两条实际路径

| 路径 | 适用情形 | 官方要求/影响 | Orbit 建议 |
| --- | --- | --- | --- |
| 个人会员更新为组织会员 | 你成立公司后，仍希望沿用同一开发者会员 | Apple 表示可提交请求；需为公司创始人/联合创始人，并提供 D-U-N-S Number 和可能的企业文件。[^2] | 优先向 Apple 支持确认是否适用于你的地区和账号；这是最省迁移工作的路径 |
| 新建组织账号后转移 App | 公司有独立 Apple Developer 组织账号，或需独立财务/团队边界 | App 必须至少有一个已在 App Store 发布的版本；双方账号状态正常并接受协议。转移可保留 Bundle ID、评分和用户更新。[^3][^19] | 可行，但在引入订阅、登录、推送、iCloud 前先做迁移规划 |

转移并非“点一下就结束”。Apple 要求转移前关闭该 App 的 TestFlight beta；接收方需要重新建立 provisioning profiles。若有自动续订订阅，要处理 app-specific shared secret；若有 Sign in with Apple、推送、Keychain sharing、iCloud 等能力，也各有迁移事项。[^3]

**最佳决策点：**如果你预计 Orbit 会在首个公开版本后很快开始收费，且公司主体已经在筹备，尽量在上线订阅和大量付费用户之前完成“转组织”决定。这样能避开订阅后迁移的复杂度。反过来，如果公司成立并不确定，就不要为了假设中的未来延迟第一轮用户测试。

## Orbit 当前的发布前风险清单

这些不是新增产品需求，而是从当前代码直接看到的上架基础项：

| 优先级 | 现状 | 为什么重要 | 建议动作 |
| --- | --- | --- | --- |
| P0 | API Key 配置会编码存入 `UserDefaults` | 用户密钥属于高敏感凭证，不应以普通偏好设置方式存储 | 迁移到 Keychain；提供删除、替换和迁移逻辑 |
| P0 | Bundle ID 仍为 `com.example.scheduleassistant`，`DEVELOPMENT_TEAM` 为空 | 无法作为正式 App Store 身份和签名配置 | 账号开通后立即换成唯一反向域名 Bundle ID，配置 Team、证书、能力 |
| P0 | 无账户、服务端、IAP、订阅验证 | 无法安全地按会员授权托管 AI 使用量 | 在公开收费前完成最小后端和 StoreKit 2 方案 |
| P1 | iOS 18 最低版本 | 覆盖面比 Toki（iOS 16.4+）和 SmoreAI（iOS 17+）窄 | 评估是否能降到 iOS 17；不要只为数字降版本，先以设备统计决定 |
| P1 | 无完整首次引导、Widget 和 App 内快捷指令配置 | 新用户不容易理解“为什么要用 Orbit” | 先做 3–4 屏引导和一个示例写入闭环；Widget/快捷指令晚于核心留存验证 |
| P1 | 公开 GitHub 仓库含侧载与构建资料 | 公开仓库本身不妨碍 App Store，但泄露密钥、证书、私钥或测试数据会造成严重问题 | secret scan、`.gitignore`、GitHub Actions secrets、隐私政策/支持页；不要提交证书、profiles、API Key |

代码定位证据：`PRODUCT_BUNDLE_IDENTIFIER = com.example.scheduleassistant` 与空 `DEVELOPMENT_TEAM` 位于 [project.pbxproj](../ScheduleAssistant.xcodeproj/project.pbxproj)；密钥持久化位于 [LLMProvider.swift](../ScheduleAssistant/Sources/LLMProvider.swift)。

## 建议的下一步顺序

1. **确定账号策略。**如果接受真实姓名显示，先注册个人 Apple Developer Program；若品牌主体必须从第一天显示，先完成公司注册和组织账号。
2. **完成发布安全底座。**正式 Bundle ID、签名、Keychain、隐私说明、权限文案、错误处理、GitHub secret scan。
3. **用 TestFlight 做封闭验证。**先找 15–30 名目标用户，重点测“识别正确率、确认率、修改率、7 天留存”，而不是先增加所有功能。
4. **用验证结果选择一个差异化场景。**例如“截图课表/值班表批量导入到指定日历”，把它做到可靠、可预览、可撤销。
5. **再建设托管 AI 与 IAP。**免费额度、Plus、Pro、点数包和服务端账本一起上线；不要先做漂亮会员页、后补额度控制。
6. **最后扩展日历界面、Widget、快捷指令和更广泛代理能力。**这些应由留存数据证明需要，而非在首版堆砌。

现有详细上架工作分解见 [APPSTORE_RELEASE_PLAN.md](../APPSTORE_RELEASE_PLAN.md)。

## 来源

[^1]: [Apple Developer Program：加入、个人/组织条件、卖家名称和年费](https://developer.apple.com/programs/enroll/)
[^2]: [Apple：更新会员信息，含个人会员更新为组织会员](https://developer.apple.com/help/account/membership/updating-your-account-information)
[^3]: [Apple：App 转移概览与迁移能力影响](https://developer.apple.com/help/app-store-connect/transfer-an-app/overview-of-app-transfer)
[^4]: [Apple App Review Guidelines 3.1.1：App 内功能/订阅/点数的 In-App Purchase 要求](https://developer.apple.com/app-store/review/guidelines/)
[^5]: [Apple 公司联系信息](https://www.apple.com/contact/)
[^6]: [Toki 美国区 App Store 产品页](https://apps.apple.com/us/app/toki-ai-scheduling-tasks/id6557056348)
[^7]: [Toki 条款：服务由 Orion Arm Pte. Ltd 运营](https://toki.com/tos)；[公开企业目录中的 Orion Arm Pte. Ltd 条目](https://www.companies.sg/cat/62011/DEVELOPMENT-OF-SOFTWARE-FOR-CYBER-SECURITY?page=310&per-page=100&sort=entity_name)
[^8]: [Toki 英国区 App Store 页面](https://apps.apple.com/gb/app/toki-ai-scheduling-tasks/id6557056348)；[Toki 澳门区 App Store 页面](https://apps.apple.com/mo/app/toki-ai-scheduling-tasks/id6557056348)
[^9]: [Toki 美国区价格、Credits、设备与系统要求](https://apps.apple.com/us/app/toki-ai-scheduling-tasks/id6557056348)
[^10]: [SmoreAI 中国大陆 App Store 产品页：价格、主体、系统要求与功能](https://apps.apple.com/cn/app/smoreai-ai%E6%97%A5%E5%8E%86-%E7%94%9F%E6%B4%BB%E5%8A%A9%E7%90%86-%E6%97%A5%E7%A8%8B%E7%AE%A1%E7%90%86-%E6%8F%90%E9%86%92%E4%BA%8B%E9%A1%B9/id6743120531)
[^11]: [SmoreAI 隐私政策](https://smoreai.com/privacy.html)
[^12]: [SmoreAI 台湾区 App Store 产品页](https://apps.apple.com/tw/app/smoreai-ai%E8%A1%8C%E4%BA%8B%E6%9B%86-%E7%94%9F%E6%B4%BB%E5%8A%A9%E7%90%86-%E6%9C%89%E6%A1%A3%E6%9C%9F-%E6%8F%90%E9%86%92%E4%BA%8B%E9%A0%85/id6743120531)
[^13]: [Apple 支持：iPhone 日历创建、编辑、删除事件与 Siri 建议](https://support.apple.com/en-ie/guide/iphone/iph3d110f84/ios)
[^14]: [Apple 支持：iPhone 日历账户、默认日历和设置](https://support.apple.com/guide/iphone/change-calendar-settings-iphc37be2016/26/ios/26)
[^15]: [Apple 支持：iCloud 日历共享](https://support.apple.com/en-au/guide/iphone/iph7613c4fb/ios)
[^16]: [Toki 官方定价与套餐说明](https://toki.com/pricing)
[^17]: [SmoreAI 会员服务协议](https://www.smoreai.com/membership.html)
[^18]: [Apple：服务端判定订阅权益](https://developer.apple.com/documentation/storekit/determining-service-entitlement-on-the-server)
[^19]: [Apple：App 转移资格条件](https://developer.apple.com/help/app-store-connect/transfer-an-app/app-transfer-criteria)
