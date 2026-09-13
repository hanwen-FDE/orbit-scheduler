import SwiftUI
import EventKit

/// 左上角用户面板（侧边抽屉）
struct SideDrawerView: View {
    @EnvironmentObject private var chat: ChatStore
    @EnvironmentObject private var settings: LLMSettings
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var app = AppSettings.shared
    @State private var briefingError = ""

    var body: some View {
        NavigationStack {
            List {
                themeSection
                defaultSettingsSection
                briefingSection
                Section {
                    NavigationLink {
                        UsageGuideView()
                    } label: {
                        drawerRow("使用说明", systemImage: "book.closed")
                    }
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            app.onboardingCompleted = false
                        }
                    } label: {
                        drawerButtonRow("使用导览", systemImage: "sparkles")
                    }
                    NavigationLink {
                        AppSettingsScreen()
                    } label: {
                        drawerRow("设置", systemImage: "gearshape")
                    }
                } header: {
                    Text("帮助与设置")
                }
            }
            .orbitEdgeSwipeBack { dismiss() }
            .navigationTitle("Orbit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .onChange(of: app.morningBriefingEnabled) { _, _ in synchronizeBriefingNotifications() }
            .onChange(of: app.eveningBriefingEnabled) { _, _ in synchronizeBriefingNotifications() }
            .onChange(of: app.morningBriefingHour) { _, _ in synchronizeBriefingNotifications() }
            .onChange(of: app.morningBriefingMinute) { _, _ in synchronizeBriefingNotifications() }
            .onChange(of: app.eveningBriefingHour) { _, _ in synchronizeBriefingNotifications() }
            .onChange(of: app.eveningBriefingMinute) { _, _ in synchronizeBriefingNotifications() }
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
        Group {
            Section {
                briefingTimeRow(title: "晨报", enabled: $app.morningBriefingEnabled, time: morningBriefingDate)
                briefingTimeRow(title: "晚报", enabled: $app.eveningBriefingEnabled, time: eveningBriefingDate)
                if !briefingError.isEmpty {
                    Text(briefingError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("每日播报")
            } footer: {
                Text("播报以对话卡片形式出现；系统通知只在设定时间提醒你打开 Orbit。")
            }

            Section("播报内容") {
                Toggle("显示本地天气", isOn: $app.weatherBriefingEnabled)
                Toggle("显示冲突摘要", isOn: $app.morningBriefingShowsConflicts)
                Toggle("周末发送", isOn: $app.morningBriefingOnWeekends)
            }
        }
    }

    private func briefingTimeRow(title: String, enabled: Binding<Bool>, time: Binding<Date>) -> some View {
        HStack {
            Toggle(title, isOn: enabled)
            Spacer()
            DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .disabled(!enabled.wrappedValue)
        }
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

    private func synchronizeBriefingNotifications() {
        Task {
            if app.morningBriefingEnabled {
                let time = app.morningBriefingTime
                let result = await MorningBriefingScheduler.enable(hour: time.hour, minute: time.minute)
                briefingError = result.hasPrefix("已设置") ? "" : result
            } else {
                MorningBriefingScheduler.disable()
            }
            if app.eveningBriefingEnabled {
                let time = app.eveningBriefingTime
                let result = await EveningBriefingScheduler.enable(hour: time.hour, minute: time.minute)
                if !result.hasPrefix("已设置") { briefingError = result }
            } else {
                EveningBriefingScheduler.disable()
            }
        }
    }

    private func drawerRow(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .foregroundStyle(orbitAccent())
                .frame(width: 20)
            Text(title)
                .foregroundStyle(.primary)
        }
    }

    private func drawerButtonRow(_ title: String, systemImage: String) -> some View {
        HStack {
            drawerRow(title, systemImage: systemImage)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
    }

}
