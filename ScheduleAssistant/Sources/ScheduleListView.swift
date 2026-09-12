import SwiftUI
import EventKit

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
                            .background(Circle().fill(.orange))
                            .offset(x: 8, y: -8)
                    }
                }
        }
        .accessibilityLabel("通知中心，\(notifications.unreadCount) 条未读")
    }
}

struct OrbitNotificationCenterView: View {
    @ObservedObject private var store = OrbitNotificationStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    ContentUnavailableView("暂无通知", systemImage: "bell", description: Text("日程提醒、每日简报和失败信息会出现在这里。"))
                } else {
                    List {
                        ForEach(store.items) { item in
                            Button { store.markRead(item.id) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: item.kind.icon)
                                        .foregroundStyle(color(for: item.kind))
                                        .frame(width: 28, height: 28)
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(item.title).font(.headline)
                                            if !item.isRead { Circle().fill(.orange).frame(width: 7, height: 7) }
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

    private func color(for kind: OrbitNotificationKind) -> Color {
        switch kind {
        case .briefing: return .orange
        case .conflict, .writeFailure, .aiFailure: return .red
        case .reminder: return .blue
        }
    }
}

/// 两个主页面之一：直接读取 Apple 日历中的当天安排。
struct TodayScheduleView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDay = Date()
    @State private var events: [EKEvent] = []
    @State private var showNotifications = false
    @State private var showDrawer = false

    var body: some View {
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
                                timelineRow(event)
                                Divider().padding(.leading, 70)
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("今天")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showDrawer = true } label: { Image(systemName: "person.crop.circle").font(.title3) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NotificationBellButton(isPresented: $showNotifications)
                }
            }
        }
        .sheet(isPresented: $showNotifications) { OrbitNotificationCenterView() }
        .sheet(isPresented: $showDrawer) { SideDrawerView() }
        .task { await refresh() }
        .onChange(of: selectedDay) { _, _ in Task { await refresh() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
    }

    private var daySelector: some View {
        HStack {
            Button { selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            VStack(spacing: 3) {
                Text(selectedDay.friendlyDay).font(.headline)
                Text(selectedDay.formatted(.dateTime.year().month().day().weekday()))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { selectedDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal, 28)
    }

    private func timelineRow(_ event: EKEvent) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(emoji(for: event.title ?? "")).font(.title2).frame(width: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.isAllDay ? "全天" : "\(event.startDate.shortTime)–\(event.endDate.shortTime)")
                    .font(.subheadline.weight(.medium))
                Text(event.title ?? "未命名日程").font(.title3.weight(.semibold)).lineLimit(2)
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

typealias ScheduleListView = TodayScheduleView
