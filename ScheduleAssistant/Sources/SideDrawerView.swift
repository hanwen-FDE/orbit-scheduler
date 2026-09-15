import SwiftUI
import EventKit

/// 左上角用户面板（侧边抽屉）
struct SideDrawerView: View {
    @EnvironmentObject private var chat: ChatStore
    @EnvironmentObject private var settings: LLMSettings
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var app = AppSettings.shared
    @ObservedObject private var account = AccountStore.shared
    @State private var briefingError = ""
    @State private var confirmLogout = false

    var body: some View {
        OrbitNavigationStack {
            List {
                accountSection
                themeSection
                defaultSettingsSection
                briefingSection
                helpAndSettingsSection
            }
            .tint(orbitAccent())
            .orbitEdgeSwipeBack { dismiss() }
            .navigationTitle("Orbit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } }
            }
            .onAppear {
                Task { await account.refreshPoints() }
            }
            .onChange(of: app.morningBriefingEnabled) { _ in synchronizeBriefingNotifications() }
            .onChange(of: app.eveningBriefingEnabled) { _ in synchronizeBriefingNotifications() }
            .onChange(of: app.morningBriefingHour) { _ in synchronizeBriefingNotifications() }
            .onChange(of: app.morningBriefingMinute) { _ in synchronizeBriefingNotifications() }
            .onChange(of: app.eveningBriefingHour) { _ in synchronizeBriefingNotifications() }
            .onChange(of: app.eveningBriefingMinute) { _ in synchronizeBriefingNotifications() }
        }
    }

    // MARK: - 我的（积分账户）

    private var accountSection: some View {
        Section {
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .orbitAuthRequired, object: nil)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(orbitAccent())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.username ?? "登录或注册")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(account.isLoggedIn ? "已登录 Orbit 账户" : "使用 Apple 账号或用户名登录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                if account.isLoggedIn {
                    Button(role: .destructive) { confirmLogout = true } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            NavigationLink(destination: PointsStoreView()) {
                HStack {
                    Label("积分余额", systemImage: "sparkles")
                        .foregroundStyle(orbitAccent())
                    Spacer()
                    if account.isFetchingPoints {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(account.points.map { "\($0) 积分" } ?? "—")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(orbitAccent())
                    }
                }
            }
            HStack {
                Label("当前模型", systemImage: "brain.head.profile")
                Spacer()
                Text(settings.activeProvider.isCloudService
                     ? (account.cloudModel.isEmpty ? "Orbit 云端模型" : account.cloudModel)
                     : settings.activeProvider.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("我的")
        }
        .alert("退出登录？", isPresented: $confirmLogout) {
            Button("退出登录", role: .destructive) {
                account.logout()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除本机的登录令牌与云端对话令牌；本地对话记录保留。")
        }
    }

    // MARK: - 主题色与 App Icon

    private var themeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("主题")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
            }
            .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 10) {
                Text("App Icon")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                logoRow
            }
            .padding(.vertical, 6)
        } header: {
            Text("主题配色")
        } footer: {
            Text("主题影响 App 内强调色；App Icon 预览展示安装到主屏幕后看到的完整图标。")
        }
    }

    /// Logo 选择只展示图标，不再额外显示容易造成误解的颜色文字。
    private var logoRow: some View {
        HStack(spacing: 17) {
            ForEach(OrbitThemePreset.allCases) { preset in
                Button { app.theme = preset } label: {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: [preset.accent, preset.accent.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 45, height: 45)
                        .overlay {
                            Ellipse().stroke(.white, lineWidth: 2.5)
                                .frame(width: 25, height: 13)
                                .rotationEffect(.degrees(-43))
                        }
                        .overlay {
                            if preset == app.theme {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                        }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 默认设置（日历与提醒 / 作息时间 / 简报推送）

    private var defaultSettingsSection: some View {
        Section {
            HStack {
                Text("默认日历")
                Spacer()
                Menu {
                    Button("未选择") { app.defaultCalendarId = nil }
                    ForEach(calendarSources, id: \.sourceIdentifier) { source in
                        Menu(source.title) {
                            ForEach(calendars(for: source), id: \.calendarIdentifier) { calendar in
                                Button {
                                    app.defaultCalendarId = calendar.calendarIdentifier
                                } label: {
                                    if app.defaultCalendarId == calendar.calendarIdentifier {
                                        Label(calendar.title, systemImage: "checkmark")
                                    } else {
                                        Text(calendar.title)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(app.defaultCalendarId.flatMap(CalendarService.shared.calendarName) ?? "未选择")
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
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

    private var calendarSources: [EKSource] {
        Dictionary(grouping: CalendarService.shared.availableCalendars(), by: { $0.source.sourceIdentifier })
            .values.compactMap { $0.first?.source }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func calendars(for source: EKSource) -> [EKCalendar] {
        CalendarService.shared.availableCalendars()
            .filter { $0.source.sourceIdentifier == source.sourceIdentifier }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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
                                Label(CalendarService.shared.calendarDisplayName(calendar), systemImage: "checkmark")
                            } else {
                                Text(CalendarService.shared.calendarDisplayName(calendar))
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
        if selectedCalendars.count == 1 { return CalendarService.shared.calendarDisplayName(selectedCalendars[0]) }
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

    // MARK: - 帮助与设置

    private var helpAndSettingsSection: some View {
        Section {
            NavigationLink(destination: UsageGuideView()) {
                drawerRow("使用说明", systemImage: "book.closed")
            }
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    NotificationCenter.default.post(name: .orbitOnboardingRequested, object: nil)
                }
            } label: {
                drawerButtonRow("使用导览", systemImage: "sparkles")
            }
            NavigationLink(destination: AppSettingsScreen()) {
                drawerRow("设置", systemImage: "gearshape")
            }

        } header: {
            Text("帮助与设置")
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
                .foregroundStyle(orbitAccent().opacity(0.6))
        }
    }

}
