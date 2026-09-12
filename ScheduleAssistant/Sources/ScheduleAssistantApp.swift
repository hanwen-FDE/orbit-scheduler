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
    @EnvironmentObject private var chat: ChatStore
    @ObservedObject private var app = AppSettings.shared
    @State private var showChat = false

    var body: some View {
        TodayScheduleView(onOpenChat: { showChat = true })
            .tint(orbitAccent())
            .fullScreenCover(isPresented: $showChat) {
                ChatView(onClose: { showChat = false })
            }
            .onOpenURL { url in
                OrbitDeepLink.accept(url)
                routeByShortcut()
            }
            .onReceive(NotificationCenter.default.publisher(for: .orbitShortcutRequested)) { _ in
                routeByShortcut()
            }
            .onChange(of: chat.pendingFocusMessageId) { _, newValue in
                // 从通知中心跳日程卡片：确保对话页已打开，ChatView 会接管并打开编辑。
                if newValue != nil { showChat = true }
            }
            .fullScreenCover(isPresented: Binding(
                get: { !app.onboardingCompleted },
                set: { if !$0 { app.onboardingCompleted = true } }
            )) {
                OnboardingView { demoText in
                    app.onboardingCompleted = true
                    if let demoText {
                        chat.send(text: demoText)
                    }
                }
            }
    }

    /// 只看请求不消费：compose 打开对话页，today 回到今天页；真正消费在 ChatView。
    private func routeByShortcut() {
        switch OrbitShortcutRequest.peek() {
        case .compose: showChat = true
        case .today: showChat = false
        case nil: break
        }
    }
}
