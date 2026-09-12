import AppIntents
import Foundation

/// Widget、URL Scheme 与系统快捷指令共用同一个“下一次打开 App 时去哪里”的轻量信号。
/// 不携带 API Key 或用户日程内容，避免深链成为数据泄露入口。
enum OrbitShortcutDestination: String {
    case compose
    case today
}

enum OrbitShortcutRequest {
    private static let destinationKey = "orbit.shortcut.destination"

    static func prepare(_ destination: OrbitShortcutDestination) {
        UserDefaults.standard.set(destination.rawValue, forKey: destinationKey)
        NotificationCenter.default.post(name: .orbitShortcutRequested, object: nil)
    }

    static func consume() -> OrbitShortcutDestination? {
        defer { UserDefaults.standard.removeObject(forKey: destinationKey) }
        guard let raw = UserDefaults.standard.string(forKey: destinationKey) else { return nil }
        return OrbitShortcutDestination(rawValue: raw)
    }
}

extension Notification.Name {
    static let orbitShortcutRequested = Notification.Name("orbit.shortcut.requested")
}

enum OrbitDeepLink {
    static func accept(_ url: URL) {
        guard url.scheme?.lowercased() == "orbit" else { return }
        switch url.host?.lowercased() {
        case "compose": OrbitShortcutRequest.prepare(.compose)
        case "today": OrbitShortcutRequest.prepare(.today)
        default: break
        }
    }
}

/// “快速记录”会打开 App，而不是在后台直接创建日程；用户始终能看到并确认写入结果。
struct OpenOrbitComposerIntent: AppIntent {
    static var title: LocalizedStringResource = "快速记录日程"
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        OrbitShortcutRequest.prepare(.compose)
        return .result(dialog: "已打开 Orbit，可以记录新的安排。")
    }
}

struct OpenOrbitTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "查看今日日程"
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        OrbitShortcutRequest.prepare(.today)
        return .result(dialog: "已打开 Orbit 的日程列表。")
    }
}

/// 系统会将这里声明的入口显示在快捷指令、Siri 和 Spotlight 中。
struct OrbitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(
                intent: OpenOrbitComposerIntent(),
                phrases: [
                    "用 \(.applicationName) 添加日程",
                    "在 \(.applicationName) 快速记录"
                ],
                shortTitle: "快速记录",
                systemImageName: "plus.circle.fill"
            ),
            AppShortcut(
                intent: OpenOrbitTodayIntent(),
                phrases: [
                    "查看 \(.applicationName) 的今天",
                    "打开 \(.applicationName) 日程"
                ],
                shortTitle: "今日日程",
                systemImageName: "calendar"
            )
        ]
    }
}

