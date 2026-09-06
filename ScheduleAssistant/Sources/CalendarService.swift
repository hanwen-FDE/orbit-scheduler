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
        try? store.save(event, span: .thisEvent)
    }

    func deleteEvent(snapshot: EventSnapshot) {
        guard let id = snapshot.eventIdentifier,
              let event = store.event(withIdentifier: id) else { return }
        try? store.remove(event, span: .thisEvent)
    }

    /// 增删提醒闹钟；minutes=nil 移除全部提醒
    func setReminder(snapshot: EventSnapshot, minutes: Int?) {
        guard let id = snapshot.eventIdentifier,
              let event = store.event(withIdentifier: id) else { return }
        event.alarms = []
        if let minutes {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes)))
        }
        try? store.save(event, span: .thisEvent)
    }

    /// 移动到另一个日历
    @discardableResult
    func moveToCalendar(snapshot: inout EventSnapshot, to calendarId: String) -> Bool {
        guard let id = snapshot.eventIdentifier,
              let event = store.event(withIdentifier: id),
              let target = store.calendar(withIdentifier: calendarId) else { return false }
        event.calendar = target
        do {
            try store.save(event, span: .thisEvent)
            snapshot.calendarIdentifier = calendarId
            snapshot.calendarTitle = target.title
            return true
        } catch {
            return false
        }
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
    }
}
