import SwiftUI

/// 日程编辑页：点击卡片打开
struct EventDetailSheet: View {
    @EnvironmentObject private var chat: ChatStore
    @Environment(\.dismiss) private var dismiss

    let messageId: UUID
    @State var snapshot: EventSnapshot

    @State private var title: String
    @State private var location: String
    @State private var notes: String
    @State private var isAllDay: Bool
    @State private var start: Date
    @State private var hasEnd: Bool
    @State private var end: Date

    init(messageId: UUID, snapshot: EventSnapshot) {
        self.messageId = messageId
        _snapshot = State(initialValue: snapshot)
        _title = State(initialValue: snapshot.title)
        _location = State(initialValue: snapshot.location ?? "")
        _notes = State(initialValue: snapshot.notes ?? "")
        _isAllDay = State(initialValue: snapshot.isAllDay)
        _start = State(initialValue: snapshot.start)
        _hasEnd = State(initialValue: snapshot.end > snapshot.start)
        _end = State(initialValue: snapshot.end > snapshot.start ? snapshot.end : snapshot.start.addingTimeInterval(3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("日程") {
                    TextField("标题", text: $title)
                    TextField("地点（可选）", text: $location)
                    TextField("备注（可选）", text: $notes, axis: .vertical)
                }
                Section("时间") {
                    Toggle("全天", isOn: $isAllDay)
                    DatePicker("开始", selection: $start)
                    Toggle("有结束时间", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("结束", selection: $end, in: start...)
                    }
                }
                Section {
                    Button("保存修改", action: save)
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                    Button("删除这个日程", role: .destructive) {
                        chat.deleteEventMessage(messageId)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("编辑日程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        var updated = snapshot
        updated.title = title.trimmingCharacters(in: .whitespaces)
        updated.location = location.isEmpty ? nil : location
        updated.notes = notes.isEmpty ? nil : notes
        updated.isAllDay = isAllDay
        updated.start = start
        if isAllDay {
            updated.end = Calendar.current.date(byAdding: .day, value: 1,
                                                to: Calendar.current.startOfDay(for: start)) ?? start
        } else if hasEnd {
            updated.end = end
        } else {
            updated.end = start.addingTimeInterval(3600)
        }
        chat.applyEdit(messageId: messageId, snapshot: updated)
        dismiss()
    }
}
