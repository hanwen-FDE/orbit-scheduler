import SwiftUI
import UIKit

@main
struct ScheduleAssistantApp: App {
    @StateObject private var settings = LLMSettings()
    @StateObject private var chat = ChatStore()

    init() {
        // 恢复上次选择的图标
        if let icon = AppSettings.shared.alternateIcon {
            IconService.apply(icon)
        }
    }

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environmentObject(settings)
                .environmentObject(chat)
        }
    }
}
