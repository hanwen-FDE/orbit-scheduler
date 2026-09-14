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
        // 内购观察者必须尽早注册：未 finish 的交易会在启动时重新下发。
        _ = IAPService.shared
        // 让“快速记录日程”“查看今日日程”在快捷指令、Siri 与 Spotlight 中注册。
        if #available(iOS 16.0, *) {
            OrbitShortcuts.updateAppShortcutParameters()
        }
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
    @ObservedObject private var account = AccountStore.shared
    @State private var showChat = false
    @State private var showAuth = false

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
            .onChange(of: chat.pendingFocusMessageId) { newValue in
                // 从通知中心跳日程卡片：确保对话页已打开，ChatView 会接管并打开编辑。
                if newValue != nil { showChat = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .orbitAuthRequired)) { _ in
                // 首次使用云端服务、或令牌 401 失效：始终实际弹出登录页。
                // 不能在对话中声称“已打开”却因状态条件而什么也不发生。
                showAuth = true
            }
            .onChange(of: account.isLoggedIn) { loggedIn in
                guard app.onboardingCompleted else { return }
                if loggedIn {
                    showAuth = false
                } else if !app.authSkipped {
                    showAuth = true
                }
            }
            .onAppear {
                if app.onboardingCompleted, !account.isLoggedIn, !app.authSkipped {
                    showAuth = true
                }
                if account.isLoggedIn {
                    Task { await account.refreshPoints() }
                }
            }
            .fullScreenCover(isPresented: $showAuth) {
                AuthView()
            }
            .fullScreenCover(isPresented: Binding(
                get: { !app.onboardingCompleted },
                set: { if !$0 { app.onboardingCompleted = true } }
            )) {
                OnboardingView {
                    app.onboardingCompleted = true
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
