import Foundation
import SwiftUI

enum ChatRole: String, Codable {
    case user, assistant
}

enum MessageKind: String, Codable {
    case text, image, voice, eventCard, briefing
    case habitCard
    case eveningBriefing
}

/// 全局主题预设：按产品设定固定为 6 色，默认蓝。
enum OrbitThemePreset: String, CaseIterable, Identifiable {
    case blue
    case yellow
    case purple
    case lightGreen
    case deepGreen
    case navy

    var id: String { rawValue }

    var accent: Color {
        switch self {
        case .blue: return Color(red: 0.18, green: 0.49, blue: 0.96)     // #2F7CF6
        case .yellow: return Color(red: 0.96, green: 0.77, blue: 0.19)   // #F5C531
        case .purple: return Color(red: 0.36, green: 0.31, blue: 0.83)   // #5B4FD4
        case .lightGreen: return Color(red: 0.27, green: 0.73, blue: 0.53) // #45B987
        case .deepGreen: return Color(red: 0.03, green: 0.36, blue: 0.04) // #085C0A
        case .navy: return Color(red: 0.03, green: 0.04, blue: 0.36)     // #080A5C
        }
    }
}

/// 左上角品牌标识：斜椭圆（随主题变色）+「Orbit 轨迹」。
struct OrbitBrandMark: View {
    @ObservedObject private var app = AppSettings.shared

    var body: some View {
        HStack(spacing: 7) {
            Ellipse()
                .stroke(
                    LinearGradient(colors: [app.theme.accent, app.theme.accent.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 2.2
                )
                .frame(width: 24, height: 13)
                .rotationEffect(.degrees(-43))
            Text("Orbit 轨迹")
                .font(.title3.bold())
                .foregroundStyle(app.theme.accent)
        }
    }
}

/// 全局统一的左缘右滑返回。使用同时识别手势，避免阻断列表滚动、按钮点击和卡片手势。
struct OrbitEdgeSwipeBackModifier: ViewModifier {
    let onBack: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .global)
                .onEnded { value in
                    let startsAtLeftEdge = value.startLocation.x <= 32
                    let movesRight = value.translation.width > 80
                    let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.2
                    if startsAtLeftEdge, movesRight, isHorizontal {
                        onBack()
                    }
                }
        )
    }
}

extension View {
    func orbitEdgeSwipeBack(perform onBack: @escaping () -> Void) -> some View {
        modifier(OrbitEdgeSwipeBackModifier(onBack: onBack))
    }
}

/// 视图里替代硬编码强调色的入口，随用户选择的主题实时变化。
@MainActor
func orbitAccent() -> Color { AppSettings.shared.theme.accent }

/// 单条聊天消息
struct ChatMessage: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var role: ChatRole
    var kind: MessageKind
    var text: String = ""
    /// 图片消息的缩略图（JPEG 数据）
    var imageData: Data?
    /// 语音消息时长；转写文本保存在 text 中。
    var voiceDuration: TimeInterval? = nil
    var event: EventSnapshot?
    /// 独立于日历事件的“习惯提醒”卡片，实际写入系统提醒事项 App。
    var habit: HabitSnapshot? = nil
    var createdAt: Date = Date()
}

/// 循环规则：日程使用 EventKit 循环事件；习惯则使用 EventKit 循环提醒事项。
/// `weekdays` 是“每个工作日”，其他规则按事件开始日期推算。
enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekdays, weekly, monthly, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "每天"
        case .weekdays: return "每个工作日"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .yearly: return "每年"
        }
    }

    var unitTitle: String {
        switch self {
        case .daily: return "天"
        case .weekdays: return "周"
        case .weekly: return "周"
        case .monthly: return "月"
        case .yearly: return "年"
        }
    }
}

struct RecurrenceSpec: Codable, Equatable {
    var frequency: RecurrenceFrequency
    var interval: Int = 1
    /// nil 代表一直循环；用户可在编辑页指定结束日。
    var endDate: Date?

    var displayText: String {
        if frequency == .weekdays { return "每个工作日" }
        let prefix = interval == 1 ? "每" : "每 \(interval)"
        return "\(prefix)\(frequency.unitTitle)"
    }
}

/// 当前日程与系统日历中已有事件的重叠摘要。
struct CalendarConflict: Codable, Equatable, Identifiable {
    var eventIdentifier: String?
    var title: String
    var start: Date
    var end: Date
    var calendarTitle: String

