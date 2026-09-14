import Foundation

/// 后端与内购的可配置项。部署前保持占位值；联调时只改 Info.plist，不改代码：
/// - OrbitBackendBaseURL：后端基地址
/// - OrbitBackendMock：开发期本地 mock（后端未部署时置 YES）
/// - OrbitPointProducts：积分包商品 ID 列表（与 App Store Connect / 后端 POINT_PACKS 一致）
/// - OrbitSupportEmail：客服邮箱
enum OrbitBackendConfig {
    /// 后端基地址（不带末尾斜杠），如 https://api.example.com
    static var baseURL: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "OrbitBackendBaseURL") as? String)
            ?? "https://api.example.com"
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// 开发期 mock：所有后端请求返回本地假数据，联调前置为 NO。
    static var useMock: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "OrbitBackendMock") as? Bool) ?? false
    }

    static var productIDs: [String] {
        (Bundle.main.object(forInfoDictionaryKey: "OrbitPointProducts") as? [String]) ??
            ["com.itransstudio.orbit.points50",
             "com.itransstudio.orbit.points250",
             "com.itransstudio.orbit.points600"]
    }

    /// 从商品 ID 推断积分数（points50 → 50）。
    static func points(forProductID id: String) -> Int? {
        guard let match = id.range(of: #"points(\d+)$"#, options: .regularExpression) else { return nil }
        return Int(id[match].replacingOccurrences(of: "points", with: ""))
    }

    static var supportEmail: String {
        (Bundle.main.object(forInfoDictionaryKey: "OrbitSupportEmail") as? String) ?? "support@example.com"
    }
}

/// 后端统一错误：HTTP 状态 + {error:{code,message}}。
struct OrbitAPIError: LocalizedError {
    let status: Int
    let code: String
    let message: String

    var errorDescription: String? {
        message.isEmpty ? "请求失败（\(status)）" : message
    }

    static func parse(status: Int, data: Data) -> OrbitAPIError {
        struct Wrapper: Codable {
            struct Detail: Codable { let code: String?; let message: String? }
            let error: Detail?
        }
        if let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data),
           let detail = wrapper.error {
            return OrbitAPIError(status: status,
                                 code: detail.code ?? "UNKNOWN",
                                 message: detail.message ?? "")
        }
        return OrbitAPIError(status: status, code: "UNKNOWN", message: "请求失败（\(status)）")
    }
}

/// Orbit 积分后端 HTTP 客户端（Node.js 后端见仓库 backend/ 目录）。
/// 全部 HTTPS + 明确超时；不打印 token、api_key、收据内容。
enum OrbitAPIClient {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 90
        return URLSession(configuration: configuration)
    }()

    // MARK: - 响应模型

    struct AuthResponse: Codable {
        let token: String
        let user: User
        struct User: Codable {
            let id: Int
            let username: String
            let role: String
            let created_at: String?
        }
    }

    struct PointsResponse: Codable {
        let wallet: String
        let points: Int
    }

    struct APIKeyResponse: Codable {
        let api_key: String
        let base_url: String
        let default_model: String?
        let note: String?
    }

    struct IAPVerifyResponse: Codable {
        let environment: String?
        let processed: [Processed]?
        let points_added: Int?
        let points: Int?
        struct Processed: Codable {
            let transaction_id: String?
            let product_id: String?
            let points: Int?
            let status: String?
        }
    }

    // MARK: - 请求

    static func request(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        token: String?
    ) async throws -> Data {
        if OrbitBackendConfig.useMock {
            return try mockResponse(for: path, method: method, body: body)
        }

        guard let url = URL(string: OrbitBackendConfig.baseURL + path) else {
            throw OrbitAPIError(status: -1, code: "BAD_URL", message: "后端地址无效，请检查配置。")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OrbitAPIError(status: -1, code: "NO_RESPONSE", message: "服务无响应。")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OrbitAPIError.parse(status: http.statusCode, data: data)
        }
        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    // MARK: - 开发期 mock

    /// mock 模式下的共享余额（App 单次运行内有效）。
    enum MockState {
        static var points = 0
    }

    private static func mockResponse(for path: String, method: String, body: [String: Any]?) throws -> Data {
        switch path {
        case "/api/auth/register", "/api/auth/login":
            let user: [String: Any] = [
                "id": 1,
                "username": (body?["username"] as? String) ?? "mock_user",
                "role": "user",
                "created_at": "2026-01-01 00:00:00"
            ]
            return try JSONSerialization.data(withJSONObject: ["token": "mock-token", "user": user])
        case "/api/me/points":
            return try JSONSerialization.data(withJSONObject: ["wallet": "ios", "points": MockState.points])
        case "/api/me/api-key":
            let payload: [String: Any] = [
                "api_key": "sk-mock-000000000000",
                "base_url": "https://mock.oneapi.example.com",
                "default_model": "glm-4v-plus",
                "note": "mock 模式下的假令牌"
            ]
            return try JSONSerialization.data(withJSONObject: payload)
        case "/api/iap/verify":
            let receipt = body?["receipt"] as? String ?? ""
            let added = receipt.count % 2 == 0 ? 50 : 0
            MockState.points += added
            let processed: [[String: Any]] = [[
                "transaction_id": "mock-txn-1",
                "product_id": "com.itransstudio.orbit.points50",
                "points": 50,
                "status": "credited"
            ]]
            return try JSONSerialization.data(withJSONObject: [
                "environment": "sandbox",
                "processed": processed,
                "points_added": added,
                "points": MockState.points
            ])
        default:
            throw OrbitAPIError(status: 404, code: "NOT_FOUND", message: "mock：未实现的接口 \(path)")
        }
    }
}
