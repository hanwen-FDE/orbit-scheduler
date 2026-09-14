import Foundation
import EventKit

/// EventKit 写操作失败原因。上层必须据此提示用户；
/// 任何写、改、删都不允许静默失败或在界面上假报成功。
enum CalendarWriteError: LocalizedError, Equatable {
    /// 原事件已不在系统日历中（多半是用户在系统日历里删掉了）。
    case eventNotFound
    /// 目标日历只读（订阅、他人共享等），不能写入或修改。
    case calendarReadOnly(String)
    /// 目标日历已不存在（被删除或账户退出）。
    case calendarUnavailable(String)
    /// EventKit 保存失败（权限、账户、存储等原因）。
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .eventNotFound:
            return "原日程已不在系统日历中（可能刚被删除）。为避免产生重复日程，Orbit 不会自动重建，请重新发送完整安排。"
        case .calendarReadOnly(let title):
            return "日历「\(title)」是只读日历（订阅或他人共享），不能在 Orbit 中修改。"
        case .calendarUnavailable(let title):
            return "找不到目标日历「\(title)」，它可能已被删除或账户已退出登录。"
        case .saveFailed(let reason):
            return "写入系统日历失败：\(reason)"
        }
    }
}

/// 系统日历读写（EventKit）
final class CalendarService {
    static let shared = CalendarService()
    let store = EKEventStore()

