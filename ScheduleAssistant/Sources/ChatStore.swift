import Foundation
import SwiftUI
import UIKit

/// 聊天数据与处理管线
@MainActor
final class ChatStore: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isThinking = false
    @Published var calendarAccessDenied = false
    /// 通知中心点击后要求聚焦（并打开编辑）的消息；由 ChatView 消费。
    @Published var pendingFocusMessageId: UUID?
    /// 跳转定位到简报等非日程卡片时的高亮标记；几秒后自动清除。
    @Published var highlightMessageId: UUID?
    /// 检测到重复日程时的提醒文案（ChatView 以 alert 展示）。
    @Published var duplicateEventNotice: String?

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
        // iCloud 同步拉到较新的数据后热加载对话。
        NotificationCenter.default.addObserver(
            forName: .orbitSyncDidPull, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
    }

    /// 供 iCloud 同步后从磁盘重新读取。
    func reloadFromDisk() {
        load()
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
        if isRevisionRequest(trimmed), let target = latestEditableEventMessage() {
            processRevision(instruction: trimmed, targetIndex: target.index, snapshot: target.snapshot)
        } else {
            process(text: trimmed, image: nil)
        }
    }

    /// 短句 + 修正类动词开头 → 接续对话，直接修改上一条日程。
    private func isRevisionRequest(_ text: String) -> Bool {
        guard text.count <= 40 else { return false }
        let prefixes = ["修正", "修改", "改到", "改成", "改", "换成", "调整", "推迟", "提前", "删掉提醒", "加提醒"]
        return prefixes.contains { text.hasPrefix($0) }
    }

    private func latestEditableEventMessage() -> (index: Int, snapshot: EventSnapshot)? {
        for index in messages.indices.reversed() {
            guard messages[index].kind == .eventCard,
                  var snap = messages[index].event,
                  !snap.deleted, snap.eventIdentifier != nil else { continue }
            snap.conflicts = nil
            return (index, snap)
        }
        return nil
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
        // 第一层：纯文字必须同时具备“何时”与“做什么”的最基本线索。
        // 这能在请求模型前拦住问候、闲聊和 API 测试文字，避免被错误写成默认“会议”。
        if image == nil, let text, !looksLikeScheduleRequest(text) {
            appendSystemMessage("我还没有看到明确的日程。请告诉我“什么时候 + 做什么”，例如“明天上午 10 点门诊随访”；也可以发一张包含日程的图片。")
            save()
            return
        }
        let settings = LLMSettings.shared
        let provider = settings.activeProvider
        let config = settings.config(for: provider)
        isThinking = true
        messages.append(ChatMessage(role: .assistant, kind: .text, text: "…"))
        let thinkingIndex = messages.count - 1

        Task {
            do {
                let parsedEvents = try await provider.parseSchedule(text: text, image: image, config: config)
                // 第二层：模型回包不能缺少标题或明确的开始时间；低置信度和“凭空默认会议”
                // 不得进入 EventKit。图片允许由模型判断内容，但仍受结构校验约束。
                let events = parsedEvents.filter { isWriteEligible($0, sourceText: text) }
                guard !events.isEmpty else {
                    messages[thinkingIndex].text = "我没有识别到可确认写入的日程，所以不会新建任何事件。请补充具体的时间和事项，例如“明天上午 10 点门诊随访”。"
                    isThinking = false
                    save()
                    return
                }
                var snapshots: [EventSnapshot] = []
                for parsed in events {
                    snapshots.append(try await prepare(parsed: parsed))
                }
                // 说清楚就直接写入日历；只有写入失败时才降级为待确认卡片。
                // 与日历中已有日程重复（同日历同标题同时间）时绑定原日程，不再新建。
                var duplicates: [Bool] = []
                var duplicateTitles: [String] = []
                for index in snapshots.indices {
                    if linkToExistingIfDuplicate(&snapshots[index]) {
                        duplicates.append(true)
                        duplicateTitles.append(snapshots[index].title)
                    } else {
                        duplicates.append(false)
                        autoAddIfNeeded(&snapshots[index])
                    }
                }
                if !duplicateTitles.isEmpty {
                    let calendarTitle = snapshots.first?.calendarTitle ?? "日历"
                    duplicateEventNotice = "《\(duplicateTitles.joined(separator: "》《"))》已存在于「\(calendarTitle)」中，本次未重复添加。"
                }
                // 回复文案：单项详细说，多项汇总说
                if snapshots.count == 1 {
                    let snap = snapshots[0]
                    let timePart = snap.isAllDay ? "" : " \(snap.start.shortTime)"
                    let reminderPart = snap.reminderMinutes != nil ? "，会准时提醒您" : ""
                    let recurrencePart = snap.recurrence.map { "，\($0.displayText)循环" } ?? ""
                    let conflictPart = (snap.conflicts?.isEmpty == false)
                        ? "\n发现时间冲突，卡片里有可选的新时间建议。" : ""
                    let addedPart: String
                    if duplicates[0] {
                        addedPart = "检测到日历中已有相同日程，未重复添加；卡片已关联原日程。"
                    } else if snap.eventIdentifier != nil {
                        addedPart = "已写入「\(snap.calendarTitle)」，点卡片可随时修改。"
                    } else {
                        addedPart = "写入日历失败，请核对卡片后手动确认添加。"
                    }
                    messages[thinkingIndex].text = "《\(snap.title)》\(snap.start.friendlyDay)\(timePart)\(recurrencePart)\(reminderPart)\(conflictPart)\n\(addedPart)"
                } else {
                    let earliest = snapshots.min { $0.start < $1.start }!
                    let conflictCount = snapshots.reduce(0) { $0 + ($1.conflicts?.count ?? 0) }
                    let conflictPart = conflictCount > 0 ? "，其中发现 \(conflictCount) 个时间冲突，可在卡片中查看建议" : ""
                    let failedCount = zip(snapshots, duplicates).filter { $0.eventIdentifier == nil && !$1 }.count
                    let addedPart: String
                    if failedCount == 0, duplicateTitles.isEmpty {
                        addedPart = "均已写入日历，点卡片可随时修改。"
                    } else if !duplicateTitles.isEmpty, failedCount == 0 {
                        addedPart = "其中 \(duplicateTitles.count) 项在日历中已存在，未重复添加；其余已写入。"
                    } else {
                        addedPart = "其中 \(failedCount) 项写入失败，需在卡片中手动确认。"
                    }
                    messages[thinkingIndex].text = "已安排 \(snapshots.count) 项日程，最早《\(earliest.title)》\(earliest.start.friendlyDay) \(earliest.start.shortTime)\(conflictPart)。\(addedPart)"
                }
                for (index, snap) in snapshots.enumerated() {
                    messages.append(ChatMessage(role: .assistant, kind: .eventCard, event: snap))
                    if snap.eventIdentifier != nil, !duplicates[index] {
                        registerEventNotifications(snap, messageId: messages[messages.count - 1].id)
                    }
                }
            } catch {
                messages[thinkingIndex].text = userFacingErrorMessage(for: error)
                // 云端专属错误：直接引导登录 / 充值，而不只是留在对话里报错。
                if let llmError = error as? LLMError {
                    switch llmError {
                    case .insufficientPoints:
                        NotificationCenter.default.post(name: .orbitPointsStoreRequested, object: nil)
                    case .cloudNotReady:
                        NotificationCenter.default.post(name: .orbitAuthRequired, object: nil)
                    case .cloudKeyInvalid:
                        AccountStore.shared.invalidateCloudKey()
                    default:
                        break
                    }
                }
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

    /// 文本日程最低限度需要“时间线索 + 事项线索”。这不是解析器，只负责拒绝显然不是日程的输入。
    private func looksLikeScheduleRequest(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "。", with: "")
        let timeSignals = ["今天", "明天", "后天", "星期", "周一", "周二", "周三", "周四", "周五", "周六", "周日", "上午", "下午", "早上", "中午", "晚上", "凌晨", "每周", "每天", "tomorrow", "today", "am", "pm"]
        let activitySignals = ["开会", "会议", "门诊", "随访", "预约", "上课", "课程", "吃饭", "吃", "运动", "锻炼", "健身", "跑步", "工作", "上班", "复习", "学习", "考试", "提醒", "拜访", "出发", "接", "送", "看", "办理", "旅行", "聚", "约", "剪", "睡", "起床", "生日", "活动", "体检", "就诊", "治疗", "打电话", "电话", "提交", "购物", "买", "回家", "面试", "检查", "取", "拿", "见", "聊", "写", "读", "做", "meeting", "appointment", "class", "workout"]
        let hasClockOrDate = normalized.range(
            of: #"\d{1,2}[:：]\d{2}|\d{1,2}(点|时)|\d{1,2}月\d{1,2}(日|号)|\d{4}[-/]\d{1,2}[-/]\d{1,2}"#,
            options: .regularExpression
        ) != nil
        let hasTime = hasClockOrDate || timeSignals.contains { normalized.contains($0) }
        let hasActivity = activitySignals.contains { normalized.contains($0) }
        return hasTime && hasActivity
    }

    /// 第三层：即使模型已返回 JSON，也必须满足写入前的完整性约束。
    private func isWriteEligible(_ event: ParsedEvent, sourceText: String?) -> Bool {
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, event.resolvedStartDate != nil else { return false }
        if let confidence = event.confidence, confidence < 0.55 { return false }
        // 当输入文本从未出现会议语义时，拒绝模型凭空给出的通用“会议”标题。
        if ["会议", "日程", "事件", "安排"].contains(title), let sourceText {
            let matchingTerms = [title, "开会", "会诊", "组会"]
            guard matchingTerms.contains(where: { sourceText.contains($0) }) else { return false }
        }
        return true
    }

    /// 接续对话：把修正语和原日程交给模型，原地更新同一条日程与卡片。
    private func processRevision(instruction: String, targetIndex: Int, snapshot original: EventSnapshot) {
        let settings = LLMSettings.shared
        let provider = settings.activeProvider
        let config = settings.config(for: provider)
        isThinking = true
        messages.append(ChatMessage(role: .assistant, kind: .text, text: "…"))
        let thinkingIndex = messages.count - 1

        Task {
            do {
                let originalJSON = Self.snapshotJSON(original)
                let revised = try await provider.reviseEvent(originalJSON: originalJSON,
                                                             instruction: instruction,
                                                             config: config)
                guard var parsed = revised.first else {
                    messages[thinkingIndex].text = "没听懂要怎么改，试试直接说完整安排，比如“明天下午4点门诊随访”。"
                    isThinking = false
                    save()
                    return
                }
                // 保持原身份：同一条日历事件、同一张卡片、提醒规则不变。
                parsed.title = parsed.title.isEmpty ? original.title : parsed.title
                var snap = original
                snap.title = parsed.title
                snap.emoji = parsed.emoji ?? original.emoji
                snap.isAllDay = parsed.isAllDay ?? original.isAllDay
                snap.location = parsed.location ?? original.location
                snap.notes = parsed.notes ?? original.notes
                snap.recurrence = parsed.recurrence ?? original.recurrence
                let newStart = parsed.resolvedStartDate ?? original.start
                snap.start = newStart
                if parsed.isAllDay == true {
                    snap.end = Calendar.current.date(byAdding: .day, value: 1,
                                                     to: Calendar.current.startOfDay(for: newStart)) ?? newStart
                } else {
                    snap.end = parsed.resolvedEndDate ?? original.end
                }
                if snap.end <= snap.start { snap.end = snap.start.addingTimeInterval(3600) }
                refreshConflictMetadata(for: &snap)
                switch CalendarService.shared.updateEvent(
                    &snap,
                    updateRecurrence: snap.recurrence != original.recurrence
                ) {
                case .success:
                    messages[targetIndex].event = snap
                    let timePart = snap.isAllDay ? "" : " \(snap.start.shortTime)"
                    messages[thinkingIndex].text = "已按你的要求更新《\(snap.title)》→ \(snap.start.cardDay)\(timePart)。"
                    registerEventNotifications(snap, messageId: messages[targetIndex].id)
                case .failure(let error):
                    // 修改没有真正写进日历时保留原卡片并明确告知，不更新成“已修改”。
                    let detail = "《\(original.title)》的修改未能保存：\(error.localizedDescription)"
                    messages[thinkingIndex].text = detail
                    OrbitNotificationStore.shared.add(
                        kind: .writeFailure,
                        title: "日程修改失败",
                        detail: detail,
                        relatedMessageId: messages[targetIndex].id
                    )
                }
            } catch {
                messages[thinkingIndex].text = userFacingErrorMessage(for: error)
            }
            isThinking = false
            save()
        }
    }

    private static func snapshotJSON(_ snap: EventSnapshot) -> String {
        let iso = ISO8601DateFormatter()
        struct Original: Codable {
            var title: String
            var emoji: String
            var startDate: String
            var endDate: String
            var location: String?
            var notes: String?
            var isAllDay: Bool
            var recurrence: RecurrenceSpec?
        }
        let original = Original(
            title: snap.title, emoji: snap.emoji,
            startDate: iso.string(from: snap.start), endDate: iso.string(from: snap.end),
            location: snap.location, notes: snap.notes,
            isAllDay: snap.isAllDay, recurrence: snap.recurrence
        )
        guard let data = try? JSONEncoder().encode(original),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    /// 用户明确选择“忽略”冲突：清掉提示与改期建议，允许两件事并行。
    func ignoreConflicts(messageId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              var snap = messages[idx].event else { return }
        snap.conflicts = nil
        snap.suggestedStart = nil
        messages[idx].event = snap
        save()
    }

    /// 区分配置、网络、模型返回和日历错误，避免所有失败都被误导为 API Key 问题。
    private func userFacingErrorMessage(for error: Error) -> String {
        let detail = error.localizedDescription
        let guidance: String

        if let llmError = error as? LLMError {
            switch llmError {
            case .noAPIKey:
                guidance = "请到「设置 → 高级 → 自定义模型服务」填写当前服务商的 API Key；或切回 Orbit 云端服务。"
            case .http(let code, _):
                switch code {
                case 401, 403:
                    guidance = LLMSettings.shared.activeProvider.isCloudService
                        ? "云端对话令牌无效，请退出登录后重新登录领取。"
                        : "API Key 无效或没有访问权限，请检查当前服务商的凭证。"
                case 402:
                    guidance = "积分或 API 额度不足，可到积分商店充值。"
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
            case .cloudNotReady:
                guidance = "需要先登录 Orbit 账号才能使用云端 AI。登录页已打开，完成登录后请直接重试。"
            case .insufficientPoints:
                guidance = "积分不足，正在为你打开积分商店；充值后直接重试即可。"
            case .cloudKeyInvalid:
                guidance = "对话令牌已失效，已清掉本地令牌；下次重试会自动重新领取，若持续失败请退出登录再登录。"
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
        guard status.orbitCanWriteEvents else {
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
        // 上游 isWriteEligible 已验证；这里仍不使用 Date() 兜底，避免任意输入写成“现在”的日程。
        guard let start = parsed.resolvedStartDate else {
            throw NSError(domain: "orbit", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "日程缺少明确开始时间"])
        }
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
            calendarTitle: CalendarService.shared.calendarDisplayName(calendar),
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

    /// 自动写入前检查：与系统日历中已有日程重复（同日历、同标题、同开始时间）时
    /// 绑定原日程，不再新建，避免同一件事在日历里出现两份。
    private func linkToExistingIfDuplicate(_ snapshot: inout EventSnapshot) -> Bool {
        guard snapshot.eventIdentifier == nil,
              let existing = CalendarService.shared.findDuplicate(of: snapshot) else { return false }
        snapshot.eventIdentifier = existing
        return true
    }

    /// 识别后立即尝试写入日历；失败时保持待确认状态，由用户在卡片上手动确认。
    private func autoAddIfNeeded(_ snapshot: inout EventSnapshot) {
        guard snapshot.eventIdentifier == nil, !snapshot.deleted else { return }
        if case .success(let identifier) = CalendarService.shared.createEvent(snapshot) {
            snapshot.eventIdentifier = identifier
        }
    }

    func confirmEvent(messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
              var snapshot = messages[index].event,
              snapshot.eventIdentifier == nil else { return }
        switch CalendarService.shared.createEvent(snapshot) {
        case .success(let identifier):
            snapshot.eventIdentifier = identifier
            messages[index].event = snapshot
            registerEventNotifications(snapshot, messageId: messageId)
            save()
        case .failure(let error):
            let detail = "《\(snapshot.title)》未能写入「\(snapshot.calendarTitle)」：\(error.localizedDescription)"
            OrbitNotificationStore.shared.add(kind: .writeFailure, title: "日历写入失败", detail: detail, relatedMessageId: messageId)
            appendSystemMessage(detail)
            save()
        }
    }

    /// 写入成功后的通知登记（自动添加和手动确认共用）。
    private func registerEventNotifications(_ snapshot: EventSnapshot, messageId: UUID) {
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
    }

    func updateMessage(_ messageId: UUID, event: EventSnapshot) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[idx].event = event
        save()
    }

    /// 从“今天”页打开系统日历事件：复用已有卡片，找不到时建立一张可编辑卡片。
    @discardableResult
    func ensureEventCard(for imported: EventSnapshot) -> UUID {
        var snapshot = imported
        refreshConflictMetadata(for: &snapshot)

        if let identifier = imported.eventIdentifier,
           let index = messages.firstIndex(where: { $0.event?.eventIdentifier == identifier }) {
            if let existing = messages[index].event {
                snapshot.emoji = existing.emoji
                snapshot.nativeReminderIdentifier = existing.nativeReminderIdentifier
            }
            messages[index].event = snapshot
            save()
            return messages[index].id
        }

        let message = ChatMessage(role: .assistant, kind: .eventCard, event: snapshot)
        messages.append(message)
        save()
        return message.id
    }

    func toggleReminder(messageId: UUID, on: Bool) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              var snap = messages[idx].event else { return }
        let minutes = on ? (snap.reminderMinutes ?? AppSettings.shared.defaultReminderMinutes) : nil
        if case .failure(let error) = CalendarService.shared.setReminder(snapshot: snap, minutes: minutes) {
            reportWriteFailure(messageId: messageId, action: "设置提醒", snapshot: snap, error: error)
            return
        }
        snap.reminderMinutes = minutes
        snap.alarmOffsets = minutes.map { [TimeInterval(-$0 * 60)] } ?? []
        messages[idx].event = snap
        save()
    }

    func changeReminderDuration(messageId: UUID, minutes: Int) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              var snap = messages[idx].event else { return }
        if case .failure(let error) = CalendarService.shared.setReminder(snapshot: snap, minutes: minutes) {
            reportWriteFailure(messageId: messageId, action: "修改提醒", snapshot: snap, error: error)
            return
        }
        snap.reminderMinutes = minutes
        snap.alarmOffsets = [TimeInterval(-minutes * 60)]
        messages[idx].event = snap
        save()
    }

    func changeCalendar(messageId: UUID, to calendarId: String) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              var snap = messages[idx].event else { return }
        if snap.eventIdentifier == nil {
            guard let calendar = CalendarService.shared.availableCalendars().first(where: { $0.calendarIdentifier == calendarId }) else { return }
            snap.calendarIdentifier = calendarId
            snap.calendarTitle = CalendarService.shared.calendarDisplayName(calendar)
        } else if case .failure(let error) = CalendarService.shared.moveToCalendar(snapshot: &snap, to: calendarId) {
            reportWriteFailure(messageId: messageId, action: "移动日历", snapshot: snap, error: error)
            return
        }
        messages[idx].event = snap
        save()
    }

    func applyEdit(messageId: UUID, snapshot: EventSnapshot, updateRecurrence: Bool = false) {
        var snap = snapshot
        refreshConflictMetadata(for: &snap)
        if snap.eventIdentifier != nil,
           case .failure(let error) = CalendarService.shared.updateEvent(&snap, updateRecurrence: updateRecurrence) {
            // 保存失败时保留卡片原状，由用户决定重试或放弃，不更新成“已修改”。
            reportWriteFailure(messageId: messageId, action: "修改", snapshot: snapshot, error: error)
            return
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
        if case .failure(let error) = CalendarService.shared.deleteEvent(snapshot: snap, includingFuture: includingFuture) {
            // 日历里的事件还在，不能把卡片标成“已删除”。
            reportWriteFailure(messageId: messageId, action: "删除", snapshot: snap, error: error)
            return
        }
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
        let index: Int
        if let existing = messages.firstIndex(where: {
            $0.kind == .briefing && calendar.isDate($0.createdAt, inSameDayAs: date)
        }) {
            messages[existing].text = text
            index = existing
        } else {
            messages.append(ChatMessage(role: .assistant, kind: .briefing, text: text, createdAt: date))
            index = messages.count - 1
        }
        let key = date.formatted(.iso8601.year().month().day())
        OrbitNotificationStore.shared.add(kind: .briefing, title: "今日简报", detail: "\(key) · \(text)", relatedMessageId: messages[index].id, dailyKey: key)
        save()
    }

    /// 每日晚报：过了设定时间且今天还没生成过时，以对话卡片形式插入。
    func upsertEveningBriefingIfDue(from briefing: DailyBriefingStore) {
        guard AppSettings.shared.eveningBriefingEnabled else { return }
        let calendar = Calendar.current
        let now = Date()
        let due = calendar.date(bySettingHour: AppSettings.shared.eveningBriefingTime.hour,
                                 minute: AppSettings.shared.eveningBriefingTime.minute,
                                 second: 0, of: now) ?? now
        guard now >= due else { return }
        if messages.contains(where: { $0.kind == .eveningBriefing && calendar.isDate($0.createdAt, inSameDayAs: now) }) {
            return
        }
        let events = briefing.todayEvents
        let remaining = events.filter { $0.end > now }.count
        let taskPart: String
        if events.isEmpty {
            taskPart = "今天没有固定日程，希望你也给自己留出了喘息的时间。"
        } else if remaining > 0 {
            taskPart = "今天大部分行程已经走完，还有 \(remaining) 项尚未结束，收尾后就安心休息吧。"
        } else if events.count >= 5 {
            taskPart = "今天的轨道很满，但这些安排现在都已经告一段落了。"
        } else {
            taskPart = "今天的安排已经走完，可以把注意力从日程表上移开了。"
        }
        var parts = ["晚上好。\(taskPart)"]
        let summary = events.count >= 5
            ? "今天节奏不慢，睡前的放松也是日程的一部分。"
            : "把今天放一放，明天的事明天再轨道上见。"
        parts.append(summary)
        parts.append(DailyBriefingStore.goodnightLine(for: now))
        let text = parts.joined(separator: "\n")
        messages.append(ChatMessage(role: .assistant, kind: .eveningBriefing, text: text, createdAt: now))
        let messageId = messages[messages.count - 1].id
        let key = now.formatted(.iso8601.year().month().day())
        OrbitNotificationStore.shared.add(kind: .briefing, title: "今日晚报", detail: text, relatedMessageId: messageId, dailyKey: key + "-evening")
        save()
    }

    func clearConversation() {
        messages = [ChatMessage(role: .assistant, kind: .text, text: "新的对话已经开始。告诉我你的安排吧。")]
        save()
    }

    func upsertDailyBriefing(from briefing: DailyBriefingStore) {
        guard AppSettings.shared.morningBriefingEnabled else { return }
        let now = Date()
        let calendar = Calendar.current
        let due = calendar.date(bySettingHour: AppSettings.shared.morningBriefingTime.hour,
                                minute: AppSettings.shared.morningBriefingTime.minute,
                                second: 0,
                                of: now) ?? now
        // 只有到达用户设定的晨报时间后，才在对话里生成；提前打开 App 不会产生一条错误的“晨报”。
        guard now >= due else { return }
        let weekday = calendar.component(.weekday, from: now)
        if !AppSettings.shared.morningBriefingOnWeekends && (weekday == 1 || weekday == 7) { return }

        // 问候语按“设定的晨报时间”推算，而不是当下钟点，
        // 避免下午才打开 App 时早报第一句错写成“下午好”。
        var parts = ["\(DailyBriefingStore.greeting(forScheduledHour: AppSettings.shared.morningBriefingTime.hour))。"]
        if AppSettings.shared.weatherBriefingEnabled, let weather = briefing.weatherText {
            parts.append(weather)
        }
        parts.append(briefing.scheduleSummary)
        if let span = briefing.daySpanSummary {
            parts.append(span)
        }
        let conflicts = allEvents.filter {
            Calendar.current.isDateInToday($0.snapshot.start) && $0.snapshot.conflicts?.isEmpty == false
        }.count
        if AppSettings.shared.morningBriefingShowsConflicts && conflicts > 0 {
            parts.append("今天有 \(conflicts) 项安排存在时间冲突，请提前确认。")
        }
        parts.append(DailyBriefingStore.cheerLine(for: now))
        let text = parts.joined(separator: "\n")
        let index: Int
        if let existing = messages.firstIndex(where: {
            $0.kind == .briefing && calendar.isDateInToday($0.createdAt)
        }) {
            messages[existing].text = text
            index = existing
        } else {
            messages.append(ChatMessage(role: .assistant, kind: .briefing, text: text))
            index = messages.count - 1
        }
        let key = Date().formatted(.dateTime.year().month().day())
        OrbitNotificationStore.shared.add(
            kind: .briefing,
            title: "今日简报",
            detail: "\(key) · \(briefing.scheduleSummary)",
            relatedMessageId: messages[index].id,
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

    /// 日历写操作失败时的统一出口：通知中心 + 对话提示；卡片保持原状，绝不假报成功。
    private func reportWriteFailure(messageId: UUID, action: String, snapshot: EventSnapshot, error: Error) {
        let detail = "《\(snapshot.title)》\(action)未生效：\(error.localizedDescription)"
        OrbitNotificationStore.shared.add(kind: .writeFailure, title: "日历\(action)失败", detail: detail, relatedMessageId: messageId)
        appendSystemMessage(detail)
        save()
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
