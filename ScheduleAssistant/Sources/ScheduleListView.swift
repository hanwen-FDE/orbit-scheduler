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

    func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

struct NotificationBellButton: View {
    @ObservedObject private var notifications = OrbitNotificationStore.shared
    @Binding var isPresented: Bool

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: notifications.unreadCount == 0 ? "bell" : "bell.fill")
                .font(.system(size: 20, weight: .semibold))
                .overlay(alignment: .topTrailing) {
                    if notifications.unreadCount > 0 {
                        Text("\(min(99, notifications.unreadCount))")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Circle().fill(orbitAccent()))
                            .offset(x: 8, y: -8)
                    }
                }
        }
        .accessibilityLabel("通知中心，\(notifications.unreadCount) 条未读")
    }
}

struct OrbitNotificationCenterView: View {
    @ObservedObject private var store = OrbitNotificationStore.shared
    @EnvironmentObject private var chat: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    ContentUnavailableView("暂无通知", systemImage: "bell", description: Text("日程提醒、每日简报和失败信息会出现在这里。"))
                } else {
                    List {
                        groupEntry(title: "通知",
                                   items: store.items.filter { $0.kind != .briefing },
                                   emptyHint: "暂无通知记录")
                        groupEntry(title: "简报",
                                   items: store.items.filter { $0.kind == .briefing },
                                   emptyHint: "还没有简报")
                    }
                }
            }
            .navigationTitle("通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if store.unreadCount > 0 { Button("全部已读") { store.markAllRead() } }
                }
            }
        }
    }

    /// 分组入口：大标题 + 最近一条预览；点进子页看该类全部记录。
    private func groupEntry(title: String, items: [OrbitNotificationItem], emptyHint: String) -> some View {
        NavigationLink {
            NotificationGroupListView(title: title, items: items)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
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
            .padding(.vertical, 4)
        }
    }
}

/// 某一类的全部记录（按时间逆序，最新在前）。
struct NotificationGroupListView: View {
    @ObservedObject private var store = OrbitNotificationStore.shared
    @EnvironmentObject private var chat: ChatStore
    @Environment(\.dismiss) private var dismiss

    let title: String
    let items: [OrbitNotificationItem]

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView("暂无记录", systemImage: "tray", description: Text("新的内容出现后会在这里逐条显示。"))
            } else {
                List {
                    ForEach(items) { item in
                        Button {
                            store.markRead(item.id)
                            // 有关联日程卡片的通知：关闭通知中心并跳去那张卡片打开编辑。
                            if let messageId = item.relatedMessageId {
                                chat.pendingFocusMessageId = messageId
                                dismiss()
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
                    .onDelete(perform: store.delete)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func color(for kind: OrbitNotificationKind) -> Color {
        switch kind {
        case .briefing: return orbitAccent()
        case .conflict, .writeFailure, .aiFailure: return .red
        case .reminder: return .blue
        }
    }
}

/// 两个主页面之一：直接读取 Apple 日历中的当天安排。
struct TodayScheduleView: View {
    @Environment(\.scenePhase) private var scenePhase
    var onOpenChat: () -> Void = {}
    @State private var breathe = false
    @State private var selectedDay = Date()
    @State private var events: [EKEvent] = []
    @State private var showNotifications = false
    @State private var showDrawer = false
    @State private var eventToEdit: EKEvent?
    @State private var eventToDelete: EKEvent?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    daySelector
                    if events.isEmpty {
                        ContentUnavailableView(
                            "今天暂无安排",
                            systemImage: "calendar.badge.plus",
                            description: Text("切换到“对话”，告诉 Orbit 你想安排什么。")
                        )
                        .padding(.top, 80)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(events, id: \.eventIdentifier) { event in
                                SwipeActionCard {
                                    eventToDelete = event
                                } onEdit: {
                                    eventToEdit = event
                                } content: {
                                    timelineRow(event)
                                }
                                Divider().padding(.leading, 70)
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showDrawer = true } label: {
                        OrbitBrandMark()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NotificationBellButton(isPresented: $showNotifications)
                }
            }
        }
            .sheet(item: $eventToEdit) { event in EKEventEditor(event: event) {
                Task { await refresh() }
            } }
            .confirmationDialog("删除这个日程？", isPresented: Binding(
                get: { eventToDelete != nil },
                set: { if !$0 { eventToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("删除日程", role: .destructive) {
                    if let event = eventToDelete {
                        CalendarService.shared.deleteEvent(snapshot: Self.snapshot(of: event))
                        Task { await refresh() }
                    }
                    eventToDelete = nil
                }
                Button("取消", role: .cancel) { eventToDelete = nil }
            } message: {
                Text("它会同时从系统日历中删除。")
            }
            .sheet(isPresented: $showNotifications) { OrbitNotificationCenterView() }
            .sheet(isPresented: $showDrawer) { SideDrawerView() }
            .task { await refresh() }
            .onChange(of: selectedDay) { _, _ in Task { await refresh() } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
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

    /// 页面顶部唯一的标题行：粗体日期 + 小字完整日期在左，前后翻天按钮在右。
    private var daySelector: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDay.friendlyDay).font(.title2.bold())
                Text(selectedDay.formatted(.dateTime.year().month().day().weekday()))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { shiftDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .buttonStyle(.plain)
            Button { shiftDay(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
    }

    private func shiftDay(_ delta: Int) {
        selectedDay = Calendar.current.date(byAdding: .day, value: delta, to: selectedDay) ?? selectedDay
    }

    private func timelineRow(_ event: EKEvent) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(emoji(for: event.title ?? "")).font(.title2).frame(width: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.isAllDay ? "全天" : "\(event.startDate.shortTime)–\(event.endDate.shortTime)")
                    .font(.subheadline.weight(.medium))
                Text(event.title ?? "未命名日程").font(.headline).lineLimit(2)
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 18)
    }

    private func refresh() async {
        _ = await CalendarService.shared.ensureAccess()
        events = CalendarService.shared.events(on: selectedDay)
    }

    private func emoji(for title: String) -> String {
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
            emoji: "📅",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            reminderMinutes: event.alarms?.first.map { Int(-$0.relativeOffset / 60) },
            calendarIdentifier: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            eventIdentifier: event.eventIdentifier
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

    init(event: EKEvent, onDone: @escaping () -> Void) {
        self.event = event
        self.onDone = onDone
        _title = State(initialValue: event.title ?? "")
        _location = State(initialValue: event.location ?? "")
        _start = State(initialValue: event.startDate)
        _end = State(initialValue: max(event.endDate, event.startDate))
    }

    var body: some View {
        NavigationStack {
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        var snap = TodayScheduleView.snapshot(of: event)
        snap.title = title.trimmingCharacters(in: .whitespaces)
        snap.location = location.isEmpty ? nil : location
        snap.start = start
        snap.end = end <= start ? start.addingTimeInterval(3600) : end
        CalendarService.shared.updateEvent(&snap)
        dismiss()
        onDone()
    }
}

typealias ScheduleListView = TodayScheduleView
