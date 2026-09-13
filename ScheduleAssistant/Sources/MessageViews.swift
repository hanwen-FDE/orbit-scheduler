import SwiftUI
import UIKit

/// 通用滑动手势容器：长按激活后，右滑露出红色删除、左滑露出主题色详情编辑。
/// 对话卡片与“今天”列表行共用，保证交互一致。
struct SwipeActionCard<Content: View>: View {
    var onDelete: () -> Void
    var onEdit: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var armed = false
    @State private var offsetX: CGFloat = 0

    private let revealThreshold: CGFloat = 56

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                actionButton(color: .red, icon: "trash.fill", visible: offsetX > 20) {
                    reset()
                    onDelete()
                }
                .frame(width: 72)
                Spacer(minLength: 0)
                actionButton(color: orbitAccent(), icon: "pencil", visible: offsetX < -20) {
                    reset()
                    onEdit()
                }
                .frame(width: 72)
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
                    offsetX = min(120, max(-120, value.translation.width))
                }
            }
            .onEnded { value in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    if value.translation.width > revealThreshold {
                        offsetX = 80
                    } else if value.translation.width < -revealThreshold {
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

/// 日程卡片：固定三行（标题 / 时间 / 提醒），其余操作收进「…」菜单。
struct EventCardView: View {
    @EnvironmentObject private var chat: ChatStore
    @ObservedObject private var app = AppSettings.shared
    let messageId: UUID
    let snapshot: EventSnapshot
    var onTap: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var showRecurringDeleteOptions = false

    var body: some View {
        SwipeActionCard {
            if snapshot.recurrence != nil {
                showRecurringDeleteOptions = true
            } else {
                showDeleteConfirmation = true
            }
        } onEdit: {
            onTap()
        } content: {
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
            // 第 1 行：图标 + 标题（点击编辑）
            HStack(alignment: .center, spacing: 10) {
                Button(action: onTap) {
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
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(snapshot.deleted)


            }

            // 第 2 行：左“日期 周几”、右“起–止”（24 小时制），整行主题色
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Text(snapshot.start.cardDay)
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                    Text(timeRangeText)
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(orbitAccent())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(snapshot.deleted)

            // 第 3 行：提醒（灰色“提前” + 橙色时长 + 开关）
            if snapshot.deleted {
                Label("这个日程已从系统日历中删除", systemImage: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                conflictRow
                if snapshot.isPendingConfirmation {
                    HStack(spacing: 10) {
                        Text("未写入日历")
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
                        Button("编辑", action: onTap)
                            .buttonStyle(.bordered)
                            .font(.subheadline)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text("提醒")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if snapshot.reminderMinutes != nil {
                            // “提前”是普通灰字，放在 Menu 外面，避免被菜单 tint 染成主题色。
                            Text("提前")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
                            Text("已关闭")
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
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.systemBackground)))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
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
                        .foregroundStyle(.secondary)
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
