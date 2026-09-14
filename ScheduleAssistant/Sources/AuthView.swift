import SwiftUI

/// 登录 / 注册页：首次启动或令牌失效时全屏展示。
/// 用户名 3~32 位字母数字下划线；密码 8~64 位。token 只进 Keychain。
struct AuthView: View {
    @ObservedObject private var account = AccountStore.shared
    @ObservedObject private var app = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var isRegisterMode = false
    @State private var isBusy = false
    @State private var errorMessage: String?

    private static let usernamePattern = "^[A-Za-z0-9_]{3,32}$"

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 56)

            VStack(spacing: 14) {
                Ellipse()
                    .stroke(
                        LinearGradient(colors: [orbitAccent(), orbitAccent().opacity(0.55)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 4
                    )
                    .frame(width: 72, height: 38)
                    .rotationEffect(.degrees(-43))
                Text(isRegisterMode ? "创建 Orbit 账号" : "登录 Orbit")
                    .font(.title2.bold())
                Text("登录后使用 Orbit 云端 AI 识别，按积分计费；\n也可以稍后在「设置 → 高级」使用自己的 API Key。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)

            VStack(spacing: 14) {
                TextField("用户名（3~32 位字母、数字或下划线）", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(isRegisterMode ? "设置密码（8~64 位）" : "密码", text: $password)
                Picker("", selection: $isRegisterMode) {
                    Text("登录").tag(false)
                    Text("注册").tag(true)
                }
                .pickerStyle(.segmented)

                Button(action: submit) {
                    HStack(spacing: 8) {
                        if isBusy { ProgressView().controlSize(.small) }
                        Text(submitTitle)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(orbitAccent())
                .controlSize(.large)
                .disabled(isBusy || username.isEmpty || password.isEmpty)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .padding(.horizontal, 24)
            .padding(.top, 32)

            Spacer()

            Button("暂不登录，先逛逛") {
                app.authSkipped = true
                dismiss()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .tint(orbitAccent())
    }

    private var submitTitle: String {
        if isBusy { return "请稍候…" }
        return isRegisterMode ? "注册并登录" : "登录"
    }

    private func submit() {
        guard username.range(of: Self.usernamePattern, options: .regularExpression) != nil else {
            errorMessage = "用户名需为 3~32 位字母、数字或下划线。"
            return
        }
        guard (8...64).contains(password.count) else {
            errorMessage = "密码需为 8~64 位。"
            return
        }
        errorMessage = nil
        isBusy = true
        let name = username
        let pass = password
        Task {
            defer { isBusy = false }
            do {
                if isRegisterMode {
                    try await account.register(username: name, password: pass)
                } else {
                    try await account.login(username: name, password: pass)
                }
                app.authSkipped = false
                // 登录成功：account.isLoggedIn 变化会触发根视图关闭本页。
            } catch let error as OrbitAPIError {
                errorMessage = friendlyMessage(for: error)
            } catch let error as URLError {
                errorMessage = "无法连接服务器：\(error.localizedDescription)"
            } catch {
                errorMessage = "出错了：\(error.localizedDescription)"
            }
        }
    }

    private func friendlyMessage(for error: OrbitAPIError) -> String {
        switch error.code {
        case "USERNAME_TAKEN": return "用户名已被占用，换一个试试。"
        case "AUTH_FAILED": return "用户名或密码错误。"
        case "BAD_USERNAME": return "用户名需为 3~32 位字母、数字或下划线。"
        case "BAD_PASSWORD": return "密码需为 8~64 位。"
        default:
            if error.status == 429 { return "操作太频繁，请稍后再试。" }
            if error.status <= 0 { return "无法连接服务器，请检查网络后重试。" }
            return error.message
        }
    }
}
