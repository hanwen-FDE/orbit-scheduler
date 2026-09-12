import Foundation
import SwiftUI
import UIKit

/// 聊天数据与处理管线
@MainActor
final class ChatStore: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isThinking = false
    @Published var calendarAccessDenied = false

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("orbit-chat.json")
        load()
        if messages.isEmpty {
            messages = [ChatMessage(
                role: .assistant, kind: .text,
                text: "你好，我是 Orbit 🪐\n所有计划，运行于时间轨道。\n告诉我你的安排，我来帮你写进日历——\n例如：下周三下午3点在门诊三楼开课题会"
            )]
        }
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([ChatMessage].self, from: data) else { return }
        messages = saved
    }

    private func save() {
        if let data = try? JSONEncoder().encode(messages) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - 发送入口

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(role: .user, kind: .text, text: trimmed))
        save()
        process(text: trimmed, image: nil)
    }

    func send(image: UIImage) {
        // 持久化用小缩略图；识别用可读版本
        let thumb = Self.downscale(image, maxSide: 420)?.jpegData(compressionQuality: 0.5)
        messages.append(ChatMessage(role: .user, kind: .image, text: "", imageData: thumb))
        save()
        process(text: nil, image: Self.downscale(image, maxSide: 900))
    }

    func send(voiceTranscript: String, duration: TimeInterval = 0) {
        let trimmed = voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(role: .user, kind: .voice, text: trimmed, voiceDuration: duration))
        save()
        process(text: trimmed, image: nil)
    }

    func retryLast() {
        // 找最近一条用户消息重新识别
        if let lastUser = messages.last(where: { $0.role == .user }) {
            var img: UIImage?
            if lastUser.kind == .image, let data = lastUser.imageData {
                img = UIImage(data: data)
            }
            process(text: (lastUser.kind == .text || lastUser.kind == .voice) ? lastUser.text : nil, image: img)
        }
    }

    // MARK: - 识别管线

    private func process(text: String?, image: UIImage?) {
        let settings = LLMSettings.shared
        let provider = settings.activeProvider
        let config = settings.config(for: provider)
        isThinking = true
        messages.append(ChatMessage(role: .assistant, kind: .text, text: "…"))
        let thinkingIndex = messages.count - 1

        Task {
            do {
                let events = try await provider.parseSchedule(text: text, image: image, config: config)
                guard !events.isEmpty else {
                    messages[thinkingIndex].text = "这段内容里我没找到日程信息，换个说法试试？例如：明天上午10点开会"
                    isThinking = false
                    save()
                    return
                }
                var snapshots: [EventSnapshot] = []
                for parsed in events {
                    snapshots.append(try await prepare(parsed: parsed))
                }
                // 回复文案：单项详细说，多项汇总说
                if snapshots.count == 1 {
                    let snap = snapshots[0]
                    let timePart = snap.isAllDay ? "" : " \(snap.start.shortTime)"
                    let reminderPart = snap.reminderMinutes != nil ? "，会准时提醒您" : ""
                    let recurrencePart = snap.recurrence.map { "，\($0.displayText)循环" } ?? ""
                    let conflictPart = (snap.conflicts?.isEmpty == false)
                        ? "\n发现时间冲突，卡片里有可选的新时间建议。" : ""
                    messages[thinkingIndex].text = "已识别《\(snap.title)》\(snap.start.friendlyDay)\(timePart)\(recurrencePart)\(reminderPart)。请核对卡片后确认添加。\(conflictPart)"
                } else {
                    let earliest = snapshots.min { $0.start < $1.start }!
                    let conflictCount = snapshots.reduce(0) { $0 + ($1.conflicts?.count ?? 0) }
                    let conflictPart = conflictCount > 0 ? "，其中发现 \(conflictCount) 个时间冲突，可在卡片中查看建议" : ""
                    messages[thinkingIndex].text = "已识别 \(snapshots.count) 项日程，最早《\(earliest.title)》\(earliest.start.friendlyDay) \(earliest.start.shortTime)。请逐项核对并确认添加\(conflictPart)"
                }
                for snap in snapshots {
                    messages.append(ChatMessage(role: .assistant, kind: .eventCard, event: snap))
                }
            } catch {
                messages[thinkingIndex].text = userFacingErrorMessage(for: error)
                OrbitNotificationStore.shared.add(
                    kind: .aiFailure,
                    title: "AI 处理失败",
                    detail: messages[thinkingIndex].text,
                    relatedMessageId: messages[thinkingIndex].id
                )
            }
            isThinking = false
            save()
        }
    }

    /// 区分配置、网络、模型返回和日历错误，避免所有失败都被误导为 API Key 问题。
    private func userFacingErrorMessage(for error: Error) -> String {
        let detail = error.localizedDescription
        let guidance: String

        if let llmError = error as? LLMError {
            switch llmError {
            case .noAPIKey:
                guidance = "请在左上角的 AI 识别（API）中填写当前服务商的 API Key。"
            case .http(let code, _):
                switch code {
                case 401, 403:
                    guidance = "API Key 无效或没有访问权限，请检查当前服务商的凭证。"
                case 402:
                    guidance = "API 账户余额或额度不足。"
                case 408:
                    guidance = "请求超时，原始输入已保留，可以直接重试。"
                case 429:
                    guidance = "请求过于频繁或额度受限，请稍后重试。"
                case 500...599:
                    guidance = "AI 服务暂时不可用，请稍后重试；这不代表 API Key 配置错误。"
                default:
                    guidance = "请检查服务商、模型名和接口地址后重试。"
                }
            case .invalidResponse:
                guidance = "AI 服务已响应，但返回内容无法识别。请重试，或更换支持当前模型的服务商。"
            case .noInput:
                guidance = "请输入文字或选择图片后再试。"
            }
        } else if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                guidance = "当前没有可用网络，原始输入已保留。恢复网络后直接重试即可。"
            case .timedOut:
                guidance = "网络请求超时，这不代表 API Key 错误，请直接重试。"
            case .cannotFindHost, .dnsLookupFailed:
                guidance = "无法连接服务商地址，请检查接口地址、DNS 或代理设置。"
            case .cancelled:
                guidance = "请求已取消，原始输入仍然保留。"
            default:
                guidance = "网络请求失败；API 测试成功时无需重新填写 Key。"
            }
        } else {
            guidance = "可以点这里重试；若持续发生，请检查日历权限和系统日历账户。"
        }

        return "出错了：\(detail)\n\(guidance)"
    }

    /// 自动写入默认日历；权限或日历不可用时降级为未写入卡片
    private func prepare(parsed: ParsedEvent) async throws -> EventSnapshot {
        let status = await CalendarService.shared.ensureAccess()
        guard status == .fullAccess || status == .writeOnly else {
            calendarAccessDenied = true
            throw NSError(domain: "orbit", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "日历权限未开启：设置 → Orbit → 日历 → 完全访问"])
        }
        let calendars = CalendarService.shared.availableCalendars()
        let preferred = calendars.first { $0.calendarIdentifier == AppSettings.shared.defaultCalendarId } ?? calendars.first
        guard let calendar = preferred else {
            throw NSError(domain: "orbit", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "没有可写入的日历，请在系统日历中确认已登录账户"])
        }
        let start = parsed.resolvedStartDate ?? Date()
        let end: Date
        if parsed.isAllDay == true {
            end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: start)) ?? start
        } else {
            end = parsed.resolvedEndDate ?? start.addingTimeInterval(3600)
        }
        var snapshot = EventSnapshot(
            title: parsed.title,
            emoji: parsed.emoji ?? "📅",
            start: start, end: end,
            isAllDay: parsed.isAllDay ?? false,
            location: parsed.location,
            notes: parsed.notes,
            reminderMinutes: AppSettings.shared.defaultReminderMinutes,
            calendarIdentifier: calendar.calendarIdentifier,
            calendarTitle: calendar.title,
            recurrence: parsed.recurrence
        )
        // 写入前检查，不自动改动用户指定时间；冲突和建议只显示在卡片中供用户决定。
        let conflicts = CalendarService.shared.conflicts(for: snapshot)
        snapshot.conflicts = conflicts
        if !conflicts.isEmpty {
            snapshot.suggestedStart = CalendarService.shared.suggestedStart(for: snapshot)
        }
        return snapshot
    }

    // MARK: - 卡片操作

    func confirmEvent(messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
              var snapshot = messages[index].event,
              snapshot.eventIdentifier == nil else { return }
        guard let identifier = CalendarService.shared.createEvent(snapshot) else {
            let detail = "《\(snapshot.title)》未能写入「\(snapshot.calendarTitle)」，请检查日历权限或更换目标日历后重试。"
            OrbitNotificationStore.shared.add(kind: .writeFailure, title: "日历写入失败", detail: detail, relatedMessageId: messageId)
            appendSystemMessage(detail)
            save()
            return
        }
        snapshot.eventIdentifier = identifier
        messages[index].event = snapshot
        OrbitNotificationStore.shared.add(
            kind: .reminder,
            title: snapshot.title,
            detail: "\(snapshot.start.friendlyDay) \(snapshot.isAllDay ? "全天" : snapshot.start.shortTime) · 已添加到「\(snapshot.calendarTitle)」",
            relatedMessageId: messageId
        )
        if snapshot.conflicts?.isEmpty == false {
            OrbitNotificationStore.shared.add(
                kind: .conflict,
                title: "《\(snapshot.title)》存在时间冲突",
                detail: "与 \(snapshot.conflicts?.count ?? 0) 项安排重叠，请查看重排建议。",
                relatedMessageId: messageId
            )
        }
        appendSystemMessage("已添加《\(snapshot.title)》到「\(snapshot.calendarTitle)」。")
        save()
    }

    func updateMessage(_ messageId: UUID, event: EventSnapshot) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[idx].event = event
        save()
    }

    func toggleReminder(messageId: UUID, on: Bool) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              var snap = messages[idx].event else { return }
        let minutes = on ? (snap.reminderMinutes ?? AppSettings.shared.defaultReminderMinutes) : nil
        CalendarService.shared.setReminder(snapshot: snap, minutes: minutes)
        snap.reminderMinutes = minutes
        messages[idx].event = snap
        save()
    }

    func changeReminderDuration(messageId: UUID, minutes: Int) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              var snap = messages[idx].event else { return }
        CalendarService.shared.setReminder(snapshot: snap, minutes: minutes)
        snap.reminderMinutes = minutes
        messages[idx].event = snap
        save()
    }

    func changeCalendar(messageId: UUID, to calendarId: String) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              var snap = messages[idx].event else { return }
        if snap.eventIdentifier == nil {
            guard let calendar = CalendarService.shared.availableCalendars().first(where: { $0.calendarIdentifier == calendarId }) else { return }
            snap.calendarIdentifier = calendarId
            snap.calendarTitle = calendar.title
        } else {
            guard CalendarService.shared.moveToCalendar(snapshot: &snap, to: calendarId) else { return }
        }
        messages[idx].event = snap
        save()
    }

    func applyEdit(messageId: UUID, snapshot: EventSnapshot) {
        var snap = snapshot
        refreshConflictMetadata(for: &snap)
        if snap.eventIdentifier != nil {
            CalendarService.shared.updateEvent(&snap)
        }
        updateMessage(messageId, event: snap)
        resyncNativeReminderIfNeeded(messageId: messageId, snapshot: snap)
    }

    func applySuggestedTime(messageId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              var snap = messages[idx].event,
              let suggestedStart = snap.suggestedStart else { return }
        let duration = snap.end.timeIntervalSince(snap.start)
        snap.start = suggestedStart
        snap.end = suggestedStart.addingTimeInterval(duration)
        applyEdit(messageId: messageId, snapshot: snap)
    }

    func refreshConflicts(messageId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              var snap = messages[idx].event else { return }
        refreshConflictMetadata(for: &snap)
        messages[idx].event = snap
        save()
    }

    /// 左滑删除：同时删除日历事件
    func deleteEventMessage(_ messageId: UUID, includingFuture: Bool = false) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              var snap = messages[idx].event else { return }
        CalendarService.shared.deleteEvent(snapshot: snap, includingFuture: includingFuture)
        if includingFuture {
            RemindersService.shared.deleteReminder(identifier: snap.nativeReminderIdentifier)
        }
        snap.deleted = true
        messages[idx].event = snap
        save()
    }

    // MARK: - 原生提醒事项与循环习惯

    func syncToNativeReminders(messageId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              let snap = messages[idx].event else { return }
        Task {
            do {
                let identifier = try await RemindersService.shared.sync(event: snap)
                guard let latestIndex = messages.firstIndex(where: { $0.id == messageId }),
                      var latest = messages[latestIndex].event else { return }
                latest.nativeReminderIdentifier = identifier
                messages[latestIndex].event = latest
                save()
            } catch {
                appendSystemMessage("未能同步到系统提醒事项：\(error.localizedDescription)")
            }
        }
    }

    func removeNativeReminder(messageId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              var snap = messages[idx].event else { return }
        RemindersService.shared.deleteReminder(identifier: snap.nativeReminderIdentifier)
        snap.nativeReminderIdentifier = nil
        messages[idx].event = snap
        save()
    }

    func createHabit(title: String, start: Date, recurrence: RecurrenceSpec, notes: String? = nil) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                var habit = HabitSnapshot(
                    title: trimmed,
                    emoji: "🌱",
                    start: start,
                    recurrence: recurrence,
                    notes: notes
                )
                habit.reminderIdentifier = try await RemindersService.shared.createHabit(habit)
                messages.append(ChatMessage(role: .assistant, kind: .habitCard, habit: habit))
                appendSystemMessage("已建立循环习惯《\(habit.title)》，它会出现在系统“提醒事项”App 中。")
                save()
            } catch {
                appendSystemMessage("未能建立习惯提醒：\(error.localizedDescription)")
            }
        }
    }

    func deleteHabitMessage(_ messageId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              var habit = messages[idx].habit else { return }
        RemindersService.shared.deleteReminder(identifier: habit.reminderIdentifier)
        habit.deleted = true
        messages[idx].habit = habit
        save()
    }

    /// 抽屉"日程管理"数据源
    var allEvents: [(messageId: UUID, snapshot: EventSnapshot)] {
        messages.compactMap { msg in
            guard msg.kind == .eventCard, let e = msg.event, !e.deleted else { return nil }
            return (msg.id, e)
        }.sorted { $0.snapshot.start < $1.snapshot.start }
    }

    func ensureDailyBriefing(text: String, date: Date = Date()) {
        guard AppSettings.shared.morningBriefingEnabled else { return }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        if !AppSettings.shared.morningBriefingOnWeekends && (weekday == 1 || weekday == 7) { return }
        let existing = messages.firstIndex {
            $0.kind == .briefing && calendar.isDate($0.createdAt, inSameDayAs: date)
        }
        if let existing {
            messages[existing].text = text
        } else {
            messages.append(ChatMessage(role: .assistant, kind: .briefing, text: text, createdAt: date))
        }
        let key = date.formatted(.iso8601.year().month().day())
        OrbitNotificationStore.shared.add(kind: .briefing, title: "今日简报", detail: "\(key) · \(text)", dailyKey: key)
        save()
    }

    func clearConversation() {
        messages = [ChatMessage(role: .assistant, kind: .text, text: "新的对话已经开始。告诉我你的安排吧。")]
        save()
    }

    func upsertDailyBriefing(from briefing: DailyBriefingStore) {
        guard AppSettings.shared.morningBriefingEnabled else { return }
        let weekday = Calendar.current.component(.weekday, from: Date())
        if !AppSettings.shared.morningBriefingOnWeekends && (weekday == 1 || weekday == 7) { return }

        var parts = ["\(briefing.greeting)。"]
        if AppSettings.shared.weatherBriefingEnabled {
            parts.append(briefing.weatherText ?? "天气暂时无法获取。")
        }
        parts.append(briefing.scheduleSummary)
        let conflicts = allEvents.filter {
            Calendar.current.isDateInToday($0.snapshot.start) && $0.snapshot.conflicts?.isEmpty == false
        }.count
        if AppSettings.shared.morningBriefingShowsConflicts && conflicts > 0 {
            parts.append("今天有 \(conflicts) 项安排存在时间冲突，请提前确认。")
        }
        if AppSettings.shared.morningBriefingShowsEncouragement {
            parts.append(briefing.encouragement)
        }
        let text = parts.joined(separator: "\n")
        if let index = messages.firstIndex(where: {
            $0.kind == .briefing && Calendar.current.isDateInToday($0.createdAt)
        }) {
            messages[index].text = text
        } else {
            messages.append(ChatMessage(role: .assistant, kind: .briefing, text: text))
        }
        let key = Date().formatted(.dateTime.year().month().day())
        OrbitNotificationStore.shared.add(
            kind: .briefing,
            title: "今日简报",
            detail: "\(key) · \(briefing.scheduleSummary)",
            dailyKey: key
        )
        save()
    }

    private func refreshConflictMetadata(for snapshot: inout EventSnapshot) {
        let conflicts = CalendarService.shared.conflicts(for: snapshot)
        snapshot.conflicts = conflicts
        snapshot.suggestedStart = conflicts.isEmpty
            ? nil : CalendarService.shared.suggestedStart(for: snapshot)
    }

    private func appendSystemMessage(_ text: String) {
        messages.append(ChatMessage(role: .assistant, kind: .text, text: text))
    }

    private func resyncNativeReminderIfNeeded(messageId: UUID, snapshot: EventSnapshot) {
        guard snapshot.nativeReminderIdentifier != nil else { return }
        Task {
            do {
                let identifier = try await RemindersService.shared.sync(event: snapshot)
                guard let idx = messages.firstIndex(where: { $0.id == messageId }),
                      var latest = messages[idx].event else { return }
                latest.nativeReminderIdentifier = identifier
                messages[idx].event = latest
                save()
            } catch {
                appendSystemMessage("日程已修改，但同步系统提醒事项失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - 工具

    static func downscale(_ image: UIImage, maxSide: CGFloat) -> UIImage? {
        let side = max(image.size.width, image.size.height)
        guard side > maxSide else { return image }
        let scale = maxSide / side
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