    /// 确保已触发权限请求；返回当前授权状态（iOS 17+：完全访问 / 仅写入）
    func ensureAccess() async -> EKAuthorizationStatus {
        var status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            if #available(iOS 17.0, *) {
                _ = try? await store.requestFullAccessToEvents()
            } else {
                // iOS 15/16 的统一授权入口；已废弃但在旧系统是唯一选择。
                _ = await withCheckedContinuation { continuation in
                    store.requestAccess(to: .event) { _, _ in continuation.resume() }
                }
            }
            status = EKEventStore.authorizationStatus(for: .event)
        }
        return status
    }

    /// 可写入的日历列表；"仅写入"授权下列表为空，退回系统默认日历
    func availableCalendars() -> [EKCalendar] {
        let writable = store.calendars(for: .event).filter { $0.allowsContentModifications }
        if !writable.isEmpty { return writable }
        if let def = store.defaultCalendarForNewEvents, def.allowsContentModifications {
            return [def]
        }
        return []
    }

    func calendarTitle(id: String) -> String? {
        store.calendar(withIdentifier: id)?.title
    }

    /// 手机上全部日历（含只读，供“读取哪些日历”设置展示）。
    func readableCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
    }

    /// 用户勾选的可见日历；nil 或空 = 不限制（全部读取）。
    private var visibleFilter: [EKCalendar]? {
        guard let ids = UserDefaults.standard.stringArray(forKey: "orbit.visibleCalendarIds"),
              !ids.isEmpty else { return nil }
        var set = Set(ids)
        if let defaultId = UserDefaults.standard.string(forKey: "orbit.defaultCalendarId") {
            set.insert(defaultId)
        }
        let all = store.calendars(for: .event)
        let picked = all.filter { set.contains($0.calendarIdentifier) }
        return picked.isEmpty ? nil : picked
    }

    // MARK: - 事件 CRUD

    @discardableResult
    func createEvent(_ snapshot: EventSnapshot) -> Result<String, CalendarWriteError> {
        let calendar = store.calendar(withIdentifier: snapshot.calendarIdentifier)
            ?? store.defaultCalendarForNewEvents
        guard let calendar, calendar.allowsContentModifications else {
            return .failure(.calendarReadOnly(snapshot.calendarTitle))
        }
        let event = EKEvent(eventStore: store)
        apply(snapshot, to: event, updateRecurrence: true)
        do {
            try store.save(event, span: .thisEvent)
            guard let identifier = event.eventIdentifier else {
                return .failure(.saveFailed("保存后未能取得日程标识"))
            }
            return .success(identifier)
        } catch {
            return .failure(.saveFailed(error.localizedDescription))
        }
    }

    /// `span` 为 nil 时按原有规则推断（循环日程 = 这一项及以后）。
    /// 原事件找不到时**绝不自动重建**，交由上层提示用户，避免制造重复日程。
    @discardableResult
    func updateEvent(
        _ snapshot: inout EventSnapshot,
        updateRecurrence: Bool = false,
        span overrideSpan: EKSpan? = nil
    ) -> Result<Void, CalendarWriteError> {
        guard let id = snapshot.eventIdentifier,
              let event = store.event(withIdentifier: id) else {
            return .failure(.eventNotFound)
        }
        guard event.calendar.allowsContentModifications else {
            return .failure(.calendarReadOnly(event.calendar.title))
        }
        apply(snapshot, to: event, updateRecurrence: updateRecurrence)
        // 对循环事件，编辑的是“这一项及后续”，避免只修改某一次后
        // 让卡片中的循环规则与系统日历中的规则脱节。
        let span: EKSpan = overrideSpan
            ?? ((snapshot.recurrence != nil || event.hasRecurrenceRules) ? .futureEvents : .thisEvent)
        do {
            try store.save(event, span: span)
            return .success(())
        } catch {
            return .failure(.saveFailed(error.localizedDescription))
        }
    }

    /// 找不到原事件视为目标已达成（它已不在日历里），其余失败必须上报。
    @discardableResult
    func deleteEvent(snapshot: EventSnapshot, includingFuture: Bool = false) -> Result<Void, CalendarWriteError> {
        guard let id = snapshot.eventIdentifier,
              let event = store.event(withIdentifier: id) else {
            return .success(())
        }
        guard event.calendar.allowsContentModifications else {
            return .failure(.calendarReadOnly(event.calendar.title))
        }
        do {
            try store.remove(event, span: includingFuture ? .futureEvents : .thisEvent)
            return .success(())
        } catch {
            return .failure(.saveFailed(error.localizedDescription))
        }
    }

    /// 增删提醒闹钟；minutes=nil 移除全部提醒
    @discardableResult
    func setReminder(snapshot: EventSnapshot, minutes: Int?) -> Result<Void, CalendarWriteError> {
        guard let id = snapshot.eventIdentifier,
              let event = store.event(withIdentifier: id) else {
            return .failure(.eventNotFound)
        }
        guard event.calendar.allowsContentModifications else {
            return .failure(.calendarReadOnly(event.calendar.title))
        }
        event.alarms = []
        if let minutes {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes * 60)))
        }
        let span: EKSpan = event.hasRecurrenceRules ? .futureEvents : .thisEvent
        do {
            try store.save(event, span: span)
            return .success(())
        } catch {
            return .failure(.saveFailed(error.localizedDescription))
        }
    }

    /// 移动到另一个日历
    @discardableResult
    func moveToCalendar(snapshot: inout EventSnapshot, to calendarId: String) -> Result<Void, CalendarWriteError> {
        guard let id = snapshot.eventIdentifier,
              let event = store.event(withIdentifier: id) else {
            return .failure(.eventNotFound)
        }
        guard let target = store.calendar(withIdentifier: calendarId) else {
            return .failure(.calendarUnavailable(snapshot.calendarTitle))
        }
        guard target.allowsContentModifications else {
            return .failure(.calendarReadOnly(target.title))
        }
        guard event.calendar.allowsContentModifications else {
            return .failure(.calendarReadOnly(event.calendar.title))
        }
        event.calendar = target
        let span: EKSpan = event.hasRecurrenceRules ? .futureEvents : .thisEvent
        do {
            try store.save(event, span: span)
            snapshot.calendarIdentifier = calendarId
            snapshot.calendarTitle = target.title
            return .success(())
        } catch {
            return .failure(.saveFailed(error.localizedDescription))
        }
    }

    // MARK: - 冲突检查与建议时间

    /// 需要“完全访问”才能读取现有日程；如果用户只给写入权限，安全地返回空结果。
    func conflicts(for snapshot: EventSnapshot) -> [CalendarConflict] {
        guard EKEventStore.authorizationStatus(for: .event).orbitCanReadEvents,
              snapshot.end > snapshot.start else { return [] }

        let predicate = store.predicateForEvents(
            withStart: snapshot.start,
            end: snapshot.end,
            calendars: visibleFilter
        )
        return store.events(matching: predicate)
            .filter { event in
                guard event.eventIdentifier != snapshot.eventIdentifier else { return false }
                // 节假日、生日、天气订阅以及被标记为空闲的事件不阻断用户安排。
                let title = (event.title ?? "").lowercased()
                let ignoredTitle = ["天气", "weather", "节假日", "holiday", "生日", "birthday"]
                    .contains { title.contains($0) }
                guard !ignoredTitle, event.availability != .free else { return false }
                // 普通定时日程可以与信息型全天事件共存。
                if event.isAllDay && !snapshot.isAllDay { return false }
                return event.startDate < snapshot.end && event.endDate > snapshot.start
            }
            .map {
                CalendarConflict(
                    eventIdentifier: $0.eventIdentifier,
                    title: $0.title ?? "未命名日程",
                    start: $0.startDate,
                    end: $0.endDate,
                    calendarTitle: $0.calendar?.title ?? "系统日历"
                )
            }
            .sorted { $0.start < $1.start }
    }

    /// 优先原日期和相近时段，并严格限制在用户清醒时间内。
    /// Orbit 只给出建议，绝不自行移动用户真实日程。
    func suggestedStart(for snapshot: EventSnapshot, searchDays: Int = 14) -> Date? {
        guard EKEventStore.authorizationStatus(for: .event).orbitCanReadEvents,
              !snapshot.isAllDay,
              snapshot.end > snapshot.start else { return nil }

        let duration = snapshot.end.timeIntervalSince(snapshot.start)
        let calendar = Calendar.current
        let wakeHour = UserDefaults.standard.object(forKey: "orbit.wakeHour") as? Int ?? 7
        let sleepHour = UserDefaults.standard.object(forKey: "orbit.sleepHour") as? Int ?? 23
        let originalHour = calendar.component(.hour, from: snapshot.start)

        for dayOffset in 0...searchDays {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: snapshot.start)),
                  let wake = calendar.date(bySettingHour: wakeHour, minute: 0, second: 0, of: day),
                  let sleep = sleepHour == 24
                    ? calendar.date(byAdding: .day, value: 1, to: day)
                    : calendar.date(bySettingHour: sleepHour, minute: 0, second: 0, of: day) else { continue }
            let preferred = calendar.date(bySettingHour: max(wakeHour, min(sleepHour - 1, originalHour)),
                                          minute: calendar.component(.minute, from: snapshot.start),
                                          second: 0, of: day) ?? wake
            var candidate = roundedUpToQuarterHour(max(wake, preferred))
            let predicate = store.predicateForEvents(withStart: wake, end: sleep, calendars: nil)
            let events = store.events(matching: predicate)
                .filter {
                    $0.eventIdentifier != snapshot.eventIdentifier &&
                    !$0.isAllDay && $0.availability != .free
                }
                .sorted { $0.startDate < $1.startDate }

            for event in events {
                if event.endDate <= candidate { continue }
                if event.startDate >= candidate.addingTimeInterval(duration) { break }
                candidate = roundedUpToQuarterHour(event.endDate)
            }
            if candidate >= wake && candidate.addingTimeInterval(duration) <= sleep {
                return candidate
            }
        }
        return nil
    }

    /// 晨间简报使用：只读取当天真正的系统日程，且要求用户已授予完全访问。
    func todayEvents() -> [EKEvent] {
        guard EKEventStore.authorizationStatus(for: .event).orbitCanReadEvents else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: visibleFilter)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    func events(on date: Date) -> [EKEvent] {
        guard EKEventStore.authorizationStatus(for: .event).orbitCanReadEvents else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: visibleFilter)
        return store.events(matching: predicate).sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.startDate < rhs.startDate
        }
    }

    /// 同一日历、同标题、同开始时间（容差 2 分钟）的日程视为重复；
    /// 返回已有事件的标识，供上层绑定原日程而不是再次新建。
    func findDuplicate(of snapshot: EventSnapshot) -> String? {
        guard EKEventStore.authorizationStatus(for: .event).orbitCanReadEvents,
              let calendar = store.calendar(withIdentifier: snapshot.calendarIdentifier) else { return nil }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: snapshot.start)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: [calendar])
        let normalizedTitle = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return nil }
        return store.events(matching: predicate).first { event in
            guard let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  title == normalizedTitle,
                  let identifier = event.eventIdentifier else { return false }
            if snapshot.isAllDay || event.isAllDay {
                return snapshot.isAllDay && event.isAllDay
            }
            return abs(event.startDate.timeIntervalSince(snapshot.start)) < 120
        }?.eventIdentifier
    }

    private func apply(_ snapshot: EventSnapshot, to event: EKEvent, updateRecurrence: Bool) {
        event.title = snapshot.title
        event.location = snapshot.location
        event.notes = snapshot.notes
        event.isAllDay = snapshot.isAllDay
        event.startDate = snapshot.start
        event.endDate = snapshot.end
        event.calendar = store.calendar(withIdentifier: snapshot.calendarIdentifier)
            ?? store.defaultCalendarForNewEvents
        // 导入 Apple 日历的事件会携带全部提醒；旧版 Orbit 快照没有该字段时，
        // 编辑既有事件应保留系统中的提醒，而新建事件才使用默认提醒分钟数。
        if let alarmOffsets = snapshot.alarmOffsets {
            event.alarms = []
            for offset in alarmOffsets {
                event.addAlarm(EKAlarm(relativeOffset: offset))
            }
        } else if event.eventIdentifier == nil {
            event.alarms = []
            if let minutes = snapshot.reminderMinutes {
                event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes * 60)))
            }
        }
        if updateRecurrence {
            event.recurrenceRules = recurrenceRule(for: snapshot.recurrence).map { [$0] }
        }
    }

    /// 将系统日历中常见的循环规则转换为 Orbit 卡片可编辑的规则。
    func recurrenceSpec(for event: EKEvent) -> RecurrenceSpec? {
        guard let rule = event.recurrenceRules?.first else { return nil }
        let frequency: RecurrenceFrequency
        switch rule.frequency {
        case .daily:
            frequency = .daily
        case .weekly:
            let selectedWeekdays = Set((rule.daysOfTheWeek ?? []).map { $0.dayOfTheWeek.rawValue })
            let workdays = Set([
                EKWeekday.monday.rawValue,
                EKWeekday.tuesday.rawValue,
                EKWeekday.wednesday.rawValue,
                EKWeekday.thursday.rawValue,
                EKWeekday.friday.rawValue
            ])
            frequency = selectedWeekdays == workdays ? .weekdays : .weekly
        case .monthly:
            frequency = .monthly
        case .yearly:
            frequency = .yearly
        @unknown default:
            return nil
        }
        return RecurrenceSpec(
            frequency: frequency,
            interval: max(1, rule.interval),
            endDate: rule.recurrenceEnd?.endDate
        )
    }

    /// EventKit 只支持 daily/weekly/monthly/yearly；“工作日”用每周一至周五表示。
    func recurrenceRule(for spec: RecurrenceSpec?) -> EKRecurrenceRule? {
        guard let spec else { return nil }
        let interval = max(1, spec.interval)
        let end = spec.endDate.map { EKRecurrenceEnd(end: $0) }

        switch spec.frequency {
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: interval, end: end)
        case .weekly:
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: interval, end: end)
        case .monthly:
            return EKRecurrenceRule(recurrenceWith: .monthly, interval: interval, end: end)
        case .yearly:
            return EKRecurrenceRule(recurrenceWith: .yearly, interval: interval, end: end)
        case .weekdays:
            let weekdays: [EKRecurrenceDayOfWeek] = [
                .init(.monday), .init(.tuesday), .init(.wednesday),
                .init(.thursday), .init(.friday)
            ]
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: interval,
                daysOfTheWeek: weekdays,
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: end
            )
        }
    }

    private func roundedUpToQuarterHour(_ date: Date) -> Date {
        let calendar = Calendar.current
        let minutes = calendar.component(.minute, from: date)
        let remainder = minutes % 15
        let extraMinutes = remainder == 0 ? 0 : 15 - remainder
        let base = calendar.date(bySetting: .second, value: 0, of: date) ?? date
        return calendar.date(byAdding: .minute, value: extraMinutes, to: base) ?? date
    }
}
