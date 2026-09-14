import Foundation
import SwiftUI

extension Notification.Name {
    /// iCloud 同步从云端拉到较新数据后广播；ChatStore / OrbitNotificationStore 热加载。
    static let orbitSyncDidPull = Notification.Name("orbit.sync.didPull")
}

/// iCloud 同步：把 Orbit 的对话与通知 JSON 镜像到 App 的 iCloud 容器，
/// 以文件修改时间决定上传或下载。需要开发者账号开启 iCloud 能力并在
/// 系统设置登录 iCloud；不可用时给出明确状态提示而不是静默失败。
@MainActor
final class ICloudSyncService: ObservableObject {
    static let shared = ICloudSyncService()

    @Published var lastResultText = ""
    @Published var isSyncing = false

    private static let syncFilenames = ["orbit-chat.json", "orbit-notifications.json"]

    private static var applicationSupport: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// 手动触发一次双向同步：本地较新则上传，云端较新则下载并热加载。
    func syncNow() async {
        guard iCloudAvailable else {
            lastResultText = "未检测到 iCloud 登录：请在系统设置 → 顶部头像 → iCloud 中登录后重试。"
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        guard let documents = await resolveContainerDocuments() else {
            lastResultText = "iCloud 容器暂不可用：请确认已在 iCloud 设置中允许 Orbit 使用 iCloud Drive。"
            return
        }

        var pushed = 0
        var pulled = 0
        for filename in Self.syncFilenames {
            let local = Self.applicationSupport.appendingPathComponent(filename)
            let remote = documents.appendingPathComponent(filename)
            let localDate = Self.modifiedDate(of: local)
            let remoteDate = Self.modifiedDate(of: remote)

            if remoteDate > localDate {
                do {
                    try? FileManager.default.removeItem(at: local)
                    try FileManager.default.copyItem(at: remote, to: local)
                    pulled += 1
                } catch {
                    lastResultText = "下载 \(filename) 失败：\(error.localizedDescription)"
                    return
                }
            } else if localDate > remoteDate {
                do {
                    try? FileManager.default.removeItem(at: remote)
                    try FileManager.default.copyItem(at: local, to: remote)
                    pushed += 1
                } catch {
                    lastResultText = "上传 \(filename) 失败：\(error.localizedDescription)"
                    return
                }
            }
        }

        if pulled > 0 {
            NotificationCenter.default.post(name: .orbitSyncDidPull, object: nil)
        }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        lastResultText = "已同步（\(timeFormatter.string(from: Date()))）：上传 \(pushed) 项，下载 \(pulled) 项。"
    }

    /// 容器地址解析可能触发网络请求，放到后台线程执行。
    private func resolveContainerDocuments() async -> URL? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let url = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
                    .appendingPathComponent("Documents")
                continuation.resume(returning: url)
            }
        }
    }

    private static func modifiedDate(of url: URL) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.modificationDate] as? Date) ?? .distantPast
    }
}
