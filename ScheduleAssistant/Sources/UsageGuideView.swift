import SwiftUI

/// 使用说明页面
struct UsageGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("① 输入方式", """
文字：在底部输入框直接打字，点箭头发送。

语音：点右侧麦克风开始说话，再点红色按钮结束，识别后自动发送。

图片：点左侧 ＋ 选择「照片」或「相机」，选取含日程信息的图片（课程表、会议通知等）。

批量录入：多行文字一次粘贴，每行写一项日程，例如：
9月10日 8:30 开幕式
9月10日 10:00 专题报告
9月10日 14:00 分组讨论
会逐项识别并生成卡片；核对后点“确认添加”才会写入日历。

整场会议：直接说「XX会议，9月10日 8点到18点」，会生成一项完整日程。
""")
                section("② 日程卡片", """
识别成功后先出现待确认卡片，不会直接修改系统日历：

• “确认添加”：核对无误后写入目标日历
• 点卡片：修改标题、时间、地点或重复规则
• 点卡片右上角「…」：直接编辑或删除这项日程；删除会同步删除系统日历事件
• 🔔 开关：要不要提醒
• 点橙色时长：准时 / 提前 5、15、30、60、120 分钟 / 提前 1 天
• 「更改目标日历」：把这项日程移到其他日历，也可设定今后新日程的默认日历
• 「同步到系统提醒事项」：为这项日程额外建立一条苹果“提醒事项”，需要时可一键取消同步
• 出现「时间冲突」时：Orbit 不会私自改动你的时间；你可点“采用建议”或进编辑页手动调整
""")
                section("③ 重复日程", """
说“每周三下午 3 点开组会”或在编辑页设置“重复”，会建立 Apple 日历的循环事件。Orbit 不再单独建立“习惯”模块。

删除循环日程时可选择只删当前一次，或删当前及后续。
""")
                section("④ 设置默认日历", """
点左上角头像 → 「默认日历与提醒」：

• 默认日历：新日程自动写入哪个日历（家庭、工作等）
• 默认提醒：新日程默认提前多久提醒
""")
                section("⑤ 设置 API Key", """
AI 识别需要大模型的 API Key：

1. 打开 open.bigmodel.cn 注册智谱账号
2. 控制台 → API Keys → 创建并复制
3. 回到本 App：左上角头像 → 「AI 识别（API）」→ 粘贴 Key → 点「测试连接」，显示 ✓ 即成功

也支持 OpenAI 及任意 OpenAI 兼容接口（DeepSeek、Kimi 等）：切换服务商后填写接口地址和模型名。API Key 会保存在本机 iPhone Keychain 中，不会作为普通偏好设置保存。
""")
                section("⑥ 晨间简报、Widget 与快捷指令", """
左上角头像 →「每日简报」：可设置提醒时间、天气、冲突摘要、鼓励语以及周末是否发送。简报会作为每天一条消息保存在对话中。

主屏幕长按 → 编辑 → 添加小组件 → Orbit：添加“快速记录”小组件，一点即可进入输入框。

在「快捷指令」App 中搜索 Orbit，可添加“快速记录日程”和“查看今日日程”，也能用于 Siri 和 Spotlight。
""")
                section("⑦ 今天与通知", """
底部“今天”按时间展示 Apple 日历中的当天安排；“对话”用于通过文字、语音和图片创建或修改日程。

右上角铃铛保存日程提醒、每日简报、时间冲突以及写入或 AI 处理失败信息。
""")
                section("⑧ 常见问题", """
• 换图标：左上角头像 → App 图标，6 套可选。

• 提醒不弹出：检查系统「设置 → 通知 → Orbit」是否允许通知，以及日历账户的提醒是否开启。

• 本 App 通过免费开发者签名安装，有效期 7 天；到期后用电脑 Sideloadly 重新安装一次即可（聊天记录和日程都在）。

• 日程同时存在于系统日历 App 中，可随时在系统日历查看、编辑。
""")
            }
            .padding()
        }
        .navigationTitle("使用说明")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        }
    }
}

struct OnboardingView: View {
    @ObservedObject private var app = AppSettings.shared
    @State private var page = 0
    let onComplete: () -> Void

    private let totalPages = 5

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Orbit").font(.headline)
                Spacer()
                Button("跳过") { onComplete() }
            }
            .padding()

            TabView(selection: $page) {
                onboardingPage(
                    icon: "sparkles",
                    title: "把零散安排变成可靠日程",
                    detail: "一句话、一段语音或一张图片，Orbit 会先整理成可核对的卡片；只有你确认后才写入 Apple 日历。"
                ).tag(0)

                VStack(spacing: 24) {
                    onboardingHeader(icon: "moon.stars.fill", title: "告诉 Orbit 你的作息边界", detail: "冲突重排只会在合理时间内给出建议，不会创建独立“习惯”。")
                    Stepper("通常 \(app.wakeHour):00 起床", value: $app.wakeHour, in: 4...12)
                    Stepper("通常 \(app.sleepHour):00 睡觉", value: $app.sleepHour, in: 19...24)
                }
                .padding(30).tag(1)

                VStack(spacing: 24) {
                    onboardingHeader(icon: "calendar.badge.checkmark", title: "连接 Apple 日历", detail: "需要完全访问才能展示今天的安排和识别冲突。Orbit 不会建立一份重复日历。")
                    Button("允许日历访问") {
                        Task { _ = await CalendarService.shared.ensureAccess() }
                    }
                    .buttonStyle(.borderedProminent).tint(.orange)
                }
                .padding(30).tag(2)

                onboardingPage(
                    icon: "waveform.circle.fill",
                    title: "试试语音输入",
                    detail: "例如：“明天下午三点和王医生开会，提前半小时提醒。”录音后可查看转写文字，再核对日程卡片。"
                ).tag(3)

                VStack(spacing: 24) {
                    onboardingHeader(icon: "sun.max.fill", title: "每天从简报开始", detail: "设置提醒时间后，Orbit 会汇总天气、今天的安排和时间冲突；即使没有日程也会问候你。")
                    DatePicker("简报时间", selection: briefingTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                    Toggle("显示本地天气", isOn: $app.weatherBriefingEnabled)
                }
                .padding(30).tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(page == totalPages - 1 ? "开始使用 Orbit" : "继续") {
                if page == totalPages - 1 {
                    Task {
                        _ = await MorningBriefingScheduler.enable(hour: app.morningBriefingHour, minute: app.morningBriefingMinute)
                    }
                    onComplete()
                } else {
                    withAnimation { page += 1 }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func onboardingPage(icon: String, title: String, detail: String) -> some View {
        onboardingHeader(icon: icon, title: title, detail: detail).padding(30)
    }

    private func onboardingHeader(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon).font(.system(size: 64)).foregroundStyle(.orange)
            Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(detail).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private var briefingTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: app.morningBriefingHour, minute: app.morningBriefingMinute, second: 0, of: Date()) ?? Date()
            },
            set: {
                app.morningBriefingHour = Calendar.current.component(.hour, from: $0)
                app.morningBriefingMinute = Calendar.current.component(.minute, from: $0)
            }
        )
    }
}
