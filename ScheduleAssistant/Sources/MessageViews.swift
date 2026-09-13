import SwiftUI
import UIKit

/// 通用滑动手势容器：长按激活后右滑露出删除；需要时才提供左滑操作。
struct SwipeActionCard<Content: View>: View {
    let onDelete: () -> Void
    let onEdit: (() -> Void)?
    let content: () -> Content

    @State private var armed = false
    @State private var offsetX: CGFloat = 0

    private let revealThreshold: CGFloat = 56

    init(
        onDelete: @escaping () -> Void,
        onEdit: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.onDelete = onDelete
        self.onEdit = onEdit
        self.content = content
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                actionButton(color: .red, icon: "trash.fill", visible: offsetX > 20) {
                    reset()
                    onDelete()
                }
                .frame(width: 72)
                Spacer(minLength: 0)
                if let onEdit {
                    actionButton(color: orbitAccent(), icon: "pencil", visible: offsetX < -20) {
                        reset()
                        onEdit()
                    }
                    .frame(width: 72)
                }
            }
            content()
                .scaleEffect(armed ? 0.985 : 1)
                .shadow(color: .black.opacity(armed ? 0.12 : 0), radius: armed ? 6 : 0, y: 2)
                .offset(x: offsetX)
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.3) {
            withAnimation(.easeOut(duration: 0.15)) { armed = true }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        .onTapGesture {
            if armed || abs(offsetX) > 1 { reset() }
        }
        .gesture(armed ? drag : nil)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    let minimumOffset: CGFloat = onEdit == nil ? 0 : -120
                    offsetX = min(120, max(minimumOffset, value.translation.width))
                }
            }
            .onEnded { value in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    if value.translation.width > revealThreshold {
                        offsetX = 80
                    } else if onEdit != nil, value.translation.width < -revealThreshold {
                        offsetX = -80
                    } else {
                        offsetX = 0
                        armed = false
                    }
                }
            }
    }

    private func reset() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            offsetX = 0
            armed = false
        }
    }

    @ViewBuilder
    private func actionButton(color: Color, icon: String, visible: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 44)
                .background(Capsule().fill(color))
                .opacity(visible ? 1 : 0)
                .scaleEffect(visible ? 1 : 0.6)
        }
        .buttonStyle(.plain)
    }
}

