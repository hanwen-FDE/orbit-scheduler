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
            .orbitEdgeSwipeBack { dismiss() }
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
            readCalendarsRow
        } header: {
            Text("默认设置")
        } footer: {
            Text("默认日历决定新日程写到哪里；日历读取决定“今天”、简报和冲突检查读取哪些日历。默认写入日历会始终包含在读取范围内。")
        }
    }

    /// 默认设置中的第 5 行：用一个下拉菜单完成多日历读取范围选择。
    @ViewBuilder
    private var readCalendarsRow: some View {
        let calendars = CalendarService.shared.readableCalendars()
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        HStack {
            Text("日历读取")
            Spacer()
            if calendars.isEmpty {
                Text("未读取到日历")
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    Button {
                        app.visibleCalendarIds = nil
                    } label: {
                        if app.visibleCalendarIds == nil {
                            Label("全部日历", systemImage: "checkmark")
                        } else {
                            Text("全部日历")
                        }
                    }
                    Divider()
                    ForEach(calendars, id: \.calendarIdentifier) { calendar in
                        Button {
                            toggleReadableCalendar(calendar.calendarIdentifier, calendars: calendars)
                        } label: {
                            if isCalendarReadable(calendar.calendarIdentifier) {
                                Label(calendar.title, systemImage: "checkmark")
                            } else {
                                Text(calendar.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(readCalendarSummary(calendars))
                            .foregroundStyle(orbitAccent())
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func isCalendarReadable(_ identifier: String) -> Bool {
        app.visibleCalendarIds?.contains(identifier) ?? true
    }

    private func readCalendarSummary(_ calendars: [EKCalendar]) -> String {
        guard let selected = app.visibleCalendarIds else { return "全部" }
        let selectedCalendars = calendars.filter { selected.contains($0.calendarIdentifier) }
        if selectedCalendars.count == 1 { return selectedCalendars[0].title }
        return "\(selectedCalendars.count) 个日历"
    }

    private func toggleReadableCalendar(_ identifier: String, calendars: [EKCalendar]) {
        let allIds = calendars.map(\.calendarIdentifier)
        var selected = Set(app.visibleCalendarIds ?? allIds)
        if selected.contains(identifier) {
            // 默认写入日历必须参与读取；也至少保留一个读取日历。
            guard identifier != app.defaultCalendarId, selected.count > 1 else { return }
            selected.remove(identifier)
        } else {
            selected.insert(identifier)
        }
        let includesAll = Set(allIds).isSubset(of: selected)
        app.visibleCalendarIds = includesAll ? nil : Array(selected).sorted()
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
            // 这三项是晨报/晚报共用偏好，不属于任一播报的折叠内容。
            Toggle("显示本地天气", isOn: $app.weatherBriefingEnabled)
            Toggle("显示冲突摘要", isOn: $app.morningBriefingShowsConflicts)
            Toggle("周末发送", isOn: $app.morningBriefingOnWeekends)
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
