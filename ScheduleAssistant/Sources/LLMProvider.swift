import Foundation
import UIKit

/// LLM 服务商统一接口：新增服务商只需实现此协议并在 LLMSettings.providers 注册
protocol LLMProvider {
    var id: String { get }
    var name: String { get }
    /// 该服务商默认的接口地址与模型名（用户可在设置页覆盖）
    var defaultBaseURL: String { get }
    var defaultModel: String { get }
    /// 是否支持图片输入（多模态）
    var supportsImage: Bool { get }

    func parseSchedule(text: String?, image: UIImage?, config: LLMProviderConfig) async throws -> [ParsedEvent]
    /// 接续对话：根据用户一句修正语修改已有日程，返回修改后的日程。
    func reviseEvent(originalJSON: String, instruction: String, config: LLMProviderConfig) async throws -> [ParsedEvent]
    func testConnection(config: LLMProviderConfig) async throws -> Bool
}

extension LLMProvider {
    /// Orbit 云端（积分制）不走 BYOK 配置界面。
    var isCloudService: Bool { id == "orbit-cloud" }
}

/// 单个服务商的用户配置。API Key 只在运行内存和 Keychain 中保存；
/// 接口地址与模型名才会进入普通偏好设置。
struct LLMProviderConfig: Codable, Equatable {
    var apiKey: String = ""
    var baseURL: String = ""
    var model: String = ""
}

// MARK: - OpenAI 兼容实现基类

/// 绝大多数服务商（OpenAI、智谱、DeepSeek、Kimi 等）都提供
/// OpenAI 兼容的 /chat/completions 接口，这里做一份共用实现。
class OpenAICompatProvider: LLMProvider {
    let id: String
    let name: String
    let defaultBaseURL: String
    let defaultModel: String
    let supportsImage: Bool

    init(id: String, name: String, baseURL: String, model: String, supportsImage: Bool) {
        self.id = id
        self.name = name
        self.defaultBaseURL = baseURL
        self.defaultModel = model
        self.supportsImage = supportsImage
    }

    func effectiveBaseURL(_ config: LLMProviderConfig) -> String {
        config.baseURL.isEmpty ? defaultBaseURL : config.baseURL
    }

    func effectiveModel(_ config: LLMProviderConfig) -> String {
        config.model.isEmpty ? defaultModel : config.model
    }

    // MARK: 请求体构造（子类可覆盖以自定义）

    struct MessageContent: Codable {
        let type: String
        let text: String?
        let image_url: ImageURL?
        struct ImageURL: Codable { let url: String }
    }

