import EventKit
import Foundation

enum RemindersServiceError: LocalizedError {
    case permissionDenied
    case noDefaultList
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "未获得“提醒事项”完全访问权限。请在系统设置中允许 Orbit 访问提醒事项。"
        case .noDefaultList:
            return "系统中没有可写入的提醒事项列表。请先打开“提醒事项”App 并登录 iCloud 或其他账户。"
        case .saveFailed:
            return "未能写入系统提醒事项。"
        }
    }
}

/// 与苹果“提醒事项”App 的最小同步层。
/// 事件提醒与习惯提醒不存成 Orbit 内部待办，数据仍在系统 Reminders 中。
@MainActor
final class RemindersService {
    static let shared = RemindersService()

    private let store = CalendarService.shared.store

    private init() {}

    func ensureAccess() async throws {
        var status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .notDetermined {
            _ = try await store.requestFullAccessToReminders()
            status = EKEventStore.authorizationStatus(for: .reminder)
        }
        guard status == .fullAccess else { throw RemindersServiceError.permissionDenied }
    }

    /// 将一个日历事件同步成同时间的原生提醒事项；已有标识时更新而不是重复创建。
    func sync(event snapshot: EventSnapshot) async throws -> String {
        try await ensureAccess()
        let reminder: EKReminder
        if let id = snapshot.nativeReminderIdentifier,
           let existing = store.calendarItem(withIdentifier: id) as? EKReminder {
            reminder = existing
        } else {
            reminder = EKReminder(eventStore: store)
        }
        try configure(
            reminder,
            title: snapshot.title,
            date: snapshot.start,
            notes: snapshot.notes,
            recurrence: snapshot.recurrence
        )
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    /// 创建一个可完成的循环习惯。完成当前提醒后，系统提醒事项会显示下一次循环。
    func createHabit(_ habit: HabitSnapshot) async throws -> String {
        try await ensureAccess()
        let reminder = EKReminder(eventStore: store)
        try configure(
            reminder,
            title: habit.title,
            date: habit.start,
            notes: habit.notes,
            recurrence: habit.recurrence
        )
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func deleteReminder(identifier: String?) {
        guard let identifier,
              let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        try? store.remove(reminder, commit: true)
    }

    private func configure(
        _ reminder: EKReminder,
        title: String,
        date: Date,
        notes: String?,
        recurrence: RecurrenceSpec?
    ) throws {
        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw RemindersServiceError.noDefaultList
        }
        var components = Calendar(identifier: .gregorian).dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
            from: date
        )
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current

        reminder.title = title
        reminder.notes = notes
        reminder.calendar = calendar
        // iOS 上设置 due date 时，也必须设置 start date。
        reminder.startDateComponents = components
        reminder.dueDateComponents = components
        reminder.alarms = [EKAlarm(absoluteDate: date)]
        reminder.recurrenceRules = CalendarService.shared.recurrenceRule(for: recurrence).map { [$0] }
    }
}
