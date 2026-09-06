import SwiftUI

/// 主页右上角"日程"页面：按时间排序的日程列表
struct ScheduleListView: View {
    @EnvironmentObject private var chat: ChatStore
    @Environment(\.dismiss) private var dismiss

    @State private var editingMessage: ChatMessage?

    var body: some View {
        NavigationStack {
            List {
                let events = chat.allEvents
                if events.isEmpty {
                    Text("还没有日程\n回到首页告诉我你的安排吧")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(events, id: \.messageId) { item in
                        row(item)
                            .swipeActions {
                                Button("删除", role: .destructive) {
                                    chat.deleteEventMessage(item.messageId)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let msg = chat.messages.first(where: { $0.id == item.messageId }) {
                                    editingMessage = msg
                                }
                            }
                    }
                }
            }
            .navigationTitle("日程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
        .sheet(item: $editingMessage) { msg in
            if let snap = msg.event {
                EventDetailSheet(messageId: msg.id, snapshot: snap)
            }
        }
    }

    private func row(_ item: (messageId: UUID, snapshot: EventSnapshot)) -> some View {
        HStack(spacing: 12) {
            Text(item.snapshot.emoji).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.snapshot.title).font(.body.weight(.semibold))
                Text(timeLine(item.snapshot))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("「\(item.snapshot.calendarTitle)」")
                    .font(.caption2).foregroundStyle(.secondary)
                if item.snapshot.reminderMinutes != nil {
                    Image(systemName: "bell.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    private func timeLine(_ snap: EventSnapshot) -> String {
        let day = snap.start.friendlyDay
        if snap.isAllDay { return "\(day) · 全天" }
        return "\(day) \(snap.start.shortTime) – \(snap.end.shortTime)"
    }
}
