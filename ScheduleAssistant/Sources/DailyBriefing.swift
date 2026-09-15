import CoreLocation
import SwiftUI
import UserNotifications
import WeatherKit

/// 晨间卡片使用的轻量日程摘要。它只读系统日历，不创建 Orbit 自己的日历副本。
struct DailyEventSummary: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
}

/// “天气 + 当日日程 + 一句问候”仅在用户主动开启本地天气后请求定位。
@MainActor
final class DailyBriefingStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var todayEvents: [DailyEventSummary] = []
    @Published private(set) var weatherText: String?
    @Published private(set) var weatherSymbolName = "cloud.sun"
    @Published private(set) var isLoadingWeather = false
    @Published private(set) var locationPermissionNeeded = false

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// 在 App 前台时刷新。iOS 不保证后台每天拉取天气，因此通知只负责把用户带回 Orbit。
    func refresh() {
        todayEvents = CalendarService.shared.todayEvents().enumerated().map { index, event in
            DailyEventSummary(
                id: event.eventIdentifier ?? "\(event.title ?? "event")-\(index)-\(event.startDate.timeIntervalSinceReferenceDate)",
                title: event.title ?? "未命名日程",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay
            )
        }
        refreshWeatherIfEnabled()
    }

    /// 这个入口同时是“用户明确同意显示天气”的操作，避免首次启动即索取定位。
    func enableWeatherBriefing() {
        AppSettings.shared.weatherBriefingEnabled = true
        refreshWeatherIfEnabled()
    }

    func refreshWeatherIfEnabled() {
        guard AppSettings.shared.weatherBriefingEnabled else {
            weatherText = nil
            locationPermissionNeeded = false
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationPermissionNeeded = false
            isLoadingWeather = true
            locationManager.requestLocation()
        case .notDetermined:
            locationPermissionNeeded = false
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            isLoadingWeather = false
            locationPermissionNeeded = true
            weatherText = nil
        @unknown default:
            isLoadingWeather = false
            weatherText = nil
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard AppSettings.shared.weatherBriefingEnabled else { return }
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            locationPermissionNeeded = false
            isLoadingWeather = true
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            isLoadingWeather = false
            locationPermissionNeeded = true
            weatherText = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { await loadWeather(for: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.isLoadingWeather = false
            self?.weatherText = nil
        }
    }

    private func loadWeather(for location: CLLocation) async {
        guard #available(iOS 16.0, *) else {
            // WeatherKit 需要 iOS 16；旧系统上明确降级而不是报错。
            weatherText = nil
            weatherSymbolName = "cloud.sun"
            isLoadingWeather = false
            return
        }
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let celsius = weather.currentWeather.temperature.converted(to: .celsius).value
            weatherText = "现在 \(Int(celsius.rounded()))°C"
            weatherSymbolName = weather.currentWeather.symbolName
        } catch {
            weatherText = nil
        }
        isLoadingWeather = false
    }

    /// 打开 App 当下的问候（卡片顶部用）。
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case ..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<19: return "下午好"
        default: return "晚上好"
        }
    }

    /// 早报问候按“设定的推送时间”推算，而不是生成简报那一刻的钟点——
    /// 否则下午打开 App 时，早报第一句会错写成“下午好”。
    static func greeting(forScheduledHour hour: Int) -> String {
        switch hour {
        case ..<11: return "早上好"
        case 11..<14: return "中午好"
        default: return "下午好"
        }
    }

    var scheduleSummary: String {
        guard !todayEvents.isEmpty else { return "今天没有固定安排，可以把时间留给最重要的事。" }
        let timed = todayEvents.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        guard let first = timed.first else { return "今天有 \(todayEvents.count) 项全天安排，节奏由你掌握。" }
        if todayEvents.count >= 6 {
            return "今天安排得比较满，第一项是 \(first.start.shortTime) 的 \(first.title)，记得给行程留一点缓冲。"
        }
        if todayEvents.count == 1 {
            return "今天的重点是 \(first.start.shortTime) 的 \(first.title)。"
        }
        return "今天从 \(first.start.shortTime) 的 \(first.title) 开始，共有 \(todayEvents.count) 项安排。"
    }

    var encouragement: String {
        let messages = [
            "按自己的节奏来，也是在前进。",
            "先开始五分钟，今天就已经在轨道上了。",
            "重要的不是塞满日程，而是把时间留给重要的事。"
        ]
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return messages[day % messages.count]
    }

    /// “最早几点、最晚几点”的一天跨度摘要（只统计有具体时间的日程）。
    var daySpanSummary: String? {
        let timed = todayEvents.filter { !$0.isAllDay }
        guard let earliest = timed.min(by: { $0.start < $1.start }),
              let latest = timed.max(by: { $0.end < $1.end }) else { return nil }
        if earliest.id == latest.id { return nil }
        return "最后一项预计在 \(latest.end.shortTime) 结束，前后别排得太紧。"
    }

    /// 早报结尾的加油语：按日期轮换，同一天内多次刷新不变。
    static func cheerLine(for date: Date) -> String {
        let lines = [
            "今天也要加油呀，一件一件来。",
            "先做最重要的那件事，其余都会跟上。",
            "把节奏握在自己手里，就是在前进。",
            "别怕慢，就怕站；开始五分钟就赢了一半。",
            "留一点空隙给自己，灵感喜欢空格。",
            "完成比完美更重要，踏实走完今天。"
        ]
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        return lines[day % lines.count]
    }

    /// 晚报结尾的晚安语：同样按日期轮换。
    static func goodnightLine(for date: Date) -> String {
        let lines = [
            "今天辛苦了，好好休息。",
            "晚安，明天轨道上见。",
            "放下手机，睡个安稳觉。",
            "今天的完成度已经足够好，晚安。"
        ]
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        return lines[day % lines.count]
    }
}

