import SwiftUI

/// 单个服务商的配置编辑 + 连接测试（用于「设置 → 高级 → 自定义模型服务」）
struct ProviderConfigView: View {
    let provider: LLMProvider
    @EnvironmentObject private var settings: LLMSettings

    @State private var apiKey = ""
    @State private var baseURL = ""
    @State private var model = ""
    @State private var isTesting = false
    @State private var testResult: String?

    var body: some View {
        Group {
            SecureField("API Key", text: $apiKey)
            TextField("接口地址", text: $baseURL, prompt: Text(provider.defaultBaseURL.isEmpty ? "https://…" : provider.defaultBaseURL))
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            TextField("模型名", text: $model, prompt: Text(provider.defaultModel.isEmpty ? "如 gpt-4o / glm-4v-plus" : provider.defaultModel))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button {
                testConnection()
            } label: {
                HStack {
                    if isTesting { ProgressView() }
                    Text(isTesting ? "测试中…" : "测试连接")
                }
            }
            .disabled(isTesting || apiKey.isEmpty)
            if let testResult {
                Text(testResult).font(.footnote)
                    .foregroundStyle(testResult.hasPrefix("✓") ? .green : .red)
            }
        }
        .onAppear { load() }
        .onDisappear { save() }
    }

    private func load() {
        let config = settings.config(for: provider)
        apiKey = config.apiKey
        baseURL = config.baseURL
        model = config.model
    }

    private func save() {
        var config = settings.config(for: provider)
        config.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        config.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        config.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.updateConfig(config, for: provider)
    }

    private func testConnection() {
        save()
        isTesting = true
        testResult = nil
        let config = settings.config(for: provider)
        Task {
            do {
                let ok = try await provider.testConnection(config: config)
                testResult = ok ? "✓ 连接成功" : "连接失败"
            } catch {
                testResult = error.localizedDescription
            }
            isTesting = false
        }
    }
}

/// 「左上角头像 → 设置」：Orbit 云端服务状态、高级（BYOK）、联系方式与关于。
/// 反馈邮箱上线前请替换为真实地址（Info.plist → OrbitSupportEmail）。
struct AppSettingsScreen: View {
    @EnvironmentObject private var settings: LLMSettings
    @EnvironmentObject private var chat: ChatStore
    @ObservedObject private var account = AccountStore.shared
    @State private var showDeleteConversationConfirmation = false

    private var usesCloud: Bool { settings.activeProvider.isCloudService }

