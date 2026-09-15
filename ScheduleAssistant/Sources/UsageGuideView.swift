import SwiftUI
import EventKit
import UIKit

/// 使用说明页面（与新版免确认流程、三行卡片、设置入口保持一致）
struct UsageGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("用一种你习惯的方式，把安排送上轨道。点开卡片查看示例。")
                    .font(.subheadline).foregroundStyle(.secondary)
                guideCard("用一句话创建日程", icon: "text.bubble", summary: "直接输入：明天下午四点开课题会", detail: "Orbit 会识别时间、标题和地点并生成日程卡片；信息明确时会写入你选择的 Apple 日历。")
                guideCard("用语音安排事情", icon: "waveform", summary: "点麦克风，说完再点一次", detail: "语音会先转成文字，再走与文字输入相同的识别流程。右侧按钮可随时切回键盘。")
                guideCard("拍张图识别日程", icon: "camera", summary: "支持课程表、会议通知和排班表", detail: "点输入框左侧＋，选择照片或相机。发送前请确认图片没有无关的敏感信息。")
                guideCard("修改刚才的日程", icon: "slider.horizontal.3", summary: "说“改成下午四点”或直接点卡片", detail: "日期、时间、日历和提醒可以就地修改；右上角菜单可编辑标题、地点和重复规则。")
                guideCard("处理时间冲突", icon: "exclamationmark.triangle", summary: "Orbit 提示冲突，但不会擅自挪动", detail: "你可以采用建议空档，也可以打开卡片手动调整。")
                guideCard("设置晨报与晚报", icon: "sun.and.horizon", summary: "在左上角 Orbit → 每日播报", detail: "晨报结合当天安排、冲突和可用天气；晚报做简短回顾。天气不可用时会自然省略。")
                guideCard("从通知找到对应日程", icon: "bell", summary: "点击通知即可定位", detail: "Orbit 会滚动到对应消息或卡片，并用当前主题色短暂高亮目标。")
                guideCard("账号、积分与 Orbit Pro", icon: "person.crop.circle", summary: "云端 AI 用积分，Pro 解锁自定义模型", detail: "Sign in with Apple 是主要登录方式。Orbit Pro 是永久买断，但继续使用 Orbit 云端 AI 仍会消耗积分。")
            }
            .padding()
        }
        .navigationTitle("使用说明")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func guideCard(_ title: String, icon: String, summary: String, detail: String) -> some View {
        DisclosureGroup {
            Text(detail).font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 28).foregroundStyle(orbitAccent())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
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
                    .foregroundStyle(orbitAccent())
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
        if calendarStatus.orbitCanWriteEvents {
            let calendars = CalendarService.shared.availableCalendars()
            VStack(spacing: 14) {
                Label("已连接 Apple 日历", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                if !calendars.isEmpty {
                    Picker("默认写入日历", selection: $app.defaultCalendarId) {
                        ForEach(calendars, id: \.calendarIdentifier) { calendar in
                            Text(CalendarService.shared.calendarDisplayName(calendar)).tag(Optional(calendar.calendarIdentifier))
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
        } else if calendarStatus == .denied || calendarStatus == .restricted {
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
        } else {
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
