import Foundation
import UIKit

/// 云端凭证的非隔离只读缓存：LLM 请求在后台组包时要同步读取基地址与模型名，
/// 而 AccountStore 是 MainActor。主线程更新，读侧只做取值。
enum CloudCredentialCache {
    static var apiKey: String?
    static var baseURL: String?
    static var model: String = ""

    @MainActor
    static func refresh() {
        apiKey = KeychainService.read(account: "orbit.cloud.api-key")
        baseURL = KeychainService.read(account: "orbit.cloud.base-url")
        model = UserDefaults.standard.string(forKey: "orbit.cloud.model") ?? ""
    }
}

/// OneAPI 直连客户端：OpenAI 兼容 + SSE 流式（stream: true）。
/// 请求头带 Authorization: Bearer {api_key} 与 Content-Type: application/json。
enum OneAPIStreamClient {
    private struct StreamDelta: Codable {
        struct Choice: Codable {
            struct Payload: Codable { let content: String? }
            let delta: Payload?
            let message: Payload?
        }
        let choices: [Choice]?
    }

    /// 发起流式请求并聚合增量文本；个别网关会忽略 stream 参数返回整段 JSON，做回落解析。
    static func complete(baseURL: String, apiKey: String, body data: Data) async throws -> String {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/v1/chat/completions") else {
            throw LLMError.invalidResponse("对话接口地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = data

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var bodyText = ""
            for try await line in bytes.lines { bodyText += line }
            throw mapError(status: http.statusCode, body: bodyText)
        }

        var collected = ""
        var raw = ""
        for try await line in bytes.lines {
            raw += line
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard trimmedLine.hasPrefix("data:") else { continue }
            let payload = String(trimmedLine.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]", !payload.isEmpty,
                  let payloadData = payload.data(using: .utf8) else { continue }
            if let delta = try? JSONDecoder().decode(StreamDelta.self, from: payloadData),
               let content = delta.choices?.first?.delta?.content {
                collected += content
            }
        }

        if collected.isEmpty {
            // 回落：按非流式整段 JSON 解析。
            if let raw_data = raw.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(OpenAICompatProvider.ChatResponse.self, from: raw_data),
               let content = decoded.choices?.first?.message?.content, !content.isEmpty {
                return content
            }
            throw LLMError.invalidResponse(String(raw.prefix(300)))
        }
        return collected
    }

    /// OneAPI 额度不足通常表现为 4xx + body 里的 insufficient quota 字样。
    static func mapError(status: Int, body: String) -> LLMError {
        let lowered = body.lowercased()
        if lowered.contains("insufficient") || lowered.contains("quota") || lowered.contains("额度不足") {
            return .insufficientPoints
        }
        if status == 401 || status == 403 {
            return .cloudKeyInvalid
        }
        return .http(status, body)
    }
}

/// 默认 AI 服务「Orbit 云端」：凭证由后端下发并存 Keychain；
/// 模型名使用后端 default_model，用户不可改（界面上隐藏模型配置）。
class OrbitCloudProvider: OpenAICompatProvider {
    init() {
        super.init(id: "orbit-cloud", name: "Orbit 云端",
                   baseURL: "", model: "", supportsImage: true)
    }

    override func effectiveBaseURL(_ config: LLMProviderConfig) -> String {
        CloudCredentialCache.baseURL ?? ""
    }

    override func effectiveModel(_ config: LLMProviderConfig) -> String {
        let model = CloudCredentialCache.model
        return model.isEmpty ? "glm-4v-plus" : model
    }

    /// 云端凭证是否可直接组包（未就绪时由 ensureCloudReady 引导登录/领令牌）。
    private func readyCredentials() throws -> (key: String, base: String) {
        guard let key = CloudCredentialCache.apiKey,
              let base = CloudCredentialCache.baseURL, !base.isEmpty else {
            throw LLMError.cloudNotReady
        }
        return (key, base)
    }

    override func parseSchedule(text: String?, image: UIImage?, config: LLMProviderConfig) async throws -> [ParsedEvent] {
        guard await AccountStore.shared.ensureCloudReady() else { throw LLMError.cloudNotReady }
        let credentials = try readyCredentials()
        let promptContext = "（当前时间：\(Self.nowString())）"
        let fullText = [text, promptContext].compactMap { $0 }.joined(separator: "\n")
        let body = try buildRequestBody(text: fullText, image: image, config: config,
                                        systemPrompt: Self.systemPrompt, stream: true)
        let content = try await OneAPIStreamClient.complete(baseURL: credentials.base,
                                                            apiKey: credentials.key,
                                                            body: body)
        return try Self.decodeEvents(from: content)
    }

    override func reviseEvent(originalJSON: String, instruction: String, config: LLMProviderConfig) async throws -> [ParsedEvent] {
        guard await AccountStore.shared.ensureCloudReady() else { throw LLMError.cloudNotReady }
        let credentials = try readyCredentials()
        let promptContext = "（当前时间：\(Self.nowString())）"
        let userText = "已有日程：\n\(originalJSON)\n\(promptContext)\n修改要求：\(instruction)"
        let body = try buildRequestBody(text: userText, image: nil, config: config,
                                        systemPrompt: Self.revisionSystemPrompt, stream: true)
        let content = try await OneAPIStreamClient.complete(baseURL: credentials.base,
                                                            apiKey: credentials.key,
                                                            body: body)
        return try Self.decodeEvents(from: content)
    }

    override func testConnection(config: LLMProviderConfig) async throws -> Bool {
        guard await AccountStore.shared.ensureCloudReady() else { throw LLMError.cloudNotReady }
        let credentials = try readyCredentials()
        let body = try buildRequestBody(
            text: "明天上午十点进行连接测试会议。",
            image: nil,
            config: config,
            systemPrompt: Self.systemPrompt,
            stream: true
        )
        let content = try await OneAPIStreamClient.complete(baseURL: credentials.base,
                                                            apiKey: credentials.key,
                                                            body: body)
        _ = try Self.decodeEvents(from: content)
        return true
    }
}