/// 本地通知只负责在设定时间提醒用户打开 Orbit；打开后才读取最新日程和天气。
enum MorningBriefingScheduler {
    static let notificationIdentifier = "orbit.morning-briefing"

    static func enable(hour: Int, minute: Int) async -> String {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else {
                return "未获得通知权限，请在系统设置中允许 Orbit 发送通知。"
            }

            center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
            let content = UNMutableNotificationContent()
            content.title = "早上好，Orbit"
            content.body = "打开 Orbit，查看今天的安排和晨间简报。"
            content.sound = .default

            var components = DateComponents()
            components.hour = max(0, min(23, hour))
            components.minute = max(0, min(59, minute))
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try await center.add(UNNotificationRequest(
                identifier: notificationIdentifier,
                content: content,
                trigger: trigger
            ))
            return "已设置每天 \(String(format: "%02d:%02d", hour, minute)) 的晨间提醒。"
        } catch {
            return "未能设置晨间提醒：\(error.localizedDescription)"
        }
    }

    static func disable() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier]
        )
    }
}

/// 晚报的每日本地通知（时间由用户在每日播报设置中直接选择）。
enum EveningBriefingScheduler {
    static let notificationIdentifier = "orbit.evening-briefing"

    static func enable(hour: Int, minute: Int) async -> String {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else {
                return "未获得通知权限，请在系统设置中允许 Orbit 发送通知。"
            }
            center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
            let content = UNMutableNotificationContent()
            content.title = "晚安，Orbit"
            content.body = "打开 Orbit，看看今天完成了多少任务。"
            content.sound = .default
            var components = DateComponents()
            components.hour = max(0, min(23, hour))
            components.minute = max(0, min(59, minute))
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try await center.add(UNNotificationRequest(
                identifier: notificationIdentifier,
                content: content,
                trigger: trigger
            ))
            return "已设置每天 \(String(format: "%02d:%02d", hour, minute)) 的晚报提醒。"
        } catch {
            return "未能设置晚报提醒：\(error.localizedDescription)"
        }
    }

    static func disable() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier]
        )
    }
}

struct DailyBriefingCard: View {
    @ObservedObject var store: DailyBriefingStore
    @ObservedObject private var app = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.greeting)
                        .font(.headline)
                    Text(store.scheduleSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: store.weatherSymbolName)
                    .font(.title2)
                    .foregroundStyle(orbitAccent())
            }

            if app.weatherBriefingEnabled, store.isLoadingWeather || store.weatherText != nil {
                HStack(spacing: 7) {
                    if store.isLoadingWeather {
                        ProgressView().controlSize(.small)
                    }
                    Text(store.weatherText ?? "正在准备天气…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("刷新") { store.refreshWeatherIfEnabled() }
                        .font(.caption.bold())
                }
            } else {
                Button {
                    store.enableWeatherBriefing()
                } label: {
                    Label("使用本地天气", systemImage: "location")
                        .font(.subheadline.bold())
                }
            }

            if !store.todayEvents.isEmpty {
                Divider()
                ForEach(store.todayEvents.prefix(3)) { event in
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .foregroundStyle(orbitAccent())
                        Text(event.title)
                            .lineLimit(1)
                        Spacer()
                        Text(event.isAllDay ? "全天" : event.start.shortTime)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                if store.todayEvents.count > 3 {
                    Text("还有 \(store.todayEvents.count - 3) 项安排")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(store.encouragement)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(orbitAccent().opacity(0.10))
        )
    }
}
