import Foundation

enum ChatRole: String, Codable {
    case user, assistant
}

enum MessageKind: String, Codable {
    case text, image, eventCard
}

/// 单条聊天消息
struct ChatMessage: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var role: ChatRole
    var kind: MessageKind
    var text: String = ""
    /// 图片消息的缩略图（JPEG 数据）
    var imageData: Data?
    var event: EventSnapshot?
    var createdAt: Date = Date()
}

/// 日程快照：独立于 EKEvent，用于卡片展示与持久化
struct EventSnapshot: Codable, Equatable {
    var title: String
    var emoji: String
    var start: Date
    var end: Date
    var isAllDay: Bool = false
    var location: String?
    var notes: String?
    /// 提前提醒的分钟数；nil = 不提醒；0 = 准时
    var reminderMinutes: Int?
    var calendarIdentifier: String
    var calendarTitle: String
    var eventIdentifier: String?
    var deleted: Bool = false
}

/// 提醒时长可选项（分钟）
enum ReminderOption: CaseIterable, Identifiable {
    case onTime, m5, m15, m30, m60, m120, day1
    var minutes: Int? {
        switch self {
        case .onTime: return 0
        case .m5: return 5
        case .m15: return 15
        case .m30: return 30
        case .m60: return 60
        case .m120: return 120
        case .day1: return 1440
        }
    }
    var label: String {
        switch self {
        case .onTime: return "准时"
        case .m5: return "提前 5 分钟"
        case .m15: return "提前 15 分钟"
        case .m30: return "提前 30 分钟"
        case .m60: return "提前 1 小时"
        case .m120: return "提前 2 小时"
        case .day1: return "提前 1 天"
        }
    }
    var id: Int { minutes ?? -1 }
}

/// 应用级偏好（UserDefaults）
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let kCalendar = "orbit.defaultCalendarId"
    private let kReminder = "orbit.defaultReminderMinutes"
    private let kIcon = "orbit.alternateIcon"

    @Published var defaultCalendarId: String? {
        didSet { UserDefaults.standard.set(defaultCalendarId, forKey: kCalendar) }
    }
    @Published var defaultReminderMinutes: Int {
        didSet { UserDefaults.standard.set(defaultReminderMinutes, forKey: kReminder) }
    }
    @Published var alternateIcon: String? {
        didSet { UserDefaults.standard.set(alternateIcon, forKey: kIcon) }
    }

    init() {
        defaultCalendarId = UserDefaults.standard.string(forKey: kCalendar)
        let saved = UserDefaults.standard.object(forKey: kReminder) as? Int
        defaultReminderMinutes = saved ?? 30
        alternateIcon = UserDefaults.standard.string(forKey: kIcon)
    }
}

extension Date {
    /// 聊天卡片用的友好日期："今天 / 明天 / 9月7日 周日"
    var friendlyDay: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "今天" }
        if cal.isDateInTomorrow(self) { return "明天" }
        if cal.isDate(self, inSameDayAs: cal.date(byAdding: .day, value: 2, to: Date()) ?? self) { return "后天" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "M月d日 EEE"
        return fmt.string(from: self)
    }

    var shortTime: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: self)
    }
}
