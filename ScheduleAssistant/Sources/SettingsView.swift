import SwiftUI

/// 单个服务商的配置编辑 + 连接测试（用于抽屉的 API 设置区）
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

/// 「左上角头像 → 设置」：AI 识别（API）、联系方式与关于。
/// 反馈邮箱上线前请替换为真实地址。
struct AppSettingsScreen: View {
    @EnvironmentObject private var settings: LLMSettings
    @EnvironmentObject private var chat: ChatStore
    @State private var showDeleteConversationConfirmation = false

    var body: some View {
        Form {
            Section {
                Picker("识别服务商", selection: $settings.activeProviderId) {
                    ForEach(settings.providers, id: \.id) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                if let active = settings.providers.first(where: { $0.id == settings.activeProviderId }) {
                    ProviderConfigView(provider: active)
                }
            } header: {
                Text("AI 识别（API）")
            } footer: {
                Text("选择服务商后只需粘贴 API Key——接口地址和模型已按国内常用服务预设，高级用户可自行修改。Key 保存在本机 Keychain 中。")
            }

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
            .confirmationDialog("删除当前对话？", isPresented: $showDeleteConversationConfirmation, titleVisibility: .visible) {
                Button("删除对话", role: .destructive) { chat.clearConversation() }
                Button("取消", role: .cancel) {}
            }

            Section {
                HStack {
                    Label("联系我们", systemImage: "envelope")
                    Spacer()
                    Text("稍后上线")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
