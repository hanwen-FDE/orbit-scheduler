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
            weatherText = "允许定位后可显示本地天气"
        @unknown default:
            isLoadingWeather = false
            weatherText = "天气暂时不可用"
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
            weatherText = "允许定位后可显示本地天气"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { await loadWeather(for: location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLoadingWeather = false
        weatherText = "天气暂时无法获取"
    }

    private func loadWeather(for location: CLLocation) async {
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let celsius = weather.currentWeather.temperature.converted(to: .celsius).value
            weatherText = "现在 \(Int(celsius.rounded()))°C"
            weatherSymbolName = weather.currentWeather.symbolName
        } catch {
            weatherText = "天气暂时无法获取"
        }
        isLoadingWeather = false
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case ..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<19: return "下午好"
        default: return "晚上好"
        }
    }

    var scheduleSummary: String {
        switch todayEvents.count {
        case 0:
            return "今天日历还没有安排，留一点空间给真正重要的事。"
        case 1:
            return "今天有 1 项安排，稳稳完成它就很好。"
        default:
            return "今天有 \(todayEvents.count) 项安排，先抓住最重要的一件。"
        }
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
                    .foregroundStyle(.orange)
            }

            if app.weatherBriefingEnabled {
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
                if store.locationPermissionNeeded {
                    Text("可在“设置 → 隐私与安全性 → 定位服务 → Orbit”中允许定位。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                            .foregroundStyle(.blue)
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
                .fill(Color.blue.opacity(0.08))
        )
    }
}
