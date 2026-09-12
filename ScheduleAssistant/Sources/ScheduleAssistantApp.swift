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
            OrbitRootView()
                .environmentObject(settings)
                .environmentObject(chat)
        }
    }
}

struct OrbitRootView: View {
    @ObservedObject private var app = AppSettings.shared
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            TodayScheduleView()
                .tabItem { Label("今天", systemImage: "calendar.day.timeline.left") }
                .tag(0)
            ChatView(selectedTab: $selection)
                .tabItem { Label("对话", systemImage: "message.fill") }
                .tag(1)
        }
        .tint(.orange)
        .fullScreenCover(isPresented: Binding(
            get: { !app.onboardingCompleted },
            set: { if !$0 { app.onboardingCompleted = true } }
        )) {
            OnboardingView {
                app.onboardingCompleted = true
                selection = 1
            }
        }
    }
}
