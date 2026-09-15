import Foundation
import SwiftUI

extension Notification.Name {
    /// 需要登录（首次启动、聊天前未登录、令牌 401 失效）时广播；根视图弹出登录页。
    static let orbitAuthRequired = Notification.Name("orbit.auth.required")
    /// 积分不足，引导打开积分商店。
    static let orbitPointsStoreRequested = Notification.Name("orbit.points.store.requested")
    /// 无论当前导航位置如何，都从根视图重新打开第一页导览。
    static let orbitOnboardingRequested = Notification.Name("orbit.onboarding.requested")
}

/// 登录态与积分账户。token 与云端对话令牌一律存 Keychain（禁止 UserDefaults），
/// 用户名等非敏感信息存 UserDefaults 以便快速恢复界面。
@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    private let tokenAccount = "orbit.auth.token"
    private let apiKeyAccount = "orbit.cloud.api-key"
    private let cloudBaseAccount = "orbit.cloud.base-url"
    private let usernameKey = "orbit.account.username"
    private let cloudModelKey = "orbit.cloud.model"
    private let proKey = "orbit.account.isPro"

    @Published var username: String?
    @Published var points: Int?
    @Published var isFetchingPoints = false
    @Published var cloudModel: String = ""
    @Published private(set) var isPro = false

    private init() {
        username = UserDefaults.standard.string(forKey: usernameKey)
        cloudModel = UserDefaults.standard.string(forKey: cloudModelKey) ?? ""
        isPro = UserDefaults.standard.bool(forKey: proKey)
        CloudCredentialCache.refresh()
    }

    // MARK: - 凭证读取（Keychain）

    var token: String? { KeychainService.read(account: tokenAccount) }
    var isLoggedIn: Bool { token != nil }
    var cloudAPIKey: String? { KeychainService.read(account: apiKeyAccount) }
    var cloudBaseURL: String? { KeychainService.read(account: cloudBaseAccount) }

    /// 云端对话（OneAPI 直连）所需的凭证是否齐备。
    var isCloudReady: Bool {
        isLoggedIn && cloudAPIKey != nil && cloudBaseURL != nil
    }

    // MARK: - 注册 / 登录 / 退出

    func register(username: String, password: String) async throws {
        let data = try await OrbitAPIClient.request(
            path: "/api/auth/register", method: "POST",
            body: ["username": username, "password": password], token: nil)
        try await finishAuth(OrbitAPIClient.decode(OrbitAPIClient.AuthResponse.self, from: data))
    }

    func login(username: String, password: String) async throws {
        let data = try await OrbitAPIClient.request(
            path: "/api/auth/login", method: "POST",
            body: ["username": username, "password": password], token: nil)
        try await finishAuth(OrbitAPIClient.decode(OrbitAPIClient.AuthResponse.self, from: data))
    }

    /// Apple 的 identityToken 只交给 Orbit 后端验签；不写入本机或服务端数据库。
    func loginWithApple(identityToken: String, fullName: String?) async throws {
        var body: [String: Any] = ["identity_token": identityToken]
        if let fullName, !fullName.isEmpty { body["full_name"] = fullName }
        let data = try await OrbitAPIClient.request(
            path: "/api/auth/apple", method: "POST", body: body, token: nil)
        try await finishAuth(OrbitAPIClient.decode(OrbitAPIClient.AuthResponse.self, from: data))
    }

    private func finishAuth(_ response: OrbitAPIClient.AuthResponse) async {
        _ = KeychainService.save(response.token, account: tokenAccount)
        username = response.user.username
        isPro = response.user.is_pro ?? false
        UserDefaults.standard.set(response.user.username, forKey: usernameKey)
        UserDefaults.standard.set(isPro, forKey: proKey)
        CloudCredentialCache.refresh()
        await refreshPoints()
        // 登录后顺手领取对话令牌；后端幂等，重复调用返回同一令牌。
        _ = try? await fetchCloudAPIKey()
    }

    /// 退出登录：清掉 Keychain 里的登录令牌与对话令牌（对话数据保留在本地）。
    func logout() {
        KeychainService.delete(account: tokenAccount)
        KeychainService.delete(account: apiKeyAccount)
        KeychainService.delete(account: cloudBaseAccount)
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: cloudModelKey)
        UserDefaults.standard.removeObject(forKey: proKey)
        username = nil
        points = nil
        cloudModel = ""
        isPro = false
        CloudCredentialCache.refresh()
    }

    // MARK: - 积分

    /// 余额以 GET /api/me/points 为准；客户端不做本地记账。
    func refreshPoints() async {
        guard let token else {
            points = nil
            return
        }
        isFetchingPoints = true
        defer { isFetchingPoints = false }
        do {
            let data = try await OrbitAPIClient.request(path: "/api/me/points", token: token)
            let response = try OrbitAPIClient.decode(OrbitAPIClient.PointsResponse.self, from: data)
            points = response.points
        } catch let error as OrbitAPIError where error.status == 401 {
            handleSessionExpired()
        } catch {
            // 余额拉取失败不打断使用，下次进入页面再试。
        }
    }

    // MARK: - 云端对话令牌

    /// 领取 / 刷新后端下发的 OneAPI 直连令牌。
    @discardableResult
    func fetchCloudAPIKey() async throws -> Bool {
        guard let token else { return false }
        do {
            let data = try await OrbitAPIClient.request(path: "/api/me/api-key", method: "POST", token: token)
            let response = try OrbitAPIClient.decode(OrbitAPIClient.APIKeyResponse.self, from: data)
            _ = KeychainService.save(response.api_key, account: apiKeyAccount)
            _ = KeychainService.save(response.base_url, account: cloudBaseAccount)
            cloudModel = response.default_model ?? ""
            UserDefaults.standard.set(cloudModel, forKey: cloudModelKey)
            CloudCredentialCache.refresh()
            return true
        } catch let error as OrbitAPIError where error.status == 401 {
            handleSessionExpired()
            return false
        }
    }

    /// 聊天前调用：保证云端凭证就绪。未登录时广播打开登录页。
    func ensureCloudReady() async -> Bool {
        if isCloudReady { return true }
        guard isLoggedIn else {
            NotificationCenter.default.post(name: .orbitAuthRequired, object: nil)
            return false
        }
        do {
            return try await fetchCloudAPIKey()
        } catch {
            return false
        }
    }

    /// 对话令牌被服务端判定无效时清缓存，下次聊天重新领取。
    func invalidateCloudKey() {
        KeychainService.delete(account: apiKeyAccount)
        CloudCredentialCache.refresh()
    }

    // MARK: - 内购收据校验

    func verifyReceipt(base64: String) async throws -> OrbitAPIClient.IAPVerifyResponse {
        guard let token else {
            throw OrbitAPIError(status: 401, code: "AUTH_MISSING", message: "请先登录后再购买积分。")
        }
        do {
            let data = try await OrbitAPIClient.request(
                path: "/api/iap/verify", method: "POST",
                body: ["receipt": base64], token: token)
            let response = try OrbitAPIClient.decode(OrbitAPIClient.IAPVerifyResponse.self, from: data)
            if let latest = response.points {
                points = latest
            }
            return response
        } catch let error as OrbitAPIError where error.status == 401 {
            handleSessionExpired()
            throw error
        }
    }

    private func handleSessionExpired() {
        logout()
        NotificationCenter.default.post(name: .orbitAuthRequired, object: nil)
    }
}