/// 单条消息：气泡或日程卡片
struct MessageRow: View {
    @EnvironmentObject private var chat: ChatStore
    let message: ChatMessage
    var onTapCard: () -> Void
    var onOpenToday: (() -> Void)? = nil

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
                    .background(bubbleShape.fill(orbitAccent()))
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
            .background(bubbleShape.fill(orbitAccent()))
        case .briefing:
            Button(action: { onOpenToday?() }) {
                briefingBody(title: "今日早报", icon: "sun.max.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .eveningBriefing:
            Button(action: { onOpenToday?() }) {
                briefingBody(title: "今日晚报", icon: "moon.stars.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

    private func briefingBody(title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline).foregroundStyle(orbitAccent())
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(message.createdAt.shortTime).font(.caption).foregroundStyle(.secondary)
            }
            Text(message.text).font(.subheadline)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(orbitAccent().opacity(0.10)))
    }

    private var bubbleShape: some Shape {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    private var durationText: String {
        let seconds = Int(message.voiceDuration ?? 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// 日程卡片：日期、时间、日历和提醒均就地修改；只有右上角「…」进入完整编辑页。
struct EventCardView: View {
    @EnvironmentObject private var chat: ChatStore
    let messageId: UUID
    let snapshot: EventSnapshot
    var onTap: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var showRecurringDeleteOptions = false
    @State private var showDatePicker = false
    @State private var showTimePicker = false
    @State private var draftDate = Date()
    @State private var draftStart = Date()
    @State private var draftEnd = Date()

    var body: some View {
        SwipeActionCard(onDelete: requestDelete) {
            cardContent
        }
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

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 第 1 行：图标 + 标题；只有右上角三个点进入完整编辑。
            HStack(alignment: .center, spacing: 10) {
                Text(snapshot.emoji)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let recurrence = snapshot.recurrence {
                        Text(recurrence.displayText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if !snapshot.deleted {
                    Button(action: onTap) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("完整编辑日程")
                }
            }

            // 第 2 行：日期和时间分别弹出自己的轻量编辑器。
            HStack(spacing: 8) {
                Button {
                    draftDate = snapshot.start
                    showDatePicker = true
                } label: {
                    Text(snapshot.start.cardDay)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(orbitAccent())
                }
                .buttonStyle(.plain)
                .disabled(snapshot.deleted)
                .popover(isPresented: $showDatePicker, arrowEdge: .top) {
                    dateEditor
                        .presentationCompactAdaptation(.popover)
                }

                Spacer(minLength: 0)

                Button {
                    draftStart = snapshot.start
                    draftEnd = snapshot.end
                    showTimePicker = true
                } label: {
                    Text(timeRangeText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(orbitAccent())
                }
                .buttonStyle(.plain)
                .disabled(snapshot.deleted)
                .popover(isPresented: $showTimePicker, arrowEdge: .top) {
                    timeEditor
                        .presentationCompactAdaptation(.popover)
                }
            }

            if snapshot.deleted {
                Label("这个日程已从系统日历中删除", systemImage: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                conflictRow
                // 第 3 行：左侧目标日历，右侧提醒时间和开关。
                HStack(spacing: 8) {
                    Menu {
                        ForEach(CalendarService.shared.availableCalendars(), id: \.calendarIdentifier) { calendar in
                            Button {
                                chat.changeCalendar(messageId: messageId, to: calendar.calendarIdentifier)
                            } label: {
                                if calendar.calendarIdentifier == snapshot.calendarIdentifier {
                                    Label(calendar.title, systemImage: "checkmark")
                                } else {
                                    Text(calendar.title)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("日历")
                                .foregroundStyle(orbitAccent().opacity(0.72))
                            Text(snapshot.calendarTitle)
                                .fontWeight(.semibold)
                                .foregroundStyle(orbitAccent().opacity(0.82))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(orbitAccent().opacity(0.72))
                        }
                    }
                    .font(.subheadline)

                    Spacer(minLength: 4)

                    Text("提前")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                            Text(reminderValueLabel)
                                .font(.subheadline.bold())
                                .foregroundStyle(orbitAccent())
                        }
                    } else {
                        Text("关闭")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("", isOn: Binding(
                        get: { snapshot.reminderMinutes != nil },
                        set: { chat.toggleReminder(messageId: messageId, on: $0) }
                    ))
                    .labelsHidden()
                    .tint(orbitAccent())
                }

                if snapshot.isPendingConfirmation {
                    HStack(spacing: 10) {
                        Text("尚未写入系统日历")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            chat.confirmEvent(messageId: messageId)
                        } label: {
                            Label("确认添加", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(orbitAccent())
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.systemBackground)))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }

    private var dateEditor: some View {
        VStack(spacing: 12) {
            Text("修改日期")
                .font(.headline)
            DatePicker("", selection: $draftDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                Button("取消") { showDatePicker = false }
                Spacer()
                Button("完成") { applyDateChange() }
                    .fontWeight(.semibold)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder
    private var timeEditor: some View {
        VStack(spacing: 14) {
            Text("修改时间")
                .font(.headline)
            if snapshot.isAllDay {
                Text("这是全天日程；如需改为具体时间，请点卡片右上角三个点。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                DatePicker("开始", selection: $draftStart, displayedComponents: .hourAndMinute)
                DatePicker("结束", selection: $draftEnd, displayedComponents: .hourAndMinute)
                HStack {
                    Button("取消") { showTimePicker = false }
                    Spacer()
                    Button("完成") { applyTimeChange() }
                        .fontWeight(.semibold)
                }
            }
        }
        .padding(18)
        .frame(width: 290)
    }

    private func requestDelete() {
        if snapshot.recurrence != nil {
            showRecurringDeleteOptions = true
        } else {
            showDeleteConfirmation = true
        }
    }

    private func applyDateChange() {
        var updated = snapshot
        let calendar = Calendar.current
        let duration = max(60, snapshot.end.timeIntervalSince(snapshot.start))
        var day = calendar.dateComponents([.year, .month, .day], from: draftDate)
        if snapshot.isAllDay {
            updated.start = calendar.date(from: day).map { calendar.startOfDay(for: $0) } ?? draftDate
            updated.end = calendar.date(byAdding: .day, value: 1, to: updated.start) ?? updated.start
        } else {
            let time = calendar.dateComponents([.hour, .minute, .second], from: snapshot.start)
            day.hour = time.hour
            day.minute = time.minute
            day.second = time.second
            updated.start = calendar.date(from: day) ?? draftDate
            updated.end = updated.start.addingTimeInterval(duration)
        }
        chat.applyEdit(messageId: messageId, snapshot: updated)
        showDatePicker = false
    }

    private func applyTimeChange() {
        guard !snapshot.isAllDay else {
            showTimePicker = false
            return
        }
        var updated = snapshot
        updated.start = draftStart
        updated.end = draftEnd > draftStart ? draftEnd : draftStart.addingTimeInterval(3600)
        chat.applyEdit(messageId: messageId, snapshot: updated)
        showTimePicker = false
    }

    /// 第 2 行右侧的时间段；日期在左侧单独显示。
    private var timeRangeText: String {
        if snapshot.isAllDay { return "全天" }
        return "\(snapshot.start.shortTime)–\(snapshot.end.shortTime)"
    }

    /// 简短提醒时长：“15分钟”/“1小时”/“1天”/“准时”
    private var reminderValueLabel: String {
        guard let minutes = snapshot.reminderMinutes else { return "关闭" }
        switch minutes {
        case 0: return "准时"
        case 1440: return "1天"
        default:
            if minutes >= 60, minutes % 60 == 0 { return "\(minutes / 60)小时" }
            return "\(minutes)分钟"
        }
    }

    /// 冲突只在存在时占一行，可展开采用建议时间。
    @ViewBuilder
    private var conflictRow: some View {
        if let conflicts = snapshot.conflicts, !conflicts.isEmpty, !snapshot.deleted {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(orbitAccent())
                Text("与 \(conflicts.count) 项日程重叠")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let suggested = snapshot.suggestedStart {
                    Button {
                        chat.applySuggestedTime(messageId: messageId)
                    } label: {
                        Text("改为 \(suggested.shortTime)")
                            .font(.caption.bold())
                            .foregroundStyle(orbitAccent())
                    }
                }
                Button {
                    chat.ignoreConflicts(messageId: messageId)
                } label: {
                    Text("忽略")
                        .font(.caption.bold())
                        .foregroundStyle(orbitAccent().opacity(0.72))
                }
            }
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
                    .background(Circle().fill(orbitAccent().opacity(0.14)))
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
                        .foregroundStyle(orbitAccent())
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