    struct ChatRequest: Codable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let stream: Bool?
        struct Message: Codable {
            let role: String
            let content: [MessageContent]
        }
    }

    func buildRequestBody(text: String?, image: UIImage?, config: LLMProviderConfig, systemPrompt: String, stream: Bool? = nil) throws -> Data {
        var content: [MessageContent] = []
        if let text, !text.isEmpty {
            content.append(.init(type: "text", text: text, image_url: nil))
        }
        if let image, let dataURL = Self.imageDataURL(image) {
            content.append(.init(type: "image_url", text: nil, image_url: .init(url: dataURL)))
        }
        guard !content.isEmpty else { throw LLMError.noInput }
        let body = ChatRequest(
            model: effectiveModel(config),
            messages: [
                .init(role: "system", content: [.init(type: "text", text: systemPrompt, image_url: nil)]),
                .init(role: "user", content: content),
            ],
            temperature: 0.1,
            stream: stream
        )
        let encoder = JSONEncoder()
        return try encoder.encode(body)
    }

    static func imageDataURL(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.6) else { return nil }
        return "data:image/jpeg;base64," + data.base64EncodedString()
    }

    static let systemPrompt = """
    你是一个日程信息提取助手。从用户提供的文字或图片中提取**所有**日程安排，严格返回 JSON（不要任何其他文字、不要 markdown 代码块），格式为：
    {"events": [{...}, {...}]}
    每个元素的字段：
    {"title": "日程标题(字符串,必填,简短)", "emoji": "一个最贴合日程主题的emoji字符", "startDate": "开始时间,ISO8601格式如2026-09-10T14:00:00+08:00", "endDate": "结束时间,ISO8601格式,可null", "location": "地点,可null", "notes": "补充说明,可null", "isAllDay": 是否全天(布尔), "recurrence": {"frequency":"daily|weekdays|weekly|monthly|yearly", "interval": 正整数} 或 null, "confidence": 置信度0到1的小数}
    注意：
    - 只有当输入同时能判断出“做什么”和“什么时候”时，才允许输出事件。问候、闲聊、提问、感想、测试 API、没有明确时间或没有明确事项的内容，一律返回 {"events":[]}。
    - 禁止猜测、补全或把普通输入默认成“会议”。没有出现会议语义时，不得生成标题为“会议”的事件。
    - 每个输出事件都必须有非空 title、明确且可解析的 startDate；不确定时间时不要用当前时间代替，直接返回空数组。
    - 内容里有几项日程，events 数组就放几个元素：整场会议只给名称和起止时间时输出 1 项；多行罗列的日程表（每行一项）要逐项输出，不可合并。
    - 用户没说年份时按当前时间推算合理的年份；没说结束时间时 endDate 填 null。
    - 仅当用户明确要求循环（例如“每天”“工作日”“每周”“每两周”“每月”“每年”）才填写 recurrence；没有循环就填 null。interval 默认 1；“每两周”填 weekly + interval 2。
    - 时间不确定时 confidence 给低值。
    - 当前系统时间会随用户消息一并提供在文字中（如有）。
    - 如果内容里完全没有日程信息，返回 {"events": []}。
    """

    // MARK: - LLMProvider 协议实现

    func parseSchedule(text: String?, image: UIImage?, config: LLMProviderConfig) async throws -> [ParsedEvent] {
        guard !config.apiKey.isEmpty else { throw LLMError.noAPIKey }
        let promptContext = "（当前时间：\(Self.nowString())）"
        let fullText = [text, promptContext].compactMap { $0 }.joined(separator: "\n")
        let url = URL(string: effectiveBaseURL(config).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try buildRequestBody(text: fullText, image: image, config: config, systemPrompt: Self.systemPrompt)

        let (data, response) = try await URLSession.shared.data(for: request)
        let jsonString = try Self.extractContent(data: data, response: response)
        return try Self.decodeEvents(from: jsonString)
    }

    func testConnection(config: LLMProviderConfig) async throws -> Bool {
        guard !config.apiKey.isEmpty else { throw LLMError.noAPIKey }
        let url = URL(string: effectiveBaseURL(config).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        // 与正式的日程解析使用相同的请求格式和 JSON 校验，避免出现
        // “测试连接成功，但实际识别失败”的假阳性。
        request.httpBody = try buildRequestBody(
            text: "明天上午十点进行连接测试会议。",
            image: nil,
            config: config,
            systemPrompt: Self.systemPrompt
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        let content = try Self.extractContent(data: data, response: response)
        _ = try Self.decodeEvents(from: content)
        return true
    }

    static let revisionSystemPrompt = """
    你是日程修改助手。用户会提供一条已有日程（JSON）和一句中文修改要求。
    请输出修改后的**完整**日程 JSON，格式：{"events": [{...}]}，字段与输入一致：
    {"title","emoji","startDate"(ISO8601),"endDate","location","notes","isAllDay","recurrence","confidence"}
    规则：
    - 只修改用户要求的部分，其余字段保持原值（包括未提及的日期、地点、循环规则）。
    - 用户说“提前/推迟 X 分钟/小时/天”时按原时间推算新 startDate/endDate。
    - 若要求与日程内容无关或无法理解，原样输出输入的日程。
    - 当前系统时间会随消息一并提供。
    """

    func reviseEvent(originalJSON: String, instruction: String, config: LLMProviderConfig) async throws -> [ParsedEvent] {
        guard !config.apiKey.isEmpty else { throw LLMError.noAPIKey }
        let promptContext = "（当前时间：\(Self.nowString())）"
        let userText = "已有日程：\n\(originalJSON)\n\(promptContext)\n修改要求：\(instruction)"
        let url = URL(string: effectiveBaseURL(config).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try buildRequestBody(text: userText, image: nil, config: config,
                                                systemPrompt: Self.revisionSystemPrompt)
        let (data, response) = try await URLSession.shared.data(for: request)
        let jsonString = try Self.extractContent(data: data, response: response)
        return try Self.decodeEvents(from: jsonString)
    }

    // MARK: - 响应解析

    struct ChatResponse: Codable {
        struct Choice: Codable {
            struct Msg: Codable { let content: String? }
            let message: Msg?
        }
        let choices: [Choice]?
    }

    static func extractContent(data: Data, response: URLResponse) throws -> String {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded?.choices?.first?.message?.content, !content.isEmpty else {
            throw LLMError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return content
    }

    /// 从模型输出中剥离 ```json 包裹并解码为日程数组
    static func decodeEvents(from content: String) throws -> [ParsedEvent] {
        var json = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```") {
            json = json.replacingOccurrences(of: "```json", with: "")
                       .replacingOccurrences(of: "```", with: "")
                       .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // 截取第一个 { 到最后一个 }，容忍模型输出多余文字
        if let first = json.firstIndex(of: "{"), let last = json.lastIndex(of: "}"), first < last {
            json = String(json[first...last])
        }
        guard let data = json.data(using: .utf8) else { throw LLMError.invalidResponse(content) }

        struct EventList: Codable { let events: [ParsedEvent]? }

        // 新格式 {"events":[...]}
        if let list = try? JSONDecoder().decode(EventList.self, from: data),
           let events = list.events {
            return events.filter { !$0.title.isEmpty }
        }
        // 兼容旧格式：单对象
        if let single = try? JSONDecoder().decode(ParsedEvent.self, from: data),
           !single.title.isEmpty {
            return [single]
        }
        // 兼容裸数组
        if let array = try? JSONDecoder().decode([ParsedEvent].self, from: data) {
            return array.filter { !$0.title.isEmpty }
        }
        throw LLMError.invalidResponse(content)
    }

    static func nowString() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm EEEE"
        return fmt.string(from: Date())
    }
}

// MARK: - 内置服务商

/// 智谱 GLM（OpenAI 兼容端点，glm-4v-plus 支持图片）
class ZhipuProvider: OpenAICompatProvider {
    init() {
        super.init(id: "zhipu", name: "智谱 GLM",
                   baseURL: "https://open.bigmodel.cn/api/paas/v4",
                   model: "glm-4v-plus", supportsImage: true)
    }
}

/// DeepSeek（OpenAI 兼容，默认 deepseek-chat）
class DeepSeekProvider: OpenAICompatProvider {
    init() {
        super.init(id: "deepseek", name: "DeepSeek",
                   baseURL: "https://api.deepseek.com/v1",
                   model: "deepseek-chat", supportsImage: false)
    }
}

/// Kimi / 月之暗面（OpenAI 兼容）
class KimiProvider: OpenAICompatProvider {
    init() {
        super.init(id: "kimi", name: "Kimi（月之暗面）",
                   baseURL: "https://api.moonshot.cn/v1",
                   model: "kimi-latest", supportsImage: false)
    }
}

/// 阿里云百炼 / 通义千问（OpenAI 兼容模式，qwen-vl-plus 支持图片）
class QwenProvider: OpenAICompatProvider {
    init() {
        super.init(id: "qwen", name: "通义千问（百炼）",
                   baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                   model: "qwen-vl-plus", supportsImage: true)
    }
}

/// OpenAI 官方（gpt-4o 多模态）
class OpenAIProvider: OpenAICompatProvider {
    init() {
        super.init(id: "openai", name: "OpenAI",
                   baseURL: "https://api.openai.com/v1",
                   model: "gpt-4o", supportsImage: true)
    }
}

/// 自定义 OpenAI 兼容服务（DeepSeek、Kimi、oneapi 等）
class CustomCompatProvider: OpenAICompatProvider {
    init() {
        super.init(id: "custom", name: "自定义（OpenAI 兼容）",
                   baseURL: "", model: "", supportsImage: true)
    }

    override func effectiveBaseURL(_ config: LLMProviderConfig) -> String {
        config.baseURL  // 自定义服务商必须由用户填写地址
    }

    override func effectiveModel(_ config: LLMProviderConfig) -> String {
        config.model
    }
}

// MARK: - 全局设置

/// 当前生效的服务商与各服务商的配置。
/// 为兼容旧版本，会把已有 UserDefaults 中的 Key 迁移到 Keychain 后立即脱敏保存。
@MainActor
final class LLMSettings: ObservableObject {
    static let shared = LLMSettings()

    let providers: [LLMProvider] = [
        OrbitCloudProvider(), ZhipuProvider(), DeepSeekProvider(), KimiProvider(), QwenProvider(),
        OpenAIProvider(), CustomCompatProvider()
    ]

    private let defaults = UserDefaults.standard
    private let activeKey = "llm.activeProvider"
    private let configKey = "llm.providerConfigs"

    @Published var activeProviderId: String {
        didSet { defaults.set(activeProviderId, forKey: activeKey) }
    }
    @Published var configs: [String: LLMProviderConfig] {
        didSet { saveConfigs() }
    }

    init() {
        activeProviderId = defaults.string(forKey: activeKey) ?? "orbit-cloud"
        var loaded: [String: LLMProviderConfig]
        if let data = defaults.data(forKey: configKey),
           let saved = try? JSONDecoder().decode([String: LLMProviderConfig].self, from: data) {
            loaded = saved
        } else {
            loaded = [:]
        }

        for provider in providers {
            let account = Self.keychainAccount(for: provider.id)
            if let secureKey = KeychainService.read(account: account) {
                var config = loaded[provider.id] ?? LLMProviderConfig()
                config.apiKey = secureKey
                loaded[provider.id] = config
            } else if let legacyKey = loaded[provider.id]?.apiKey, !legacyKey.isEmpty {
                // 首次升级时，把旧版明文偏好迁到 Keychain；保存阶段会把它从偏好中抹掉。
                _ = KeychainService.save(legacyKey, account: account)
            }
        }
        configs = loaded
        saveConfigs()
    }

    var activeProvider: LLMProvider {
        providers.first { $0.id == activeProviderId } ?? providers[0]
    }

    func config(for provider: LLMProvider) -> LLMProviderConfig {
        configs[provider.id] ?? LLMProviderConfig()
    }

    func updateConfig(_ config: LLMProviderConfig, for provider: LLMProvider) {
        configs[provider.id] = config
    }

    private func saveConfigs() {
        var redacted = configs
        for provider in providers {
            guard let config = configs[provider.id] else { continue }
            let account = Self.keychainAccount(for: provider.id)
            if config.apiKey.isEmpty {
                KeychainService.delete(account: account)
                continue
            }
            guard KeychainService.save(config.apiKey, account: account) else { continue }
            var publicConfig = config
            publicConfig.apiKey = ""
            redacted[provider.id] = publicConfig
        }
        if let data = try? JSONEncoder().encode(redacted) {
            defaults.set(data, forKey: configKey)
        }
    }

    private static func keychainAccount(for providerId: String) -> String {
        "orbit.llm.api-key.\(providerId)"
    }
}
