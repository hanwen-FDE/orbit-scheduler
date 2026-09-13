import SwiftUI
import EventKit

/// 左上角用户面板（侧边抽屉）
struct SideDrawerView: View {
    @EnvironmentObject private var chat: ChatStore
    @EnvironmentObject private var settings: LLMSettings
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var app = AppSettings.shared
    @State private var morningStatus = ""
    @State private var eveningStatus = ""

    var body: some View {
        NavigationStack {
            List {
                themeSection
                defaultSettingsSection
                visibleCalendarsSection
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

    // MARK: - 默认设置（日历与提醒 / 作息时间 / 简报推送）

    private var defaultSettingsSection: some View {
        Section {
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
            DatePicker("通常起床", selection: wakeTime, displayedComponents: .hourAndMinute)
            DatePicker("通常睡觉", selection: sleepTime, displayedComponents: .hourAndMinute)
        } header: {
            Text("默认设置")
        } footer: {
            Text("作息决定早报与晚报的推送时间，也用于筛选合理的冲突重排建议；“读取哪些日历”控制 Orbit 展示与检查冲突的范围。")
        }
    }

    /// 读取哪些日历：空选 = 全部。
    private var visibleCalendarsSection: some View {
        Section {
            let calendars = CalendarService.shared.readableCalendars()
            if calendars.isEmpty {
                Text("未读取到日历，请检查系统日历账户")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(calendars, id: \.calendarIdentifier) { cal in
                    Toggle(cal.title, isOn: Binding(
                        get: {
                            guard let visible = app.visibleCalendarIds else { return true }
                            return visible.contains(cal.calendarIdentifier)
                        },
                        set: { on in
                            var ids = Set(app.visibleCalendarIds ?? calendars.map { $0.calendarIdentifier })
                            if on {
                                ids.insert(cal.calendarIdentifier)
                            } else {
                                ids.remove(cal.calendarIdentifier)
                            }
                            app.visibleCalendarIds = ids.isEmpty ? nil : Array(ids)
                        }
                    ))
                }
            }
        } header: {
            Text("读取哪些日历")
        } footer: {
            Text("关闭的日历不会出现在“今天”列表、简报统计和冲突检查里；全部关闭等同全部开启。")
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

    // MARK: - 每日简报

    private var briefingSection: some View {
        Section {
            Toggle("晨报", isOn: $app.morningBriefingEnabled)
            if app.morningBriefingEnabled {
                Text("起床后 \(app.morningBriefingOffsetMinutes) 分钟（\(timeText(app.morningBriefingTime))）推送到对话")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("设置晨报推送提醒") {
                    Task { morningStatus = await enableMorningNotification() }
                }
                if !morningStatus.isEmpty {
                    Text(morningStatus).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Toggle("晚报", isOn: $app.eveningBriefingEnabled)
            if app.eveningBriefingEnabled {
                Text("睡前 \(app.eveningBriefingOffsetMinutes) 分钟（\(timeText(app.eveningBriefingTime))）总结今天任务")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("设置晚报推送提醒") {
                    Task { eveningStatus = await enableEveningNotification() }
                }
                if !eveningStatus.isEmpty {
                    Text(eveningStatus).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if app.morningBriefingEnabled || app.eveningBriefingEnabled {
                Toggle("显示本地天气", isOn: $app.weatherBriefingEnabled)
                Toggle("显示冲突摘要", isOn: $app.morningBriefingShowsConflicts)
                Toggle("周末发送", isOn: $app.morningBriefingOnWeekends)
            }
        } header: {
            Text("每日播报")
        } footer: {
            Text("播报以对话卡片形式出现在对话窗口；系统通知只负责到点提醒你打开 Orbit。")
        }
    }

    private func timeText(_ time: (hour: Int, minute: Int)) -> String {
        String(format: "%02d:%02d", time.hour, time.minute)
    }

    private func enableMorningNotification() async -> String {
        let morning = app.morningBriefingTime
        return await MorningBriefingScheduler.enable(hour: morning.hour, minute: morning.minute)
    }

    private func enableEveningNotification() async -> String {
        let evening = app.eveningBriefingTime
        return await EveningBriefingScheduler.enable(hour: evening.hour, minute: evening.minute)
    }

}
