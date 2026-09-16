import SwiftUI
import EventKit

extension EKEvent: Identifiable {}

@MainActor
final class OrbitNotificationStore: ObservableObject {
    static let shared = OrbitNotificationStore()
    @Published private(set) var items: [OrbitNotificationItem] = []
    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("orbit-notifications.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([OrbitNotificationItem].self, from: data) {
            items = saved
        }
        // iCloud 同步拉到较新的数据后热加载通知记录。
        NotificationCenter.default.addObserver(
            forName: .orbitSyncDidPull, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadFromDisk() }
        }
    }

    /// 供 iCloud 同步后从磁盘重新读取。
    func reloadFromDisk() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([OrbitNotificationItem].self, from: data) {
            items = saved
        }
    }

    var unreadCount: Int { items.filter { !$0.isRead }.count }

    func add(kind: OrbitNotificationKind, title: String, detail: String, relatedMessageId: UUID? = nil, dailyKey: String? = nil) {
        if let dailyKey,
           let index = items.firstIndex(where: { $0.detail.contains(dailyKey) && $0.kind == kind }) {
            items[index].title = title
            items[index].detail = detail
            items[index].createdAt = Date()
        } else {
            items.insert(OrbitNotificationItem(kind: kind, title: title, detail: detail, relatedMessageId: relatedMessageId), at: 0)
        }
        persist()
    }

    func markRead(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isRead = true
        persist()
    }

    func markAllRead() {
        for index in items.indices { items[index].isRead = true }
        persist()
    }

    func delete(ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

struct NotificationBellButton: View {
    @ObservedObject private var notifications = OrbitNotificationStore.shared
    @ObservedObject private var app = AppSettings.shared
    @Binding var isPresented: Bool

    var body: some View {
        Button { isPresented = true } label: {
            // 只使用一个 SF Symbol。此前 badge/offset 与 bell 的多层叠加会在
            // 小尺寸按钮上形成白色缺口和右上角残影。
            Image(systemName: notifications.unreadCount == 0 ? "bell" : "bell.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(orbitAccent())
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("通知中心，\(notifications.unreadCount) 条未读")
    }
}

struct OrbitNotificationCenterView: View {
    @ObservedObject private var store = OrbitNotificationStore.shared
    @EnvironmentObject private var chat: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        OrbitNavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    groupEntry(title: "通知",
                               showsBriefings: false,
                               items: store.items.filter { $0.kind != .briefing },
                               emptyHint: "暂无通知记录")
                    groupEntry(title: "简报",
                               showsBriefings: true,
                               items: store.items.filter { $0.kind == .briefing },
                               emptyHint: "还没有简报")
                }
                .padding(18)
            }
            .orbitEdgeSwipeBack { dismiss() }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("消息")
            .navigationBarTitleDisplayMode(.inline)
            .tint(orbitAccent())
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if store.unreadCount > 0 { Button("全部已读") { store.markAllRead() } }
                }
            }
        }
    }

    /// 分组入口：大标题 + 最近一条预览；点进子页看该类全部记录。
    private func groupEntry(
        title: String,
        showsBriefings: Bool,
        items: [OrbitNotificationItem],
        emptyHint: String
    ) -> some View {
        NavigationLink(destination: NotificationGroupListView(
            title: title,
            showsBriefings: showsBriefings,
            onOpenMessage: { messageId in
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    chat.pendingFocusMessageId = messageId
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.bold())
                        .foregroundStyle(orbitAccent().opacity(0.6))
                }
                if let latest = items.first {
                    Text(latest.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if !latest.isRead { Circle().fill(orbitAccent()).frame(width: 7, height: 7) }
                        Text(latest.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if items.count > 1 {
                            Text("共 \(items.count) 条")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    Text(emptyHint)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 某一类的全部记录（按时间逆序，最新在前）。
struct NotificationGroupListView: View {
    @ObservedObject private var store = OrbitNotificationStore.shared

    let title: String
    let showsBriefings: Bool
    let onOpenMessage: (UUID) -> Void

    private var items: [OrbitNotificationItem] {
        store.items.filter { showsBriefings ? $0.kind == .briefing : $0.kind != .briefing }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                OrbitUnavailableView(title: "暂无记录", systemImage: "tray", description: "新的内容出现后会在这里逐条显示。")
            } else {
                List {
                    ForEach(items) { item in
                        Button {
                            store.markRead(item.id)
                            if let messageId = item.relatedMessageId {
                                onOpenMessage(messageId)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.kind.icon)
                                    .foregroundStyle(color(for: item.kind))
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(item.title).font(.headline)
                                        if !item.isRead { Circle().fill(orbitAccent()).frame(width: 7, height: 7) }
                                    }
                                    Text(item.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let ids = Set(offsets.compactMap { index in
                            items.indices.contains(index) ? items[index].id : nil
                        })
                        store.delete(ids: ids)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(orbitAccent())
    }

    private func color(for kind: OrbitNotificationKind) -> Color {
        switch kind {
        case .briefing, .reminder: return orbitAccent()
        case .conflict, .writeFailure, .aiFailure: return .red
        }
    }
}

/// 两个主页面之一：直接读取 Apple 日历中的当天安排。
struct TodayScheduleView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var chat: ChatStore
    var onOpenChat: () -> Void = {}
    @State private var breathe = false
    @State private var selectedDay = Date()
    @State private var events: [EKEvent] = []
    @State private var showNotifications = false
    @State private var showDrawer = false
    @State private var eventToDelete: EKEvent?
    @State private var deleteErrorText: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            OrbitNavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    daySelector
                    if events.isEmpty {
                        OrbitUnavailableView(
                            title: "今天暂无安排",
                            systemImage: "calendar.badge.plus",
                            description: "切换到“对话”，告诉 Orbit 你想安排什么。"
                        )
                        .padding(.top, 80)
                    } else {
                        LazyVStack(spacing: 0) {
                            if shouldShowWakeAnchor {
                                wakeAnchor
                            }
                            ForEach(events, id: \.eventIdentifier) { event in
                                SwipeActionCard(onDelete: {
                                    eventToDelete = event
                                }) {
                                    Button {
                                        openEventInChat(event)
                                    } label: {
                                        timelineRow(event)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showDrawer = true } label: {
                        OrbitBrandMark()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NotificationBellButton(isPresented: $showNotifications)
                }
            }
        }
            .confirmationDialog("删除这个日程？", isPresented: Binding(
                get: { eventToDelete != nil },
                set: { if !$0 { eventToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("删除日程", role: .destructive) {
                    if let event = eventToDelete {
                        if case .failure(let error) = CalendarService.shared.deleteEvent(snapshot: Self.snapshot(of: event)) {
                            // 只读日历、账户异常等情况下删除会失败，必须如实告知。
                            deleteErrorText = error.localizedDescription
                            OrbitNotificationStore.shared.add(
                                kind: .writeFailure,
                                title: "日历删除失败",
                                detail: "《\(event.title ?? "未命名日程")》删除失败：\(error.localizedDescription)"
                            )
                        }
                        Task { await refresh() }
                    }
                    eventToDelete = nil
                }
                Button("取消", role: .cancel) { eventToDelete = nil }
            } message: {
                Text("它会同时从系统日历中删除。")
            }
            .alert("删除失败", isPresented: Binding(
                get: { deleteErrorText != nil },
                set: { if !$0 { deleteErrorText = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(deleteErrorText ?? "")
            }
            .sheet(isPresented: $showNotifications) { OrbitNotificationCenterView() }
            .sheet(isPresented: $showDrawer) { SideDrawerView() }
            .task { await refresh() }
            .onChange(of: selectedDay) { _ in Task { await refresh() } }
            .onChange(of: scenePhase) { phase in if phase == .active { Task { await refresh() } } }
            chatBubble
        }
    }

    /// 右下角悬浮呼吸泡：点击进入对话页。
    private var chatBubble: some View {
        Button(action: onOpenChat) {
            Image(systemName: "message.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(orbitAccent()))
                .shadow(color: orbitAccent().opacity(0.35), radius: 10, y: 5)
        }
        .scaleEffect(breathe ? 1.06 : 1.0)
        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: breathe)
        .padding(.trailing, 26)
        .padding(.bottom, 30)
        .accessibilityLabel("打开对话")
        .onAppear { breathe = true }
    }

    /// 日期严格居中，前一天/后一天按钮分列左右两侧。
    private var daySelector: some View {
        ZStack {
            Button {
                selectedDay = Date()
            } label: {
                VStack(spacing: 3) {
                    Text(dayHeaderTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color(.label).opacity(0.82))
                    Text(dayNumericTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("回到今天")

            HStack {
                dayShiftButton(systemImage: "chevron.left", delta: -1)
                Spacer()
                dayShiftButton(systemImage: "chevron.right", delta: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
    }

    private func dayShiftButton(systemImage: String, delta: Int) -> some View {
        Button { shiftDay(delta) } label: {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }

    private func shiftDay(_ delta: Int) {
        selectedDay = Calendar.current.date(byAdding: .day, value: delta, to: selectedDay) ?? selectedDay
    }

    private var dayHeaderTitle: String {
        let calendar = Calendar.current
        let weekday = selectedDay.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN")))
        if calendar.isDateInToday(selectedDay) { return "今天 · \(weekday)" }
        if calendar.isDateInTomorrow(selectedDay) { return "明天 · \(weekday)" }
        if calendar.isDateInYesterday(selectedDay) { return "昨天 · \(weekday)" }
        return weekday
    }

    private var dayNumericTitle: String {
        selectedDay.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).locale(Locale(identifier: "zh_CN")))
    }

    private var shouldShowWakeAnchor: Bool {
        guard let firstTimed = events.first(where: { !$0.isAllDay }) else { return false }
        let wake = Calendar.current.date(bySettingHour: AppSettings.shared.wakeHour,
                                         minute: AppSettings.shared.wakeMinute,
                                         second: 0,
                                         of: selectedDay) ?? selectedDay
        return firstTimed.startDate > wake
    }

    /// 若当天首项日程晚于起床时间，时间轴以起床作为可见起点；有更早日程时则直接从首项开始。
    private var wakeAnchor: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(String(format: "%02d:%02d", AppSettings.shared.wakeHour, AppSettings.shared.wakeMinute))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
            timelineAxisNode(isAnchor: true)
            HStack(spacing: 8) {
                Image(systemName: "sun.horizon")
                    .foregroundStyle(orbitAccent().opacity(0.78))
                Text("起床")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.leading, 10)
            Spacer(minLength: 0)
        }
    }

    private func timelineRow(_ event: EKEvent) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(event.isAllDay ? "全天" : event.startDate.shortTime)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
                .padding(.top, 17)
            timelineAxisNode(isAnchor: false)
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(orbitAccent().opacity(0.34))
                    .frame(width: 11, height: 1)
                    .padding(.top, 23)
                Text(emoji(for: event.title ?? ""))
                    .font(.title3)
                    .frame(width: 30, alignment: .leading)
                    .padding(.top, 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.isAllDay ? "全天" : "\(event.startDate.shortTime)–\(event.endDate.shortTime)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(.label).opacity(0.82))
                    Text(event.title ?? "未命名日程")
                        .font(.headline)
                        .lineLimit(2)
                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 14)
        }
    }

    private func timelineAxisNode(isAnchor: Bool) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color(.separator).opacity(0.40))
                .frame(width: 1)
            Circle()
                .fill(isAnchor ? orbitAccent().opacity(0.45) : orbitAccent())
                .frame(width: isAnchor ? 9 : 11, height: isAnchor ? 9 : 11)
                .padding(.top, isAnchor ? 14 : 18)
        }
        .frame(width: 28)
        .frame(maxHeight: .infinity)
    }

    private func refresh() async {
        _ = await CalendarService.shared.ensureAccess()
        events = CalendarService.shared.events(on: selectedDay)
    }

    private func openEventInChat(_ event: EKEvent) {
        let messageId = chat.ensureEventCard(for: Self.snapshot(of: event))
        chat.pendingFocusMessageId = messageId
        onOpenChat()
    }

    private func emoji(for title: String) -> String {
        Self.eventEmoji(for: title)
    }

    private static func eventEmoji(for title: String) -> String {
        let value = title.lowercased()
        if value.contains("饭") || value.contains("餐") { return "🍽️" }
        if value.contains("会") { return "💬" }
        if value.contains("运动") || value.contains("锻炼") { return "💪" }
        if value.contains("工作") || value.contains("上班") { return "💼" }
        if value.contains("睡") || value.contains("起床") { return "⏰" }
        return "📅"
    }
}

extension TodayScheduleView {
    /// 把系统日历事件包成快照，供删除/编辑复用 ChatStore 之外的日历服务。
    static func snapshot(of event: EKEvent) -> EventSnapshot {
        EventSnapshot(
            title: event.title ?? "未命名日程",
            emoji: eventEmoji(for: event.title ?? ""),
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            reminderMinutes: event.alarms?.first.map { Int(-$0.relativeOffset / 60) },
            alarmOffsets: event.alarms?.map(\.relativeOffset),
            calendarIdentifier: event.calendar.calendarIdentifier,
            calendarTitle: CalendarService.shared.calendarDisplayName(event.calendar),
            eventIdentifier: event.eventIdentifier,
            recurrence: CalendarService.shared.recurrenceSpec(for: event)
        )
    }
}

/// “今天”页的轻量编辑：不依赖聊天卡片，直接改系统日历。
struct EKEventEditor: View {
    @Environment(\.dismiss) private var dismiss

    let event: EKEvent
    var onDone: () -> Void

    @State private var title: String
    @State private var location: String
    @State private var start: Date
    @State private var end: Date
    @State private var saveErrorText: String?
    @State private var showRecurrenceSpanOptions = false

    init(event: EKEvent, onDone: @escaping () -> Void) {
        self.event = event
        self.onDone = onDone
        _title = State(initialValue: event.title ?? "")
        _location = State(initialValue: event.location ?? "")
        _start = State(initialValue: event.startDate)
        _end = State(initialValue: max(event.endDate, event.startDate))
    }

    var body: some View {
        OrbitNavigationStack {
            Form {
                Section("日程") {
                    TextField("标题", text: $title)
                    TextField("地点（可选）", text: $location)
                }
                Section("时间") {
                    DatePicker("开始", selection: $start)
                    DatePicker("结束", selection: $end, in: start...)
                }
                Section {
                    Button("保存修改") { save() }
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
            }
            .navigationTitle("编辑日程")
            .navigationBarTitleDisplayMode(.inline)
            .tint(orbitAccent())
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } }
            }
        }
        .orbitEdgeSwipeBack { dismiss() }
        .confirmationDialog("这是一个循环日程", isPresented: $showRecurrenceSpanOptions, titleVisibility: .visible) {
            Button("只改这一次") { applyEdits(span: .thisEvent) }
            Button("改这一次及后续") { applyEdits(span: .futureEvents) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择修改影响的范围，避免误改整个系列。")
        }
        .alert("保存失败", isPresented: Binding(
            get: { saveErrorText != nil },
            set: { if !$0 { saveErrorText = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(saveErrorText ?? "")
        }
    }

    private func save() {
        // 循环日程必须先问影响范围；单次日程直接保存。
        if event.hasRecurrenceRules {
            showRecurrenceSpanOptions = true
        } else {
            applyEdits(span: nil)
        }
    }

    private func applyEdits(span: EKSpan?) {
        var snap = TodayScheduleView.snapshot(of: event)
        snap.title = title.trimmingCharacters(in: .whitespaces)
        snap.location = location.isEmpty ? nil : location
        snap.start = start
        snap.end = end <= start ? start.addingTimeInterval(3600) : end
        if case .failure(let error) = CalendarService.shared.updateEvent(&snap, span: span) {
            // 保存失败时停留在编辑页，不关闭、不回调，让用户重试或取消。
            saveErrorText = error.localizedDescription
            return
        }
        dismiss()
        onDone()
    }
}

typealias ScheduleListView = TodayScheduleView
