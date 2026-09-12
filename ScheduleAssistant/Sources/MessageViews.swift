import SwiftUI

/// 单条消息：气泡或日程卡片
struct MessageRow: View {
    @EnvironmentObject private var chat: ChatStore
    let message: ChatMessage
    var onTapCard: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 48) }
            content
            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch message.kind {
        case .text:
            if message.text == "…" && message.role == .assistant {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(.secondary).frame(width: 7, height: 7)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .background(bubbleShape.fill(Color(.secondarySystemBackground)))
            } else if message.role == .assistant {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.text)
                    if message.text.hasPrefix("出错了") {
                        Button("重试") { chat.retryLast() }
                            .font(.footnote.bold())
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(bubbleShape.fill(Color(.secondarySystemBackground)))
            } else {
                Text(message.text)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(bubbleShape.fill(.blue))
            }
        case .image:
            if let data = message.imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable().scaledToFill()
                    .frame(maxWidth: 210, maxHeight: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        case .voice:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                    Text(durationText)
                        .font(.caption.monospacedDigit())
                }
                Text(message.text)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .foregroundStyle(.white)
            .background(bubbleShape.fill(Color.orange))
        case .briefing:
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("今日简报", systemImage: "sun.max.fill")
                        .font(.headline).foregroundStyle(.orange)
                    Spacer()
                    Text(message.createdAt.shortTime).font(.caption).foregroundStyle(.secondary)
                }
                Text(message.text).font(.subheadline)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.orange.opacity(0.10)))
        case .eventCard:
            if let snap = message.event {
                EventCardView(messageId: message.id, snapshot: snap, onTap: onTapCard)
            }
        case .habitCard:
            if let habit = message.habit {
                HabitCardView(messageId: message.id, habit: habit)
            }
        }
    }

    private var bubbleShape: some Shape {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    private var durationText: String {
        let seconds = Int(message.voiceDuration ?? 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// 日程卡片
struct EventCardView: View {
    @EnvironmentObject private var chat: ChatStore
    @ObservedObject private var app = AppSettings.shared
    let messageId: UUID
    let snapshot: EventSnapshot
    var onTap: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var showRecurringDeleteOptions = false
    @State private var showConflictDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题和详情编辑入口。日程卡片不再用整卡 onTapGesture，
            // 这样底部菜单和删除按钮不会被父级手势抢走。
            HStack(alignment: .top, spacing: 10) {
                Button(action: onTap) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(snapshot.emoji)
                            .font(.system(size: 30))
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                        Text(snapshot.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(snapshot.deleted)

                if !snapshot.deleted {
                    Menu {
                        Button(action: onTap) {
                            Label("编辑详情", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            if snapshot.recurrence != nil {
                                showRecurringDeleteOptions = true
                            } else {
                                showDeleteConfirmation = true
                            }
                        } label: {
                            Label("删除这个日程", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                }
            }
            .padding(.bottom, 12)

            Divider()

            Button(action: onTap) {
                // 日期 / 时间
                VStack(spacing: 10) {
                    row(icon: "calendar", label: "日期", value: snapshot.start.friendlyDay)
                    if snapshot.isAllDay {
                        row(icon: "clock", label: "时间", value: "全天")
                    } else {
                        row(icon: "clock", label: "时间",
                            value: "\(snapshot.start.shortTime) ▶ \(snapshot.end.shortTime)",
                            valueColor: .orange)
                    }
                    if let location = snapshot.location, !location.isEmpty {
                        row(icon: "mappin.and.ellipse", label: "地点", value: location)
                    }
                    if let recurrence = snapshot.recurrence {
                        row(icon: "repeat", label: "循环", value: recurrence.displayText, valueColor: .blue)
                    }
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(snapshot.deleted)

            Divider()

            if snapshot.deleted {
                Label("这个日程已从系统日历中删除", systemImage: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                if snapshot.isPendingConfirmation {
                    HStack(spacing: 10) {
                        Button {
                            chat.confirmEvent(messageId: messageId)
                        } label: {
                            Label("确认添加", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        Button("编辑", action: onTap)
                            .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 10)
                    Divider()
                }
                if let conflicts = snapshot.conflicts, !conflicts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("与 \(conflicts.count) 项日程时间重叠", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.orange)
                            Spacer()
                            Button(showConflictDetails ? "收起" : "查看建议") {
                                withAnimation { showConflictDetails.toggle() }
                            }.font(.caption.bold())
                        }
                        if showConflictDetails {
                            ForEach(conflicts.prefix(2)) { conflict in
                                Text("《\(conflict.title)》· \(conflict.start.friendlyDay) \(conflict.start.shortTime)–\(conflict.end.shortTime)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button("重新检查冲突") { chat.refreshConflicts(messageId: messageId) }
                                .font(.caption)
                            if let suggested = snapshot.suggestedStart {
                                Button {
                                    chat.applySuggestedTime(messageId: messageId)
                                } label: {
                                    Label("采用建议：\(suggested.friendlyDay) \(suggested.shortTime)", systemImage: "arrow.right.circle.fill")
                                        .font(.subheadline.bold())
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    Divider()
                }

                // 提醒开关 + 时长
                HStack {
                    Label("提醒", systemImage: "bell")
                        .font(.subheadline)
                    Spacer()
                    if snapshot.reminderMinutes != nil {
                        Menu {
                            ForEach(ReminderOption.allCases) { option in
                                Button {
                                    chat.changeReminderDuration(
                                        messageId: messageId,
                                        minutes: option.minutes ?? 0)
                                } label: {
                                    if option.minutes == snapshot.reminderMinutes {
                                        Label(option.label, systemImage: "checkmark")
                                    } else {
                                        Text(option.label)
                                    }
                                }
                            }
                        } label: {
                            Text(currentReminderLabel)
                                .font(.subheadline.bold())
                                .foregroundStyle(.orange)
                        }
                    }
                    Toggle("", isOn: Binding(
                        get: { snapshot.reminderMinutes != nil },
                        set: { chat.toggleReminder(messageId: messageId, on: $0) }
                    ))
                    .labelsHidden()
                    .tint(.orange)
                }
                .padding(.vertical, 10)

                if !snapshot.isPendingConfirmation {
                    Divider()

                    HStack {
                        Label("提醒事项", systemImage: "checklist")
                            .font(.subheadline)
                        Spacer()
                        if snapshot.nativeReminderIdentifier != nil {
                            Button("已同步") { chat.removeNativeReminder(messageId: messageId) }
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)
                        } else {
                            Button("同步一份到系统提醒事项") {
                                chat.syncToNativeReminders(messageId: messageId)
                            }
                            .font(.subheadline.bold())
                        }
                    }
                    .padding(.vertical, 10)
                }

                Divider()

                // 这里专门管理“写入哪一个日历”，不再被理解成编辑标题、时间等详情。
                HStack {
                    Menu {
                        Section("将此日程移动到") {
                            ForEach(CalendarService.shared.availableCalendars(), id: \.calendarIdentifier) { cal in
                                Button {
                                    chat.changeCalendar(messageId: messageId,
                                                        to: cal.calendarIdentifier)
                                } label: {
                                    if cal.calendarIdentifier == snapshot.calendarIdentifier {
                                        Label(cal.title, systemImage: "checkmark")
                                    } else {
                                        Text(cal.title)
                                    }
                                }
                            }
                        }
                        Section("设为今后新日程的默认日历") {
                            ForEach(CalendarService.shared.availableCalendars(), id: \.calendarIdentifier) { cal in
                                Button {
                                    app.defaultCalendarId = cal.calendarIdentifier
                                } label: {
                                    if cal.calendarIdentifier == app.defaultCalendarId {
                                        Label(cal.title, systemImage: "checkmark")
                                    } else {
                                        Text(cal.title)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("更改目标日历", systemImage: "calendar.badge.plus")
                            .font(.subheadline)
                    }
                    Spacer()
                    Text(snapshot.isPendingConfirmation
                         ? "将添加到「\(snapshot.calendarTitle)」"
                         : "已添加到「\(snapshot.calendarTitle)」")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.systemBackground)))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .confirmationDialog("删除这个日程？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("删除日程", role: .destructive) {
                chat.deleteEventMessage(messageId)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("它会同时从「\(snapshot.calendarTitle)」中删除。")
        }
        .confirmationDialog("删除循环日程", isPresented: $showRecurringDeleteOptions, titleVisibility: .visible) {
            Button("只删除这一次", role: .destructive) {
                chat.deleteEventMessage(messageId)
            }
            Button("删除这一次及后续", role: .destructive) {
                chat.deleteEventMessage(messageId, includingFuture: true)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择是否保留后续循环。")
        }
    }

    private var currentReminderLabel: String {
        ReminderOption.allCases.first { $0.minutes == snapshot.reminderMinutes }?.label
            ?? "提前 \(snapshot.reminderMinutes ?? 0) 分钟"
    }

    private func row(icon: String, label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(valueColor)
        }
    }
}

/// 循环习惯卡：保存到系统“提醒事项”，而不是增加 Orbit 内部待办模块。
struct HabitCardView: View {
    @EnvironmentObject private var chat: ChatStore
    let messageId: UUID
    let habit: HabitSnapshot

    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(habit.emoji)
                    .font(.system(size: 30))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.green.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.title).font(.headline)
                    Text("习惯提醒 · \(habit.recurrence.displayText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !habit.deleted {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            if habit.deleted {
                Label("这个习惯已从系统提醒事项中删除", systemImage: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Label("提醒时间", systemImage: "bell")
                        .font(.subheadline)
                    Spacer()
                    Text("\(habit.start.friendlyDay) \(habit.start.shortTime)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                }
                Text("已同步到系统“提醒事项”。完成当前项后，系统会按循环规则显示下一次。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.systemBackground)))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .confirmationDialog("删除这个习惯？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("删除习惯", role: .destructive) {
                chat.deleteHabitMessage(messageId)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("它会同时从系统“提醒事项”中删除。")
        }
    }
}
