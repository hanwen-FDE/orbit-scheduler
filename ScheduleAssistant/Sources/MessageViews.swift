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
        case .eventCard:
            if let snap = message.event {
                EventCardView(messageId: message.id, snapshot: snap, onTap: onTapCard)
            }
        }
    }

    private var bubbleShape: some Shape {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }
}

/// 日程卡片
struct EventCardView: View {
    @EnvironmentObject private var chat: ChatStore
    let messageId: UUID
    let snapshot: EventSnapshot
    var onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题
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
            .padding(.bottom, 12)

            Divider()

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
            }
            .padding(.vertical, 12)

            Divider()

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

            Divider()

            // 更改日历
            HStack {
                Menu {
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
                } label: {
                    Label("修改日程", systemImage: "calendar.badge.plus")
                        .font(.subheadline)
                }
                Spacer()
                Text(snapshot.deleted ? "已删除" : "已添加到「\(snapshot.calendarTitle)」")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.systemBackground)))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(12)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
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
