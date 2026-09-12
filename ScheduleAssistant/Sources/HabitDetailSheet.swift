import SwiftUI

/// 创建“习惯提醒”：它会建立一个循环 EKReminder，而非 Orbit 内部待办。
struct HabitDetailSheet: View {
    @EnvironmentObject private var chat: ChatStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var start = Date()
    @State private var frequency: RecurrenceFrequency = .daily
    @State private var interval = 1
    @State private var hasEndDate = false
    @State private var endDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("习惯") {
                    TextField("例如：吃维生素 D / 睡前阅读", text: $title)
                    DatePicker("第一次提醒", selection: $start)
                }
                Section("循环规则") {
                    Picker("重复", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Stepper(value: $interval, in: 1...12) {
                        Text(recurrenceDescription)
                    }
                    Toggle("设置结束日期", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("结束于", selection: $endDate, in: start...)
                    }
                }
                Section {
                    Text("保存后会请求“提醒事项”完全访问权限，并把习惯写入苹果系统提醒事项。完成当前项后，系统会自动出现下一次。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("新增习惯提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        let rule = RecurrenceSpec(
                            frequency: frequency,
                            interval: interval,
                            endDate: hasEndDate ? endDate : nil
                        )
                        chat.createHabit(title: title, start: start, recurrence: rule)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var recurrenceDescription: String {
        if frequency == .weekdays {
            return interval == 1 ? "每周工作日" : "每 \(interval) 周的工作日"
        }
        return interval == 1 ? frequency.title : "每 \(interval) \(frequency.unitTitle)"
    }
}
