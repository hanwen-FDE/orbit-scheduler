import SwiftUI
import EventKit
import UIKit

/// 使用说明页面（与新版免确认流程、三行卡片、设置入口保持一致）
struct UsageGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("① 输入方式", """
文字：在“对话”页底部输入框直接打字，点箭头发送。

语音：默认点输入卡片中间的麦克风开始说话，再点一次结束，识别后自动发送；右侧按钮可切换键盘输入。

图片：点左侧 ＋ 选择「照片」或「相机」，选取含日程信息的图片（课程表、会议通知等）。

批量录入：多行文字一次粘贴，每行写一项日程，例如：
9月10日 8:30 开幕式
9月10日 10:00 专题报告
9月10日 14:00 分组讨论
会逐项识别并直接写入日历。

整场会议：直接说「XX会议，9月10日 8点到18点」，会生成一项完整日程。
""")
                section("② 日程卡片", """
说得清楚就直接写入 Apple 日历，无需再次确认：

• 点日期：只修改日期；点时间：只修改开始/结束时间
• 点“日历”：快速切换写入的日历；点提醒时长：快速修改提醒
• 点卡片右上角三个点：打开完整编辑页，修改标题、地点或重复规则
• 长按卡片后右滑：出现红色删除（二次确认后删除）
• “同步提醒事项、移动日历”在详情编辑页底部
• 🔔 第 3 行滑动开关：要不要提醒；点亮后可点橙色时长切换“提前 15 分钟 / 1 小时 / 1 天”等
• 出现「时间重叠」提示时：Orbit 不会私自改动你的时间；可一键点“改为 XX:XX”采用建议，或进编辑页手动调整
""")
                section("③ 重复日程", """
说“每周三下午 3 点开组会”或在编辑页设置“重复”，会建立 Apple 日历的循环事件。

删除循环日程时可选择只删当前一次，或删当前及后续。
""")
                section("④ 主题配色", """
左上角 Orbit →「主题配色」可选择蓝、黄、紫、浅绿、深绿和深紫蓝黑；App 内按钮和卡片强调色会即时跟随。
""")
                section("⑤ 设置 API Key", """
AI 识别需要大模型的 API Key：

1. 左上角头像 → 设置 → AI 识别
2. 选择服务商（智谱、DeepSeek、Kimi、通义千问、OpenAI 均已预设接口地址和默认模型）
3. 粘贴 API Key → 点「测试连接」，显示 ✓ 即成功

高级用户可在同一页修改接口地址和模型名，或选“自定义（OpenAI 兼容）”。API Key 保存在本机 iPhone Keychain 中。
""")
                section("⑥ 简报设置", """
晨报、晚报均可在左上角 Orbit →「每日播报」中分别开启，并直接选择每天的推送时间。

晨报会汇总天气（可选）、今天的安排和冲突；晚报会总结今天的安排情况。
""")
                section("⑦ 通知与跳转", """
右上角铃铛保存日程提醒、每日简报、时间冲突等信息；点击通知条目可直接跳转到对应的日程卡片进行修改。

对话页左上角返回按钮可回到“今天”页，按时间轴展示 Apple 日历中的当天安排，可左右翻页查看前后几天。
""")
                section("⑧ 常见问题", """
• 提醒不弹出：检查系统「设置 → 通知 → Orbit」是否允许通知，以及日历账户的提醒是否开启。

• 本 App 通过免费开发者签名安装，有效期 7 天；到期后用电脑 Sideloadly 重新安装一次即可（聊天记录和日程都在）。

• 日程同时存在于系统日历 App 中，可随时在系统日历查看、编辑。

• 修正日程：直接说“改成下午四点”，Orbit 会更新刚才那条日程而不是新建。
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

/// 首次教学（7 页）：总介绍 → 作息 → 播报偏移 → 日历授权 → 多模态录入 → 开始使用。
struct OnboardingView: View {
    @ObservedObject private var app = AppSettings.shared
    @State private var page = 0
    @State private var calendarStatus: EKAuthorizationStatus = .notDetermined
    let onComplete: () -> Void

    private let totalPages = 7

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                OrbitBrandMark()
                Spacer()
                Button("跳过") { onComplete() }
            }
            .padding()

            TabView(selection: $page) {
                // 1. 总介绍：与 GitHub 首页保持一致的产品句。
                VStack(spacing: 18) {
                    Ellipse()
                        .stroke(
                            LinearGradient(colors: [orbitAccent(), orbitAccent().opacity(0.55)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 5
                        )
                        .frame(width: 120, height: 60)
                        .rotationEffect(.degrees(-43))
                        .offset(y: -26)
                        .padding(.bottom, 28)
                    Text("All your plans run on time orbit.")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text("所有计划，运行于时间轨道。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .italic()
                    VStack(alignment: .leading, spacing: 10) {
                        pain("安排散落在聊天、备忘录和脑子里，总是漏")
                        pain("手动一个个建日程，又慢又麻烦")
                        pain("两件事撞在同一个时间，没人提醒")
                    }
                    .padding(.horizontal, 8)
                    Text("Orbit：一句话、一段语音、一张图片，直接写进 Apple 日历。")
                        .font(.headline)
                        .foregroundStyle(orbitAccent())
                        .multilineTextAlignment(.center)
                }
                .padding(30).tag(0)

                // 2. 起床时间
                timeQuestionPage(
                    icon: "sun.horizon.fill",
                    title: "设置起床时间",
                    subtitle: "每天这个时候，Orbit 会把早报送进对话：天气 + 今日安排",
                    time: wakeTime
                ).tag(1)

                // 3. 睡觉时间
                timeQuestionPage(
                    icon: "moon.zzz.fill",
                    title: "设置睡觉时间",
                    subtitle: "睡前 Orbit 会发来晚报，告诉你今天完成了几件事",
                    time: sleepTime
                ).tag(2)

                // 4. 播报时间：在首次导览中即可直接选择每天的时间。
                VStack(spacing: 18) {
                    onboardingHeader(
                        icon: "newspaper.fill",
                        title: "播报时间微调",
                        detail: "选择晨报和晚报每天推送到 Orbit 的时间"
                    )
                    briefingTimePicker(title: "晨报", isSelected: $app.morningBriefingEnabled, time: morningBriefingDate)
                    briefingTimePicker(title: "晚报", isSelected: $app.eveningBriefingEnabled, time: eveningBriefingDate)
                }
                .padding(26).tag(3)

                // 5. 接入 Apple 日历
                VStack(spacing: 18) {
                    onboardingHeader(
                        icon: "calendar.badge.checkmark",
                        title: "接入 Apple 日历",
                        detail: "Orbit 直接读写 iPhone 自带的日历 App，不建立重复副本；授权后日程双向同步，提醒准时到达。"
                    )
                    calendarStatusRow
                }
                .padding(30).tag(4)

                // 6. 多模态录入（三合一）
                VStack(spacing: 18) {
                    onboardingHeader(
                        icon: "square.stack.3d.up.fill",
                        title: "支持文字、语音、图片多模态录入",
                        detail: "打字说一句、点按说一段、拍一张课程表——Orbit 都会识别成日程，直接写进日历。"
                    )
                    HStack(spacing: 22) {
                        modeIcon("character.cursor.ibeam", "文字")
                        modeIcon("waveform", "语音")
                        modeIcon("photo", "图片")
                    }
                }
                .padding(30).tag(5)

                // 7. 开始使用
                VStack(spacing: 18) {
                    onboardingHeader(
                        icon: "sparkles",
                        title: "准备就绪",
                        detail: "从今天页右下角的对话气泡开始，把第一件事交给 Orbit。"
                    )
                }
                .padding(30).tag(6)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(page == totalPages - 1 ? "开始使用 Orbit" : "继续") {
                if page == totalPages - 1 {
                    Task {
                        if app.morningBriefingEnabled {
                            let morning = app.morningBriefingTime
                            _ = await MorningBriefingScheduler.enable(hour: morning.hour, minute: morning.minute)
                        }
                        if app.eveningBriefingEnabled {
                            let evening = app.eveningBriefingTime
                            _ = await EveningBriefingScheduler.enable(hour: evening.hour, minute: evening.minute)
                        }
                    }
                    onComplete()
                } else {
                    withAnimation { page += 1 }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(orbitAccent())
            .controlSize(.large)
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            calendarStatus = EKEventStore.authorizationStatus(for: .event)
            selectDefaultCalendarIfNeeded()
        }
    }

    // MARK: - 组件

    private func pain(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.dotted")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func modeIcon(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(orbitAccent())
                .frame(width: 56, height: 56)
                .background(Circle().fill(orbitAccent().opacity(0.12)))
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func timeQuestionPage(icon: String, title: String, subtitle: String, time: Binding<Date>) -> some View {
        VStack(spacing: 18) {
            onboardingHeader(icon: icon, title: title, detail: subtitle)
            DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: 240)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
        }
        .padding(30)
    }

    private func briefingTimePicker(title: String, isSelected: Binding<Bool>, time: Binding<Date>) -> some View {
        HStack {
            Toggle(isOn: isSelected) {
                Text(title)
                    .font(.headline)
            }
            .tint(orbitAccent())
            Spacer()
            DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .disabled(!isSelected.wrappedValue)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.systemBackground)))
    }

    /// 日历授权状态行：未决定 → 请求；被拒 → 去系统设置；已授权 → 绿色对勾。
    @ViewBuilder
    private var calendarStatusRow: some View {
        switch calendarStatus {
        case .fullAccess, .writeOnly:
            let calendars = CalendarService.shared.availableCalendars()
            VStack(spacing: 14) {
                Label("已连接 Apple 日历", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                if !calendars.isEmpty {
                    Picker("默认写入日历", selection: $app.defaultCalendarId) {
                        ForEach(calendars, id: \.calendarIdentifier) { calendar in
                            Text(calendar.title).tag(Optional(calendar.calendarIdentifier))
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemBackground)))
                    Text("新日程默认写入这里，之后可在卡片上随时切换。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .denied, .restricted:
            VStack(spacing: 10) {
                Label("日历权限未开启", systemImage: "exclamationmark.circle")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("去系统设置开启", systemImage: "arrow.up.forward.app")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(orbitAccent())
            }
        case .notDetermined:
            Button {
                Task {
                    _ = await CalendarService.shared.ensureAccess()
                    calendarStatus = EKEventStore.authorizationStatus(for: .event)
                    selectDefaultCalendarIfNeeded()
                }
            } label: {
                Label("允许访问日历", systemImage: "calendar.badge.plus")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(orbitAccent())
        @unknown default:
            EmptyView()
        }
    }

    private func selectDefaultCalendarIfNeeded() {
        let calendars = CalendarService.shared.availableCalendars()
        guard !calendars.isEmpty else { return }
        if !calendars.contains(where: { $0.calendarIdentifier == app.defaultCalendarId }) {
            app.defaultCalendarId = calendars[0].calendarIdentifier
        }
    }

    private func onboardingHeader(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon).font(.system(size: 52)).foregroundStyle(orbitAccent())
            Text(title).font(.title.bold()).multilineTextAlignment(.center)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private var wakeTime: Binding<Date> {
        Binding(
            get: {
                var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                components.hour = app.wakeHour
                components.minute = app.wakeMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                app.wakeHour = Calendar.current.component(.hour, from: date)
                app.wakeMinute = Calendar.current.component(.minute, from: date)
            }
        )
    }

    private var sleepTime: Binding<Date> {
        Binding(
            get: {
                var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                components.hour = app.sleepHour
                components.minute = app.sleepMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                app.sleepHour = Calendar.current.component(.hour, from: date)
                app.sleepMinute = Calendar.current.component(.minute, from: date)
            }
        )
    }

    private var morningBriefingDate: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: app.morningBriefingHour,
                                         minute: app.morningBriefingMinute,
                                         second: 0,
                                         of: Date()) ?? Date()
            },
            set: { date in
                app.morningBriefingHour = Calendar.current.component(.hour, from: date)
                app.morningBriefingMinute = Calendar.current.component(.minute, from: date)
            }
        )
    }

    private var eveningBriefingDate: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: app.eveningBriefingHour,
                                         minute: app.eveningBriefingMinute,
                                         second: 0,
                                         of: Date()) ?? Date()
            },
            set: { date in
                app.eveningBriefingHour = Calendar.current.component(.hour, from: date)
                app.eveningBriefingMinute = Calendar.current.component(.minute, from: date)
            }
        )
    }
}