    var id: String {
        eventIdentifier ?? "\(title)-\(start.timeIntervalSinceReferenceDate)"
    }
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
    /// 从 Apple 日历读取的全部提醒偏移。nil 表示沿用 reminderMinutes；空数组表示无提醒。
    var alarmOffsets: [TimeInterval]? = nil
    var calendarIdentifier: String
    var calendarTitle: String
    var eventIdentifier: String?
    /// 日程循环规则；nil 表示一次性日程。
    var recurrence: RecurrenceSpec? = nil
    /// 用户选择“同步到提醒事项”后，系统 EKReminder 的标识。
    var nativeReminderIdentifier: String? = nil
    /// 创建或修改时发现的冲突；nil 表示还未检查。
    var conflicts: [CalendarConflict]? = nil
    /// 仅作为建议，绝不自动移动用户的日程。
    var suggestedStart: Date? = nil
    var deleted: Bool = false

    var isPendingConfirmation: Bool {
        eventIdentifier == nil && !deleted
    }
}

enum OrbitNotificationKind: String, Codable, CaseIterable {
    case reminder, briefing, conflict, writeFailure, aiFailure

    var title: String {
        switch self {
        case .reminder: return "日程提醒"
        case .briefing: return "简报"
        case .conflict: return "时间冲突"
        case .writeFailure: return "写入失败"
        case .aiFailure: return "AI 处理失败"
        }
    }

    var icon: String {
        switch self {
        case .reminder: return "bell.fill"
        case .briefing: return "sun.max.fill"
        case .conflict: return "exclamationmark.triangle.fill"
        case .writeFailure: return "calendar.badge.exclamationmark"
        case .aiFailure: return "wifi.exclamationmark"
        }
    }
}

struct OrbitNotificationItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: OrbitNotificationKind
    var title: String
    var detail: String
    var createdAt = Date()
    var isRead = false
    var relatedMessageId: UUID?
}

/// “习惯”不是 Orbit 内部待办；它是同步到苹果“提醒事项”App 的循环 EKReminder。
struct HabitSnapshot: Codable, Equatable {
    var title: String
    var emoji: String
    var start: Date
    var recurrence: RecurrenceSpec
    var notes: String?
    var reminderIdentifier: String?
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
    private let kMorningBriefing = "orbit.morningBriefingEnabled"
    private let kMorningHour = "orbit.morningBriefingHour"
    private let kMorningMinute = "orbit.morningBriefingMinute"
    private let kEveningHour = "orbit.eveningBriefingHour"
    private let kEveningMinute = "orbit.eveningBriefingMinute"
    private let kWeatherBriefing = "orbit.weatherBriefingEnabled"
    private let kBriefingConflicts = "orbit.morningBriefingConflicts"
    private let kBriefingWeekends = "orbit.morningBriefingWeekends"
    private let kWakeHour = "orbit.wakeHour"
    private let kWakeMinute = "orbit.wakeMinute"
    private let kSleepHour = "orbit.sleepHour"
    private let kSleepMinute = "orbit.sleepMinute"
    private let kEveningBriefing = "orbit.eveningBriefingEnabled"
    private let kTheme = "orbit.theme"
    private let kVisibleCalendars = "orbit.visibleCalendarIds"
    private let kOnboarding = "orbit.onboardingCompleted"

