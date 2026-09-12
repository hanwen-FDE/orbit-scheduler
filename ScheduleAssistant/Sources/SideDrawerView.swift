import SwiftUI
import EventKit

/// 左上角用户面板（侧边抽屉）
struct SideDrawerView: View {
    @EnvironmentObject private var chat: ChatStore
    @EnvironmentObject private var settings: LLMSettings
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var app = AppSettings.shared
    @State private var morningReminderStatus = ""
    @State private var showDeleteConversationConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                iconSection
                apiSection
                calendarSection
                schedulePreferenceSection
                morningBriefingSection
                shortcutSection
                Section {
                    NavigationLink("使用教程") { UsageGuideView() }
                    Button("重新观看首次教学") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            app.onboardingCompleted = false
                        }
                    }
                }
                Section {
                    Button("删除当前对话", role: .destructive) {
                        showDeleteConversationConfirmation = true
                    }
                }
            }
            .navigationTitle("Orbit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .confirmationDialog("删除当前对话？", isPresented: $showDeleteConversationConfirmation, titleVisibility: .visible) {
            Button("删除对话", role: .destructive) { chat.clearConversation() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除 Orbit 对话记录，不会删除已经写入 Apple 日历的日程。")
        }
    }

    private var schedulePreferenceSection: some View {
        Section {
            Stepper("通常 \(app.wakeHour):00 起床", value: $app.wakeHour, in: 4...12)
            Stepper("通常 \(app.sleepHour):00 睡觉", value: $app.sleepHour, in: 19...24)
        } header: {
            Text("智能排程边界")
        } footer: {
            Text("只用于筛选合理的冲突重排建议，不会自动创建“习惯”或作息日程。")
        }
    }

    // MARK: - 图标

    private var iconSection: some View {
        Section("App 图标") {
            let icons = IconService.allIcons
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                ForEach(icons, id: \.name) { icon in
                    Button {
                        IconService.apply(icon.name)
                        app.alternateIcon = icon.name
                    } label: {
                        VStack(spacing: 6) {
                            IconService.previewImage(named: icon.name)
                                .resizable()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            Text(icon.title)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                            if app.alternateIcon == icon.name {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - API

    private var apiSection: some View {
        Section {
            Picker("识别服务商", selection: $settings.activeProviderId) {
                ForEach(settings.providers, id: \.id) { p in
                    Text(p.name).tag(p.id)
                }
            }
            if let active = settings.providers.first(where: { $0.id == settings.activeProviderId }) {
                ProviderConfigView(provider: active)
            }
        } header: {
            Text("AI 识别（API）")
        } footer: {
            Text("智谱 API Key 在 open.bigmodel.cn 申请。")
        }
    }

    // MARK: - 默认日历与提醒

    private var calendarSection: some View {
        Section("默认日历与提醒") {
            Picker("默认日历", selection: $app.defaultCalendarId) {
                Text("未选择").tag(Optional<String>.none)
                ForEach(CalendarService.shared.availableCalendars(), id: \.calendarIdentifier) { cal in
                    Text(cal.title).tag(Optional(cal.calendarIdentifier))
                }
            }
            Picker("默认提醒", selection: $app.defaultReminderMinutes) {
                ForEach(ReminderOption.allCases) { option in
                    Text(option.label).tag(option.minutes ?? 0)
                }
            }
        }
    }

    // MARK: - 晨间简报

    private var morningBriefingSection: some View {
        Section {
            Toggle("打开 App 时显示简报", isOn: Binding(
                get: { app.morningBriefingEnabled },
                set: { enabled in
                    app.morningBriefingEnabled = enabled
                    if !enabled { MorningBriefingScheduler.disable() }
                }
            ))
            if app.morningBriefingEnabled {
                Toggle("简报显示本地天气", isOn: $app.weatherBriefingEnabled)
                Toggle("显示冲突摘要", isOn: $app.morningBriefingShowsConflicts)
                Toggle("显示鼓励语", isOn: $app.morningBriefingShowsEncouragement)
                Toggle("周末发送", isOn: $app.morningBriefingOnWeekends)
                DatePicker("每日提醒时间", selection: morningTime, displayedComponents: .hourAndMinute)
                Button("设置每天晨间提醒") {
                    Task {
                        morningReminderStatus = await MorningBriefingScheduler.enable(
                            hour: app.morningBriefingHour,
                            minute: app.morningBriefingMinute
                        )
                    }
                }
                Button("关闭每天晨间提醒", role: .destructive) {
                    MorningBriefingScheduler.disable()
                    morningReminderStatus = "已关闭每天晨间提醒。"
                }
                if !morningReminderStatus.isEmpty {
                    Text(morningReminderStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("晨间简报")
        } footer: {
            Text("通知只会提醒你打开 Orbit；打开后才会读取最新的日程和你主动允许的本地天气。WeatherKit 需要正式开发者账号启用，侧载期天气不可用时日程简报仍会正常显示。")
        }
    }

    // MARK: - 系统快捷入口

    private var shortcutSection: some View {
        Section("小组件与快捷指令") {
            Label("添加 Orbit 小组件", systemImage: "rectangle.on.rectangle")
            Text("在主屏幕长按 → 编辑 → 添加小组件 → 选择 Orbit，即可一键进入快速记录。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let shortcutsURL = URL(string: "shortcuts://") {
                Link(destination: shortcutsURL) {
                    Label("打开“快捷指令”App", systemImage: "square.and.arrow.up")
                }
            }
            Text("可添加“快速记录日程”和“查看今日日程”；系统也会将它们用于 Siri 和 Spotlight。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var morningTime: Binding<Date> {
        Binding(
            get: {
                var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                components.hour = app.morningBriefingHour
                components.minute = app.morningBriefingMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                app.morningBriefingHour = Calendar.current.component(.hour, from: date)
                app.morningBriefingMinute = Calendar.current.component(.minute, from: date)
            }
        )
    }
}

