import SwiftUI
import EventKit

/// 左上角用户面板（侧边抽屉）
struct SideDrawerView: View {
    @EnvironmentObject private var chat: ChatStore
    @EnvironmentObject private var settings: LLMSettings
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var app = AppSettings.shared
    @State private var briefingReminderStatus = ""
    @State private var showDeleteConversationConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                themeSection
                calendarSection
                schedulePreferenceSection
                briefingSection
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
                Section {
                    NavigationLink {
                        AppSettingsScreen()
                    } label: {
                        Label("设置", systemImage: "gearshape")
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
            DatePicker("通常起床", selection: wakeTime, displayedComponents: .hourAndMinute)
            DatePicker("通常睡觉", selection: sleepTime, displayedComponents: .hourAndMinute)
        } header: {
            Text("作息时间")
        } footer: {
            Text("作息决定早报（起床后 30 分钟）与晚报（睡前 30 分钟）的推送时间，也用于筛选合理的冲突重排建议；不会自动创建“习惯”或作息日程。")
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

    // MARK: - 主题色

    private var themeSection: some View {
        Section {
            HStack(spacing: 18) {
                ForEach(OrbitThemePreset.allCases) { preset in
                    Button {
                        app.theme = preset
                    } label: {
                        Circle()
                            .fill(preset.accent)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if app.theme == preset {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        } header: {
            Text("主题配色")
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

    // MARK: - 每日简报

    private var briefingSection: some View {
        Section {
            Toggle("晨间早报", isOn: $app.morningBriefingEnabled)
            if app.morningBriefingEnabled {
                Text("起床后 30 分钟（\(timeText(app.morningBriefingTime))）推送到对话窗口")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Toggle("每日晚报", isOn: $app.eveningBriefingEnabled)
            if app.eveningBriefingEnabled {
                Text("睡前 30 分钟（\(timeText(app.eveningBriefingTime))）总结今天的任务数")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if app.morningBriefingEnabled || app.eveningBriefingEnabled {
                Toggle("简报显示本地天气", isOn: $app.weatherBriefingEnabled)
                Toggle("显示冲突摘要", isOn: $app.morningBriefingShowsConflicts)
                Toggle("显示鼓励语", isOn: $app.morningBriefingShowsEncouragement)
                Toggle("周末发送", isOn: $app.morningBriefingOnWeekends)
                Button("设置每日推送提醒") {
                    Task { briefingReminderStatus = await enableDailyNotifications() }
                }
                if !briefingReminderStatus.isEmpty {
                    Text(briefingReminderStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("每日简报")
        } footer: {
            Text("简报以对话卡片形式出现在对话窗口；系统通知只负责提醒你打开 Orbit。")
        }
    }

    private func timeText(_ time: (hour: Int, minute: Int)) -> String {
        String(format: "%02d:%02d", time.hour, time.minute)
    }

    private func enableDailyNotifications() async -> String {
        let morning = app.morningBriefingTime
        let evening = app.eveningBriefingTime
        let morningResult = await MorningBriefingScheduler.enable(
            hour: morning.hour, minute: morning.minute)
        let eveningResult = await EveningBriefingScheduler.enable(
            hour: evening.hour, minute: evening.minute)
        return morningResult + "\n" + eveningResult
    }

    private func timeText(_ time: (hour: Int, minute: Int)) -> String {
        String(format: "%02d:%02d", time.hour, time.minute)
    }

    private func enableDailyNotifications() async -> String {
        let morning = app.morningBriefingTime
        let evening = app.eveningBriefingTime
        let morningResult = await MorningBriefingScheduler.enable(
            hour: morning.hour, minute: morning.minute)
        let eveningResult = await EveningBriefingScheduler.enable(
            hour: evening.hour, minute: evening.minute)
        return morningResult + "\n" + eveningResult
    }
}
