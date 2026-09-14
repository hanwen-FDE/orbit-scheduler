import SwiftUI
import EventKit

/// iOS 15 兼容层：集中放置高版本系统 API 的降级实现，
/// 业务代码统一走 orbit 前缀入口，部署目标保持在 iOS 15。

// MARK: - NavigationStack（iOS 16+；iOS 15 退回 NavigationView）

struct OrbitNavigationStack<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack(root: content)
        } else {
            NavigationView(content: content)
                .navigationViewStyle(.stack)
        }
    }
}

// MARK: - Sheet 高度与键盘行为

extension View {
    /// iOS 16+ 应用指定高度的 detent；iOS 15 保持系统默认整页 sheet。
    @ViewBuilder
    func orbitDetent(height: CGFloat) -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.height(height)])
        } else {
            self
        }
    }

    /// iOS 16+ 滚动时交互式收起键盘；iOS 15 无此能力，保持默认。
    @ViewBuilder
    func orbitScrollDismissesKeyboardInteractively() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }
}

// MARK: - 空状态（ContentUnavailableView 的 iOS 15 替代）

struct OrbitUnavailableView: View {
    let title: String
    let systemImage: String
    var description: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            if let description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

// MARK: - EventKit 授权（iOS 17 拆分了 fullAccess / writeOnly）

extension EKAuthorizationStatus {
    /// 能否读取现有日程（冲突检查、今天页、简报）。
    var orbitCanReadEvents: Bool {
        if #available(iOS 17.0, *) {
            return self == .fullAccess
        }
        return self == .authorized
    }

    /// 能否写入日程。iOS 17 的“仅写入”也算可写。
    var orbitCanWriteEvents: Bool {
        if #available(iOS 17.0, *) {
            return self == .fullAccess || self == .writeOnly
        }
        return self == .authorized
    }

    /// 提醒事项（Reminder）的可用判断。
    var orbitCanUseReminders: Bool {
        if #available(iOS 17.0, *) {
            return self == .fullAccess
        }
        return self == .authorized
    }
}
