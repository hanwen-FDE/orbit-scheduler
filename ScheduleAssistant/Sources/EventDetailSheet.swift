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
    @State private var recurrenceFrequency: RecurrenceFrequency?
    @State private var recurrenceInterval: Int
    @State private var recurrenceHasEnd: Bool
    @State private var recurrenceEnd: Date
    @State private var showDeleteOptions = false

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
        _recurrenceFrequency = State(initialValue: snapshot.recurrence?.frequency)
        _recurrenceInterval = State(initialValue: snapshot.recurrence?.interval ?? 1)
        _recurrenceHasEnd = State(initialValue: snapshot.recurrence?.endDate != nil)
        _recurrenceEnd = State(initialValue: snapshot.recurrence?.endDate
            ?? Calendar.current.date(byAdding: .year, value: 1, to: snapshot.start)
            ?? snapshot.start)
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
                Section("循环") {
                    Picker("重复", selection: $recurrenceFrequency) {
                        Text("不重复").tag(RecurrenceFrequency?.none)
                        ForEach(RecurrenceFrequency.allCases) { frequency in
                            Text(frequency.title).tag(Optional(frequency))
                        }
                    }
                    if let recurrenceFrequency {
                        Stepper(value: $recurrenceInterval, in: 1...12) {
                            Text(recurrenceDescription(for: recurrenceFrequency))
                        }
                        Toggle("设置结束日期", isOn: $recurrenceHasEnd)
                        if recurrenceHasEnd {
                            DatePicker("结束于", selection: $recurrenceEnd, in: start...)
                        }
                        Text("循环日程会写入系统日历。编辑后将影响这一项及之后的循环。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let conflicts = snapshot.conflicts, !conflicts.isEmpty {
                    Section("时间冲突") {
                        ForEach(conflicts) { conflict in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("与《\(conflict.title)》重叠")
                                Text("\(conflict.start.friendlyDay) \(conflict.start.shortTime)–\(conflict.end.shortTime) · \(conflict.calendarTitle)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let suggested = snapshot.suggestedStart {
                            Button("采用建议时间：\(suggested.friendlyDay) \(suggested.shortTime)") {
                                let duration = end.timeIntervalSince(start)
                                start = suggested
                                end = suggested.addingTimeInterval(duration)
                            }
                        }
                    }
                }
                Section {
                    Button("保存修改", action: save)
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                    Button("删除这个日程", role: .destructive) {
                        if snapshot.recurrence != nil {
                            showDeleteOptions = true
                        } else {
                            chat.deleteEventMessage(messageId)
                            dismiss()
                        }
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
        .confirmationDialog("删除循环日程", isPresented: $showDeleteOptions, titleVisibility: .visible) {
            Button("只删除这一次", role: .destructive) {
                chat.deleteEventMessage(messageId)
                dismiss()
            }
            Button("删除这一次及后续", role: .destructive) {
                chat.deleteEventMessage(messageId, includingFuture: true)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择是否保留后续循环。")
        }
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
        if let recurrenceFrequency {
            updated.recurrence = RecurrenceSpec(
                frequency: recurrenceFrequency,
                interval: recurrenceInterval,
                endDate: recurrenceHasEnd ? recurrenceEnd : nil
            )
        } else {
            updated.recurrence = nil
        }
        chat.applyEdit(messageId: messageId, snapshot: updated)
        dismiss()
    }

    private func recurrenceDescription(for frequency: RecurrenceFrequency) -> String {
        if frequency == .weekdays {
            return recurrenceInterval == 1
                ? "每周工作日"
                : "每 \(recurrenceInterval) 周的工作日"
        }
        return recurrenceInterval == 1
            ? frequency.title
            : "每 \(recurrenceInterval) \(frequency.unitTitle)"
    }
}