    @Published var defaultCalendarId: String? {
        didSet {
            UserDefaults.standard.set(defaultCalendarId, forKey: kCalendar)
            // “默认日历”决定写入目标；“日历读取”决定展示与冲突范围。
            // 显式筛选读取范围时，写入目标必须始终可见。
            if let calendarId = defaultCalendarId,
               var readableIds = visibleCalendarIds,
               !readableIds.contains(calendarId) {
                readableIds.append(calendarId)
                visibleCalendarIds = readableIds
            }
        }
    }
    @Published var defaultReminderMinutes: Int {
        didSet { UserDefaults.standard.set(defaultReminderMinutes, forKey: kReminder) }
    }
    @Published var alternateIcon: String? {
        didSet { UserDefaults.standard.set(alternateIcon, forKey: kIcon) }
    }
    @Published var morningBriefingEnabled: Bool {
        didSet { UserDefaults.standard.set(morningBriefingEnabled, forKey: kMorningBriefing) }
    }
    @Published var morningBriefingHour: Int {
        didSet { UserDefaults.standard.set(morningBriefingHour, forKey: kMorningHour) }
    }
    @Published var morningBriefingMinute: Int {
        didSet { UserDefaults.standard.set(morningBriefingMinute, forKey: kMorningMinute) }
    }
    @Published var eveningBriefingHour: Int {
        didSet { UserDefaults.standard.set(eveningBriefingHour, forKey: kEveningHour) }
    }
    @Published var eveningBriefingMinute: Int {
        didSet { UserDefaults.standard.set(eveningBriefingMinute, forKey: kEveningMinute) }
    }
    @Published var weatherBriefingEnabled: Bool {
        didSet { UserDefaults.standard.set(weatherBriefingEnabled, forKey: kWeatherBriefing) }
    }
    @Published var morningBriefingShowsConflicts: Bool {
        didSet { UserDefaults.standard.set(morningBriefingShowsConflicts, forKey: kBriefingConflicts) }
    }
    @Published var morningBriefingOnWeekends: Bool {
        didSet { UserDefaults.standard.set(morningBriefingOnWeekends, forKey: kBriefingWeekends) }
    }
    @Published var wakeHour: Int {
        didSet { UserDefaults.standard.set(wakeHour, forKey: kWakeHour) }
    }
    @Published var wakeMinute: Int {
        didSet { UserDefaults.standard.set(wakeMinute, forKey: kWakeMinute) }
    }
    @Published var sleepHour: Int {
        didSet { UserDefaults.standard.set(sleepHour, forKey: kSleepHour) }
    }
    @Published var sleepMinute: Int {
        didSet { UserDefaults.standard.set(sleepMinute, forKey: kSleepMinute) }
    }
    @Published var eveningBriefingEnabled: Bool {
        didSet { UserDefaults.standard.set(eveningBriefingEnabled, forKey: kEveningBriefing) }
    }
    /// nil 或空 = 读取全部日历
    @Published var visibleCalendarIds: [String]? {
        didSet { UserDefaults.standard.set(visibleCalendarIds, forKey: kVisibleCalendars) }
    }
    @Published var theme: OrbitThemePreset {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: kTheme) }
    }
    @Published var onboardingCompleted: Bool {
        didSet { UserDefaults.standard.set(onboardingCompleted, forKey: kOnboarding) }
    }

    /// 晨报和晚报均由用户直接选择固定的每天推送时间。
    var morningBriefingTime: (hour: Int, minute: Int) {
        (morningBriefingHour, morningBriefingMinute)
    }

    var eveningBriefingTime: (hour: Int, minute: Int) {
        (eveningBriefingHour, eveningBriefingMinute)
    }

    init() {
        defaultCalendarId = UserDefaults.standard.string(forKey: kCalendar)
        let saved = UserDefaults.standard.object(forKey: kReminder) as? Int
        defaultReminderMinutes = saved ?? 30
        alternateIcon = UserDefaults.standard.string(forKey: kIcon)
        morningBriefingEnabled = UserDefaults.standard.object(forKey: kMorningBriefing) as? Bool ?? true
        morningBriefingHour = UserDefaults.standard.object(forKey: kMorningHour) as? Int ?? 7
        morningBriefingMinute = UserDefaults.standard.object(forKey: kMorningMinute) as? Int ?? 30
        eveningBriefingHour = UserDefaults.standard.object(forKey: kEveningHour) as? Int ?? 22
        eveningBriefingMinute = UserDefaults.standard.object(forKey: kEveningMinute) as? Int ?? 30
        weatherBriefingEnabled = UserDefaults.standard.object(forKey: kWeatherBriefing) as? Bool ?? false
        morningBriefingShowsConflicts = UserDefaults.standard.object(forKey: kBriefingConflicts) as? Bool ?? true
        morningBriefingOnWeekends = UserDefaults.standard.object(forKey: kBriefingWeekends) as? Bool ?? true
        wakeHour = UserDefaults.standard.object(forKey: kWakeHour) as? Int ?? 7
        wakeMinute = UserDefaults.standard.object(forKey: kWakeMinute) as? Int ?? 0
        sleepHour = UserDefaults.standard.object(forKey: kSleepHour) as? Int ?? 23
        sleepMinute = UserDefaults.standard.object(forKey: kSleepMinute) as? Int ?? 0
        eveningBriefingEnabled = UserDefaults.standard.object(forKey: kEveningBriefing) as? Bool ?? true
        visibleCalendarIds = UserDefaults.standard.stringArray(forKey: kVisibleCalendars)
        theme = OrbitThemePreset(rawValue: UserDefaults.standard.string(forKey: kTheme) ?? "") ?? .blue
        onboardingCompleted = UserDefaults.standard.bool(forKey: kOnboarding)
        if let calendarId = defaultCalendarId,
           var readableIds = visibleCalendarIds,
           !readableIds.contains(calendarId) {
            readableIds.append(calendarId)
            visibleCalendarIds = readableIds
        }
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

    /// 卡片固定格式日期："9月14日 周一"。不随“今天/明天/下周三”等说法变化。
    var cardDay: String {
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
