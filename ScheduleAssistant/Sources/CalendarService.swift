import Foundation
import EventKit

/// 系统日历读写（EventKit）
final class CalendarService {
    static let shared = CalendarService()
    let store = EKEventStore()

    /// 确保已触发权限请求；返回当前授权状态（iOS 17+：完全访问 / 仅写入）
    func ensureAccess() async -> EKAuthorizationStatus {
        var status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
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

    // MARK: - 事件 CRUD

    @discardableResult
    func createEvent(_ snapshot: EventSnapshot) -> String? {
        let event = EKEvent(eventStore: store)
        apply(snapshot, to: event)
        do {
            try store.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    func updateEvent(_ snapshot: inout EventSnapshot) {
        guard let id = snapshot.eventIdentifier,
              let event = store.event(withIdentifier: id) else {
            // 原事件不存在（可能被用户在系统日历里删了），重新创建
            snapshot.eventIdentifier = createEvent(snapshot)
            return
        }
        apply(snapshot, to: event)
        // 对循环事件，编辑的是“这一项及后续”，避免只修改某一次后
        // 让卡片中的循环规则与系统日历中的规则脱节。
        let span: EKSpan = (snapshot.recurrence != nil || event.hasRecurrenceRules)
            ? .futureEvents : .thisEvent
        try? store.save(event, span: span)
    }

    func deleteEvent(snapshot: EventSnapshot, includingFuture: Bool = false) {
        guard let id = snapshot.eventIdentifier,
              let event = store.event(withIdentifier: id) else { return }
        try? store.remove(event, span: includingFuture ? .futureEvents : .thisEvent)
    }

    /// 增删提醒闹钟；minutes=nil 移除全部提醒
    func setReminder(snapshot: EventSnapshot, minutes: Int?) {
        guard let id = snapshot.eventIdentifier,
              let event = store.event(withIdentifier: id) else { return }
        event.alarms = []
        if let minutes {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes)))
        }
        let span: EKSpan = event.hasRecurrenceRules ? .futureEvents : .thisEvent
        try? store.save(event, span: span)
    }

    /// 移动到另一个日历
    @discardableResult
    func moveToCalendar(snapshot: inout EventSnapshot, to calendarId: String) -> Bool {
        guard let id = snapshot.eventIdentifier,
              let event = store.event(withIdentifier: id),
              let target = store.calendar(withIdentifier: calendarId) else { return false }
        event.calendar = target
        do {
            let span: EKSpan = event.hasRecurrenceRules ? .futureEvents : .thisEvent
            try store.save(event, span: span)
            snapshot.calendarIdentifier = calendarId
            snapshot.calendarTitle = target.title
            return true
        } catch {
            return false
        }
    }

    // MARK: - 冲突检查与建议时间

    /// 需要“完全访问”才能读取现有日程；如果用户只给写入权限，安全地返回空结果。
    func conflicts(for snapshot: EventSnapshot) -> [CalendarConflict] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              snapshot.end > snapshot.start else { return [] }

        let predicate = store.predicateForEvents(
            withStart: snapshot.start,
            end: snapshot.end,
            calendars: nil
        )
        return store.events(matching: predicate)
            .filter { event in
                guard event.eventIdentifier != snapshot.eventIdentifier else { return false }
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

    /// 从原计划时间起，在未来两周查找同等时长的第一个空档。
    /// Orbit 只给出建议，绝不自行移动用户真实日程。
    func suggestedStart(for snapshot: EventSnapshot, searchDays: Int = 14) -> Date? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              !snapshot.isAllDay,
              snapshot.end > snapshot.start else { return nil }

        let duration = snapshot.end.timeIntervalSince(snapshot.start)
        let calendar = Calendar.current
        var candidate = roundedUpToQuarterHour(snapshot.start)
        let searchEnd = calendar.date(byAdding: .day, value: searchDays, to: candidate) ?? candidate
        let predicate = store.predicateForEvents(withStart: candidate, end: searchEnd, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.eventIdentifier != snapshot.eventIdentifier }
            .sorted { $0.startDate < $1.startDate }

        for event in events {
            if event.endDate <= candidate { continue }
            if event.startDate >= candidate.addingTimeInterval(duration) {
                return candidate
            }
            candidate = roundedUpToQuarterHour(max(candidate, event.endDate))
            if candidate.addingTimeInterval(duration) > searchEnd { return nil }
        }
        return candidate.addingTimeInterval(duration) <= searchEnd ? candidate : nil
    }

    /// 晨间简报使用：只读取当天真正的系统日程，且要求用户已授予完全访问。
    func todayEvents() -> [EKEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    private func apply(_ snapshot: EventSnapshot, to event: EKEvent) {
        event.title = snapshot.title
        event.location = snapshot.location
        event.notes = snapshot.notes
        event.isAllDay = snapshot.isAllDay
        event.startDate = snapshot.start
        event.endDate = snapshot.end
        event.calendar = store.calendar(withIdentifier: snapshot.calendarIdentifier)
            ?? store.defaultCalendarForNewEvents
        event.alarms = []
        if let minutes = snapshot.reminderMinutes {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes)))
        }
        event.recurrenceRules = recurrenceRule(for: snapshot.recurrence).map { [$0] }
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