    var body: some View {
        Form {
            cloudSection
            advancedSection
            widgetSection
            dataSection
            contactSection
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .tint(orbitAccent())
        .onAppear {
            Task { await account.refreshPoints() }
        }
        .confirmationDialog("删除当前对话？", isPresented: $showDeleteConversationConfirmation, titleVisibility: .visible) {
            Button("删除对话", role: .destructive) { chat.clearConversation() }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - Orbit 云端服务（默认路径）

    private var cloudSection: some View {
        Section {
            HStack {
                Label("识别服务", systemImage: "brain.head.profile")
                Spacer()
                Text(settings.activeProvider.name)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("账号", systemImage: "person.crop.circle")
                Spacer()
                if account.isLoggedIn {
                    Text(account.username ?? "已登录")
                        .foregroundStyle(.secondary)
                } else {
                    Button("登录 / 注册") {
                        NotificationCenter.default.post(name: .orbitAuthRequired, object: nil)
                    }
                    .font(.subheadline.bold())
                }
            }
            if usesCloud {
                HStack {
                    Label("默认模型", systemImage: "cube.transparent")
                    Spacer()
                    Text(account.cloudModel.isEmpty ? "由服务端下发" : account.cloudModel)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                HStack {
                    Label("积分余额", systemImage: "sparkles")
                    Spacer()
                    if account.isFetchingPoints {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(account.points.map { "\($0)" } ?? "—")
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink(destination: PointsStoreView()) {
                    Label("充值 · 积分商店", systemImage: "cart.circle")
                        .foregroundStyle(orbitAccent())
                }
            } else {
                Button {
                    settings.activeProviderId = "orbit-cloud"
                } label: {
                    Label("切换回 Orbit 云端", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        } header: {
            Text("Orbit 云端服务")
        } footer: {
            Text(usesCloud
                 ? "云端服务使用 Orbit 账号的积分按量计费，对话令牌自动领取并保存在 Keychain；模型由服务端下发，不可修改。"
                 : "当前识别走自定义模型服务（自带 API Key）。云端服务按积分计费，无需填写 Key。")
        }
    }

    // MARK: - 高级（BYOK）

    private var advancedSection: some View {
        Section {
            NavigationLink(destination: CustomModelServiceView()) {
                Label("自定义模型服务（自带 API Key）", systemImage: "wrench.and.screwdriver")
            }
        } header: {
            Text("高级")
        } footer: {
            Text("高级用法：使用自己的 API Key（智谱、DeepSeek、Kimi、通义千问、OpenAI 或任意 OpenAI 兼容接口）。选择后识别请求将改走该服务。")
        }
    }

    // MARK: - 小组件与快捷指令

    private var widgetSection: some View {
        Section {
            Label("添加 Orbit 小组件", systemImage: "rectangle.on.rectangle")
            Text("在主屏幕长按 → 编辑 → 添加小组件 → 选择 Orbit，即可一键进入快速记录。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let shortcutsURL = URL(string: "shortcuts://") {
                Link(destination: shortcutsURL) {
                    Label("打开“快捷指令”App", systemImage: "square.and.arrow.up")
                }
            }
            Text("可添加“快速记录日程”和“查看今日日程”；系统也会将它们用于 Siri 和 Spotlight。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("小组件与快捷指令")
        }
    }

    // MARK: - 数据

    private var dataSection: some View {
        Section {
            Button("删除当前对话", role: .destructive) {
                showDeleteConversationConfirmation = true
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            Text("数据")
        } footer: {
            Text("只删除 Orbit 对话记录，不会删除已经写入 Apple 日历的日程。")
        }
    }

    // MARK: - 联系与关于

    private var contactSection: some View {
        Section {
            if let url = URL(string: "mailto:" + OrbitBackendConfig.supportEmail) {
                Link(destination: url) {
                    HStack {
                        Label("联系我们", systemImage: "envelope")
                        Spacer()
                        Text(OrbitBackendConfig.supportEmail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Label("关于 Orbit", systemImage: "info.circle")
                Spacer()
                Text("稍后上线")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("联系与关于")
        }
    }
}

/// BYOK 高级页：服务商选择 + Key 配置 + 连接测试。
struct CustomModelServiceView: View {
    @EnvironmentObject private var settings: LLMSettings

    /// 供 Picker 显示的 BYOK 服务商（不含 Orbit 云端）。
    private var byokProviders: [LLMProvider] {
        settings.providers.filter { !$0.isCloudService }
    }

    var body: some View {
        Form {
            Section {
                Picker("识别服务商", selection: $settings.activeProviderId) {
                    ForEach(byokProviders, id: \.id) { provider in
                        Text(provider.name).tag(provider.id)
                    }
                }
                if let active = byokProviders.first(where: { $0.id == settings.activeProviderId }) {
                    ProviderConfigView(provider: active)
                }
                Button {
                    settings.activeProviderId = "orbit-cloud"
                } label: {
                    Label("切回 Orbit 云端（推荐）", systemImage: "arrow.triangle.2.circlepath")
                }
            } header: {
                Text("自定义模型服务")
            } footer: {
                Text("在此选择服务商并粘贴 API Key 后，识别请求改走该服务；接口地址和模型已按国内常用服务预设，可自行修改。Key 保存在本机 Keychain 中。")
            }
        }
        .navigationTitle("自定义模型服务")
        .navigationBarTitleDisplayMode(.inline)
        .tint(orbitAccent())
    }
}
