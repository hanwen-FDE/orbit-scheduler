import SwiftUI
import UIKit

@main
struct ScheduleAssistantApp: App {
    // 聊天处理和设置界面必须共享同一份配置。此前这里新建了实例，
    // 而 ChatStore 使用 LLMSettings.shared，导致刚保存/测试成功的 Key
    // 有时还没有同步到实际的日程请求。
    @StateObject private var settings = LLMSettings.shared
    @StateObject private var chat = ChatStore()

    init() {
        // 恢复上次选择的图标
        if let icon = AppSettings.shared.alternateIcon {
            IconService.apply(icon)
        }
        // 让“快速记录日程”“查看今日日程”在快捷指令、Siri 与 Spotlight 中注册。
        OrbitShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environmentObject(settings)
                .environmentObject(chat)
        }
    }
}
